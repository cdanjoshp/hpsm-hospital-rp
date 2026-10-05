-- Ajusta o texto amigável da timeline sem depender do locale do banco.

create or replace function public.patient_timeline(p_patient_id bigint, p_limit integer default 50)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if not private.has_permission((select auth.uid()), 'patients.view') then
    raise exception 'Você não possui permissão para consultar pacientes.';
  end if;
  if p_limit < 1 or p_limit > 100 then
    raise exception 'Limite inválido.';
  end if;

  with events as (
    select
      'patient-created-' || patient.id::text as id,
      patient.created_at as event_at,
      'cadastro'::text as event_type,
      'Paciente cadastrado no HPSM'::text as title,
      'Passaporte ' || patient.passport as description
    from public.patients as patient
    where patient.id = p_patient_id

    union all

    select
      'attendance-' || attendance.id::text,
      attendance.created_at,
      'attendance',
      case when attendance.status = 'cancelled' then 'Atendimento cancelado' else 'Atendimento realizado' end,
      coalesce(professional.display_name, 'Profissional') || ' · atendimento #' || attendance.id::text
    from public.attendances as attendance
    left join public.profiles as professional on professional.user_id = attendance.performed_by
    where attendance.patient_id = p_patient_id

    union all

    select
      'plan-request-' || request.id::text,
      request.requested_at,
      'health-plan-request',
      'Solicitação de Plano de Saúde registrada',
      'Atendimento #' || request.attendance_id::text || ' · aguardando conferência'
    from public.patient_health_plan_requests as request
    where request.patient_id = p_patient_id

    union all

    select
      'plan-review-' || request.id::text,
      request.reviewed_at,
      'health-plan-review',
      case
        when request.status = 'rejected' then 'Ativação do plano recusada'
        when request.coverage_start > request.reviewed_at + interval '1 minute' then 'Plano de Saúde renovado'
        else 'Plano de Saúde ativado'
      end,
      case
        when request.status = 'rejected' then coalesce(request.rejection_reason, 'Solicitação recusada')
        else 'Validade até ' || to_char(request.coverage_end at time zone 'UTC', 'DD/MM/YYYY')
      end
    from public.patient_health_plan_requests as request
    where request.patient_id = p_patient_id
      and request.status in ('approved', 'rejected')
      and request.reviewed_at is not null
  ), limited as (
    select *
    from events
    order by event_at desc, id desc
    limit p_limit
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', limited.id,
      'date', limited.event_at,
      'type', limited.event_type,
      'title', limited.title,
      'description', limited.description
    ) order by limited.event_at desc, limited.id desc
  ), '[]'::jsonb)
  into v_result
  from limited;

  return v_result;
end;
$$;

revoke all on function public.patient_timeline(bigint, integer) from public, anon, authenticated;
grant execute on function public.patient_timeline(bigint, integer) to authenticated;

notify pgrst, 'reload schema';
