-- HPSM · Fase 10.5 — Parcerias e Convênios.
-- Estrutura institucional, beneficiários, pré-beneficiários, responsável no
-- Portal do Paciente e vínculo histórico com Parceiros do HP.

set lock_timeout = '5s';
set statement_timeout = '120s';

-- ---------------------------------------------------------------------------
-- Permissões efetivas
-- ---------------------------------------------------------------------------

insert into public.system_permissions (code, module, label, description, sort_order)
values
  ('partnerships.view', 'Administrativo', 'Consultar parcerias', 'Consulta parcerias, responsáveis, beneficiários e pré-beneficiários.', 135),
  ('partnerships.manage', 'Administrativo', 'Gerenciar parcerias', 'Cria, altera, ativa, inativa e administra a composição das parcerias.', 136)
on conflict (code) do update set
  module = excluded.module,
  label = excluded.label,
  description = excluded.description,
  sort_order = excluded.sort_order;

insert into public.staff_position_permissions (position_id, permission_code, granted_by)
select position.id, permission.code, position.created_by
from public.staff_positions position
cross join (values ('partnerships.view'), ('partnerships.manage')) as permission(code)
where position.official
  and position.level between 11 and 14
on conflict (position_id, permission_code) do nothing;

-- Acesso Direto aceita Parcerias sem alterar os sete widgets da Dashboard.
alter table public.dashboard_preferences
  drop constraint if exists dashboard_preferences_shortcuts_json_check;
alter table public.dashboard_preferences
  add constraint dashboard_preferences_shortcuts_json_check check (
    jsonb_typeof(shortcuts_json) = 'array' and jsonb_array_length(shortcuts_json) <= 19
  );

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
    'career', 'recruitment', 'partnerships', 'team', 'profiles', 'reports',
    'audit', 'communications'
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
  if v_count <> 3 or not (p_config -> 'layouts' ?& array['lg', 'md', 'sm']) then return false; end if;

  foreach v_breakpoint in array array['lg', 'md', 'sm'] loop
    v_cols := case v_breakpoint when 'lg' then 12 when 'md' then 8 else 1 end;
    v_layout := p_config -> 'layouts' -> v_breakpoint;
    if jsonb_typeof(v_layout) <> 'array' or jsonb_array_length(v_layout) <> 7 then return false; end if;

    select count(*), count(distinct item ->> 'i'), coalesce(bool_and(
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

    if v_count <> 7 or v_unique_count <> 7 or not v_valid then return false; end if;

    if exists (
      select 1
      from jsonb_array_elements(v_layout) with ordinality left_item(item, position)
      join jsonb_array_elements(v_layout) with ordinality right_item(item, position)
        on left_item.position < right_item.position
      where left_item.item ->> 'i' not in ('shortcuts', 'hospital_overview')
        and right_item.item ->> 'i' not in ('shortcuts', 'hospital_overview')
        and not (p_config -> 'hiddenWidgets' ? (left_item.item ->> 'i'))
        and not (p_config -> 'hiddenWidgets' ? (right_item.item ->> 'i'))
        and (left_item.item ->> 'x')::integer < (right_item.item ->> 'x')::integer + (right_item.item ->> 'w')::integer
        and (left_item.item ->> 'x')::integer + (left_item.item ->> 'w')::integer > (right_item.item ->> 'x')::integer
        and (left_item.item ->> 'y')::integer < (right_item.item ->> 'y')::integer + (right_item.item ->> 'h')::integer
        and (left_item.item ->> 'y')::integer + (left_item.item ->> 'h')::integer > (right_item.item ->> 'y')::integer
    ) then return false; end if;
  end loop;

  select count(*), count(distinct value), coalesce(bool_and(value = any(v_allowed_widgets)), false)
  into v_count, v_unique_count, v_valid
  from jsonb_array_elements_text(p_config -> 'hiddenWidgets') value;
  if v_count > 7 or v_count <> v_unique_count or (v_count > 0 and not v_valid) then return false; end if;

  select count(*), count(distinct value), coalesce(bool_and(value = any(v_allowed_shortcuts)), false)
  into v_count, v_unique_count, v_valid
  from jsonb_array_elements_text(p_config -> 'shortcuts') value;
  if v_count > 19 or v_count <> v_unique_count or (v_count > 0 and not v_valid) then return false; end if;

  return true;
exception when others then return false;
end;
$$;

revoke all on function private.hpsm_dashboard_config_valid(jsonb) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Modelagem e histórico
-- ---------------------------------------------------------------------------

create table public.partnerships (
  id bigint generated always as identity primary key,
  name text not null,
  status text not null default 'active',
  notes text,
  responsible_patient_id bigint references public.patients(id) on delete restrict,
  responsible_assigned_at timestamptz,
  responsible_assigned_by uuid references public.profiles(user_id) on delete restrict,
  created_at timestamptz not null default now(),
  created_by uuid not null references public.profiles(user_id) on delete restrict,
  updated_at timestamptz not null default now(),
  updated_by uuid not null references public.profiles(user_id) on delete restrict,
  deactivated_at timestamptz,
  deactivated_by uuid references public.profiles(user_id) on delete restrict,
  deactivation_reason text,
  constraint partnerships_name_check check (char_length(btrim(name)) between 2 and 120),
  constraint partnerships_status_check check (status in ('active', 'inactive')),
  constraint partnerships_notes_check check (notes is null or char_length(btrim(notes)) between 2 and 2000),
  constraint partnerships_responsible_assignment_check check (
    (responsible_patient_id is null and responsible_assigned_at is null and responsible_assigned_by is null)
    or
    (responsible_patient_id is not null and responsible_assigned_at is not null and responsible_assigned_by is not null)
  ),
  constraint partnerships_deactivation_check check (
    (status = 'active' and deactivated_at is null and deactivated_by is null and deactivation_reason is null)
    or
    (status = 'inactive' and deactivated_at is not null and deactivated_by is not null and char_length(btrim(deactivation_reason)) between 2 and 500)
  )
);

create unique index partnerships_name_unique_idx on public.partnerships (lower(btrim(name)));
create index partnerships_status_name_idx on public.partnerships (status, lower(name), id);
create index partnerships_responsible_idx on public.partnerships (responsible_patient_id, status, id)
  where responsible_patient_id is not null;

create table public.partnership_responsible_history (
  id bigint generated always as identity primary key,
  partnership_id bigint not null references public.partnerships(id) on delete restrict,
  previous_patient_id bigint references public.patients(id) on delete restrict,
  responsible_patient_id bigint references public.patients(id) on delete restrict,
  changed_at timestamptz not null default now(),
  changed_by uuid not null references public.profiles(user_id) on delete restrict,
  constraint partnership_responsible_history_change_check check (previous_patient_id is distinct from responsible_patient_id)
);

create index partnership_responsible_history_partnership_idx
  on public.partnership_responsible_history (partnership_id, changed_at desc, id desc);

create table public.partnership_status_history (
  id bigint generated always as identity primary key,
  partnership_id bigint not null references public.partnerships(id) on delete restrict,
  previous_status text,
  status text not null,
  reason text,
  changed_at timestamptz not null default now(),
  changed_by uuid not null references public.profiles(user_id) on delete restrict,
  constraint partnership_status_history_previous_check check (previous_status is null or previous_status in ('active', 'inactive')),
  constraint partnership_status_history_status_check check (status in ('active', 'inactive')),
  constraint partnership_status_history_reason_check check (reason is null or char_length(btrim(reason)) between 2 and 500)
);

create index partnership_status_history_partnership_idx
  on public.partnership_status_history (partnership_id, changed_at desc, id desc);

create table public.patient_partnerships (
  id bigint generated always as identity primary key,
  patient_id bigint not null references public.patients(id) on delete restrict,
  partnership_id bigint not null references public.partnerships(id) on delete restrict,
  status text not null default 'active',
  linked_at timestamptz not null default now(),
  linked_by_type text not null,
  linked_by_user_id uuid references public.profiles(user_id) on delete restrict,
  linked_by_patient_id bigint references public.patients(id) on delete restrict,
  unlinked_at timestamptz,
  unlinked_by_type text,
  unlinked_by_user_id uuid references public.profiles(user_id) on delete restrict,
  unlinked_by_patient_id bigint references public.patients(id) on delete restrict,
  unlink_reason text,
  constraint patient_partnerships_status_check check (status in ('active', 'inactive')),
  constraint patient_partnerships_linked_origin_check check (
    (linked_by_type = 'professional' and linked_by_user_id is not null and linked_by_patient_id is null)
    or (linked_by_type = 'partnership_responsible' and linked_by_user_id is null and linked_by_patient_id is not null)
    or (linked_by_type = 'system' and linked_by_user_id is null and linked_by_patient_id is null)
  ),
  constraint patient_partnerships_unlinked_state_check check (
    (status = 'active' and unlinked_at is null and unlinked_by_type is null and unlinked_by_user_id is null and unlinked_by_patient_id is null and unlink_reason is null)
    or
    (status = 'inactive' and unlinked_at is not null and unlinked_by_type in ('professional', 'partnership_responsible', 'system') and char_length(btrim(unlink_reason)) between 2 and 500)
  ),
  constraint patient_partnerships_unlinked_origin_check check (
    unlinked_by_type is null
    or (unlinked_by_type = 'professional' and unlinked_by_user_id is not null and unlinked_by_patient_id is null)
    or (unlinked_by_type = 'partnership_responsible' and unlinked_by_user_id is null and unlinked_by_patient_id is not null)
    or (unlinked_by_type = 'system' and unlinked_by_user_id is null and unlinked_by_patient_id is null)
  )
);

create unique index patient_partnerships_active_unique_idx
  on public.patient_partnerships (partnership_id, patient_id)
  where status = 'active';
create index patient_partnerships_partnership_status_idx
  on public.patient_partnerships (partnership_id, status, linked_at desc, id desc);
create index patient_partnerships_patient_status_idx
  on public.patient_partnerships (patient_id, status, partnership_id);

create table public.partnership_pending_beneficiaries (
  id bigint generated always as identity primary key,
  partnership_id bigint not null references public.partnerships(id) on delete restrict,
  passport text not null,
  informed_name text not null,
  status text not null default 'pending_registration',
  created_at timestamptz not null default now(),
  source text not null,
  created_by_type text not null,
  created_by_user_id uuid references public.profiles(user_id) on delete restrict,
  created_by_patient_id bigint references public.patients(id) on delete restrict,
  resolved_at timestamptz,
  resolved_patient_id bigint references public.patients(id) on delete restrict,
  canceled_at timestamptz,
  canceled_by_type text,
  canceled_by_user_id uuid references public.profiles(user_id) on delete restrict,
  canceled_by_patient_id bigint references public.patients(id) on delete restrict,
  cancellation_reason text,
  constraint partnership_pending_passport_check check (passport ~ '^[0-9]{1,4}$'),
  constraint partnership_pending_name_check check (char_length(btrim(informed_name)) between 2 and 120),
  constraint partnership_pending_status_check check (status in ('pending_registration', 'name_review', 'resolved', 'canceled')),
  constraint partnership_pending_source_check check (source in ('individual', 'batch', 'automatic')),
  constraint partnership_pending_created_origin_check check (
    (created_by_type = 'professional' and created_by_user_id is not null and created_by_patient_id is null)
    or (created_by_type = 'partnership_responsible' and created_by_user_id is null and created_by_patient_id is not null)
    or (created_by_type = 'system' and created_by_user_id is null and created_by_patient_id is null)
  ),
  constraint partnership_pending_resolution_check check (
    (status in ('pending_registration', 'name_review') and resolved_at is null and resolved_patient_id is null and canceled_at is null and canceled_by_type is null and canceled_by_user_id is null and canceled_by_patient_id is null and cancellation_reason is null)
    or (status = 'resolved' and resolved_at is not null and resolved_patient_id is not null and canceled_at is null and canceled_by_type is null and canceled_by_user_id is null and canceled_by_patient_id is null and cancellation_reason is null)
    or (status = 'canceled' and resolved_at is null and resolved_patient_id is null and canceled_at is not null and canceled_by_type in ('professional', 'partnership_responsible', 'system') and char_length(btrim(cancellation_reason)) between 2 and 500)
  ),
  constraint partnership_pending_canceled_origin_check check (
    canceled_by_type is null
    or (canceled_by_type = 'professional' and canceled_by_user_id is not null and canceled_by_patient_id is null)
    or (canceled_by_type = 'partnership_responsible' and canceled_by_user_id is null and canceled_by_patient_id is not null)
    or (canceled_by_type = 'system' and canceled_by_user_id is null and canceled_by_patient_id is null)
  )
);

create unique index partnership_pending_open_unique_idx
  on public.partnership_pending_beneficiaries (partnership_id, passport)
  where status in ('pending_registration', 'name_review');
create index partnership_pending_partnership_status_idx
  on public.partnership_pending_beneficiaries (partnership_id, status, created_at desc, id desc);
create index partnership_pending_passport_status_idx
  on public.partnership_pending_beneficiaries (passport, status, partnership_id);

alter table public.partnerships enable row level security;
alter table public.partnerships force row level security;
alter table public.partnership_responsible_history enable row level security;
alter table public.partnership_responsible_history force row level security;
alter table public.partnership_status_history enable row level security;
alter table public.partnership_status_history force row level security;
alter table public.patient_partnerships enable row level security;
alter table public.patient_partnerships force row level security;
alter table public.partnership_pending_beneficiaries enable row level security;
alter table public.partnership_pending_beneficiaries force row level security;

revoke all on public.partnerships, public.partnership_responsible_history,
  public.partnership_status_history, public.patient_partnerships,
  public.partnership_pending_beneficiaries
from public, anon, authenticated, service_role;

revoke all on sequence public.partnerships_id_seq,
  public.partnership_responsible_history_id_seq,
  public.partnership_status_history_id_seq,
  public.patient_partnerships_id_seq,
  public.partnership_pending_beneficiaries_id_seq
from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Helpers privados
-- ---------------------------------------------------------------------------

create or replace function private.partnership_name_key(p_value text)
returns text
language sql
immutable
set search_path = ''
as $$
  select regexp_replace(
    lower(translate(btrim(coalesce(p_value, '')),
      'áàâãäéèêëíìîïóòôõöúùûüçñÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ',
      'aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN')),
    '[^a-z0-9]+', ' ', 'g'
  );
$$;

revoke all on function private.partnership_name_key(text)
from public, anon, authenticated, service_role;

create or replace function private.partnership_patient_can_use_portal(p_patient_id bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.patients patient
    where patient.id = p_patient_id
      and patient.birth_date is not null
      and patient.passport ~ '^[0-9]{1,4}$'
  );
$$;

revoke all on function private.partnership_patient_can_use_portal(bigint)
from public, anon, authenticated, service_role;

create or replace function private.partnership_audit(
  p_action text,
  p_entity_name text,
  p_entity_id text,
  p_origin text,
  p_actor_user_id uuid,
  p_actor_patient_id bigint,
  p_old_values jsonb,
  p_new_values jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_passport text;
begin
  if p_origin not in ('professional', 'partnership_responsible', 'system') then
    raise exception 'Origem de auditoria inválida.';
  end if;

  if p_origin = 'professional' then
    select profile.passport into v_passport
    from public.profiles profile where profile.user_id = p_actor_user_id;
  elsif p_origin = 'partnership_responsible' then
    select patient.passport into v_passport
    from public.patients patient where patient.id = p_actor_patient_id;
  end if;

  insert into public.audit_logs (
    actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values
  ) values (
    case when p_origin = 'professional' then p_actor_user_id else null end,
    v_passport,
    p_action,
    p_entity_name,
    p_entity_id,
    p_old_values,
    coalesce(p_new_values, '{}'::jsonb) || jsonb_build_object('origin', p_origin)
  );
end;
$$;

revoke all on function private.partnership_audit(text, text, text, text, uuid, bigint, jsonb, jsonb)
from public, anon, authenticated, service_role;

create or replace function private.partnership_assert_professional(p_permission text)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
begin
  if not private.has_permission(v_actor, p_permission) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  return v_actor;
end;
$$;

revoke all on function private.partnership_assert_professional(text)
from public, anon, authenticated, service_role;

create or replace function private.partnership_portal_actor(
  p_token_hash text,
  p_partnership_id bigint,
  p_require_active boolean default false
)
returns bigint
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_patient_id bigint;
  v_status text;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'Sessão do Portal inválida.' using errcode = '42501';
  end if;

  select session.patient_id, partnership.status
  into v_patient_id, v_status
  from private.patient_portal_session_record(p_token_hash) session
  join public.partnerships partnership
    on partnership.id = p_partnership_id
   and partnership.responsible_patient_id = session.patient_id;

  if not found then
    raise exception 'Parceria não localizada para esta sessão.' using errcode = '42501';
  end if;
  if p_require_active and v_status <> 'active' then
    raise exception 'Esta parceria está inativa e não permite alterações.' using errcode = '22023';
  end if;

  return v_patient_id;
end;
$$;

revoke all on function private.partnership_portal_actor(text, bigint, boolean)
from public, anon, authenticated, service_role;

create or replace function private.partnership_apply_people(
  p_partnership_id bigint,
  p_people jsonb,
  p_origin text,
  p_actor_user_id uuid,
  p_actor_patient_id bigint,
  p_source text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_partnership public.partnerships%rowtype;
  v_entry jsonb;
  v_patient public.patients%rowtype;
  v_membership_id bigint;
  v_pending_id bigint;
  v_passport text;
  v_name text;
  v_line integer := 0;
  v_result text;
  v_items jsonb := '[]'::jsonb;
  v_linked integer := 0;
  v_existing integer := 0;
  v_pending integer := 0;
  v_review integer := 0;
  v_invalid integer := 0;
begin
  select * into v_partnership
  from public.partnerships partnership
  where partnership.id = p_partnership_id
  for update;

  if not found then raise exception 'Parceria não localizada.' using errcode = '22023'; end if;
  if v_partnership.status <> 'active' then
    raise exception 'Esta parceria está inativa e não permite novas inclusões.' using errcode = '22023';
  end if;
  if p_origin not in ('professional', 'partnership_responsible') then
    raise exception 'Origem inválida.' using errcode = '22023';
  end if;
  if p_source not in ('individual', 'batch') then
    raise exception 'Origem da inclusão inválida.' using errcode = '22023';
  end if;
  if p_people is null or jsonb_typeof(p_people) <> 'array' or jsonb_array_length(p_people) < 1 or jsonb_array_length(p_people) > 500 then
    raise exception 'Informe entre 1 e 500 pessoas por operação.' using errcode = '22023';
  end if;

  for v_entry in select value from jsonb_array_elements(p_people)
  loop
    v_line := v_line + 1;
    v_passport := btrim(coalesce(v_entry ->> 'passport', ''));
    v_name := btrim(coalesce(v_entry ->> 'name', ''));
    v_membership_id := null;
    v_pending_id := null;

    if jsonb_typeof(v_entry) <> 'object'
       or v_passport !~ '^[0-9]{1,4}$'
       or char_length(v_name) not between 2 and 120 then
      v_result := 'invalid';
      v_invalid := v_invalid + 1;
    else
      select * into v_patient
      from public.patients patient
      where patient.passport = v_passport;

      if found and private.partnership_name_key(v_patient.name) = private.partnership_name_key(v_name) then
        insert into public.patient_partnerships (
          patient_id, partnership_id, linked_by_type, linked_by_user_id, linked_by_patient_id
        ) values (
          v_patient.id, p_partnership_id, p_origin, p_actor_user_id, p_actor_patient_id
        )
        on conflict (partnership_id, patient_id) where status = 'active' do nothing
        returning id into v_membership_id;

        update public.partnership_pending_beneficiaries pending_beneficiary
        set status = 'resolved', resolved_at = now(), resolved_patient_id = v_patient.id
        where pending_beneficiary.partnership_id = p_partnership_id
          and pending_beneficiary.passport = v_passport
          and pending_beneficiary.status in ('pending_registration', 'name_review');

        if v_membership_id is null then
          v_result := 'already_linked';
          v_existing := v_existing + 1;
        else
          v_result := 'linked';
          v_linked := v_linked + 1;
        end if;
      elsif found then
        insert into public.partnership_pending_beneficiaries (
          partnership_id, passport, informed_name, status, source,
          created_by_type, created_by_user_id, created_by_patient_id
        ) values (
          p_partnership_id, v_passport, v_name, 'name_review', p_source,
          p_origin, p_actor_user_id, p_actor_patient_id
        )
        on conflict (partnership_id, passport) where status in ('pending_registration', 'name_review')
        do update set informed_name = excluded.informed_name, status = 'name_review'
        returning id into v_pending_id;
        v_result := 'name_review';
        v_review := v_review + 1;
      else
        insert into public.partnership_pending_beneficiaries (
          partnership_id, passport, informed_name, status, source,
          created_by_type, created_by_user_id, created_by_patient_id
        ) values (
          p_partnership_id, v_passport, v_name, 'pending_registration', p_source,
          p_origin, p_actor_user_id, p_actor_patient_id
        )
        on conflict (partnership_id, passport) where status in ('pending_registration', 'name_review')
        do update set informed_name = excluded.informed_name
        returning id into v_pending_id;
        v_result := 'pending_registration';
        v_pending := v_pending + 1;
      end if;
    end if;

    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'line', v_line,
      'passport', v_passport,
      'name', v_name,
      'result', v_result
    ));
  end loop;

  perform private.partnership_audit(
    case when jsonb_array_length(p_people) = 1 then 'PARTNERSHIP_PERSON_ADDED' else 'PARTNERSHIP_BATCH_IMPORTED' end,
    'partnerships', p_partnership_id::text, p_origin, p_actor_user_id, p_actor_patient_id,
    null,
    jsonb_build_object(
      'partnership_name', v_partnership.name,
      'source', p_source,
      'total', jsonb_array_length(p_people),
      'linked', v_linked,
      'already_linked', v_existing,
      'pending_registration', v_pending,
      'name_review', v_review,
      'invalid', v_invalid
    )
  );

  return jsonb_build_object(
    'items', v_items,
    'summary', jsonb_build_object(
      'total', jsonb_array_length(p_people),
      'linked', v_linked,
      'already_linked', v_existing,
      'pending_registration', v_pending,
      'name_review', v_review,
      'invalid', v_invalid
    )
  );
end;
$$;

revoke all on function private.partnership_apply_people(bigint, jsonb, text, uuid, bigint, text)
from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- RPCs profissionais
-- ---------------------------------------------------------------------------

create or replace function public.hpsm_partnership_page(
  p_status text default 'active',
  p_search text default null,
  p_limit integer default 24,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.partnership_assert_professional('partnerships.view');
  v_status text := lower(btrim(coalesce(p_status, 'active')));
  v_search text := lower(btrim(coalesce(p_search, '')));
  v_limit integer := least(greatest(coalesce(p_limit, 24), 1), 50);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_result jsonb;
begin
  if v_status not in ('active', 'inactive') then raise exception 'Status de parceria inválido.' using errcode = '22023'; end if;

  with filtered as materialized (
    select partnership.*
    from public.partnerships partnership
    where partnership.status = v_status
      and (v_search = '' or lower(partnership.name) like '%' || v_search || '%')
  ), member_counts as materialized (
    select membership.partnership_id, count(*)::integer as linked
    from public.patient_partnerships membership
    join filtered partnership on partnership.id = membership.partnership_id
    where membership.status = 'active'
    group by membership.partnership_id
  ), pending_counts as materialized (
    select pending.partnership_id,
      count(*) filter (where pending.status = 'pending_registration')::integer as pending_registration,
      count(*) filter (where pending.status = 'name_review')::integer as name_review
    from public.partnership_pending_beneficiaries pending
    join filtered partnership on partnership.id = pending.partnership_id
    where pending.status in ('pending_registration', 'name_review')
    group by pending.partnership_id
  ), page_rows as (
    select partnership.*, patient.name as responsible_name, patient.passport as responsible_passport,
      coalesce(member_counts.linked, 0) as linked,
      coalesce(pending_counts.pending_registration, 0) as pending_registration,
      coalesce(pending_counts.name_review, 0) as name_review
    from filtered partnership
    left join public.patients patient on patient.id = partnership.responsible_patient_id
    left join member_counts on member_counts.partnership_id = partnership.id
    left join pending_counts on pending_counts.partnership_id = partnership.id
    order by lower(partnership.name), partnership.id
    limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'id', row.id,
      'name', row.name,
      'status', row.status,
      'responsible', case when row.responsible_patient_id is null then null else jsonb_build_object(
        'id', row.responsible_patient_id, 'name', row.responsible_name, 'passport', row.responsible_passport
      ) end,
      'linked', row.linked,
      'pending_registration', row.pending_registration,
      'name_review', row.name_review,
      'total_informed', row.linked + row.pending_registration + row.name_review,
      'created_at', row.created_at,
      'updated_at', row.updated_at
    ) order by lower(row.name), row.id), '[]'::jsonb),
    'total', (select count(*)::integer from filtered),
    'limit', v_limit,
    'offset', v_offset
  ) into v_result
  from page_rows row;
  return v_result;
end;
$$;

create or replace function public.hpsm_partnership_detail(p_partnership_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.partnership_assert_professional('partnerships.view');
  v_result jsonb;
begin
  select jsonb_build_object(
    'found', true,
    'partnership', jsonb_build_object(
      'id', partnership.id,
      'name', partnership.name,
      'status', partnership.status,
      'notes', partnership.notes,
      'responsible', case when patient.id is null then null else jsonb_build_object(
        'id', patient.id, 'name', patient.name, 'passport', patient.passport,
        'portal_ready', patient.birth_date is not null
      ) end,
      'created_at', partnership.created_at,
      'updated_at', partnership.updated_at,
      'deactivated_at', partnership.deactivated_at,
      'deactivation_reason', partnership.deactivation_reason
    ),
    'metrics', jsonb_build_object(
      'linked', (select count(*) from public.patient_partnerships membership where membership.partnership_id = partnership.id and membership.status = 'active'),
      'pending_registration', (select count(*) from public.partnership_pending_beneficiaries pending where pending.partnership_id = partnership.id and pending.status = 'pending_registration'),
      'name_review', (select count(*) from public.partnership_pending_beneficiaries pending where pending.partnership_id = partnership.id and pending.status = 'name_review')
    )
  ) into v_result
  from public.partnerships partnership
  left join public.patients patient on patient.id = partnership.responsible_patient_id
  where partnership.id = p_partnership_id;

  return coalesce(v_result, jsonb_build_object('found', false));
end;
$$;

create or replace function public.hpsm_partnership_member_page(
  p_partnership_id bigint,
  p_filter text default 'all',
  p_search text default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.partnership_assert_professional('partnerships.view');
  v_filter text := lower(btrim(coalesce(p_filter, 'all')));
  v_search text := lower(btrim(coalesce(p_search, '')));
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_result jsonb;
begin
  if v_filter not in ('all', 'linked', 'pending_registration', 'name_review') then
    raise exception 'Filtro de beneficiários inválido.' using errcode = '22023';
  end if;
  if not exists (select 1 from public.partnerships where id = p_partnership_id) then
    raise exception 'Parceria não localizada.' using errcode = '22023';
  end if;

  with combined as materialized (
    select
      'membership'::text as record_type,
      membership.id,
      patient.id as patient_id,
      patient.passport,
      patient.name,
      'linked'::text as status,
      membership.linked_at as occurred_at,
      membership.linked_by_type as origin,
      null::text as canonical_name
    from public.patient_partnerships membership
    join public.patients patient on patient.id = membership.patient_id
    where membership.partnership_id = p_partnership_id and membership.status = 'active'
    union all
    select
      'pending'::text,
      pending.id,
      canonical.id,
      pending.passport,
      pending.informed_name,
      pending.status,
      pending.created_at,
      pending.created_by_type,
      case when pending.status = 'name_review' then canonical.name else null end
    from public.partnership_pending_beneficiaries pending
    left join public.patients canonical on canonical.passport = pending.passport
    where pending.partnership_id = p_partnership_id
      and pending.status in ('pending_registration', 'name_review')
  ), filtered as (
    select * from combined row
    where (v_filter = 'all' or row.status = v_filter)
      and (v_search = '' or lower(row.name) like '%' || v_search || '%' or row.passport like v_search || '%')
  ), page_rows as (
    select * from filtered row
    order by lower(row.name), row.passport, row.record_type, row.id
    limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'record_type', row.record_type,
      'id', row.id,
      'patient_id', row.patient_id,
      'passport', row.passport,
      'name', row.name,
      'status', row.status,
      'occurred_at', row.occurred_at,
      'origin', row.origin,
      'canonical_name', row.canonical_name
    ) order by lower(row.name), row.passport, row.record_type, row.id), '[]'::jsonb),
    'total', (select count(*)::integer from filtered),
    'limit', v_limit,
    'offset', v_offset
  ) into v_result
  from page_rows row;
  return v_result;
end;
$$;

create or replace function public.hpsm_partnership_patient_lookup(p_search text, p_limit integer default 8)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.partnership_assert_professional('partnerships.manage');
  v_search text := lower(btrim(coalesce(p_search, '')));
  v_limit integer := least(greatest(coalesce(p_limit, 8), 1), 12);
  v_result jsonb;
begin
  if char_length(v_search) < 1 then return '[]'::jsonb; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', patient.id,
    'name', patient.name,
    'passport', patient.passport,
    'portal_ready', patient.birth_date is not null
  ) order by (patient.passport = v_search) desc, patient.passport, patient.name), '[]'::jsonb)
  into v_result
  from (
    select patient.*
    from public.patients patient
    where patient.passport like v_search || '%'
       or lower(patient.name) like '%' || v_search || '%'
    order by (patient.passport = v_search) desc, patient.passport, patient.name
    limit v_limit
  ) patient;
  return v_result;
end;
$$;

create or replace function public.create_partnership(p_name text, p_notes text default null, p_responsible_patient_id bigint default null)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.partnership_assert_professional('partnerships.manage');
  v_name text := btrim(coalesce(p_name, ''));
  v_notes text := nullif(btrim(coalesce(p_notes, '')), '');
  v_id bigint;
begin
  if char_length(v_name) not between 2 and 120 then raise exception 'Informe o nome da parceria.' using errcode = '22023'; end if;
  if v_notes is not null and char_length(v_notes) > 2000 then raise exception 'A observação pode ter até 2.000 caracteres.' using errcode = '22023'; end if;
  if p_responsible_patient_id is not null and not private.partnership_patient_can_use_portal(p_responsible_patient_id) then
    raise exception 'O responsável precisa ser um paciente cadastrado com data de nascimento válida para acessar o Portal.' using errcode = '22023';
  end if;

  insert into public.partnerships (
    name, notes, responsible_patient_id, responsible_assigned_at, responsible_assigned_by,
    created_by, updated_by
  ) values (
    v_name, v_notes, p_responsible_patient_id,
    case when p_responsible_patient_id is null then null else now() end,
    case when p_responsible_patient_id is null then null else v_actor end,
    v_actor, v_actor
  ) returning id into v_id;

  insert into public.partnership_status_history (partnership_id, previous_status, status, changed_by)
  values (v_id, null, 'active', v_actor);
  if p_responsible_patient_id is not null then
    insert into public.partnership_responsible_history (partnership_id, previous_patient_id, responsible_patient_id, changed_by)
    values (v_id, null, p_responsible_patient_id, v_actor);
  end if;
  perform private.partnership_audit('PARTNERSHIP_CREATED', 'partnerships', v_id::text, 'professional', v_actor, null, null,
    jsonb_build_object('name', v_name, 'responsible_patient_id', p_responsible_patient_id, 'status', 'active'));
  return v_id;
exception when unique_violation then
  raise exception 'Já existe uma parceria com este nome.' using errcode = '23505';
end;
$$;

create or replace function public.update_partnership(
  p_partnership_id bigint,
  p_name text,
  p_notes text default null,
  p_responsible_patient_id bigint default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.partnership_assert_professional('partnerships.manage');
  v_current public.partnerships%rowtype;
  v_name text := btrim(coalesce(p_name, ''));
  v_notes text := nullif(btrim(coalesce(p_notes, '')), '');
begin
  select * into v_current from public.partnerships where id = p_partnership_id for update;
  if not found then raise exception 'Parceria não localizada.' using errcode = '22023'; end if;
  if char_length(v_name) not between 2 and 120 then raise exception 'Informe o nome da parceria.' using errcode = '22023'; end if;
  if v_notes is not null and char_length(v_notes) > 2000 then raise exception 'A observação pode ter até 2.000 caracteres.' using errcode = '22023'; end if;
  if p_responsible_patient_id is not null and not private.partnership_patient_can_use_portal(p_responsible_patient_id) then
    raise exception 'O responsável precisa ser um paciente cadastrado com data de nascimento válida para acessar o Portal.' using errcode = '22023';
  end if;

  update public.partnerships set
    name = v_name,
    notes = v_notes,
    responsible_patient_id = p_responsible_patient_id,
    responsible_assigned_at = case
      when responsible_patient_id is distinct from p_responsible_patient_id and p_responsible_patient_id is not null then now()
      when p_responsible_patient_id is null then null
      else responsible_assigned_at end,
    responsible_assigned_by = case
      when responsible_patient_id is distinct from p_responsible_patient_id and p_responsible_patient_id is not null then v_actor
      when p_responsible_patient_id is null then null
      else responsible_assigned_by end,
    updated_at = now(),
    updated_by = v_actor
  where id = p_partnership_id;

  if v_current.responsible_patient_id is distinct from p_responsible_patient_id then
    insert into public.partnership_responsible_history (partnership_id, previous_patient_id, responsible_patient_id, changed_by)
    values (p_partnership_id, v_current.responsible_patient_id, p_responsible_patient_id, v_actor);
  end if;
  perform private.partnership_audit('PARTNERSHIP_UPDATED', 'partnerships', p_partnership_id::text, 'professional', v_actor, null,
    jsonb_build_object('name', v_current.name, 'responsible_patient_id', v_current.responsible_patient_id),
    jsonb_build_object('name', v_name, 'responsible_patient_id', p_responsible_patient_id));
  return true;
exception when unique_violation then
  raise exception 'Já existe uma parceria com este nome.' using errcode = '23505';
end;
$$;

create or replace function public.set_partnership_status(p_partnership_id bigint, p_status text, p_reason text default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.partnership_assert_professional('partnerships.manage');
  v_current public.partnerships%rowtype;
  v_status text := lower(btrim(coalesce(p_status, '')));
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if v_status not in ('active', 'inactive') then raise exception 'Status de parceria inválido.' using errcode = '22023'; end if;
  if v_status = 'inactive' and (v_reason is null or char_length(v_reason) not between 2 and 500) then
    raise exception 'Informe o motivo da inativação.' using errcode = '22023';
  end if;
  select * into v_current from public.partnerships where id = p_partnership_id for update;
  if not found then raise exception 'Parceria não localizada.' using errcode = '22023'; end if;
  if v_current.status = v_status then return true; end if;

  update public.partnerships set
    status = v_status,
    deactivated_at = case when v_status = 'inactive' then now() else null end,
    deactivated_by = case when v_status = 'inactive' then v_actor else null end,
    deactivation_reason = case when v_status = 'inactive' then v_reason else null end,
    updated_at = now(), updated_by = v_actor
  where id = p_partnership_id;
  insert into public.partnership_status_history (partnership_id, previous_status, status, reason, changed_by)
  values (p_partnership_id, v_current.status, v_status, v_reason, v_actor);
  perform private.partnership_audit(
    case when v_status = 'active' then 'PARTNERSHIP_REACTIVATED' else 'PARTNERSHIP_DEACTIVATED' end,
    'partnerships', p_partnership_id::text, 'professional', v_actor, null,
    jsonb_build_object('status', v_current.status), jsonb_build_object('status', v_status, 'reason', v_reason)
  );
  return true;
end;
$$;

create or replace function public.import_partnership_people(p_partnership_id bigint, p_people jsonb, p_source text default 'batch')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.partnership_assert_professional('partnerships.manage');
begin
  return private.partnership_apply_people(p_partnership_id, p_people, 'professional', v_actor, null, p_source);
end;
$$;

create or replace function public.unlink_patient_partnership(p_membership_id bigint, p_reason text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.partnership_assert_professional('partnerships.manage');
  v_membership public.patient_partnerships%rowtype;
  v_reason text := btrim(coalesce(p_reason, ''));
begin
  if char_length(v_reason) not between 2 and 500 then raise exception 'Informe o motivo da remoção.' using errcode = '22023'; end if;
  select * into v_membership from public.patient_partnerships where id = p_membership_id for update;
  if not found or v_membership.status <> 'active' then raise exception 'Vínculo ativo não localizado.' using errcode = '22023'; end if;
  update public.patient_partnerships set status = 'inactive', unlinked_at = now(),
    unlinked_by_type = 'professional', unlinked_by_user_id = v_actor, unlink_reason = v_reason
  where id = p_membership_id;
  perform private.partnership_audit('PARTNERSHIP_MEMBER_REMOVED', 'patient_partnerships', p_membership_id::text,
    'professional', v_actor, null, null,
    jsonb_build_object('partnership_id', v_membership.partnership_id, 'patient_id', v_membership.patient_id, 'reason', v_reason));
  return true;
end;
$$;

create or replace function public.cancel_partnership_pending(p_pending_id bigint, p_reason text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.partnership_assert_professional('partnerships.manage');
  v_pending public.partnership_pending_beneficiaries%rowtype;
  v_reason text := btrim(coalesce(p_reason, ''));
begin
  if char_length(v_reason) not between 2 and 500 then raise exception 'Informe o motivo do cancelamento.' using errcode = '22023'; end if;
  select * into v_pending from public.partnership_pending_beneficiaries where id = p_pending_id for update;
  if not found or v_pending.status not in ('pending_registration', 'name_review') then
    raise exception 'Pré-beneficiário pendente não localizado.' using errcode = '22023';
  end if;
  update public.partnership_pending_beneficiaries set status = 'canceled', canceled_at = now(),
    canceled_by_type = 'professional', canceled_by_user_id = v_actor, cancellation_reason = v_reason
  where id = p_pending_id;
  perform private.partnership_audit('PARTNERSHIP_PENDING_CANCELED', 'partnership_pending_beneficiaries', p_pending_id::text,
    'professional', v_actor, null, null,
    jsonb_build_object('partnership_id', v_pending.partnership_id, 'passport', v_pending.passport, 'reason', v_reason));
  return true;
end;
$$;

create or replace function public.review_partnership_pending(p_pending_id bigint, p_decision text, p_reason text default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.partnership_assert_professional('partnerships.manage');
  v_pending public.partnership_pending_beneficiaries%rowtype;
  v_patient public.patients%rowtype;
  v_decision text := lower(btrim(coalesce(p_decision, '')));
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if v_decision not in ('confirm', 'reject') then raise exception 'Decisão inválida.' using errcode = '22023'; end if;
  select * into v_pending from public.partnership_pending_beneficiaries where id = p_pending_id for update;
  if not found or v_pending.status <> 'name_review' then raise exception 'Revisão pendente não localizada.' using errcode = '22023'; end if;
  if v_decision = 'reject' then
    if v_reason is null or char_length(v_reason) not between 2 and 500 then raise exception 'Informe o motivo da rejeição.' using errcode = '22023'; end if;
    update public.partnership_pending_beneficiaries set status = 'canceled', canceled_at = now(),
      canceled_by_type = 'professional', canceled_by_user_id = v_actor, cancellation_reason = v_reason
    where id = p_pending_id;
    perform private.partnership_audit('PARTNERSHIP_NAME_REVIEW_REJECTED', 'partnership_pending_beneficiaries', p_pending_id::text,
      'professional', v_actor, null, null,
      jsonb_build_object('partnership_id', v_pending.partnership_id, 'passport', v_pending.passport, 'reason', v_reason));
    return true;
  end if;

  select * into v_patient from public.patients where passport = v_pending.passport;
  if not found then raise exception 'O paciente deste passaporte não está cadastrado.' using errcode = '22023'; end if;
  insert into public.patient_partnerships (patient_id, partnership_id, linked_by_type, linked_by_user_id)
  values (v_patient.id, v_pending.partnership_id, 'professional', v_actor)
  on conflict (partnership_id, patient_id) where status = 'active' do nothing;
  update public.partnership_pending_beneficiaries set status = 'resolved', resolved_at = now(), resolved_patient_id = v_patient.id
  where id = p_pending_id;
  perform private.partnership_audit('PARTNERSHIP_NAME_REVIEW_CONFIRMED', 'partnership_pending_beneficiaries', p_pending_id::text,
    'professional', v_actor, null, null,
    jsonb_build_object('partnership_id', v_pending.partnership_id, 'patient_id', v_patient.id, 'passport', v_pending.passport));
  return true;
end;
$$;

create or replace function public.patient_partnership_page(p_patient_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.partnership_assert_professional('patients.view');
  v_result jsonb;
begin
  if not exists (select 1 from public.patients where id = p_patient_id) then
    raise exception 'Paciente não localizado.' using errcode = '22023';
  end if;
  select jsonb_build_object(
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'id', partnership.id,
      'name', partnership.name,
      'status', partnership.status,
      'linked_at', membership.linked_at
    ) order by (partnership.status = 'active') desc, lower(partnership.name)), '[]'::jsonb)
  ) into v_result
  from public.patient_partnerships membership
  join public.partnerships partnership on partnership.id = membership.partnership_id
  where membership.patient_id = p_patient_id and membership.status = 'active';
  return v_result;
end;
$$;

-- ---------------------------------------------------------------------------
-- Portal do Paciente: leitura mínima e mutations de composição
-- ---------------------------------------------------------------------------

create or replace function public.patient_portal_partnership_page(p_token_hash text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_session record;
  v_result jsonb;
begin
  select * into v_session from private.patient_portal_session_record(p_token_hash);
  if not found then return jsonb_build_object('authenticated', false); end if;

  with responsible as materialized (
    select partnership.*
    from public.partnerships partnership
    where partnership.responsible_patient_id = v_session.patient_id
  ), member_counts as materialized (
    select membership.partnership_id, count(*)::integer as linked
    from public.patient_partnerships membership
    join responsible partnership on partnership.id = membership.partnership_id
    where membership.status = 'active'
    group by membership.partnership_id
  ), pending_counts as materialized (
    select pending.partnership_id,
      count(*) filter (where pending.status = 'pending_registration')::integer as pending_registration,
      count(*) filter (where pending.status = 'name_review')::integer as name_review
    from public.partnership_pending_beneficiaries pending
    join responsible partnership on partnership.id = pending.partnership_id
    where pending.status in ('pending_registration', 'name_review')
    group by pending.partnership_id
  )
  select jsonb_build_object(
    'authenticated', true,
    'patient', jsonb_build_object('name', v_session.patient_name, 'passport', v_session.patient_passport),
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'id', partnership.id,
      'name', partnership.name,
      'status', partnership.status,
      'linked', coalesce(member_counts.linked, 0),
      'pending_registration', coalesce(pending_counts.pending_registration, 0),
      'name_review', coalesce(pending_counts.name_review, 0),
      'total_informed', coalesce(member_counts.linked, 0) + coalesce(pending_counts.pending_registration, 0) + coalesce(pending_counts.name_review, 0)
    ) order by (partnership.status = 'active') desc, lower(partnership.name)), '[]'::jsonb)
  ) into v_result
  from responsible partnership
  left join member_counts on member_counts.partnership_id = partnership.id
  left join pending_counts on pending_counts.partnership_id = partnership.id;
  return v_result;
end;
$$;

create or replace function public.patient_portal_partnership_member_page(
  p_token_hash text,
  p_partnership_id bigint,
  p_filter text default 'all',
  p_search text default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor_patient_id bigint := private.partnership_portal_actor(p_token_hash, p_partnership_id, false);
  v_filter text := lower(btrim(coalesce(p_filter, 'all')));
  v_search text := lower(btrim(coalesce(p_search, '')));
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_result jsonb;
  v_partnership public.partnerships%rowtype;
  v_patient public.patients%rowtype;
begin
  if v_filter not in ('all', 'linked', 'pending_registration', 'name_review') then
    raise exception 'Filtro inválido.' using errcode = '22023';
  end if;
  select * into v_partnership from public.partnerships where id = p_partnership_id;
  select * into v_patient from public.patients where id = v_actor_patient_id;

  with combined as materialized (
    select 'membership'::text as record_type, membership.id, patient.passport, patient.name,
      'linked'::text as status, membership.linked_at as occurred_at
    from public.patient_partnerships membership
    join public.patients patient on patient.id = membership.patient_id
    where membership.partnership_id = p_partnership_id and membership.status = 'active'
    union all
    select 'pending'::text, pending.id, pending.passport, pending.informed_name,
      pending.status, pending.created_at
    from public.partnership_pending_beneficiaries pending
    where pending.partnership_id = p_partnership_id and pending.status in ('pending_registration', 'name_review')
  ), filtered as (
    select * from combined row
    where (v_filter = 'all' or row.status = v_filter)
      and (v_search = '' or lower(row.name) like '%' || v_search || '%' or row.passport like v_search || '%')
  ), page_rows as (
    select * from filtered row order by lower(row.name), row.passport, row.record_type, row.id
    limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'authenticated', true,
    'patient', jsonb_build_object('name', v_patient.name, 'passport', v_patient.passport),
    'partnership', jsonb_build_object('id', v_partnership.id, 'name', v_partnership.name, 'status', v_partnership.status),
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'record_key', case when row.record_type = 'membership' then 'm:' else 'p:' end || row.id::text,
      'name', row.name,
      'passport', row.passport,
      'status', row.status,
      'occurred_at', row.occurred_at
    ) order by lower(row.name), row.passport, row.record_type, row.id), '[]'::jsonb),
    'total', (select count(*)::integer from filtered),
    'limit', v_limit,
    'offset', v_offset
  ) into v_result
  from page_rows row;
  return v_result;
end;
$$;

create or replace function public.patient_portal_import_partnership_people(
  p_token_hash text,
  p_partnership_id bigint,
  p_people jsonb,
  p_source text default 'batch'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_patient_id bigint := private.partnership_portal_actor(p_token_hash, p_partnership_id, true);
begin
  return private.partnership_apply_people(p_partnership_id, p_people, 'partnership_responsible', null, v_actor_patient_id, p_source);
end;
$$;

create or replace function public.patient_portal_unlink_partnership_member(
  p_token_hash text,
  p_partnership_id bigint,
  p_record_key text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_patient_id bigint := private.partnership_portal_actor(p_token_hash, p_partnership_id, true);
  v_membership public.patient_partnerships%rowtype;
  v_id bigint;
begin
  if p_record_key !~ '^m:[0-9]+$' then raise exception 'Beneficiário inválido.' using errcode = '22023'; end if;
  v_id := substring(p_record_key from 3)::bigint;
  select * into v_membership from public.patient_partnerships
  where id = v_id and partnership_id = p_partnership_id for update;
  if not found or v_membership.status <> 'active' then raise exception 'Beneficiário ativo não localizado.' using errcode = '22023'; end if;
  update public.patient_partnerships set status = 'inactive', unlinked_at = now(),
    unlinked_by_type = 'partnership_responsible', unlinked_by_patient_id = v_actor_patient_id,
    unlink_reason = 'Removido pelo responsável da parceria.'
  where id = v_id;
  perform private.partnership_audit('PARTNERSHIP_MEMBER_REMOVED', 'patient_partnerships', v_id::text,
    'partnership_responsible', null, v_actor_patient_id, null,
    jsonb_build_object('partnership_id', p_partnership_id, 'patient_id', v_membership.patient_id));
  return true;
end;
$$;

create or replace function public.patient_portal_cancel_partnership_pending(
  p_token_hash text,
  p_partnership_id bigint,
  p_record_key text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_patient_id bigint := private.partnership_portal_actor(p_token_hash, p_partnership_id, true);
  v_pending public.partnership_pending_beneficiaries%rowtype;
  v_id bigint;
begin
  if p_record_key !~ '^p:[0-9]+$' then raise exception 'Pré-beneficiário inválido.' using errcode = '22023'; end if;
  v_id := substring(p_record_key from 3)::bigint;
  select * into v_pending from public.partnership_pending_beneficiaries
  where id = v_id and partnership_id = p_partnership_id for update;
  if not found or v_pending.status not in ('pending_registration', 'name_review') then
    raise exception 'Pré-beneficiário pendente não localizado.' using errcode = '22023';
  end if;
  update public.partnership_pending_beneficiaries set status = 'canceled', canceled_at = now(),
    canceled_by_type = 'partnership_responsible', canceled_by_patient_id = v_actor_patient_id,
    cancellation_reason = 'Cancelado pelo responsável da parceria.'
  where id = v_id;
  perform private.partnership_audit('PARTNERSHIP_PENDING_CANCELED', 'partnership_pending_beneficiaries', v_id::text,
    'partnership_responsible', null, v_actor_patient_id, null,
    jsonb_build_object('partnership_id', p_partnership_id, 'passport', v_pending.passport));
  return true;
end;
$$;

-- A sessão existente passa a informar somente se há alguma responsabilidade atual.
create or replace function public.patient_portal_session_me(p_token_hash text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_session record;
begin
  select * into v_session from private.patient_portal_session_record(p_token_hash);
  if not found then return jsonb_build_object('authenticated', false); end if;
  return jsonb_build_object(
    'authenticated', true,
    'name', v_session.patient_name,
    'passport', v_session.patient_passport,
    'expires_at', v_session.expires_at,
    'manages_partnerships', exists (
      select 1 from public.partnerships partnership
      where partnership.responsible_patient_id = v_session.patient_id
    )
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Resolução automática de pré-beneficiários em todos os cadastros canônicos
-- ---------------------------------------------------------------------------

create or replace function private.resolve_partnership_pending_for_patient()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pending record;
  v_membership_id bigint;
begin
  for v_pending in
    select pending.*
    from public.partnership_pending_beneficiaries pending
    where pending.passport = new.passport
      and pending.status = 'pending_registration'
    order by pending.id
    for update
  loop
    if private.partnership_name_key(v_pending.informed_name) <> private.partnership_name_key(new.name) then
      update public.partnership_pending_beneficiaries set status = 'name_review'
      where id = v_pending.id;
      perform private.partnership_audit('PARTNERSHIP_PENDING_NAME_REVIEW_REQUIRED', 'partnership_pending_beneficiaries', v_pending.id::text,
        'system', null, null, null,
        jsonb_build_object('partnership_id', v_pending.partnership_id, 'passport', new.passport));
      continue;
    end if;

    insert into public.patient_partnerships (patient_id, partnership_id, linked_by_type)
    values (new.id, v_pending.partnership_id, 'system')
    on conflict (partnership_id, patient_id) where status = 'active' do nothing
    returning id into v_membership_id;
    update public.partnership_pending_beneficiaries
    set status = 'resolved', resolved_at = now(), resolved_patient_id = new.id
    where id = v_pending.id;
    perform private.partnership_audit('PARTNERSHIP_PENDING_RESOLVED', 'partnership_pending_beneficiaries', v_pending.id::text,
      'system', null, null, null,
      jsonb_build_object('partnership_id', v_pending.partnership_id, 'patient_id', new.id, 'passport', new.passport));
  end loop;
  return new;
end;
$$;

revoke all on function private.resolve_partnership_pending_for_patient()
from public, anon, authenticated, service_role;

create trigger patients_resolve_partnership_pending
after insert on public.patients
for each row execute function private.resolve_partnership_pending_for_patient();

-- ---------------------------------------------------------------------------
-- Atendimento: elegibilidade e snapshot da parceria utilizada
-- ---------------------------------------------------------------------------

alter table public.attendances
  add column partnership_id bigint references public.partnerships(id) on delete restrict,
  add column partnership_name text;

alter table public.attendances
  add constraint attendances_partnership_snapshot_check check (
    (plan_code = 'parceiros_hp' and (
      (partnership_id is null and partnership_name is null)
      or (partnership_id is not null and char_length(btrim(partnership_name)) between 2 and 120)
    ))
    or (plan_code is distinct from 'parceiros_hp' and partnership_id is null and partnership_name is null)
  );

create index attendances_partnership_completed_idx
  on public.attendances (partnership_id, created_at desc, id desc)
  where status = 'completed' and partnership_id is not null;

drop function if exists public.create_attendance(bigint, jsonb, text, text);
drop function if exists private.create_attendance(bigint, jsonb, text, text);

create function private.create_attendance(
  p_patient_id bigint,
  p_items jsonb,
  p_notes text default null,
  p_benefit_code text default null,
  p_partnership_id bigint default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attendance_id bigint;
  v_discount numeric(18, 2);
  v_input_count integer;
  v_patient_name text;
  v_patient_passport text;
  v_plan_code text;
  v_plan_name text;
  v_partnership_name text;
  v_subtotal numeric(18, 2);
  v_valid_count integer;
  v_priced_items jsonb;
begin
  perform private.hpsm_current_actor();
  if not private.has_permission((select auth.uid()), 'attendances.create') then
    raise exception 'Você não possui permissão para registrar atendimentos.';
  end if;

  if p_patient_id is null then
    v_patient_name := 'Venda avulsa';
    v_patient_passport := '—';
  else
    select patient.name, patient.passport into v_patient_name, v_patient_passport
    from public.patients patient where patient.id = p_patient_id;
    if not found then raise exception 'Paciente não localizado.'; end if;
  end if;

  v_plan_code := nullif(btrim(coalesce(p_benefit_code, '')), '');
  if v_plan_code is not null then
    select plan.name into v_plan_name from public.benefit_plans plan where plan.code = v_plan_code;
    if not found then raise exception 'Benefício inválido ou indisponível.'; end if;
  end if;

  if v_plan_code = 'parceiros_hp' then
    if p_patient_id is null or p_partnership_id is null then
      raise exception 'Selecione a parceria responsável por este benefício.' using errcode = '22023';
    end if;
    select partnership.name into v_partnership_name
    from public.partnerships partnership
    join public.patient_partnerships membership
      on membership.partnership_id = partnership.id
     and membership.patient_id = p_patient_id
     and membership.status = 'active'
    where partnership.id = p_partnership_id and partnership.status = 'active';
    if not found then
      raise exception 'O paciente não possui vínculo ativo com a parceria selecionada.' using errcode = '22023';
    end if;
  elsif p_partnership_id is not null then
    raise exception 'A parceria só pode ser informada com o benefício Parceiro do HP.' using errcode = '22023';
  end if;

  if p_notes is not null and char_length(p_notes) > 1000 then raise exception 'Observação muito longa.'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then raise exception 'Inclua ao menos um item.'; end if;
  v_input_count := jsonb_array_length(p_items);
  if v_input_count < 1 or v_input_count > 50 then raise exception 'Quantidade de itens inválida.'; end if;
  if exists (select 1 from jsonb_to_recordset(p_items) item(service_id bigint, quantity integer) group by service_id having count(*) <> 1) then
    raise exception 'Cada item deve aparecer apenas uma vez.';
  end if;
  if exists (
    select 1 from jsonb_to_recordset(p_items) item(service_id bigint, quantity integer)
    join public.service_catalog catalog on catalog.id = item.service_id
    where catalog.code = 'plano_saude_convenio' and item.quantity <> 1
  ) then raise exception 'O plano de saúde pode aparecer somente uma vez no atendimento.'; end if;
  if p_patient_id is null and exists (
    select 1 from jsonb_to_recordset(p_items) item(service_id bigint, quantity integer)
    join public.service_catalog catalog on catalog.id = item.service_id
    where lower(btrim(catalog.category)) not in ('insumos', 'medicamentos')
  ) then raise exception 'Venda avulsa aceita somente insumos e medicamentos.'; end if;
  if not private.has_permission((select auth.uid()), 'catalog.view')
     or (p_patient_id is not null and not private.has_permission((select auth.uid()), 'patients.view')) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  perform 1 from public.service_catalog where id in (
    select service_id from jsonb_to_recordset(p_items) item(service_id bigint, quantity integer)
  ) for share;
  perform 1 from public.plan_discounts where plan_code = v_plan_code and service_id in (
    select service_id from jsonb_to_recordset(p_items) item(service_id bigint, quantity integer)
  ) for share;
  with input_items as (
    select service_id, quantity from jsonb_to_recordset(p_items) item(service_id bigint, quantity integer)
  )
  select count(*), coalesce(sum(catalog.unit_price * input_items.quantity), 0),
    coalesce(sum(round(catalog.unit_price * input_items.quantity * coalesce(discount.discount_percent, 0) / 100, 2)), 0),
    coalesce(jsonb_agg(jsonb_build_object(
      'service_id', catalog.id, 'service_name', catalog.name, 'unit_price', catalog.unit_price,
      'quantity', input_items.quantity, 'discount_percent', coalesce(discount.discount_percent, 0)
    )), '[]'::jsonb)
  into v_valid_count, v_subtotal, v_discount, v_priced_items
  from input_items
  join public.service_catalog catalog on catalog.id = input_items.service_id and catalog.active
  left join public.plan_discounts discount on discount.service_id = catalog.id and discount.plan_code = v_plan_code
  where input_items.quantity between 1 and 99;
  if v_valid_count <> v_input_count then raise exception 'Um dos itens não está disponível.'; end if;

  insert into public.attendances (
    patient_id, patient_name, patient_passport, plan_code, plan_name, partnership_id, partnership_name,
    subtotal, discount, notes, performed_by
  ) values (
    p_patient_id, v_patient_name, v_patient_passport, v_plan_code, v_plan_name, p_partnership_id, v_partnership_name,
    v_subtotal, v_discount, nullif(btrim(coalesce(p_notes, '')), ''), (select auth.uid())
  ) returning id into v_attendance_id;

  insert into public.attendance_items (attendance_id, service_id, service_name, unit_price, quantity, discount_percent)
  select v_attendance_id, priced.service_id, priced.service_name, priced.unit_price, priced.quantity, priced.discount_percent
  from jsonb_to_recordset(v_priced_items) priced(
    service_id bigint, service_name text, unit_price numeric, quantity smallint, discount_percent numeric
  );
  return v_attendance_id;
end;
$$;

create function public.create_attendance(
  p_patient_id bigint,
  p_items jsonb,
  p_notes text default null,
  p_benefit_code text default null,
  p_partnership_id bigint default null
)
returns bigint
language sql
security invoker
set search_path = ''
as $$
  select private.create_attendance(p_patient_id, p_items, p_notes, p_benefit_code, p_partnership_id);
$$;

revoke all on function private.create_attendance(bigint, jsonb, text, text, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.create_attendance(bigint, jsonb, text, text, bigint)
from public, anon, authenticated, service_role;
grant execute on function public.create_attendance(bigint, jsonb, text, text, bigint) to authenticated;
grant execute on function private.create_attendance(bigint, jsonb, text, text, bigint) to authenticated, service_role;
grant execute on function public.create_attendance(bigint, jsonb, text, text, bigint) to service_role;

-- Busca operacional inclui apenas vínculos ativos de parcerias ativas.
create or replace function public.hpsm_patient_quick_lookup(p_passport text, p_limit integer default 8)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_permissions text[] := public.effective_permission_codes(v_actor);
  v_passport text := btrim(coalesce(p_passport, ''));
  v_limit integer := least(greatest(coalesce(p_limit, 8), 1), 8);
  v_result jsonb;
begin
  if not ('patients.view' = any(v_permissions)) then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if v_passport !~ '^[0-9]{1,4}$' then raise exception 'Informe um passaporte válido.' using errcode = '22023'; end if;

  with matching as materialized (
    select patient.id, patient.passport, patient.name, patient.phone, patient.birth_date,
      patient.emergency_contact_name, patient.emergency_contact_phone, patient.created_at, patient.updated_at
    from public.patients patient where patient.passport like v_passport || '%'
    order by (patient.passport = v_passport) desc, patient.passport limit v_limit
  ), plan_states as materialized (
    select matching.id as patient_id,
      case when approved.coverage_end > now() then 'active' when approved.id is not null then 'expired'
        when pending.id is not null then 'awaiting_confirmation' else 'none' end as status,
      approved.coverage_start as activated_at, approved.coverage_end as valid_until,
      approved.reviewed_by as authorized_by, reviewer.display_name as authorized_by_name,
      pending.id as pending_request_id, pending.requested_at as pending_requested_at
    from matching
    left join lateral (
      select request.id, request.coverage_start, request.coverage_end, request.reviewed_by
      from public.patient_health_plan_requests request
      where request.patient_id = matching.id and request.status = 'approved'
      order by request.coverage_end desc, request.id desc limit 1
    ) approved on true
    left join public.profiles reviewer on reviewer.user_id = approved.reviewed_by
    left join lateral (
      select request.id, request.requested_at from public.patient_health_plan_requests request
      where request.patient_id = matching.id and request.status = 'pending'
      order by request.requested_at, request.id limit 1
    ) pending on true
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', matching.id, 'passport', matching.passport, 'name', matching.name, 'phone', matching.phone,
    'birth_date', matching.birth_date, 'emergency_contact_name', matching.emergency_contact_name,
    'emergency_contact_phone', matching.emergency_contact_phone, 'created_at', matching.created_at,
    'updated_at', matching.updated_at,
    'health_plan', jsonb_build_object(
      'status', plan_states.status, 'activated_at', plan_states.activated_at, 'valid_until', plan_states.valid_until,
      'authorized_by', plan_states.authorized_by, 'authorized_by_name', plan_states.authorized_by_name,
      'pending_request_id', plan_states.pending_request_id, 'pending_requested_at', plan_states.pending_requested_at
    ),
    'partnerships', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', partnership.id, 'name', partnership.name, 'status', partnership.status, 'linked_at', membership.linked_at
      ) order by lower(partnership.name))
      from public.patient_partnerships membership
      join public.partnerships partnership on partnership.id = membership.partnership_id and partnership.status = 'active'
      where membership.patient_id = matching.id and membership.status = 'active'
    ), '[]'::jsonb)
  ) order by (matching.passport = v_passport) desc, matching.passport), '[]'::jsonb)
  into v_result from matching join plan_states on plan_states.patient_id = matching.id;
  return v_result;
end;
$$;

revoke all on function public.hpsm_patient_quick_lookup(text, integer)
from public, anon, authenticated, service_role;
grant execute on function public.hpsm_patient_quick_lookup(text, integer) to authenticated;

-- Histórico profissional expõe o snapshot da parceria, inclusive após remoção.
create or replace function public.hpsm_attendance_history_page(
  p_limit integer default 20,
  p_offset integer default 0,
  p_focus_id bigint default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_permissions text[] := public.effective_permission_codes(v_actor);
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_focus_created_at timestamptz;
  v_rows_before integer;
  v_result jsonb;
begin
  if not ('attendances.create' = any(v_permissions) or 'attendances.manage' = any(v_permissions) or 'patients.view' = any(v_permissions)) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if p_focus_id is not null then
    select target.created_at into v_focus_created_at from public.attendances target
    where target.id = p_focus_id and (target.performed_by = v_actor or 'attendances.manage' = any(v_permissions) or 'patients.view' = any(v_permissions));
    if found then
      select count(*)::integer into v_rows_before from public.attendances source
      where (source.performed_by = v_actor or 'attendances.manage' = any(v_permissions) or 'patients.view' = any(v_permissions))
        and (source.created_at, source.id) > (v_focus_created_at, p_focus_id);
      v_offset := (v_rows_before / v_limit) * v_limit;
    end if;
  end if;
  with visible as materialized (
    select source.* from public.attendances source
    where source.performed_by = v_actor or 'attendances.manage' = any(v_permissions) or 'patients.view' = any(v_permissions)
  ), page_rows as (
    select source.* from visible source order by source.created_at desc, source.id desc limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'id', attendance.id, 'patient_id', attendance.patient_id, 'patient_name', attendance.patient_name,
      'patient_passport', attendance.patient_passport, 'plan_code', attendance.plan_code,
      'plan_name', attendance.plan_name, 'partnership_id', attendance.partnership_id,
      'partnership_name', attendance.partnership_name, 'status', attendance.status,
      'subtotal', attendance.subtotal, 'discount', attendance.discount, 'total', attendance.total,
      'notes', attendance.notes, 'performed_by', attendance.performed_by, 'created_at', attendance.created_at,
      'professional_name', coalesce(profile.display_name, 'Profissional'),
      'professional_passport', coalesce(profile.passport, '—'),
      'professional_position', coalesce(position.name, 'Cargo não definido'),
      'attendance_items', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', item.id, 'service_id', item.service_id, 'service_name', item.service_name,
        'unit_price', item.unit_price, 'quantity', item.quantity, 'discount_percent', item.discount_percent,
        'discount_amount', item.discount_amount, 'line_total', item.line_total
      ) order by item.id), '[]'::jsonb) from public.attendance_items item where item.attendance_id = attendance.id)
    ) order by attendance.created_at desc, attendance.id desc) filter (where attendance.id is not null), '[]'::jsonb),
    'total', (select count(*) from visible), 'page', floor(v_offset::numeric / v_limit)::integer + 1, 'pageSize', v_limit
  ) into v_result
  from page_rows attendance
  left join public.profiles profile on profile.user_id = attendance.performed_by
  left join public.staff_positions position on position.id = profile.position_id;
  return v_result;
end;
$$;

revoke all on function public.hpsm_attendance_history_page(integer, integer, bigint)
from public, anon, authenticated, service_role;
grant execute on function public.hpsm_attendance_history_page(integer, integer, bigint) to authenticated;

-- Relatório financeiro agrega o snapshot do Parceiro do HP por organização.
create or replace function public.hpsm_report_partnerships(p_start_date date, p_end_date date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_result jsonb;
begin
  if not private.has_permission(v_actor, 'hr.reports.view') or not private.has_permission(v_actor, 'attendances.manage') then
    raise exception 'Acesso financeiro não autorizado.' using errcode = '42501';
  end if;
  perform private.hpsm_report_validate_period(p_start_date, p_end_date);
  select coalesce(jsonb_agg(jsonb_build_object(
    'partnership_id', source.partnership_id,
    'name', source.partnership_name,
    'attendance_count', source.attendance_count,
    'total_amount', source.total_amount,
    'discount_amount', source.discount_amount
  ) order by source.attendance_count desc, source.partnership_name), '[]'::jsonb)
  into v_result
  from (
    select attendance.partnership_id,
      coalesce(attendance.partnership_name, 'Parceria não registrada') as partnership_name,
      count(*)::integer as attendance_count,
      coalesce(sum(attendance.total), 0) as total_amount,
      coalesce(sum(attendance.discount), 0) as discount_amount
    from public.attendances attendance
    where attendance.status = 'completed'
      and attendance.plan_code = 'parceiros_hp'
      and attendance.created_at >= (p_start_date::timestamp at time zone 'America/Sao_Paulo')
      and attendance.created_at < ((p_end_date + 1)::timestamp at time zone 'America/Sao_Paulo')
    group by attendance.partnership_id, attendance.partnership_name
  ) source;
  return v_result;
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants explícitos de RPC
-- ---------------------------------------------------------------------------

revoke all on function public.hpsm_partnership_page(text, text, integer, integer),
  public.hpsm_partnership_detail(bigint),
  public.hpsm_partnership_member_page(bigint, text, text, integer, integer),
  public.hpsm_partnership_patient_lookup(text, integer),
  public.create_partnership(text, text, bigint),
  public.update_partnership(bigint, text, text, bigint),
  public.set_partnership_status(bigint, text, text),
  public.import_partnership_people(bigint, jsonb, text),
  public.unlink_patient_partnership(bigint, text),
  public.cancel_partnership_pending(bigint, text),
  public.review_partnership_pending(bigint, text, text),
  public.patient_partnership_page(bigint),
  public.hpsm_report_partnerships(date, date)
from public, anon, authenticated, service_role;

grant execute on function public.hpsm_partnership_page(text, text, integer, integer),
  public.hpsm_partnership_detail(bigint),
  public.hpsm_partnership_member_page(bigint, text, text, integer, integer),
  public.hpsm_partnership_patient_lookup(text, integer),
  public.create_partnership(text, text, bigint),
  public.update_partnership(bigint, text, text, bigint),
  public.set_partnership_status(bigint, text, text),
  public.import_partnership_people(bigint, jsonb, text),
  public.unlink_patient_partnership(bigint, text),
  public.cancel_partnership_pending(bigint, text),
  public.review_partnership_pending(bigint, text, text),
  public.patient_partnership_page(bigint),
  public.hpsm_report_partnerships(date, date)
to authenticated;

revoke all on function public.patient_portal_partnership_page(text),
  public.patient_portal_partnership_member_page(text, bigint, text, text, integer, integer),
  public.patient_portal_import_partnership_people(text, bigint, jsonb, text),
  public.patient_portal_unlink_partnership_member(text, bigint, text),
  public.patient_portal_cancel_partnership_pending(text, bigint, text),
  public.patient_portal_session_me(text)
from public, anon, authenticated, service_role;

grant execute on function public.patient_portal_partnership_page(text),
  public.patient_portal_partnership_member_page(text, bigint, text, text, integer, integer),
  public.patient_portal_import_partnership_people(text, bigint, jsonb, text),
  public.patient_portal_unlink_partnership_member(text, bigint, text),
  public.patient_portal_cancel_partnership_pending(text, bigint, text),
  public.patient_portal_session_me(text)
to service_role;

comment on table public.partnerships is 'Organizações conveniadas ao HPSM; inativação preserva vínculos e histórico.';
comment on table public.patient_partnerships is 'Vínculos temporais entre pacientes canônicos e parcerias.';
comment on table public.partnership_pending_beneficiaries is 'Pessoas informadas por passaporte que ainda aguardam cadastro ou revisão interna.';
comment on function public.patient_portal_partnership_page(text) is 'Lista somente parcerias atualmente administradas pelo paciente da sessão opaca.';
comment on function public.patient_portal_partnership_member_page(text, bigint, text, text, integer, integer) is 'Lista mínima paginada da parceria após validar a responsabilidade atual em cada chamada.';
