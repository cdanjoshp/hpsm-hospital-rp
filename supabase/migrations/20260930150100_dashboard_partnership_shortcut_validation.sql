-- Dashboard: compatibiliza Consultas, Internações e Parcerias ao catálogo de atalhos
-- sem mudar o contrato v1 das preferências existentes.

set lock_timeout = '5s';
set statement_timeout = '30s';

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
    'exams', 'casts', 'consultations', 'hospitalizations', 'my_hr', 'administrative', 'pending', 'rh',
    'career', 'recruitment', 'partnerships', 'team', 'profiles', 'reports', 'audit',
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
      where left_item.item ->> 'i' <> 'shortcuts'
        and right_item.item ->> 'i' <> 'shortcuts'
        and not (p_config -> 'hiddenWidgets' ? (left_item.item ->> 'i'))
        and not (p_config -> 'hiddenWidgets' ? (right_item.item ->> 'i'))
        and (left_item.item ->> 'x')::integer < (right_item.item ->> 'x')::integer + (right_item.item ->> 'w')::integer
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

comment on function private.hpsm_dashboard_config_valid(jsonb) is
  'Valida preferências v1 e aceita atalhos de Consultas, Internações e Parcerias, preservando os IDs legados.';
