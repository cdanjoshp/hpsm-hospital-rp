-- Primeiro rollup pós-GO: alergias de pacientes e apresentação v2 de novos laudos.
-- Compatível com produção: pacientes legados permanecem com allergies nulo e
-- snapshots/documentos finais já concluídos não são reescritos.

set lock_timeout = '5s';
set statement_timeout = '120s';

alter table public.patients
  add column if not exists allergies text;

alter table public.patients
  drop constraint if exists patients_allergies_check,
  add constraint patients_allergies_check
    check (
      allergies is null
      or char_length(btrim(allergies)) between 1 and 1000
    );

comment on column public.patients.allergies is
  'Alergias declaradas pelo paciente. Nulo apenas para cadastros legados ainda não atualizados; a aplicação exige o campo em novos cadastros e edições.';

create or replace view public.patient_directory
with (security_invoker = true)
as
select
  patient.id,
  patient.passport,
  patient.name,
  patient.phone,
  patient.emergency_contact_name,
  patient.emergency_contact_phone,
  patient.created_at,
  patient.updated_at,
  last_attendance.created_at as last_attendance_at,
  case
    when approved.coverage_end > now() then 'active'
    when approved.id is not null then 'expired'
    when pending.id is not null then 'awaiting_confirmation'
    else 'none'
  end as plan_status,
  approved.coverage_start as plan_activated_at,
  approved.coverage_end as plan_valid_until,
  approved.reviewed_by as plan_authorized_by,
  reviewer.display_name as plan_authorized_by_name,
  pending.id as pending_request_id,
  pending.requested_at as pending_requested_at,
  patient.birth_date,
  patient.allergies
from public.patients patient
left join lateral (
  select attendance.created_at
  from public.attendances attendance
  where attendance.patient_id = patient.id
    and attendance.status = 'completed'
  order by attendance.created_at desc, attendance.id desc
  limit 1
) last_attendance on true
left join lateral (
  select request.id, request.coverage_start, request.coverage_end, request.reviewed_by
  from public.patient_health_plan_requests request
  where request.patient_id = patient.id
    and request.status = 'approved'
  order by request.reviewed_at desc nulls last, request.id desc
  limit 1
) approved on true
left join public.profiles reviewer on reviewer.user_id = approved.reviewed_by
left join lateral (
  select request.id, request.requested_at
  from public.patient_health_plan_requests request
  where request.patient_id = patient.id
    and request.status = 'pending'
  order by request.requested_at, request.id
  limit 1
) pending on true;

revoke all on public.patient_directory from public, anon, authenticated;
grant select on public.patient_directory to authenticated;

create or replace function public.hpsm_patient_quick_lookup(
  p_passport text,
  p_limit integer default 8
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
  v_passport text := btrim(coalesce(p_passport, ''));
  v_limit integer := least(greatest(coalesce(p_limit, 8), 1), 8);
  v_result jsonb;
begin
  if not ('patients.view' = any(v_permissions)) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if v_passport !~ '^[0-9]{1,4}$' then
    raise exception 'Informe um passaporte válido.' using errcode = '22023';
  end if;

  with matching as materialized (
    select patient.id, patient.passport, patient.name, patient.phone, patient.birth_date,
      patient.emergency_contact_name, patient.emergency_contact_phone, patient.allergies,
      patient.created_at, patient.updated_at
    from public.patients patient
    where patient.passport like v_passport || '%'
    order by (patient.passport = v_passport) desc, patient.passport
    limit v_limit
  ), plan_states as materialized (
    select matching.id as patient_id,
      case
        when approved.coverage_end > now() then 'active'
        when approved.id is not null then 'expired'
        when pending.id is not null then 'awaiting_confirmation'
        else 'none'
      end as status,
      approved.coverage_start as activated_at,
      approved.coverage_end as valid_until,
      approved.reviewed_by as authorized_by,
      reviewer.display_name as authorized_by_name,
      pending.id as pending_request_id,
      pending.requested_at as pending_requested_at
    from matching
    left join lateral (
      select request.id, request.coverage_start, request.coverage_end, request.reviewed_by
      from public.patient_health_plan_requests request
      where request.patient_id = matching.id
        and request.status = 'approved'
      order by request.reviewed_at desc nulls last, request.id desc
      limit 1
    ) approved on true
    left join public.profiles reviewer on reviewer.user_id = approved.reviewed_by
    left join lateral (
      select request.id, request.requested_at
      from public.patient_health_plan_requests request
      where request.patient_id = matching.id
        and request.status = 'pending'
      order by request.requested_at, request.id
      limit 1
    ) pending on true
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', matching.id,
    'passport', matching.passport,
    'name', matching.name,
    'phone', matching.phone,
    'birth_date', matching.birth_date,
    'emergency_contact_name', matching.emergency_contact_name,
    'emergency_contact_phone', matching.emergency_contact_phone,
    'allergies', matching.allergies,
    'created_at', matching.created_at,
    'updated_at', matching.updated_at,
    'health_plan', jsonb_build_object(
      'status', plan_states.status,
      'activated_at', plan_states.activated_at,
      'valid_until', plan_states.valid_until,
      'authorized_by', plan_states.authorized_by,
      'authorized_by_name', plan_states.authorized_by_name,
      'pending_request_id', plan_states.pending_request_id,
      'pending_requested_at', plan_states.pending_requested_at
    ),
    'partnerships', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', partnership.id,
        'name', partnership.name,
        'status', partnership.status,
        'linked_at', membership.linked_at
      ) order by lower(partnership.name))
      from public.patient_partnerships membership
      join public.partnerships partnership
        on partnership.id = membership.partnership_id
       and partnership.status = 'active'
      where membership.patient_id = matching.id
        and membership.status = 'active'
    ), '[]'::jsonb)
  ) order by (matching.passport = v_passport) desc, matching.passport), '[]'::jsonb)
  into v_result
  from matching
  join plan_states on plan_states.patient_id = matching.id;

  return v_result;
end;
$$;

revoke all on function public.hpsm_patient_quick_lookup(text, integer)
from public, anon, authenticated, service_role;
grant execute on function public.hpsm_patient_quick_lookup(text, integer) to authenticated;

-- Somente snapshots criados daqui em diante recebem o layout pós-GO.
-- O campo indication continua armazenado no snapshot e disponível ao fluxo interno.
do $$
declare
  v_definition text;
begin
  v_definition := pg_get_functiondef('private.build_clinical_exam_report_snapshot(bigint)'::regprocedure);
  if position('hpsm.exam_report_snapshot.v1' in v_definition) > 0 then
    execute replace(
      v_definition,
      '''hpsm.exam_report_snapshot.v1''',
      '''hpsm.exam_report_snapshot.v2'''
    );
  end if;
end;
$$;

comment on function private.build_clinical_exam_report_snapshot(bigint) is
  'Snapshot final v2: preserva toda a indicação clínica internamente; novos documentos omitem apenas sua apresentação ao paciente.';

notify pgrst, 'reload schema';
