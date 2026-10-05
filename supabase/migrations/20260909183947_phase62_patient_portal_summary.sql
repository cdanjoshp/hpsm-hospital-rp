-- HPSM — Fase 6.2: resumo seguro, derivado e somente leitura do Portal do Paciente.

create or replace function public.patient_portal_summary(p_token_hash text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
  v_session record;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('authenticated', false);
  end if;

  select *
  into v_session
  from private.patient_portal_session_record(p_token_hash);

  if not found then
    return jsonb_build_object('authenticated', false);
  end if;

  with valid_attendances as materialized (
    select
      attendance.id,
      attendance.created_at,
      attendance.total,
      attendance.performed_by
    from public.attendances attendance
    where attendance.patient_id = v_session.patient_id
      and attendance.status = 'completed'
  ), attendance_metrics as (
    select
      count(*)::integer as total_attendances,
      coalesce(sum(attendance.total), 0)::numeric(18, 2) as lifetime_spent
    from valid_attendances attendance
  ), last_attendance as (
    select
      attendance.id,
      attendance.created_at,
      attendance.total,
      professional.display_name as professional_name
    from valid_attendances attendance
    left join public.profiles professional on professional.user_id = attendance.performed_by
    order by attendance.created_at desc, attendance.id desc
    limit 1
  ), latest_approved_plan as (
    select request.id, request.coverage_end
    from public.patient_health_plan_requests request
    where request.patient_id = v_session.patient_id
      and request.status = 'approved'
    order by request.coverage_end desc, request.id desc
    limit 1
  ), latest_pending_plan as (
    select request.id
    from public.patient_health_plan_requests request
    where request.patient_id = v_session.patient_id
      and request.status = 'pending'
    order by request.requested_at, request.id
    limit 1
  ), health_plan_payload as (
    select jsonb_build_object(
      'status', case
        when approved.id is not null and approved.coverage_end > clock_timestamp() then 'active'
        when approved.id is not null then 'expired'
        when pending.id is not null then 'awaiting_confirmation'
        else 'none'
      end,
      'valid_until', approved.coverage_end
    ) as value
    from (select true) singleton
    left join latest_approved_plan approved on true
    left join latest_pending_plan pending on true
  ), recent_exams as materialized (
    select
      exam.id,
      exam.requested_at,
      exam.status,
      exam_type.name as type_name
    from public.clinical_exams exam
    join public.exam_types exam_type on exam_type.id = exam.exam_type_id
    where exam.patient_id = v_session.patient_id
    order by exam.requested_at desc, exam.id desc
    limit 3
  ), recent_exams_payload as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'type', exam.type_name,
          'occurred_at', exam.requested_at,
          'status', exam.status
        ) order by exam.requested_at desc, exam.id desc
      ),
      '[]'::jsonb
    ) as value
    from recent_exams exam
  ), active_casts as materialized (
    select
      cast_record.id,
      cast_record.body_region,
      cast_record.laterality,
      cast_record.applied_at,
      cast_record.expected_removal_at
    from public.clinical_casts cast_record
    where cast_record.patient_id = v_session.patient_id
      and cast_record.status = 'in_use'
    order by cast_record.expected_removal_at, cast_record.id
  ), active_casts_payload as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'body_region', cast_record.body_region,
          'laterality', cast_record.laterality,
          'applied_at', cast_record.applied_at,
          'expected_removal_at', cast_record.expected_removal_at
        ) order by cast_record.expected_removal_at, cast_record.id
      ),
      '[]'::jsonb
    ) as value
    from active_casts cast_record
  )
  select jsonb_build_object(
    'authenticated', true,
    'patient', jsonb_build_object(
      'name', v_session.patient_name,
      'passport', v_session.patient_passport
    ),
    'summary', jsonb_build_object(
      'total_attendances', metrics.total_attendances,
      'lifetime_spent', metrics.lifetime_spent,
      'last_attendance', case
        when latest.id is null then null
        else jsonb_build_object(
          'occurred_at', latest.created_at,
          'total', latest.total,
          'professional_name', latest.professional_name
        )
      end
    ),
    'health_plan', plan.value,
    'recent_exams', exams.value,
    'active_casts', casts.value
  )
  into v_result
  from attendance_metrics metrics
  left join last_attendance latest on true
  cross join health_plan_payload plan
  cross join recent_exams_payload exams
  cross join active_casts_payload casts;

  return v_result;
end;
$$;

revoke all on function public.patient_portal_summary(text)
from public, anon, authenticated, service_role;
grant execute on function public.patient_portal_summary(text)
to service_role;

comment on function public.patient_portal_summary(text) is
  'Retorna o resumo mínimo do paciente derivado exclusivamente de uma sessão válida do Portal. Somente service_role.';
