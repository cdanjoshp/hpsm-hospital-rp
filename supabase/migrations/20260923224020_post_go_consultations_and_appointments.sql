-- HPSM · Pós-GO · Consultas e Agendamentos
-- Agenda clínica e prontuário longitudinal independentes do fluxo financeiro.

create extension if not exists btree_gist;

insert into public.system_permissions (code, module, label, description, sort_order) values
  ('consultations.view', 'Consultas e Agendamentos', 'Visualizar consultas', 'Consulta a agenda e os prontuários clínicos.', 54),
  ('consultations.create', 'Consultas e Agendamentos', 'Agendar e iniciar consultas', 'Agenda consultas próprias e inicia consultas com ou sem agendamento.', 55),
  ('consultations.complete', 'Consultas e Agendamentos', 'Concluir consultas', 'Registra a evolução clínica e conclui consultas próprias.', 56),
  ('consultations.manage', 'Consultas e Agendamentos', 'Gerenciar agenda clínica', 'Gerencia agendamentos de outros profissionais e estados administrativos.', 57)
on conflict (code) do update set
  module = excluded.module,
  label = excluded.label,
  description = excluded.description,
  sort_order = excluded.sort_order;

with grants(permission_code, min_level) as (
  values
    ('consultations.view', 1),
    ('consultations.create', 1),
    ('consultations.complete', 1),
    ('consultations.manage', 11)
)
insert into public.staff_position_permissions (position_id, permission_code, granted_by)
select
  position.id,
  grant_row.permission_code,
  coalesce(
    (select profile.user_id from public.profiles profile where profile.role_code = 'diretor_geral' and profile.status = 'active' limit 1),
    position.updated_by,
    position.created_by
  )
from public.staff_positions position
join grants grant_row on position.level >= grant_row.min_level
where position.official and position.active
on conflict (position_id, permission_code) do nothing;

insert into public.staff_position_permissions (position_id, permission_code, granted_by)
select position.id, 'consultations.view', actor.user_id
from public.staff_positions position
cross join lateral (
  select profile.user_id
  from public.profiles profile
  where profile.role_code = 'diretor_geral' and profile.status = 'active'
  order by profile.created_at
  limit 1
) actor
where position.code = 'diretores_sr'
on conflict (position_id, permission_code) do update
set granted_by = excluded.granted_by, granted_at = now();

create table public.patient_appointments (
  id bigint generated always as identity primary key,
  patient_id bigint not null references public.patients(id) on delete restrict,
  professional_id uuid not null references public.profiles(user_id) on delete restrict,
  scheduled_start timestamptz not null,
  scheduled_end timestamptz not null,
  duration_minutes smallint not null,
  reason text not null,
  notes text,
  status text not null default 'scheduled',
  created_by uuid not null references public.profiles(user_id) on delete restrict,
  confirmed_by uuid references public.profiles(user_id) on delete restrict,
  confirmed_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  cancelled_by uuid references public.profiles(user_id) on delete restrict,
  cancelled_at timestamptz,
  cancellation_reason text,
  no_show_by uuid references public.profiles(user_id) on delete restrict,
  no_show_at timestamptz,
  follow_up_of_consultation_id bigint,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint patient_appointments_time_check check (
    scheduled_end > scheduled_start
    and duration_minutes between 5 and 480
    and scheduled_end = scheduled_start + make_interval(mins => duration_minutes)
  ),
  constraint patient_appointments_reason_check check (char_length(btrim(reason)) between 3 and 500),
  constraint patient_appointments_notes_check check (notes is null or char_length(btrim(notes)) between 1 and 4000),
  constraint patient_appointments_status_check check (status in ('scheduled', 'confirmed', 'in_progress', 'completed', 'cancelled', 'no_show')),
  constraint patient_appointments_state_check check (
    (status = 'scheduled' and confirmed_at is null and started_at is null and completed_at is null and cancelled_at is null and no_show_at is null)
    or (status = 'confirmed' and confirmed_at is not null and confirmed_by is not null and started_at is null and completed_at is null and cancelled_at is null and no_show_at is null)
    or (status = 'in_progress' and started_at is not null and completed_at is null and cancelled_at is null and no_show_at is null)
    or (status = 'completed' and started_at is not null and completed_at is not null and cancelled_at is null and no_show_at is null)
    or (status = 'cancelled' and cancelled_at is not null and cancelled_by is not null and cancellation_reason is not null and completed_at is null and no_show_at is null)
    or (status = 'no_show' and no_show_at is not null and no_show_by is not null and started_at is null and completed_at is null and cancelled_at is null)
  ),
  exclude using gist (
    professional_id with =,
    tstzrange(scheduled_start, scheduled_end, '[)') with &&
  ) where (status in ('scheduled', 'confirmed', 'in_progress'))
);

create table public.clinical_consultations (
  id bigint generated always as identity primary key,
  patient_id bigint not null references public.patients(id) on delete restrict,
  professional_id uuid not null references public.profiles(user_id) on delete restrict,
  appointment_id bigint unique references public.patient_appointments(id) on delete restrict,
  status text not null default 'in_progress',
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  blood_pressure_systolic smallint,
  blood_pressure_diastolic smallint,
  blood_pressure_class text,
  temperature_c numeric(4,1),
  temperature_class text,
  heart_rate_bpm smallint,
  heart_rate_class text,
  oxygen_saturation_percent smallint,
  oxygen_saturation_class text,
  pain_score smallint,
  anamnesis text,
  selected_diagnosis jsonb,
  final_diagnosis_plan text,
  complementary_action text not null default 'NONE',
  orientation_text text,
  final_snapshot jsonb,
  created_by uuid not null references public.profiles(user_id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint clinical_consultations_status_check check (status in ('in_progress', 'completed')),
  constraint clinical_consultations_vitals_check check (
    (blood_pressure_systolic is null or blood_pressure_systolic between 40 and 300)
    and (blood_pressure_diastolic is null or blood_pressure_diastolic between 20 and 200)
    and (temperature_c is null or temperature_c between 30 and 45)
    and (heart_rate_bpm is null or heart_rate_bpm between 20 and 260)
    and (oxygen_saturation_percent is null or oxygen_saturation_percent between 50 and 100)
    and (pain_score is null or pain_score between 0 and 10)
  ),
  constraint clinical_consultations_text_check check (
    (anamnesis is null or char_length(btrim(anamnesis)) between 3 and 12000)
    and (final_diagnosis_plan is null or char_length(btrim(final_diagnosis_plan)) between 3 and 12000)
    and (orientation_text is null or char_length(btrim(orientation_text)) between 3 and 12000)
  ),
  constraint clinical_consultations_action_check check (complementary_action in ('NONE', 'CAST', 'HOSPITALIZATION')),
  constraint clinical_consultations_completion_check check (
    (status = 'in_progress' and completed_at is null and final_snapshot is null)
    or (status = 'completed' and completed_at is not null and final_snapshot is not null)
  )
);

alter table public.patient_appointments
  add constraint patient_appointments_follow_up_fkey
  foreign key (follow_up_of_consultation_id)
  references public.clinical_consultations(id)
  on delete restrict;

create table public.consultation_ai_generations (
  id bigint generated always as identity primary key,
  consultation_id bigint not null references public.clinical_consultations(id) on delete restrict,
  action_type text not null,
  status text not null default 'pending',
  request_key uuid not null,
  response_payload jsonb,
  error_message text,
  model text,
  prompt_version text,
  requested_by uuid not null references public.profiles(user_id) on delete restrict,
  requested_at timestamptz not null default now(),
  completed_at timestamptz,
  failed_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint consultation_ai_action_check check (action_type in ('ANAMNESIS_REWRITE', 'EXAM_SUGGESTIONS', 'DIAGNOSIS_OPTIONS', 'FINAL_DIAGNOSIS_PLAN', 'ORIENTATION_MEDICATION')),
  constraint consultation_ai_status_check check (status in ('pending', 'completed', 'failed')),
  constraint consultation_ai_state_check check (
    (status = 'pending' and response_payload is null and completed_at is null and failed_at is null)
    or (status = 'completed' and response_payload is not null and completed_at is not null and failed_at is null and model is not null and prompt_version is not null)
    or (status = 'failed' and response_payload is null and completed_at is null and failed_at is not null and error_message is not null)
  ),
  unique (consultation_id, action_type)
);

create table public.consultation_vital_ranges (
  code text primary key,
  label text not null,
  configuration jsonb not null,
  updated_at timestamptz not null default now(),
  constraint consultation_vital_ranges_code_check check (code in ('blood_pressure', 'temperature', 'heart_rate', 'oxygen_saturation')),
  constraint consultation_vital_ranges_configuration_check check (jsonb_typeof(configuration) = 'object')
);

insert into public.consultation_vital_ranges (code, label, configuration) values
  ('blood_pressure', 'Pressão arterial', '{"lowSystolicMax":89,"normalSystolicMax":129,"normalDiastolicMax":84,"highSystolicMin":130,"highDiastolicMin":85}'::jsonb),
  ('temperature', 'Temperatura', '{"lowMax":35.4,"normalMax":37.4,"highMin":37.5,"criticalMin":39.5}'::jsonb),
  ('heart_rate', 'Frequência cardíaca', '{"lowMax":59,"normalMax":100,"highMin":101,"criticalHighMin":150}'::jsonb),
  ('oxygen_saturation', 'Saturação de oxigênio', '{"criticalMax":89,"lowMax":94,"normalMin":95}'::jsonb)
on conflict (code) do update set label = excluded.label, configuration = excluded.configuration, updated_at = now();

alter table public.clinical_exams add column if not exists consultation_id bigint references public.clinical_consultations(id) on delete restrict;
alter table public.clinical_casts add column if not exists consultation_id bigint references public.clinical_consultations(id) on delete restrict;
alter table public.hospitalizations add column if not exists consultation_id bigint references public.clinical_consultations(id) on delete restrict;
alter table public.medical_certificates alter column attendance_id drop not null;
alter table public.medical_certificates add column if not exists consultation_id bigint references public.clinical_consultations(id) on delete restrict;
alter table public.medical_certificates add constraint medical_certificates_single_origin_check
  check (num_nonnulls(attendance_id, consultation_id) = 1);

create index patient_appointments_patient_start_idx on public.patient_appointments (patient_id, scheduled_start desc, id desc);
create index patient_appointments_professional_start_idx on public.patient_appointments (professional_id, scheduled_start, id);
create index patient_appointments_status_start_idx on public.patient_appointments (status, scheduled_start, id);
create index patient_appointments_follow_up_idx on public.patient_appointments (follow_up_of_consultation_id) where follow_up_of_consultation_id is not null;
create index clinical_consultations_patient_started_idx on public.clinical_consultations (patient_id, started_at desc, id desc);
create index clinical_consultations_professional_started_idx on public.clinical_consultations (professional_id, started_at desc, id desc);
create index clinical_consultations_status_started_idx on public.clinical_consultations (status, started_at desc, id desc);
create index consultation_ai_consultation_idx on public.consultation_ai_generations (consultation_id, requested_at, id);
create index clinical_exams_consultation_idx on public.clinical_exams (consultation_id) where consultation_id is not null;
create index clinical_casts_consultation_idx on public.clinical_casts (consultation_id) where consultation_id is not null;
create index hospitalizations_consultation_idx on public.hospitalizations (consultation_id) where consultation_id is not null;
create index medical_certificates_consultation_idx on public.medical_certificates (consultation_id) where consultation_id is not null;

create trigger patient_appointments_touch_updated_at before update on public.patient_appointments
for each row execute function private.touch_updated_at();
create trigger clinical_consultations_touch_updated_at before update on public.clinical_consultations
for each row execute function private.touch_updated_at();
create trigger consultation_ai_generations_touch_updated_at before update on public.consultation_ai_generations
for each row execute function private.touch_updated_at();

create or replace function private.guard_completed_consultation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Consultas clínicas não podem ser excluídas.' using errcode = '42501';
  end if;
  if old.status = 'completed' and new is distinct from old then
    raise exception 'Uma consulta concluída é imutável.' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger clinical_consultations_guard_completed
before update or delete on public.clinical_consultations
for each row execute function private.guard_completed_consultation();

create trigger patient_appointments_audit after insert or update or delete on public.patient_appointments
for each row execute function private.audit_row_change();
create trigger clinical_consultations_audit after insert or update or delete on public.clinical_consultations
for each row execute function private.audit_row_change();
create trigger consultation_ai_generations_audit after insert or update or delete on public.consultation_ai_generations
for each row execute function private.audit_row_change();

create or replace function private.validate_medical_certificate_link()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if num_nonnulls(new.attendance_id, new.consultation_id) <> 1 then
    raise exception 'Informe uma única origem clínica para o atestado.';
  end if;
  if new.attendance_id is not null and not exists (
    select 1 from public.attendances attendance
    where attendance.id = new.attendance_id and attendance.patient_id = new.patient_id and attendance.status = 'completed'
  ) then
    raise exception 'O atendimento informado não pertence ao paciente ou não está concluído.';
  end if;
  if new.consultation_id is not null and not exists (
    select 1 from public.clinical_consultations consultation
    where consultation.id = new.consultation_id and consultation.patient_id = new.patient_id
  ) then
    raise exception 'A consulta informada não pertence ao paciente.';
  end if;
  return new;
end;
$$;

drop trigger if exists medical_certificates_validate_link on public.medical_certificates;
create trigger medical_certificates_validate_link
before insert or update of patient_id, attendance_id, consultation_id on public.medical_certificates
for each row execute function private.validate_medical_certificate_link();

alter table public.patient_appointments enable row level security;
alter table public.patient_appointments force row level security;
alter table public.clinical_consultations enable row level security;
alter table public.clinical_consultations force row level security;
alter table public.consultation_ai_generations enable row level security;
alter table public.consultation_ai_generations force row level security;
alter table public.consultation_vital_ranges enable row level security;
alter table public.consultation_vital_ranges force row level security;

create policy patient_appointments_read_authorized on public.patient_appointments
for select to authenticated using ((select private.has_permission((select auth.uid()), 'consultations.view')));
create policy clinical_consultations_read_authorized on public.clinical_consultations
for select to authenticated using ((select private.has_permission((select auth.uid()), 'consultations.view')));
create policy consultation_ai_generations_read_authorized on public.consultation_ai_generations
for select to authenticated using ((select private.has_permission((select auth.uid()), 'consultations.view')));
create policy consultation_vital_ranges_read_authorized on public.consultation_vital_ranges
for select to authenticated using ((select private.has_permission((select auth.uid()), 'consultations.view')));

create policy patient_appointments_valid_session on public.patient_appointments as restrictive
for all to authenticated using ((select private.hpsm_session_valid(true))) with check ((select private.hpsm_session_valid(true)));
create policy clinical_consultations_valid_session on public.clinical_consultations as restrictive
for all to authenticated using ((select private.hpsm_session_valid(true))) with check ((select private.hpsm_session_valid(true)));
create policy consultation_ai_generations_valid_session on public.consultation_ai_generations as restrictive
for all to authenticated using ((select private.hpsm_session_valid(true))) with check ((select private.hpsm_session_valid(true)));
create policy consultation_vital_ranges_valid_session on public.consultation_vital_ranges as restrictive
for all to authenticated using ((select private.hpsm_session_valid(true))) with check ((select private.hpsm_session_valid(true)));

revoke all on public.patient_appointments, public.clinical_consultations, public.consultation_ai_generations, public.consultation_vital_ranges
from public, anon, authenticated, service_role;
grant select on public.patient_appointments, public.clinical_consultations, public.consultation_ai_generations, public.consultation_vital_ranges to authenticated;
grant select, insert, update, delete on public.patient_appointments, public.clinical_consultations, public.consultation_ai_generations, public.consultation_vital_ranges to service_role;
grant usage, select on sequence public.patient_appointments_id_seq, public.clinical_consultations_id_seq, public.consultation_ai_generations_id_seq to service_role;

create or replace function private.can_edit_consultation(p_actor uuid, p_professional uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_actor is not null
    and p_actor = p_professional
    and private.is_hpsm_workforce(p_actor)
    and private.has_permission(p_actor, 'consultations.complete');
$$;

revoke all on function private.can_edit_consultation(uuid, uuid) from public, anon, authenticated, service_role;

create or replace function public.consultation_reference_data()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
begin
  if not private.has_permission(v_actor, 'consultations.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'professionals', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', profile.user_id,
        'name', profile.display_name,
        'position', position.name
      ) order by position.level, profile.display_name)
      from public.profiles profile
      join public.staff_positions position on position.id = profile.position_id
      where profile.status = 'active'
        and position.official
        and position.active
        and private.has_permission(profile.user_id, 'consultations.create')
    ), '[]'::jsonb),
    'vital_ranges', coalesce((
      select jsonb_object_agg(range.code, range.configuration)
      from public.consultation_vital_ranges range
    ), '{}'::jsonb),
    'exam_types', case when private.has_permission(v_actor, 'exams.view') then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', exam_type.id,
        'name', exam_type.name,
        'category', category.name
      ) order by category.sort_order, exam_type.sort_order, exam_type.name)
      from public.exam_types exam_type
      join public.exam_categories category on category.id = exam_type.category_id
      where exam_type.active and category.active
    ), '[]'::jsonb) else '[]'::jsonb end
  );
end;
$$;

create or replace function public.consultation_schedule_page(
  p_search text default null,
  p_professional_id uuid default null,
  p_status text default null,
  p_date_from timestamptz default null,
  p_date_to timestamptz default null,
  p_mine boolean default false,
  p_limit integer default 50,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_result jsonb;
begin
  if not private.has_permission(v_actor, 'consultations.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if p_status is not null and p_status not in ('scheduled', 'confirmed', 'in_progress', 'completed', 'cancelled', 'no_show') then
    raise exception 'Status inválido.';
  end if;

  with records as (
    select
      appointment.id as appointment_id,
      consultation.id as consultation_id,
      appointment.patient_id,
      patient.name as patient_name,
      patient.passport as patient_passport,
      appointment.professional_id,
      professional.display_name as professional_name,
      position.name as professional_position,
      appointment.scheduled_start as starts_at,
      appointment.scheduled_end as ends_at,
      appointment.duration_minutes,
      appointment.reason,
      appointment.notes,
      appointment.status,
      false as walk_in,
      appointment.follow_up_of_consultation_id,
      appointment.created_at
    from public.patient_appointments appointment
    join public.patients patient on patient.id = appointment.patient_id
    join public.profiles professional on professional.user_id = appointment.professional_id
    left join public.staff_positions position on position.id = professional.position_id
    left join public.clinical_consultations consultation on consultation.appointment_id = appointment.id
    union all
    select
      null::bigint,
      consultation.id,
      consultation.patient_id,
      patient.name,
      patient.passport,
      consultation.professional_id,
      professional.display_name,
      position.name,
      consultation.started_at,
      consultation.completed_at,
      null::smallint,
      'Consulta por demanda espontânea',
      null::text,
      consultation.status,
      true,
      null::bigint,
      consultation.created_at
    from public.clinical_consultations consultation
    join public.patients patient on patient.id = consultation.patient_id
    join public.profiles professional on professional.user_id = consultation.professional_id
    left join public.staff_positions position on position.id = professional.position_id
    where consultation.appointment_id is null
  ), filtered as (
    select * from records record
    where (
      nullif(btrim(coalesce(p_search, '')), '') is null
      or record.patient_name ilike '%' || btrim(p_search) || '%'
      or record.patient_passport ilike btrim(p_search) || '%'
      or record.professional_name ilike '%' || btrim(p_search) || '%'
    )
      and (p_professional_id is null or record.professional_id = p_professional_id)
      and (not coalesce(p_mine, false) or record.professional_id = v_actor)
      and (p_status is null or record.status = p_status)
      and (p_date_from is null or record.starts_at >= p_date_from)
      and (p_date_to is null or record.starts_at < p_date_to)
  ), page_rows as (
    select * from filtered order by starts_at desc, created_at desc limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'items', coalesce((select jsonb_agg(to_jsonb(page_row) order by page_row.starts_at desc, page_row.created_at desc) from page_rows page_row), '[]'::jsonb),
    'total', (select count(*) from filtered)
  ) into v_result;
  return v_result;
end;
$$;

create or replace function public.clinical_consultation_detail(p_consultation_id bigint)
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
  if not private.has_permission(v_actor, 'consultations.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  select jsonb_build_object(
    'id', consultation.id,
    'status', consultation.status,
    'patient', jsonb_build_object(
      'id', patient.id,
      'name', patient.name,
      'passport', patient.passport,
      'allergies', patient.allergies,
      'plan_active', exists (
        select 1 from public.patient_health_plan_requests plan
        where plan.patient_id = patient.id and plan.status = 'approved'
          and (plan.coverage_end is null or plan.coverage_end >= current_date)
      ),
      'cast_active', exists (
        select 1 from public.clinical_casts cast_record
        where cast_record.patient_id = patient.id and cast_record.status = 'in_use'
      ),
      'hospitalization_active', exists (
        select 1 from public.hospitalizations hospitalization
        where hospitalization.patient_id = patient.id and hospitalization.status = 'active'
      )
    ),
    'professional', jsonb_build_object('id', professional.user_id, 'name', professional.display_name, 'position', position.name),
    'appointment', case when appointment.id is null then null else jsonb_build_object(
      'id', appointment.id,
      'scheduled_start', appointment.scheduled_start,
      'scheduled_end', appointment.scheduled_end,
      'reason', appointment.reason,
      'notes', appointment.notes
    ) end,
    'started_at', consultation.started_at,
    'completed_at', consultation.completed_at,
    'vitals', jsonb_build_object(
      'blood_pressure_systolic', consultation.blood_pressure_systolic,
      'blood_pressure_diastolic', consultation.blood_pressure_diastolic,
      'blood_pressure_class', consultation.blood_pressure_class,
      'temperature_c', consultation.temperature_c,
      'temperature_class', consultation.temperature_class,
      'heart_rate_bpm', consultation.heart_rate_bpm,
      'heart_rate_class', consultation.heart_rate_class,
      'oxygen_saturation_percent', consultation.oxygen_saturation_percent,
      'oxygen_saturation_class', consultation.oxygen_saturation_class,
      'pain_score', consultation.pain_score
    ),
    'anamnesis', consultation.anamnesis,
    'selected_diagnosis', consultation.selected_diagnosis,
    'final_diagnosis_plan', consultation.final_diagnosis_plan,
    'complementary_action', consultation.complementary_action,
    'orientation_text', consultation.orientation_text,
    'final_snapshot', consultation.final_snapshot,
    'ai_generations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'action_type', generation.action_type,
        'status', generation.status,
        'response', generation.response_payload,
        'error', generation.error_message,
        'requested_at', generation.requested_at,
        'completed_at', generation.completed_at
      ) order by generation.id)
      from public.consultation_ai_generations generation
      where generation.consultation_id = consultation.id
    ), '[]'::jsonb),
    'exams', case when private.has_permission(v_actor, 'exams.view') then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', exam.id,
        'type', exam_type.name,
        'status', exam.status,
        'conclusion', exam.conclusion,
        'completed_at', exam.completed_at
      ) order by exam.requested_at desc, exam.id desc)
      from public.clinical_exams exam
      join public.exam_types exam_type on exam_type.id = exam.exam_type_id
      where exam.consultation_id = consultation.id
    ), '[]'::jsonb) else '[]'::jsonb end,
    'casts', case when private.has_permission(v_actor, 'casts.view') then coalesce((
      select jsonb_agg(jsonb_build_object('id', cast_record.id, 'body_region', cast_record.body_region, 'status', cast_record.status, 'applied_at', cast_record.applied_at) order by cast_record.id desc)
      from public.clinical_casts cast_record where cast_record.consultation_id = consultation.id
    ), '[]'::jsonb) else '[]'::jsonb end,
    'hospitalizations', case when private.has_permission(v_actor, 'hospitalizations.view') then coalesce((
      select jsonb_agg(jsonb_build_object('id', hospitalization.id, 'status', hospitalization.status, 'admitted_at', hospitalization.admitted_at) order by hospitalization.id desc)
      from public.hospitalizations hospitalization where hospitalization.consultation_id = consultation.id
    ), '[]'::jsonb) else '[]'::jsonb end,
    'certificates', case when private.has_permission(v_actor, 'atestados.view') then coalesce((
      select jsonb_agg(jsonb_build_object('id', certificate.id, 'status', certificate.status, 'leave_days', certificate.leave_days, 'created_at', certificate.created_at) order by certificate.id desc)
      from public.medical_certificates certificate where certificate.consultation_id = consultation.id
    ), '[]'::jsonb) else '[]'::jsonb end,
    'can_edit', private.can_edit_consultation(v_actor, consultation.professional_id) and consultation.status = 'in_progress'
  ) into v_result
  from public.clinical_consultations consultation
  join public.patients patient on patient.id = consultation.patient_id
  join public.profiles professional on professional.user_id = consultation.professional_id
  left join public.staff_positions position on position.id = professional.position_id
  left join public.patient_appointments appointment on appointment.id = consultation.appointment_id
  where consultation.id = p_consultation_id;
  if v_result is null then raise exception 'Consulta não localizada.'; end if;
  return v_result;
end;
$$;

create or replace function public.create_patient_appointment(
  p_patient_id bigint,
  p_professional_id uuid,
  p_scheduled_start timestamptz,
  p_duration_minutes integer,
  p_reason text,
  p_notes text default null,
  p_follow_up_of_consultation_id bigint default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_professional uuid := coalesce(p_professional_id, v_actor);
  v_appointment public.patient_appointments;
begin
  if not private.has_permission(v_actor, 'consultations.create') or not private.has_permission(v_actor, 'patients.view') or not private.is_hpsm_workforce(v_actor) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if v_professional <> v_actor and not private.has_permission(v_actor, 'consultations.manage') then
    raise exception 'Somente gestores podem agendar para outro profissional.' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.profiles profile
    join public.staff_positions position on position.id = profile.position_id
    where profile.user_id = v_professional and profile.status = 'active' and position.official and position.active
      and private.has_permission(profile.user_id, 'consultations.create')
  ) then raise exception 'Profissional inválido.'; end if;
  if not exists (select 1 from public.patients patient where patient.id = p_patient_id) then raise exception 'Paciente não localizado.'; end if;
  if p_scheduled_start < now() - interval '5 minutes' then raise exception 'O horário precisa ser atual ou futuro.'; end if;
  if p_duration_minutes is null or p_duration_minutes not between 5 and 480 then raise exception 'A duração deve ficar entre 5 e 480 minutos.'; end if;
  if char_length(btrim(coalesce(p_reason, ''))) not between 3 and 500 then raise exception 'Informe o motivo da consulta.'; end if;
  if p_follow_up_of_consultation_id is not null and not exists (
    select 1 from public.clinical_consultations consultation
    where consultation.id = p_follow_up_of_consultation_id and consultation.patient_id = p_patient_id and consultation.professional_id = v_actor
  ) then raise exception 'A consulta de origem não é válida.'; end if;

  insert into public.patient_appointments (
    patient_id, professional_id, scheduled_start, scheduled_end, duration_minutes,
    reason, notes, created_by, follow_up_of_consultation_id
  ) values (
    p_patient_id, v_professional, p_scheduled_start, p_scheduled_start + make_interval(mins => p_duration_minutes), p_duration_minutes,
    btrim(p_reason), nullif(btrim(coalesce(p_notes, '')), ''), v_actor, p_follow_up_of_consultation_id
  ) returning * into v_appointment;
  return v_appointment.id;
exception
  when exclusion_violation then
    raise exception 'Este profissional já possui um compromisso no período informado.' using errcode = '23P01';
end;
$$;

create or replace function public.set_patient_appointment_status(
  p_appointment_id bigint,
  p_status text,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_appointment public.patient_appointments;
begin
  select * into v_appointment from public.patient_appointments where id = p_appointment_id for update;
  if v_appointment.id is null then raise exception 'Agendamento não localizado.'; end if;
  if not private.has_permission(v_actor, 'consultations.create') or not private.is_hpsm_workforce(v_actor)
     or (v_appointment.professional_id <> v_actor and not private.has_permission(v_actor, 'consultations.manage')) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if p_status = 'confirmed' and v_appointment.status = 'scheduled' then
    update public.patient_appointments set status = 'confirmed', confirmed_by = v_actor, confirmed_at = now() where id = p_appointment_id;
  elsif p_status = 'cancelled' and v_appointment.status in ('scheduled', 'confirmed') then
    if char_length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'Informe o motivo do cancelamento.'; end if;
    update public.patient_appointments set status = 'cancelled', cancelled_by = v_actor, cancelled_at = now(), cancellation_reason = btrim(p_reason) where id = p_appointment_id;
  elsif p_status = 'no_show' and v_appointment.status in ('scheduled', 'confirmed') then
    update public.patient_appointments set status = 'no_show', no_show_by = v_actor, no_show_at = now() where id = p_appointment_id;
  else
    raise exception 'Transição de status inválida.';
  end if;
end;
$$;

create or replace function public.start_scheduled_consultation(p_appointment_id bigint)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_appointment public.patient_appointments;
  v_consultation public.clinical_consultations;
begin
  select * into v_appointment from public.patient_appointments where id = p_appointment_id for update;
  if v_appointment.id is null then raise exception 'Agendamento não localizado.'; end if;
  if v_appointment.professional_id <> v_actor or not private.has_permission(v_actor, 'consultations.create') or not private.is_hpsm_workforce(v_actor) then
    raise exception 'Somente o profissional responsável pode iniciar a consulta.' using errcode = '42501';
  end if;
  if v_appointment.status not in ('scheduled', 'confirmed') then raise exception 'Este agendamento não pode ser iniciado.'; end if;
  if exists (select 1 from public.clinical_consultations where appointment_id = p_appointment_id) then
    select * into v_consultation from public.clinical_consultations where appointment_id = p_appointment_id;
    return v_consultation.id;
  end if;
  insert into public.clinical_consultations (patient_id, professional_id, appointment_id, created_by)
  values (v_appointment.patient_id, v_actor, p_appointment_id, v_actor)
  returning * into v_consultation;
  update public.patient_appointments set status = 'in_progress', started_at = v_consultation.started_at where id = p_appointment_id;
  return v_consultation.id;
end;
$$;

create or replace function public.start_walk_in_consultation(p_patient_id bigint)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_consultation public.clinical_consultations;
begin
  if not private.has_permission(v_actor, 'consultations.create') or not private.has_permission(v_actor, 'patients.view') or not private.is_hpsm_workforce(v_actor) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.patients patient where patient.id = p_patient_id) then raise exception 'Paciente não localizado.'; end if;
  insert into public.clinical_consultations (patient_id, professional_id, created_by)
  values (p_patient_id, v_actor, v_actor) returning * into v_consultation;
  return v_consultation.id;
end;
$$;

create or replace function public.save_clinical_consultation_draft(
  p_consultation_id bigint,
  p_blood_pressure_systolic integer,
  p_blood_pressure_diastolic integer,
  p_blood_pressure_class text,
  p_temperature_c numeric,
  p_temperature_class text,
  p_heart_rate_bpm integer,
  p_heart_rate_class text,
  p_oxygen_saturation_percent integer,
  p_oxygen_saturation_class text,
  p_pain_score integer,
  p_anamnesis text,
  p_selected_diagnosis jsonb,
  p_final_diagnosis_plan text,
  p_complementary_action text,
  p_orientation_text text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_consultation public.clinical_consultations;
begin
  select * into v_consultation from public.clinical_consultations where id = p_consultation_id for update;
  if v_consultation.id is null then raise exception 'Consulta não localizada.'; end if;
  if not private.can_edit_consultation(v_actor, v_consultation.professional_id) then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if v_consultation.status <> 'in_progress' then raise exception 'A consulta já foi concluída.'; end if;
  if p_complementary_action not in ('NONE', 'CAST', 'HOSPITALIZATION') then raise exception 'Conduta complementar inválida.'; end if;
  if p_selected_diagnosis is not null and (
    jsonb_typeof(p_selected_diagnosis) <> 'object'
    or p_selected_diagnosis->>'severity' not in ('normal', 'grave', 'gravissimo')
    or char_length(btrim(coalesce(p_selected_diagnosis->>'title', ''))) < 3
  ) then raise exception 'Diagnóstico selecionado inválido.'; end if;

  update public.clinical_consultations set
    blood_pressure_systolic = p_blood_pressure_systolic,
    blood_pressure_diastolic = p_blood_pressure_diastolic,
    blood_pressure_class = nullif(btrim(coalesce(p_blood_pressure_class, '')), ''),
    temperature_c = p_temperature_c,
    temperature_class = nullif(btrim(coalesce(p_temperature_class, '')), ''),
    heart_rate_bpm = p_heart_rate_bpm,
    heart_rate_class = nullif(btrim(coalesce(p_heart_rate_class, '')), ''),
    oxygen_saturation_percent = p_oxygen_saturation_percent,
    oxygen_saturation_class = nullif(btrim(coalesce(p_oxygen_saturation_class, '')), ''),
    pain_score = p_pain_score,
    anamnesis = nullif(btrim(coalesce(p_anamnesis, '')), ''),
    selected_diagnosis = p_selected_diagnosis,
    final_diagnosis_plan = nullif(btrim(coalesce(p_final_diagnosis_plan, '')), ''),
    complementary_action = p_complementary_action,
    orientation_text = nullif(btrim(coalesce(p_orientation_text, '')), '')
  where id = p_consultation_id;
end;
$$;

create or replace function public.complete_clinical_consultation(p_consultation_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_consultation public.clinical_consultations;
  v_snapshot jsonb;
begin
  select * into v_consultation from public.clinical_consultations where id = p_consultation_id for update;
  if v_consultation.id is null then raise exception 'Consulta não localizada.'; end if;
  if not private.can_edit_consultation(v_actor, v_consultation.professional_id) then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if v_consultation.status <> 'in_progress' then raise exception 'A consulta já foi concluída.'; end if;
  if v_consultation.blood_pressure_systolic is null or v_consultation.blood_pressure_diastolic is null or v_consultation.blood_pressure_class is null
     or v_consultation.temperature_c is null or v_consultation.temperature_class is null
     or v_consultation.heart_rate_bpm is null or v_consultation.heart_rate_class is null
     or v_consultation.oxygen_saturation_percent is null or v_consultation.oxygen_saturation_class is null
     or v_consultation.pain_score is null then
    raise exception 'Preencha e classifique todos os sinais vitais e a escala de dor.';
  end if;
  if char_length(btrim(coalesce(v_consultation.anamnesis, ''))) < 3 then raise exception 'Preencha a anamnese e evolução.'; end if;
  if v_consultation.selected_diagnosis is null then raise exception 'Selecione uma hipótese diagnóstica.'; end if;
  if char_length(btrim(coalesce(v_consultation.final_diagnosis_plan, ''))) < 3 then raise exception 'Preencha o diagnóstico final e o plano.'; end if;

  select jsonb_build_object(
    'schema', 'hpsm.clinical_consultation.v1',
    'consultation_id', v_consultation.id,
    'patient', jsonb_build_object('id', patient.id, 'name', patient.name, 'passport', patient.passport),
    'professional', jsonb_build_object('id', profile.user_id, 'name', profile.display_name, 'position', position.name),
    'appointment_id', v_consultation.appointment_id,
    'started_at', v_consultation.started_at,
    'completed_at', now(),
    'vitals', jsonb_build_object(
      'blood_pressure_systolic', v_consultation.blood_pressure_systolic,
      'blood_pressure_diastolic', v_consultation.blood_pressure_diastolic,
      'blood_pressure_class', v_consultation.blood_pressure_class,
      'temperature_c', v_consultation.temperature_c,
      'temperature_class', v_consultation.temperature_class,
      'heart_rate_bpm', v_consultation.heart_rate_bpm,
      'heart_rate_class', v_consultation.heart_rate_class,
      'oxygen_saturation_percent', v_consultation.oxygen_saturation_percent,
      'oxygen_saturation_class', v_consultation.oxygen_saturation_class,
      'pain_score', v_consultation.pain_score
    ),
    'anamnesis', v_consultation.anamnesis,
    'selected_diagnosis', v_consultation.selected_diagnosis,
    'final_diagnosis_plan', v_consultation.final_diagnosis_plan,
    'complementary_action', v_consultation.complementary_action,
    'orientation_text', v_consultation.orientation_text,
    'exam_ids', coalesce((select jsonb_agg(exam.id order by exam.id) from public.clinical_exams exam where exam.consultation_id = v_consultation.id), '[]'::jsonb),
    'cast_ids', coalesce((select jsonb_agg(cast_record.id order by cast_record.id) from public.clinical_casts cast_record where cast_record.consultation_id = v_consultation.id), '[]'::jsonb),
    'hospitalization_ids', coalesce((select jsonb_agg(hospitalization.id order by hospitalization.id) from public.hospitalizations hospitalization where hospitalization.consultation_id = v_consultation.id), '[]'::jsonb),
    'certificate_ids', coalesce((select jsonb_agg(certificate.id order by certificate.id) from public.medical_certificates certificate where certificate.consultation_id = v_consultation.id), '[]'::jsonb)
  ) into v_snapshot
  from public.patients patient
  join public.profiles profile on profile.user_id = v_consultation.professional_id
  left join public.staff_positions position on position.id = profile.position_id
  where patient.id = v_consultation.patient_id;

  update public.clinical_consultations
  set status = 'completed', completed_at = now(), final_snapshot = v_snapshot
  where id = p_consultation_id;
  if v_consultation.appointment_id is not null then
    update public.patient_appointments
    set status = 'completed', completed_at = now()
    where id = v_consultation.appointment_id and status = 'in_progress';
  end if;
  return v_snapshot;
end;
$$;

create or replace function public.begin_consultation_ai_generation(
  p_consultation_id bigint,
  p_action_type text,
  p_request_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_consultation public.clinical_consultations;
  v_generation public.consultation_ai_generations;
begin
  select * into v_consultation from public.clinical_consultations where id = p_consultation_id for update;
  if v_consultation.id is null then raise exception 'Consulta não localizada.'; end if;
  if not private.can_edit_consultation(v_actor, v_consultation.professional_id) or v_consultation.status <> 'in_progress' then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if p_action_type not in ('ANAMNESIS_REWRITE', 'EXAM_SUGGESTIONS', 'DIAGNOSIS_OPTIONS', 'FINAL_DIAGNOSIS_PLAN', 'ORIENTATION_MEDICATION') then
    raise exception 'Ação de IA inválida.';
  end if;
  if p_request_key is null then raise exception 'Identificador da solicitação ausente.'; end if;

  select * into v_generation from public.consultation_ai_generations
  where consultation_id = p_consultation_id and action_type = p_action_type
  for update;
  if v_generation.id is null then
    insert into public.consultation_ai_generations (consultation_id, action_type, request_key, requested_by)
    values (p_consultation_id, p_action_type, p_request_key, v_actor)
    returning * into v_generation;
  elsif v_generation.status = 'failed' then
    update public.consultation_ai_generations set
      status = 'pending', request_key = p_request_key, response_payload = null, error_message = null,
      model = null, prompt_version = null, requested_by = v_actor, requested_at = now(), completed_at = null, failed_at = null
    where id = v_generation.id returning * into v_generation;
  end if;
  return jsonb_build_object(
    'id', v_generation.id,
    'status', v_generation.status,
    'request_key', v_generation.request_key,
    'response', v_generation.response_payload
  );
end;
$$;

create or replace function public.complete_consultation_ai_generation(
  p_consultation_id bigint,
  p_action_type text,
  p_request_key uuid,
  p_response_payload jsonb,
  p_model text,
  p_prompt_version text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_generation public.consultation_ai_generations;
begin
  select generation.* into v_generation
  from public.consultation_ai_generations generation
  join public.clinical_consultations consultation on consultation.id = generation.consultation_id
  where generation.consultation_id = p_consultation_id and generation.action_type = p_action_type
    and private.can_edit_consultation(v_actor, consultation.professional_id)
  for update of generation;
  if v_generation.id is null or v_generation.request_key <> p_request_key then raise exception 'Solicitação de IA inválida.' using errcode = '42501'; end if;
  if v_generation.status = 'completed' then return v_generation.response_payload; end if;
  if v_generation.status <> 'pending' or p_response_payload is null or jsonb_typeof(p_response_payload) <> 'object' then raise exception 'Resposta de IA inválida.'; end if;
  if p_action_type = 'DIAGNOSIS_OPTIONS' and (
    jsonb_typeof(p_response_payload->'options') <> 'array'
    or jsonb_array_length(p_response_payload->'options') <> 3
    or (select array_agg(option->>'severity' order by option->>'severity') from jsonb_array_elements(p_response_payload->'options') option)
       <> array['grave', 'gravissimo', 'normal']::text[]
  ) then raise exception 'A IA deve retornar exatamente as opções Normal, Grave e Gravíssimo.'; end if;
  if p_action_type = 'EXAM_SUGGESTIONS' and exists (
    select 1
    from jsonb_array_elements(coalesce(p_response_payload->'suggestions', '[]'::jsonb)) suggestion
    where not exists (
      select 1 from public.exam_types exam_type
      join public.exam_categories category on category.id = exam_type.category_id
      where exam_type.id = nullif(suggestion->>'exam_type_id', '')::bigint and exam_type.active and category.active
    )
  ) then raise exception 'A IA sugeriu um tipo de exame indisponível.'; end if;
  update public.consultation_ai_generations set
    status = 'completed', response_payload = p_response_payload, error_message = null,
    model = btrim(p_model), prompt_version = btrim(p_prompt_version), completed_at = now(), failed_at = null
  where id = v_generation.id;
  return p_response_payload;
end;
$$;

create or replace function public.fail_consultation_ai_generation(
  p_consultation_id bigint,
  p_action_type text,
  p_request_key uuid,
  p_error_message text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
begin
  update public.consultation_ai_generations generation set
    status = 'failed', error_message = left(coalesce(nullif(btrim(p_error_message), ''), 'Falha ao gerar assistência.'), 1000), failed_at = now()
  from public.clinical_consultations consultation
  where generation.consultation_id = p_consultation_id
    and generation.action_type = p_action_type
    and generation.request_key = p_request_key
    and generation.status = 'pending'
    and consultation.id = generation.consultation_id
    and private.can_edit_consultation(v_actor, consultation.professional_id);
end;
$$;

create or replace function public.create_consultation_clinical_exam(
  p_consultation_id bigint,
  p_exam_type_id bigint,
  p_indication text,
  p_clinical_context text default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_consultation public.clinical_consultations;
  v_exam_id bigint;
begin
  select * into v_consultation from public.clinical_consultations where id = p_consultation_id for update;
  if v_consultation.id is null then raise exception 'Consulta não localizada.'; end if;
  if not private.can_edit_consultation(v_actor, v_consultation.professional_id) or v_consultation.status <> 'in_progress' then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  v_exam_id := public.create_clinical_exam(
    v_consultation.patient_id,
    p_exam_type_id,
    v_actor,
    p_indication,
    p_clinical_context,
    null
  );
  update public.clinical_exams set consultation_id = p_consultation_id where id = v_exam_id;
  return v_exam_id;
end;
$$;

create or replace function public.link_consultation_cast(p_consultation_id bigint, p_cast_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_consultation public.clinical_consultations;
begin
  select * into v_consultation from public.clinical_consultations where id = p_consultation_id;
  if v_consultation.id is null or not private.can_edit_consultation(v_actor, v_consultation.professional_id) or v_consultation.status <> 'in_progress' then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  update public.clinical_casts set consultation_id = p_consultation_id
  where id = p_cast_id and patient_id = v_consultation.patient_id and created_by = v_actor and consultation_id is null;
  if not found then raise exception 'Registro de gesso incompatível com a consulta.'; end if;
end;
$$;

create or replace function public.link_consultation_hospitalization(p_consultation_id bigint, p_hospitalization_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_consultation public.clinical_consultations;
begin
  select * into v_consultation from public.clinical_consultations where id = p_consultation_id;
  if v_consultation.id is null or not private.can_edit_consultation(v_actor, v_consultation.professional_id) or v_consultation.status <> 'in_progress' then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  update public.hospitalizations set consultation_id = p_consultation_id
  where id = p_hospitalization_id and patient_id = v_consultation.patient_id and admitted_by = v_actor and consultation_id is null;
  if not found then raise exception 'Internação incompatível com a consulta.'; end if;
end;
$$;

create or replace function public.create_consultation_medical_certificate(
  p_consultation_id bigint,
  p_medical_context text,
  p_leave_days integer,
  p_exam_ids bigint[] default '{}'::bigint[],
  p_cast_ids bigint[] default '{}'::bigint[]
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_consultation public.clinical_consultations;
  v_context text := btrim(coalesce(p_medical_context, ''));
  v_certificate public.medical_certificates;
begin
  if not private.has_permission(v_actor, 'atestados.create') or not private.has_permission(v_actor, 'patients.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  select * into v_consultation from public.clinical_consultations where id = p_consultation_id;
  if v_consultation.id is null or not private.can_edit_consultation(v_actor, v_consultation.professional_id) or v_consultation.status <> 'in_progress' then
    raise exception 'A consulta não está disponível para emissão.' using errcode = '42501';
  end if;
  if char_length(v_context) not between 3 and 4000 then raise exception 'Informe o motivo e o contexto médico.'; end if;
  if p_leave_days is null or p_leave_days not between 1 and 365 then raise exception 'Informe manualmente uma quantidade inteira e positiva de dias.'; end if;
  insert into public.medical_certificates (patient_id, consultation_id, created_by, medical_context, leave_days)
  values (v_consultation.patient_id, p_consultation_id, v_actor, v_context, p_leave_days)
  returning * into v_certificate;
  perform private.set_medical_certificate_links(v_certificate.id, v_consultation.patient_id, v_actor, p_exam_ids, p_cast_ids);
  perform private.audit_medical_certificate_action(v_actor, 'MEDICAL_CERTIFICATE_CREATED', v_certificate.id, null, jsonb_build_object(
    'patient_id', v_consultation.patient_id, 'consultation_id', p_consultation_id, 'leave_days', p_leave_days,
    'exam_ids', coalesce(p_exam_ids, '{}'::bigint[]), 'cast_ids', coalesce(p_cast_ids, '{}'::bigint[]), 'status', 'draft'
  ));
  return v_certificate.id;
end;
$$;

create or replace function public.medical_certificate_detail(p_certificate_id bigint)
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
  if not private.has_permission(v_actor, 'atestados.view') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  select jsonb_build_object(
    'id', certificate.id,
    'patient_id', certificate.patient_id,
    'patient_name', patient.name,
    'patient_passport', patient.passport,
    'attendance_id', certificate.attendance_id,
    'consultation_id', certificate.consultation_id,
    'origin_type', case when certificate.consultation_id is not null then 'consultation' else 'attendance' end,
    'attendance_created_at', coalesce(attendance.created_at, consultation.started_at),
    'attendance_summary', case when certificate.consultation_id is not null then 'Consulta clínica #' || certificate.consultation_id::text else coalesce((
      select string_agg(item.service_name || case when item.quantity > 1 then ' ×' || item.quantity::text else '' end, ', ' order by item.id)
      from public.attendance_items item where item.attendance_id = attendance.id
    ), 'Atendimento sem itens') end,
    'created_by', certificate.created_by,
    'professional_name', creator.display_name,
    'professional_position', position.name,
    'medical_context', certificate.medical_context,
    'leave_days', certificate.leave_days,
    'generated_text', certificate.generated_text,
    'final_text', certificate.final_text,
    'status', certificate.status,
    'ai_model', certificate.ai_model,
    'ai_prompt_version', certificate.ai_prompt_version,
    'ai_generated_at', certificate.ai_generated_at,
    'finalized_at', certificate.finalized_at,
    'professional_snapshot', certificate.professional_snapshot,
    'document_ready', certificate.final_png_path is not null,
    'cancelled_at', certificate.cancelled_at,
    'cancellation_reason', certificate.cancellation_reason,
    'created_at', certificate.created_at,
    'updated_at', certificate.updated_at,
    'exams', coalesce((
      select jsonb_agg(jsonb_build_object('id', exam.id, 'type', exam_type.name, 'status', exam.status, 'requested_at', exam.requested_at, 'completed_at', exam.completed_at) order by exam.requested_at desc, exam.id desc)
      from public.medical_certificate_exams link
      join public.clinical_exams exam on exam.id = link.exam_id
      join public.exam_types exam_type on exam_type.id = exam.exam_type_id
      where link.certificate_id = certificate.id
    ), '[]'::jsonb),
    'casts', coalesce((
      select jsonb_agg(jsonb_build_object('id', cast_record.id, 'body_region', cast_record.body_region, 'laterality', cast_record.laterality, 'status', cast_record.status, 'applied_at', cast_record.applied_at) order by cast_record.applied_at desc, cast_record.id desc)
      from public.medical_certificate_casts link
      join public.clinical_casts cast_record on cast_record.id = link.cast_id
      where link.certificate_id = certificate.id
    ), '[]'::jsonb)
  ) into v_result
  from public.medical_certificates certificate
  join public.patients patient on patient.id = certificate.patient_id
  left join public.attendances attendance on attendance.id = certificate.attendance_id
  left join public.clinical_consultations consultation on consultation.id = certificate.consultation_id
  join public.profiles creator on creator.user_id = certificate.created_by
  left join public.staff_positions position on position.id = creator.position_id
  where certificate.id = p_certificate_id;
  if v_result is null then raise exception 'Atestado não localizado.'; end if;
  return v_result;
end;
$$;

create or replace function public.finalize_medical_certificate(p_certificate_id bigint, p_final_text text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_certificate public.medical_certificates;
  v_text text := btrim(coalesce(p_final_text, ''));
  v_snapshot jsonb;
begin
  if not private.has_permission(v_actor, 'atestados.finalize') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  select * into v_certificate from public.medical_certificates where id = p_certificate_id for update;
  if v_certificate.id is null then raise exception 'Atestado não localizado.'; end if;
  if v_certificate.status <> 'draft' then raise exception 'Este atestado já foi finalizado ou cancelado.'; end if;
  if v_certificate.created_by <> v_actor then raise exception 'Somente o responsável pode finalizar este atestado.' using errcode = '42501'; end if;
  if not private.medical_certificate_text_matches_days(v_text, v_certificate.leave_days) then
    raise exception 'O texto final precisa mencionar exatamente % dias e não pode conter outro período divergente.', v_certificate.leave_days;
  end if;
  select jsonb_build_object(
    'schema', 'hpsm.medical_certificate_snapshot.v1',
    'certificate_id', v_certificate.id,
    'origin_type', case when v_certificate.consultation_id is not null then 'consultation' else 'attendance' end,
    'patient', jsonb_build_object('id', patient.id, 'name', patient.name, 'passport', patient.passport),
    'attendance', jsonb_build_object('id', coalesce(attendance.id, consultation.id), 'created_at', coalesce(attendance.created_at, consultation.started_at)),
    'consultation_id', v_certificate.consultation_id,
    'leave_days', v_certificate.leave_days,
    'text', v_text,
    'issued_at', now(),
    'professional', jsonb_build_object(
      'id', profile.user_id, 'name', profile.display_name, 'position', position.name,
      'crm_code', identity.crm_code, 'registration_date', identity.registration_date,
      'signature_image_path', identity.signature_image_path
    )
  ) into v_snapshot
  from public.patients patient
  left join public.attendances attendance on attendance.id = v_certificate.attendance_id and attendance.patient_id = patient.id
  left join public.clinical_consultations consultation on consultation.id = v_certificate.consultation_id and consultation.patient_id = patient.id
  join public.profiles profile on profile.user_id = v_actor and profile.status = 'active'
  left join public.staff_positions position on position.id = profile.position_id
  join public.professional_identities identity on identity.user_id = profile.user_id
    and identity.status = 'active' and identity.signature_image_path is not null and identity.crm_code ~ '^[0-9]{8}$'
  where patient.id = v_certificate.patient_id
    and (attendance.id is not null or consultation.id is not null);
  if v_snapshot is null then raise exception 'A identidade profissional precisa estar ativa antes da finalização.'; end if;
  update public.medical_certificates set status = 'finalized', final_text = v_text, finalized_at = now(), finalized_by = v_actor, professional_snapshot = v_snapshot where id = p_certificate_id;
  perform private.audit_medical_certificate_action(v_actor, 'MEDICAL_CERTIFICATE_FINALIZED', p_certificate_id,
    jsonb_build_object('status', 'draft'), jsonb_build_object('status', 'finalized', 'leave_days', v_certificate.leave_days, 'snapshot_schema', v_snapshot->>'schema'));
  return v_snapshot;
end;
$$;

revoke all on function public.consultation_reference_data() from public, anon;
revoke all on function public.consultation_schedule_page(text, uuid, text, timestamptz, timestamptz, boolean, integer, integer) from public, anon;
revoke all on function public.clinical_consultation_detail(bigint) from public, anon;
revoke all on function public.create_patient_appointment(bigint, uuid, timestamptz, integer, text, text, bigint) from public, anon;
revoke all on function public.set_patient_appointment_status(bigint, text, text) from public, anon;
revoke all on function public.start_scheduled_consultation(bigint) from public, anon;
revoke all on function public.start_walk_in_consultation(bigint) from public, anon;
revoke all on function public.save_clinical_consultation_draft(bigint, integer, integer, text, numeric, text, integer, text, integer, text, integer, text, jsonb, text, text, text) from public, anon;
revoke all on function public.complete_clinical_consultation(bigint) from public, anon;
revoke all on function public.begin_consultation_ai_generation(bigint, text, uuid) from public, anon;
revoke all on function public.complete_consultation_ai_generation(bigint, text, uuid, jsonb, text, text) from public, anon;
revoke all on function public.fail_consultation_ai_generation(bigint, text, uuid, text) from public, anon;
revoke all on function public.create_consultation_clinical_exam(bigint, bigint, text, text) from public, anon;
revoke all on function public.link_consultation_cast(bigint, bigint) from public, anon;
revoke all on function public.link_consultation_hospitalization(bigint, bigint) from public, anon;
revoke all on function public.create_consultation_medical_certificate(bigint, text, integer, bigint[], bigint[]) from public, anon;

grant execute on function public.consultation_reference_data() to authenticated, service_role;
grant execute on function public.consultation_schedule_page(text, uuid, text, timestamptz, timestamptz, boolean, integer, integer) to authenticated, service_role;
grant execute on function public.clinical_consultation_detail(bigint) to authenticated, service_role;
grant execute on function public.create_patient_appointment(bigint, uuid, timestamptz, integer, text, text, bigint) to authenticated, service_role;
grant execute on function public.set_patient_appointment_status(bigint, text, text) to authenticated, service_role;
grant execute on function public.start_scheduled_consultation(bigint) to authenticated, service_role;
grant execute on function public.start_walk_in_consultation(bigint) to authenticated, service_role;
grant execute on function public.save_clinical_consultation_draft(bigint, integer, integer, text, numeric, text, integer, text, integer, text, integer, text, jsonb, text, text, text) to authenticated, service_role;
grant execute on function public.complete_clinical_consultation(bigint) to authenticated, service_role;
grant execute on function public.begin_consultation_ai_generation(bigint, text, uuid) to authenticated, service_role;
grant execute on function public.complete_consultation_ai_generation(bigint, text, uuid, jsonb, text, text) to authenticated, service_role;
grant execute on function public.fail_consultation_ai_generation(bigint, text, uuid, text) to authenticated, service_role;
grant execute on function public.create_consultation_clinical_exam(bigint, bigint, text, text) to authenticated, service_role;
grant execute on function public.link_consultation_cast(bigint, bigint) to authenticated, service_role;
grant execute on function public.link_consultation_hospitalization(bigint, bigint) to authenticated, service_role;
grant execute on function public.create_consultation_medical_certificate(bigint, text, integer, bigint[], bigint[]) to authenticated, service_role;

comment on table public.patient_appointments is 'Agenda clínica sem vínculo com vendas, plantões, metas ou disponibilidade funcional.';
comment on table public.clinical_consultations is 'Prontuário clínico longitudinal independente do fluxo financeiro.';
comment on table public.consultation_ai_generations is 'Execuções idempotentes e auditáveis de assistência por IA na consulta.';
