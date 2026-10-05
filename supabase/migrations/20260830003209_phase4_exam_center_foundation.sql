-- HPSM · Fase 4.1 · Fundação da Central de Exames
-- Atendimento financeiro e exame clínico permanecem domínios independentes.

-- ---------------------------------------------------------------------------
-- Permissões granulares
-- ---------------------------------------------------------------------------

insert into public.system_permissions (code, module, label, description, sort_order) values
  ('exams.view', 'Exames', 'Visualizar exames', 'Consulta a Central de Exames e seus registros clínicos.', 20),
  ('exams.create', 'Exames', 'Solicitar exames', 'Cria solicitações clínicas vinculadas a pacientes reais.', 21),
  ('exams.perform', 'Exames', 'Executar exames', 'Inicia, preenche e envia exames para revisão.', 22),
  ('exams.review', 'Exames', 'Revisar exames', 'Aprova, conclui ou devolve exames para correção.', 23),
  ('exams.catalog.manage', 'Exames', 'Gerenciar catálogo de exames', 'Administra categorias e tipos de exame sem apagar histórico.', 24)
on conflict (code) do update set
  module = excluded.module,
  label = excluded.label,
  description = excluded.description,
  sort_order = excluded.sort_order;

with grants(permission_code, min_level) as (
  values
    ('exams.view', 1),
    ('exams.create', 1),
    ('exams.perform', 1),
    ('exams.review', 11),
    ('exams.catalog.manage', 13)
)
insert into public.staff_position_permissions (position_id, permission_code, granted_by)
select
  position.id,
  grant_row.permission_code,
  coalesce(
    (select profile.user_id from public.profiles profile where profile.role_code = 'diretor_geral' limit 1),
    position.updated_by,
    position.created_by
  )
from public.staff_positions position
join grants grant_row on position.level >= grant_row.min_level
where position.official
on conflict (position_id, permission_code) do nothing;

-- ---------------------------------------------------------------------------
-- Catálogo configurável e registro clínico
-- ---------------------------------------------------------------------------

create table public.exam_categories (
  id bigint generated always as identity primary key,
  code text not null unique,
  name text not null,
  active boolean not null default true,
  sort_order integer not null default 0,
  created_by uuid references public.profiles(user_id) on delete restrict,
  updated_by uuid references public.profiles(user_id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint exam_categories_code_check check (code ~ '^[a-z0-9_]{2,48}$'),
  constraint exam_categories_name_check check (char_length(btrim(name)) between 2 and 80),
  constraint exam_categories_sort_order_check check (sort_order between -10000 and 10000)
);

create unique index exam_categories_name_unique_idx on public.exam_categories (lower(name));
create index exam_categories_active_sort_idx on public.exam_categories (active, sort_order, name);
create index exam_categories_created_by_idx on public.exam_categories (created_by) where created_by is not null;
create index exam_categories_updated_by_idx on public.exam_categories (updated_by) where updated_by is not null;

create table public.exam_types (
  id bigint generated always as identity primary key,
  category_id bigint not null references public.exam_categories(id) on delete restrict,
  code text not null unique,
  name text not null,
  description text,
  active boolean not null default true,
  sort_order integer not null default 0,
  result_config jsonb not null default '{}'::jsonb,
  created_by uuid references public.profiles(user_id) on delete restrict,
  updated_by uuid references public.profiles(user_id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint exam_types_code_check check (code ~ '^[a-z0-9_]{2,64}$'),
  constraint exam_types_name_check check (char_length(btrim(name)) between 2 and 100),
  constraint exam_types_description_check check (description is null or char_length(btrim(description)) between 2 and 1000),
  constraint exam_types_sort_order_check check (sort_order between -10000 and 10000),
  constraint exam_types_result_config_check check (jsonb_typeof(result_config) = 'object')
);

create unique index exam_types_category_name_unique_idx on public.exam_types (category_id, lower(name));
create index exam_types_category_active_sort_idx on public.exam_types (category_id, active, sort_order, name);
create index exam_types_created_by_idx on public.exam_types (created_by) where created_by is not null;
create index exam_types_updated_by_idx on public.exam_types (updated_by) where updated_by is not null;

create table public.clinical_exams (
  id bigint generated always as identity primary key,
  patient_id bigint not null references public.patients(id) on delete restrict,
  exam_type_id bigint not null references public.exam_types(id) on delete restrict,
  attendance_id bigint references public.attendances(id) on delete restrict,
  status text not null default 'requested',
  requested_by uuid not null references public.profiles(user_id) on delete restrict,
  responsible_professional_id uuid not null references public.profiles(user_id) on delete restrict,
  indication text not null,
  clinical_context text,
  technique text,
  findings text,
  conclusion text,
  result_data jsonb not null default '{}'::jsonb,
  correction_reason text,
  requested_at timestamptz not null default now(),
  started_at timestamptz,
  submitted_for_review_at timestamptz,
  completed_at timestamptz,
  reviewed_by uuid references public.profiles(user_id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint clinical_exams_status_check check (status in ('requested', 'in_progress', 'awaiting_review', 'completed')),
  constraint clinical_exams_indication_check check (char_length(btrim(indication)) between 2 and 2000),
  constraint clinical_exams_context_check check (clinical_context is null or char_length(btrim(clinical_context)) between 2 and 4000),
  constraint clinical_exams_technique_check check (technique is null or char_length(btrim(technique)) between 2 and 4000),
  constraint clinical_exams_findings_check check (findings is null or char_length(btrim(findings)) between 2 and 8000),
  constraint clinical_exams_conclusion_check check (conclusion is null or char_length(btrim(conclusion)) between 2 and 4000),
  constraint clinical_exams_result_data_check check (jsonb_typeof(result_data) = 'object'),
  constraint clinical_exams_correction_reason_check check (correction_reason is null or char_length(btrim(correction_reason)) between 2 and 2000),
  constraint clinical_exams_timeline_check check (
    (status = 'requested' and started_at is null and submitted_for_review_at is null and completed_at is null and reviewed_by is null)
    or (status = 'in_progress' and started_at is not null and submitted_for_review_at is null and completed_at is null and reviewed_by is null)
    or (status = 'awaiting_review' and started_at is not null and submitted_for_review_at is not null and completed_at is null and reviewed_by is null)
    or (status = 'completed' and started_at is not null and submitted_for_review_at is not null and completed_at is not null and reviewed_by is not null)
  )
);

create index clinical_exams_requested_at_idx on public.clinical_exams (requested_at desc, id desc);
create index clinical_exams_patient_requested_idx on public.clinical_exams (patient_id, requested_at desc, id desc);
create index clinical_exams_status_requested_idx on public.clinical_exams (status, requested_at desc, id desc);
create index clinical_exams_type_requested_idx on public.clinical_exams (exam_type_id, requested_at desc, id desc);
create index clinical_exams_responsible_status_idx on public.clinical_exams (responsible_professional_id, status, requested_at desc);
create index clinical_exams_requested_by_idx on public.clinical_exams (requested_by, requested_at desc);
create index clinical_exams_reviewed_by_idx on public.clinical_exams (reviewed_by, completed_at desc) where reviewed_by is not null;
create index clinical_exams_attendance_idx on public.clinical_exams (attendance_id) where attendance_id is not null;

create table public.clinical_exam_status_history (
  id bigint generated always as identity primary key,
  exam_id bigint not null references public.clinical_exams(id) on delete restrict,
  from_status text,
  to_status text not null,
  changed_by uuid not null references public.profiles(user_id) on delete restrict,
  note text,
  changed_at timestamptz not null default now(),
  constraint clinical_exam_history_from_status_check check (from_status is null or from_status in ('requested', 'in_progress', 'awaiting_review', 'completed')),
  constraint clinical_exam_history_to_status_check check (to_status in ('requested', 'in_progress', 'awaiting_review', 'completed')),
  constraint clinical_exam_history_note_check check (note is null or char_length(btrim(note)) between 2 and 2000)
);

create index clinical_exam_history_exam_date_idx on public.clinical_exam_status_history (exam_id, changed_at, id);
create index clinical_exam_history_changed_by_idx on public.clinical_exam_status_history (changed_by, changed_at desc);

drop trigger if exists exam_categories_touch_updated_at on public.exam_categories;
create trigger exam_categories_touch_updated_at
before update on public.exam_categories
for each row execute function private.touch_updated_at();

drop trigger if exists exam_types_touch_updated_at on public.exam_types;
create trigger exam_types_touch_updated_at
before update on public.exam_types
for each row execute function private.touch_updated_at();

drop trigger if exists clinical_exams_touch_updated_at on public.clinical_exams;
create trigger clinical_exams_touch_updated_at
before update on public.clinical_exams
for each row execute function private.touch_updated_at();

create or replace function private.validate_clinical_exam_link()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.attendance_id is not null and not exists (
    select 1
    from public.attendances attendance
    where attendance.id = new.attendance_id
      and attendance.patient_id = new.patient_id
      and attendance.status = 'completed'
  ) then
    raise exception 'O atendimento informado não pertence ao paciente ou não está concluído.';
  end if;
  return new;
end;
$$;

drop trigger if exists clinical_exams_validate_link on public.clinical_exams;
create trigger clinical_exams_validate_link
before insert or update of patient_id, attendance_id on public.clinical_exams
for each row execute function private.validate_clinical_exam_link();

-- ---------------------------------------------------------------------------
-- Seeds idempotentes do catálogo inicial
-- ---------------------------------------------------------------------------

with actor as (
  select (select profile.user_id from public.profiles profile order by (profile.role_code = 'diretor_geral') desc, profile.created_at limit 1) as user_id
), seed(code, name, sort_order) as (
  values
    ('imagem', 'Imagem', 10),
    ('laboratorial', 'Laboratorial', 20),
    ('patologico', 'Patológico', 30),
    ('cardiologia', 'Cardiologia', 40),
    ('outros', 'Outros', 50)
)
insert into public.exam_categories (code, name, sort_order, created_by, updated_by)
select seed.code, seed.name, seed.sort_order, actor.user_id, actor.user_id
from seed cross join actor
on conflict (code) do nothing;

with actor as (
  select (select profile.user_id from public.profiles profile order by (profile.role_code = 'diretor_geral') desc, profile.created_at limit 1) as user_id
), seed(category_code, code, name, description, sort_order) as (
  values
    ('imagem', 'raio_x', 'Raio-X', 'Exame radiográfico convencional.', 10),
    ('imagem', 'tomografia', 'Tomografia', 'Exame de imagem por tomografia.', 20),
    ('imagem', 'ressonancia_magnetica', 'Ressonância Magnética', 'Exame de imagem por ressonância magnética.', 30),
    ('imagem', 'ultrassom', 'Ultrassom', 'Exame de imagem por ultrassonografia.', 40),
    ('laboratorial', 'hemograma', 'Hemograma', 'Avaliação hematológica básica.', 10),
    ('laboratorial', 'bioquimica', 'Bioquímica', 'Avaliação bioquímica laboratorial.', 20),
    ('laboratorial', 'tipagem_sanguinea', 'Tipagem Sanguínea', 'Identificação do grupo e fator sanguíneo.', 30),
    ('laboratorial', 'toxicologia', 'Toxicologia', 'Avaliação toxicológica.', 40),
    ('patologico', 'biopsia', 'Biópsia', 'Análise clínica de material obtido por biópsia.', 10),
    ('patologico', 'citologia', 'Citologia', 'Análise citológica.', 20),
    ('cardiologia', 'eletrocardiograma', 'Eletrocardiograma', 'Registro da atividade elétrica cardíaca.', 10)
)
insert into public.exam_types (category_id, code, name, description, sort_order, created_by, updated_by)
select category.id, seed.code, seed.name, seed.description, seed.sort_order, actor.user_id, actor.user_id
from seed
join public.exam_categories category on category.code = seed.category_code
cross join actor
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- RLS e grants explícitos para o Data API
-- ---------------------------------------------------------------------------

alter table public.exam_categories enable row level security;
alter table public.exam_categories force row level security;
alter table public.exam_types enable row level security;
alter table public.exam_types force row level security;
alter table public.clinical_exams enable row level security;
alter table public.clinical_exams force row level security;
alter table public.clinical_exam_status_history enable row level security;
alter table public.clinical_exam_status_history force row level security;

create policy exam_categories_read_authorized
on public.exam_categories for select to authenticated
using (
  (select private.has_permission((select auth.uid()), 'exams.view'))
  or (select private.has_permission((select auth.uid()), 'exams.create'))
  or (select private.has_permission((select auth.uid()), 'exams.perform'))
  or (select private.has_permission((select auth.uid()), 'exams.review'))
  or (select private.has_permission((select auth.uid()), 'exams.catalog.manage'))
);

create policy exam_types_read_authorized
on public.exam_types for select to authenticated
using (
  (select private.has_permission((select auth.uid()), 'exams.view'))
  or (select private.has_permission((select auth.uid()), 'exams.create'))
  or (select private.has_permission((select auth.uid()), 'exams.perform'))
  or (select private.has_permission((select auth.uid()), 'exams.review'))
  or (select private.has_permission((select auth.uid()), 'exams.catalog.manage'))
);

create policy clinical_exams_read_authorized
on public.clinical_exams for select to authenticated
using ((select private.has_permission((select auth.uid()), 'exams.view')));

create policy clinical_exam_history_read_authorized
on public.clinical_exam_status_history for select to authenticated
using ((select private.has_permission((select auth.uid()), 'exams.view')));

revoke all on public.exam_categories from public, anon, authenticated, service_role;
revoke all on public.exam_types from public, anon, authenticated, service_role;
revoke all on public.clinical_exams from public, anon, authenticated, service_role;
revoke all on public.clinical_exam_status_history from public, anon, authenticated, service_role;
grant select on public.exam_categories, public.exam_types, public.clinical_exams, public.clinical_exam_status_history to authenticated;
grant select, insert, update on public.exam_categories, public.exam_types, public.clinical_exams, public.clinical_exam_status_history to service_role;
grant usage, select on sequence public.exam_categories_id_seq, public.exam_types_id_seq, public.clinical_exams_id_seq, public.clinical_exam_status_history_id_seq to service_role;

revoke all on function private.validate_clinical_exam_link() from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Auditoria clínica sem substituir o histórico funcional de status
-- ---------------------------------------------------------------------------

create or replace function private.audit_exam_action(
  p_actor_id uuid,
  p_action text,
  p_entity_name text,
  p_entity_id text,
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
  if p_actor_id is null then
    raise exception 'Ação sem profissional autenticado.';
  end if;
  select profile.passport into v_passport
  from public.profiles profile
  where profile.user_id = p_actor_id and profile.status = 'active';
  if v_passport is null then
    raise exception 'Profissional não autorizado.';
  end if;
  insert into public.audit_logs (actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values)
  values (p_actor_id, v_passport, p_action, p_entity_name, p_entity_id, p_old_values, p_new_values);
end;
$$;

revoke all on function private.audit_exam_action(uuid, text, text, text, jsonb, jsonb) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Consultas paginadas e identidades profissionais mínimas
-- ---------------------------------------------------------------------------

create or replace function public.clinical_exam_page(
  p_search text default null,
  p_passport text default null,
  p_category_id bigint default null,
  p_exam_type_id bigint default null,
  p_status text default null,
  p_date_from date default null,
  p_date_to date default null,
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
  v_actor uuid := auth.uid();
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_result jsonb;
begin
  if v_actor is null or not private.has_permission(v_actor, 'exams.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if p_status is not null and p_status not in ('requested', 'in_progress', 'awaiting_review', 'completed') then
    raise exception 'Status inválido.';
  end if;

  with filtered as (
    select
      exam.id,
      exam.patient_id,
      patient.name as patient_name,
      patient.passport as patient_passport,
      exam.exam_type_id,
      exam_type.name as exam_type_name,
      category.id as category_id,
      category.name as category_name,
      exam.responsible_professional_id,
      responsible.display_name as responsible_name,
      position.name as responsible_position,
      exam.status,
      exam.requested_at
    from public.clinical_exams exam
    join public.patients patient on patient.id = exam.patient_id
    join public.exam_types exam_type on exam_type.id = exam.exam_type_id
    join public.exam_categories category on category.id = exam_type.category_id
    join public.profiles responsible on responsible.user_id = exam.responsible_professional_id
    left join public.staff_positions position on position.id = responsible.position_id
    where (nullif(btrim(p_search), '') is null or patient.name ilike '%' || btrim(p_search) || '%')
      and (nullif(btrim(p_passport), '') is null or patient.passport ilike btrim(p_passport) || '%')
      and (p_category_id is null or category.id = p_category_id)
      and (p_exam_type_id is null or exam_type.id = p_exam_type_id)
      and (p_status is null or exam.status = p_status)
      and (p_date_from is null or exam.requested_at >= p_date_from::timestamptz)
      and (p_date_to is null or exam.requested_at < (p_date_to + 1)::timestamptz)
  ), page_rows as (
    select * from filtered order by requested_at desc, id desc limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'items', coalesce((select jsonb_agg(to_jsonb(page_row) order by page_row.requested_at desc, page_row.id desc) from page_rows page_row), '[]'::jsonb),
    'total', (select count(*) from filtered)
  ) into v_result;
  return v_result;
end;
$$;

create or replace function public.clinical_exam_detail(p_exam_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_result jsonb;
begin
  if v_actor is null or not private.has_permission(v_actor, 'exams.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  select jsonb_build_object(
    'id', exam.id,
    'patient', jsonb_build_object('id', patient.id, 'name', patient.name, 'passport', patient.passport),
    'exam_type', jsonb_build_object('id', exam_type.id, 'name', exam_type.name, 'category_id', category.id, 'category_name', category.name),
    'attendance_id', exam.attendance_id,
    'status', exam.status,
    'requested_by', jsonb_build_object('id', requester.user_id, 'name', requester.display_name, 'position', requester_position.name),
    'responsible_professional', jsonb_build_object('id', responsible.user_id, 'name', responsible.display_name, 'position', responsible_position.name),
    'reviewed_by', case when reviewer.user_id is null then null else jsonb_build_object('id', reviewer.user_id, 'name', reviewer.display_name, 'position', reviewer_position.name) end,
    'indication', exam.indication,
    'clinical_context', exam.clinical_context,
    'technique', exam.technique,
    'findings', exam.findings,
    'conclusion', exam.conclusion,
    'result_data', exam.result_data,
    'correction_reason', exam.correction_reason,
    'requested_at', exam.requested_at,
    'started_at', exam.started_at,
    'submitted_for_review_at', exam.submitted_for_review_at,
    'completed_at', exam.completed_at,
    'created_at', exam.created_at,
    'updated_at', exam.updated_at,
    'history', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', history.id,
        'from_status', history.from_status,
        'to_status', history.to_status,
        'note', history.note,
        'changed_at', history.changed_at,
        'changed_by', jsonb_build_object('id', changer.user_id, 'name', changer.display_name, 'position', changer_position.name)
      ) order by history.changed_at, history.id)
      from public.clinical_exam_status_history history
      join public.profiles changer on changer.user_id = history.changed_by
      left join public.staff_positions changer_position on changer_position.id = changer.position_id
      where history.exam_id = exam.id
    ), '[]'::jsonb)
  ) into v_result
  from public.clinical_exams exam
  join public.patients patient on patient.id = exam.patient_id
  join public.exam_types exam_type on exam_type.id = exam.exam_type_id
  join public.exam_categories category on category.id = exam_type.category_id
  join public.profiles requester on requester.user_id = exam.requested_by
  left join public.staff_positions requester_position on requester_position.id = requester.position_id
  join public.profiles responsible on responsible.user_id = exam.responsible_professional_id
  left join public.staff_positions responsible_position on responsible_position.id = responsible.position_id
  left join public.profiles reviewer on reviewer.user_id = exam.reviewed_by
  left join public.staff_positions reviewer_position on reviewer_position.id = reviewer.position_id
  where exam.id = p_exam_id;
  if v_result is null then raise exception 'Exame não localizado.'; end if;
  return v_result;
end;
$$;

create or replace function public.clinical_exam_reference_data()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null or not (
    private.has_permission(v_actor, 'exams.view')
    or private.has_permission(v_actor, 'exams.create')
    or private.has_permission(v_actor, 'exams.perform')
    or private.has_permission(v_actor, 'exams.review')
    or private.has_permission(v_actor, 'exams.catalog.manage')
  ) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'categories', coalesce((
      select jsonb_agg(jsonb_build_object('id', category.id, 'code', category.code, 'name', category.name, 'active', category.active, 'sort_order', category.sort_order) order by category.sort_order, category.name)
      from public.exam_categories category
    ), '[]'::jsonb),
    'types', coalesce((
      select jsonb_agg(jsonb_build_object('id', exam_type.id, 'category_id', exam_type.category_id, 'code', exam_type.code, 'name', exam_type.name, 'description', exam_type.description, 'active', exam_type.active, 'sort_order', exam_type.sort_order) order by exam_type.category_id, exam_type.sort_order, exam_type.name)
      from public.exam_types exam_type
    ), '[]'::jsonb),
    'professionals', coalesce((
      select jsonb_agg(jsonb_build_object('id', profile.user_id, 'name', profile.display_name, 'position', position.name) order by position.level, profile.display_name)
      from public.profiles profile
      left join public.staff_positions position on position.id = profile.position_id
      where profile.status = 'active'
        and (private.has_permission(profile.user_id, 'exams.perform') or private.has_permission(profile.user_id, 'exams.review'))
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.clinical_exam_attendance_options(p_patient_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null
     or not private.has_permission(v_actor, 'exams.create')
     or not private.has_permission(v_actor, 'patients.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.patients patient where patient.id = p_patient_id) then
    raise exception 'Paciente não localizado.';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', attendance.id,
      'created_at', attendance.created_at,
      'total', attendance.total,
      'summary', coalesce((
        select string_agg(item.service_name || case when item.quantity > 1 then ' ×' || item.quantity::text else '' end, ', ' order by item.id)
        from public.attendance_items item where item.attendance_id = attendance.id
      ), 'Atendimento sem itens')
    ) order by attendance.created_at desc)
    from (
      select * from public.attendances
      where patient_id = p_patient_id and status = 'completed'
      order by created_at desc limit 30
    ) attendance
  ), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------------
-- Fluxo clínico atômico
-- ---------------------------------------------------------------------------

create or replace function private.can_perform_clinical_exam(p_actor uuid, p_responsible uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_actor is not null and (
    (p_actor = p_responsible and private.has_permission(p_actor, 'exams.perform'))
    or private.has_permission(p_actor, 'exams.review')
  );
$$;

revoke all on function private.can_perform_clinical_exam(uuid, uuid) from public, anon, authenticated, service_role;

create or replace function public.create_clinical_exam(
  p_patient_id bigint,
  p_exam_type_id bigint,
  p_responsible_professional_id uuid,
  p_indication text,
  p_clinical_context text default null,
  p_attendance_id bigint default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_responsible uuid := coalesce(p_responsible_professional_id, v_actor);
  v_exam public.clinical_exams;
begin
  if v_actor is null
     or not private.has_permission(v_actor, 'exams.create')
     or not private.has_permission(v_actor, 'patients.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.patients patient where patient.id = p_patient_id) then
    raise exception 'Paciente não localizado.';
  end if;
  if not exists (
    select 1 from public.exam_types exam_type
    join public.exam_categories category on category.id = exam_type.category_id
    where exam_type.id = p_exam_type_id and exam_type.active and category.active
  ) then
    raise exception 'Tipo de exame indisponível.';
  end if;
  if not exists (select 1 from public.profiles profile where profile.user_id = v_responsible and profile.status = 'active')
     or not (private.has_permission(v_responsible, 'exams.perform') or private.has_permission(v_responsible, 'exams.review')) then
    raise exception 'Profissional responsável inválido.';
  end if;
  insert into public.clinical_exams (
    patient_id, exam_type_id, attendance_id, requested_by, responsible_professional_id,
    indication, clinical_context
  ) values (
    p_patient_id, p_exam_type_id, p_attendance_id, v_actor, v_responsible,
    btrim(p_indication), nullif(btrim(p_clinical_context), '')
  ) returning * into v_exam;
  insert into public.clinical_exam_status_history (exam_id, from_status, to_status, changed_by, note)
  values (v_exam.id, null, 'requested', v_actor, 'Exame solicitado.');
  perform private.audit_exam_action(v_actor, 'clinical_exam.created', 'clinical_exams', v_exam.id::text, null, to_jsonb(v_exam));
  return v_exam.id;
end;
$$;

create or replace function public.start_clinical_exam(p_exam_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_old public.clinical_exams;
  v_new public.clinical_exams;
begin
  select * into v_old from public.clinical_exams where id = p_exam_id for update;
  if v_old.id is null then raise exception 'Exame não localizado.'; end if;
  if not private.can_perform_clinical_exam(v_actor, v_old.responsible_professional_id) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if v_old.status <> 'requested' then raise exception 'O exame não está disponível para início.'; end if;
  update public.clinical_exams set status = 'in_progress', started_at = now()
  where id = p_exam_id returning * into v_new;
  insert into public.clinical_exam_status_history (exam_id, from_status, to_status, changed_by, note)
  values (p_exam_id, 'requested', 'in_progress', v_actor, 'Execução iniciada.');
  perform private.audit_exam_action(v_actor, 'clinical_exam.started', 'clinical_exams', p_exam_id::text, to_jsonb(v_old), to_jsonb(v_new));
end;
$$;

create or replace function public.save_clinical_exam_draft(
  p_exam_id bigint,
  p_technique text,
  p_findings text,
  p_conclusion text,
  p_result_data jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_exam public.clinical_exams;
begin
  select * into v_exam from public.clinical_exams where id = p_exam_id for update;
  if v_exam.id is null then raise exception 'Exame não localizado.'; end if;
  if not private.can_perform_clinical_exam(v_actor, v_exam.responsible_professional_id) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if v_exam.status <> 'in_progress' then raise exception 'O exame não está em andamento.'; end if;
  if p_result_data is null or jsonb_typeof(p_result_data) <> 'object' then raise exception 'Dados adicionais inválidos.'; end if;
  update public.clinical_exams set
    technique = nullif(btrim(p_technique), ''),
    findings = nullif(btrim(p_findings), ''),
    conclusion = nullif(btrim(p_conclusion), ''),
    result_data = p_result_data
  where id = p_exam_id;
end;
$$;

create or replace function public.submit_clinical_exam_review(p_exam_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_old public.clinical_exams;
  v_new public.clinical_exams;
begin
  select * into v_old from public.clinical_exams where id = p_exam_id for update;
  if v_old.id is null then raise exception 'Exame não localizado.'; end if;
  if not private.can_perform_clinical_exam(v_actor, v_old.responsible_professional_id) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if v_old.status <> 'in_progress' then raise exception 'O exame não está em andamento.'; end if;
  if v_old.technique is null or v_old.findings is null or v_old.conclusion is null then
    raise exception 'Preencha técnica, achados e conclusão antes do envio.';
  end if;
  update public.clinical_exams set status = 'awaiting_review', submitted_for_review_at = now()
  where id = p_exam_id returning * into v_new;
  insert into public.clinical_exam_status_history (exam_id, from_status, to_status, changed_by, note)
  values (p_exam_id, 'in_progress', 'awaiting_review', v_actor, 'Exame enviado para revisão.');
  perform private.audit_exam_action(v_actor, 'clinical_exam.submitted_for_review', 'clinical_exams', p_exam_id::text, to_jsonb(v_old), to_jsonb(v_new));
end;
$$;

create or replace function public.review_clinical_exam(p_exam_id bigint, p_decision text, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_old public.clinical_exams;
  v_new public.clinical_exams;
begin
  if v_actor is null or not private.has_permission(v_actor, 'exams.review') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  select * into v_old from public.clinical_exams where id = p_exam_id for update;
  if v_old.id is null then raise exception 'Exame não localizado.'; end if;
  if v_old.status <> 'awaiting_review' then raise exception 'O exame não está aguardando revisão.'; end if;
  if p_decision = 'approve' then
    update public.clinical_exams set status = 'completed', reviewed_by = v_actor, completed_at = now()
    where id = p_exam_id returning * into v_new;
    insert into public.clinical_exam_status_history (exam_id, from_status, to_status, changed_by, note)
    values (p_exam_id, 'awaiting_review', 'completed', v_actor, 'Exame revisado e concluído.');
    perform private.audit_exam_action(v_actor, 'clinical_exam.completed', 'clinical_exams', p_exam_id::text, to_jsonb(v_old), to_jsonb(v_new));
  elsif p_decision = 'return' then
    if nullif(btrim(p_reason), '') is null or char_length(btrim(p_reason)) < 2 then
      raise exception 'Informe o motivo da correção.';
    end if;
    update public.clinical_exams set
      status = 'in_progress',
      submitted_for_review_at = null,
      reviewed_by = null,
      completed_at = null,
      correction_reason = btrim(p_reason)
    where id = p_exam_id returning * into v_new;
    insert into public.clinical_exam_status_history (exam_id, from_status, to_status, changed_by, note)
    values (p_exam_id, 'awaiting_review', 'in_progress', v_actor, btrim(p_reason));
    perform private.audit_exam_action(v_actor, 'clinical_exam.returned_for_correction', 'clinical_exams', p_exam_id::text, to_jsonb(v_old), to_jsonb(v_new));
  else
    raise exception 'Decisão de revisão inválida.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Administração sem exclusão física do catálogo
-- ---------------------------------------------------------------------------

create or replace function public.manage_exam_category(
  p_id bigint,
  p_name text,
  p_code text,
  p_active boolean,
  p_sort_order integer
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_old public.exam_categories;
  v_new public.exam_categories;
  v_action text;
begin
  if v_actor is null or not private.has_permission(v_actor, 'exams.catalog.manage') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if p_id is null then
    insert into public.exam_categories (code, name, active, sort_order, created_by, updated_by)
    values (btrim(p_code), btrim(p_name), coalesce(p_active, true), p_sort_order, v_actor, v_actor)
    returning * into v_new;
    v_action := 'exam_category.created';
  else
    select * into v_old from public.exam_categories where id = p_id for update;
    if v_old.id is null then raise exception 'Categoria não localizada.'; end if;
    update public.exam_categories set
      name = btrim(p_name), active = p_active, sort_order = p_sort_order, updated_by = v_actor
    where id = p_id returning * into v_new;
    v_action := case when v_old.active is distinct from v_new.active then 'exam_category.status_changed' else 'exam_category.updated' end;
  end if;
  perform private.audit_exam_action(v_actor, v_action, 'exam_categories', v_new.id::text, case when v_old.id is null then null else to_jsonb(v_old) end, to_jsonb(v_new));
  return v_new.id;
end;
$$;

create or replace function public.manage_exam_type(
  p_id bigint,
  p_category_id bigint,
  p_name text,
  p_code text,
  p_description text,
  p_active boolean,
  p_sort_order integer
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_old public.exam_types;
  v_new public.exam_types;
  v_category_active boolean;
  v_action text;
begin
  if v_actor is null or not private.has_permission(v_actor, 'exams.catalog.manage') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  select category.active into v_category_active from public.exam_categories category where category.id = p_category_id;
  if v_category_active is null then raise exception 'Categoria não localizada.'; end if;
  if p_active and not v_category_active then raise exception 'Ative a categoria antes de ativar o tipo de exame.'; end if;
  if p_id is null then
    insert into public.exam_types (category_id, code, name, description, active, sort_order, created_by, updated_by)
    values (p_category_id, btrim(p_code), btrim(p_name), nullif(btrim(p_description), ''), coalesce(p_active, true), p_sort_order, v_actor, v_actor)
    returning * into v_new;
    v_action := 'exam_type.created';
  else
    select * into v_old from public.exam_types where id = p_id for update;
    if v_old.id is null then raise exception 'Tipo de exame não localizado.'; end if;
    update public.exam_types set
      category_id = p_category_id,
      name = btrim(p_name),
      description = nullif(btrim(p_description), ''),
      active = p_active,
      sort_order = p_sort_order,
      updated_by = v_actor
    where id = p_id returning * into v_new;
    v_action := case when v_old.active is distinct from v_new.active then 'exam_type.status_changed' else 'exam_type.updated' end;
  end if;
  perform private.audit_exam_action(v_actor, v_action, 'exam_types', v_new.id::text, case when v_old.id is null then null else to_jsonb(v_old) end, to_jsonb(v_new));
  return v_new.id;
end;
$$;

-- RPCs não ficam executáveis por PUBLIC/anon; o próprio corpo repete autorização.
revoke all on function public.clinical_exam_page(text, text, bigint, bigint, text, date, date, integer, integer) from public, anon, authenticated;
revoke all on function public.clinical_exam_detail(bigint) from public, anon, authenticated;
revoke all on function public.clinical_exam_reference_data() from public, anon, authenticated;
revoke all on function public.clinical_exam_attendance_options(bigint) from public, anon, authenticated;
revoke all on function public.create_clinical_exam(bigint, bigint, uuid, text, text, bigint) from public, anon, authenticated;
revoke all on function public.start_clinical_exam(bigint) from public, anon, authenticated;
revoke all on function public.save_clinical_exam_draft(bigint, text, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.submit_clinical_exam_review(bigint) from public, anon, authenticated;
revoke all on function public.review_clinical_exam(bigint, text, text) from public, anon, authenticated;
revoke all on function public.manage_exam_category(bigint, text, text, boolean, integer) from public, anon, authenticated;
revoke all on function public.manage_exam_type(bigint, bigint, text, text, text, boolean, integer) from public, anon, authenticated;

grant execute on function public.clinical_exam_page(text, text, bigint, bigint, text, date, date, integer, integer) to authenticated;
grant execute on function public.clinical_exam_detail(bigint) to authenticated;
grant execute on function public.clinical_exam_reference_data() to authenticated;
grant execute on function public.clinical_exam_attendance_options(bigint) to authenticated;
grant execute on function public.create_clinical_exam(bigint, bigint, uuid, text, text, bigint) to authenticated;
grant execute on function public.start_clinical_exam(bigint) to authenticated;
grant execute on function public.save_clinical_exam_draft(bigint, text, text, text, jsonb) to authenticated;
grant execute on function public.submit_clinical_exam_review(bigint) to authenticated;
grant execute on function public.review_clinical_exam(bigint, text, text) to authenticated;
grant execute on function public.manage_exam_category(bigint, text, text, boolean, integer) to authenticated;
grant execute on function public.manage_exam_type(bigint, bigint, text, text, text, boolean, integer) to authenticated;

comment on table public.exam_categories is 'Categorias configuráveis da Central de Exames; histórico é preservado por inativação.';
comment on table public.exam_types is 'Tipos clínicos configuráveis, independentes do catálogo financeiro.';
comment on table public.clinical_exams is 'Exames clínicos manuais; não são criados automaticamente por vendas.';
comment on table public.clinical_exam_status_history is 'Histórico funcional imutável das transições do exame clínico.';
comment on column public.clinical_exams.attendance_id is 'Vínculo opcional e explícito com atendimento financeiro real do mesmo paciente.';

notify pgrst, 'reload schema';
