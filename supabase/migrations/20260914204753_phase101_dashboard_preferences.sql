-- HPSM · Fase 10.1 — Dashboard modular e preferências pessoais.
-- Timestamp alinhado ao histórico canônico aplicado no Supabase.
-- Persiste somente layout/visibilidade/atalhos; os dados dos widgets continuam
-- vindo exclusivamente de hpsm_dashboard_summary().

set lock_timeout = '5s';
set statement_timeout = '120s';

create table public.dashboard_preferences (
  user_id uuid primary key references public.profiles(user_id) on delete cascade,
  config_version smallint not null default 1 check (config_version = 1),
  layout_json jsonb not null check (jsonb_typeof(layout_json) = 'object' and pg_column_size(layout_json) <= 28672),
  hidden_widgets jsonb not null default '[]'::jsonb check (jsonb_typeof(hidden_widgets) = 'array' and jsonb_array_length(hidden_widgets) <= 7),
  shortcuts_json jsonb not null default '[]'::jsonb check (jsonb_typeof(shortcuts_json) = 'array' and jsonb_array_length(shortcuts_json) <= 18),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.dashboard_preferences enable row level security;
alter table public.dashboard_preferences force row level security;

create policy dashboard_preferences_own_read
on public.dashboard_preferences
for select
to authenticated
using ((select auth.uid()) = user_id);

create policy phase101_dashboard_valid_session
on public.dashboard_preferences
as restrictive
for select
to authenticated
using ((select private.hpsm_session_valid(true)));

revoke all on table public.dashboard_preferences from public, anon, authenticated;
grant select on table public.dashboard_preferences to authenticated;
grant all on table public.dashboard_preferences to service_role;

create or replace function private.hpsm_dashboard_config_valid(p_config jsonb)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_allowed_widgets constant text[] := array[
    'my_week', 'my_production', 'career', 'attention',
    'communications', 'shortcuts', 'hospital_overview'
  ];
  v_allowed_shortcuts constant text[] := array[
    'overview', 'new_attendance', 'attendances', 'patients', 'catalog',
    'exams', 'casts', 'my_hr', 'administrative', 'pending', 'rh',
    'career', 'recruitment', 'team', 'profiles', 'reports', 'audit',
    'communications'
  ];
  v_breakpoint text;
  v_cols integer;
  v_layout jsonb;
  v_count integer;
  v_unique_count integer;
  v_valid boolean;
begin
  if p_config is null
     or jsonb_typeof(p_config) <> 'object'
     or pg_column_size(p_config) > 32768
     or p_config - array['configVersion', 'layouts', 'hiddenWidgets', 'shortcuts'] <> '{}'::jsonb
     or not (p_config ?& array['configVersion', 'layouts', 'hiddenWidgets', 'shortcuts'])
     or p_config ->> 'configVersion' <> '1'
     or jsonb_typeof(p_config -> 'layouts') <> 'object'
     or jsonb_typeof(p_config -> 'hiddenWidgets') <> 'array'
     or jsonb_typeof(p_config -> 'shortcuts') <> 'array'
  then
    return false;
  end if;

  select count(*) into v_count from jsonb_object_keys(p_config -> 'layouts');
  if v_count <> 3
     or not (p_config -> 'layouts' ?& array['lg', 'md', 'sm'])
  then
    return false;
  end if;

  foreach v_breakpoint in array array['lg', 'md', 'sm'] loop
    v_cols := case v_breakpoint when 'lg' then 12 when 'md' then 8 else 1 end;
    v_layout := p_config -> 'layouts' -> v_breakpoint;
    if jsonb_typeof(v_layout) <> 'array' or jsonb_array_length(v_layout) <> 7 then
      return false;
    end if;

    select
      count(*),
      count(distinct item ->> 'i'),
      coalesce(bool_and(
        jsonb_typeof(item) = 'object'
        and item - array['i', 'x', 'y', 'w', 'h'] = '{}'::jsonb
        and item ?& array['i', 'x', 'y', 'w', 'h']
        and item ->> 'i' = any(v_allowed_widgets)
        and (item ->> 'x') ~ '^[0-9]+$'
        and (item ->> 'y') ~ '^[0-9]+$'
        and (item ->> 'w') ~ '^[0-9]+$'
        and (item ->> 'h') ~ '^[0-9]+$'
        and (item ->> 'x')::integer between 0 and v_cols - 1
        and (item ->> 'y')::integer between 0 and 240
        and (item ->> 'w')::integer between 1 and v_cols
        and (item ->> 'h')::integer between 4 and 40
        and (item ->> 'x')::integer + (item ->> 'w')::integer <= v_cols
      ), false)
    into v_count, v_unique_count, v_valid
    from jsonb_array_elements(v_layout) item;

    if v_count <> 7 or v_unique_count <> 7 or not v_valid then
      return false;
    end if;

    if exists (
      select 1
      from jsonb_array_elements(v_layout) with ordinality left_item(item, position)
      join jsonb_array_elements(v_layout) with ordinality right_item(item, position)
        on left_item.position < right_item.position
      where (left_item.item ->> 'x')::integer < (right_item.item ->> 'x')::integer + (right_item.item ->> 'w')::integer
        and (left_item.item ->> 'x')::integer + (left_item.item ->> 'w')::integer > (right_item.item ->> 'x')::integer
        and (left_item.item ->> 'y')::integer < (right_item.item ->> 'y')::integer + (right_item.item ->> 'h')::integer
        and (left_item.item ->> 'y')::integer + (left_item.item ->> 'h')::integer > (right_item.item ->> 'y')::integer
    ) then
      return false;
    end if;
  end loop;

  select count(*), count(distinct value), coalesce(bool_and(value = any(v_allowed_widgets)), false)
  into v_count, v_unique_count, v_valid
  from jsonb_array_elements_text(p_config -> 'hiddenWidgets') value;
  if v_count > 7 or v_count <> v_unique_count or (v_count > 0 and not v_valid) then
    return false;
  end if;

  select count(*), count(distinct value), coalesce(bool_and(value = any(v_allowed_shortcuts)), false)
  into v_count, v_unique_count, v_valid
  from jsonb_array_elements_text(p_config -> 'shortcuts') value;
  if v_count > 18 or v_count <> v_unique_count or (v_count > 0 and not v_valid) then
    return false;
  end if;

  return true;
exception
  when others then
    return false;
end;
$$;

revoke all on function private.hpsm_dashboard_config_valid(jsonb) from public, anon, authenticated;

create or replace function public.save_dashboard_preferences(p_config jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
begin
  if not private.hpsm_dashboard_config_valid(p_config) then
    raise exception 'Configuração do Dashboard inválida.' using errcode = '22023';
  end if;

  insert into public.dashboard_preferences (
    user_id,
    config_version,
    layout_json,
    hidden_widgets,
    shortcuts_json
  ) values (
    v_actor,
    1,
    p_config -> 'layouts',
    p_config -> 'hiddenWidgets',
    p_config -> 'shortcuts'
  )
  on conflict (user_id) do update set
    config_version = excluded.config_version,
    layout_json = excluded.layout_json,
    hidden_widgets = excluded.hidden_widgets,
    shortcuts_json = excluded.shortcuts_json,
    updated_at = now();

  return jsonb_build_object(
    'configVersion', 1,
    'layouts', p_config -> 'layouts',
    'hiddenWidgets', p_config -> 'hiddenWidgets',
    'shortcuts', p_config -> 'shortcuts'
  );
end;
$$;

revoke all on function public.save_dashboard_preferences(jsonb) from public, anon, authenticated, service_role;
grant execute on function public.save_dashboard_preferences(jsonb) to authenticated, service_role;

create or replace function public.hpsm_dashboard_bundle()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_summary jsonb := public.hpsm_dashboard_summary();
  v_preferences jsonb;
begin
  select jsonb_build_object(
    'configVersion', preference.config_version,
    'layouts', preference.layout_json,
    'hiddenWidgets', preference.hidden_widgets,
    'shortcuts', preference.shortcuts_json
  )
  into v_preferences
  from public.dashboard_preferences preference
  where preference.user_id = v_actor;

  return v_summary || jsonb_build_object('preferences', v_preferences);
end;
$$;

revoke all on function public.hpsm_dashboard_bundle() from public, anon, authenticated, service_role;
grant execute on function public.hpsm_dashboard_bundle() to authenticated, service_role;

comment on table public.dashboard_preferences is
  'Preferência pessoal de layout, widgets ocultos e atalhos do Dashboard; não armazena conteúdo operacional.';
comment on function public.save_dashboard_preferences(jsonb) is
  'Valida e salva somente a preferência do ator autenticado, sem aceitar user_id do cliente.';
