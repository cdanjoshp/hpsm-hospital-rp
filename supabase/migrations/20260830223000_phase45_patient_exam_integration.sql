-- Fase 4.5: integra os exames clínicos reais ao Perfil do Paciente.
-- Não cria entidade paralela; a fonte canônica permanece public.clinical_exams.

create or replace function public.patient_clinical_exam_page(
  p_patient_id bigint,
  p_category_id bigint default null,
  p_exam_type_id bigint default null,
  p_status text default null,
  p_date_from date default null,
  p_date_to date default null,
  p_limit integer default 10,
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
  v_limit integer := least(greatest(coalesce(p_limit, 10), 1), 20);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_result jsonb;
begin
  if v_actor is null
     or not private.has_permission(v_actor, 'patients.view')
     or not private.has_permission(v_actor, 'exams.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if p_patient_id is null or not exists (select 1 from public.patients patient where patient.id = p_patient_id) then
    raise exception 'Paciente não localizado.';
  end if;
  if p_status is not null and p_status not in ('requested', 'in_progress', 'awaiting_review', 'completed') then
    raise exception 'Status inválido.';
  end if;

  with base as materialized (
    select
      exam.id,
      exam.patient_id,
      exam.exam_type_id,
      exam_type.name as exam_type_name,
      category.id as category_id,
      category.name as category_name,
      exam.status,
      exam.indication,
      exam.responsible_professional_id,
      responsible.display_name as responsible_name,
      responsible_position.name as responsible_position,
      reviewer.display_name as reviewer_name,
      reviewer_position.name as reviewer_position,
      exam.requested_at,
      exam.completed_at,
      coalesce(exam.completed_at, exam.requested_at) as relevant_at
    from public.clinical_exams exam
    join public.exam_types exam_type on exam_type.id = exam.exam_type_id
    join public.exam_categories category on category.id = exam_type.category_id
    join public.profiles responsible on responsible.user_id = exam.responsible_professional_id
    left join public.staff_positions responsible_position on responsible_position.id = responsible.position_id
    left join public.profiles reviewer on reviewer.user_id = exam.reviewed_by
    left join public.staff_positions reviewer_position on reviewer_position.id = reviewer.position_id
    where exam.patient_id = p_patient_id
  ), filtered as materialized (
    select *
    from base
    where (p_category_id is null or category_id = p_category_id)
      and (p_exam_type_id is null or exam_type_id = p_exam_type_id)
      and (p_status is null or status = p_status)
      and (p_date_from is null or relevant_at >= p_date_from::timestamptz)
      and (p_date_to is null or relevant_at < (p_date_to + 1)::timestamptz)
  ), page_rows as materialized (
    select * from filtered order by relevant_at desc, id desc limit v_limit offset v_offset
  ), image_counts as (
    select image.exam_id, count(*)::integer as image_count
    from public.clinical_exam_images image
    where image.removed_at is null
      and image.exam_id in (select page_row.id from page_rows page_row)
    group by image.exam_id
  )
  select jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(
        to_jsonb(page_row) || jsonb_build_object('image_count', coalesce(image_count.image_count, 0))
        order by page_row.relevant_at desc, page_row.id desc
      )
      from page_rows page_row
      left join image_counts image_count on image_count.exam_id = page_row.id
    ), '[]'::jsonb),
    'total', (select count(*) from filtered),
    'summary', jsonb_build_object(
      'total', (select count(*) from base),
      'completed', (select count(*) from base where status = 'completed'),
      'awaiting_review', (select count(*) from base where status = 'awaiting_review')
    )
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.patient_clinical_exam_page(bigint, bigint, bigint, text, date, date, integer, integer) from public, anon, authenticated;
grant execute on function public.patient_clinical_exam_page(bigint, bigint, bigint, text, date, date, integer, integer) to authenticated;

create or replace function public.patient_timeline(p_patient_id bigint, p_limit integer default 50)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_result jsonb;
begin
  if not private.has_permission(v_actor, 'patients.view') then
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
      'Passaporte ' || patient.passport as description,
      null::bigint as exam_id
    from public.patients as patient
    where patient.id = p_patient_id

    union all

    select
      'attendance-' || attendance.id::text,
      attendance.created_at,
      'attendance',
      case when attendance.status = 'cancelled' then 'Atendimento cancelado' else 'Atendimento realizado' end,
      coalesce(professional.display_name, 'Profissional') || ' · atendimento #' || attendance.id::text,
      null::bigint
    from public.attendances as attendance
    left join public.profiles as professional on professional.user_id = attendance.performed_by
    where attendance.patient_id = p_patient_id

    union all

    select
      'plan-request-' || request.id::text,
      request.requested_at,
      'health-plan-request',
      'Solicitação de Plano de Saúde registrada',
      'Atendimento #' || request.attendance_id::text || ' · aguardando conferência',
      null::bigint
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
      end,
      null::bigint
    from public.patient_health_plan_requests as request
    where request.patient_id = p_patient_id
      and request.status in ('approved', 'rejected')
      and request.reviewed_at is not null

    union all

    select
      'exam-requested-' || exam.id::text,
      exam.requested_at,
      'exam-requested',
      exam_type.name || ' solicitado',
      'Solicitado por ' || requester.display_name || coalesce(' · ' || requester_position.name, ''),
      exam.id
    from public.clinical_exams exam
    join public.exam_types exam_type on exam_type.id = exam.exam_type_id
    join public.profiles requester on requester.user_id = exam.requested_by
    left join public.staff_positions requester_position on requester_position.id = requester.position_id
    where exam.patient_id = p_patient_id
      and private.has_permission(v_actor, 'exams.view')

    union all

    select
      'exam-completed-' || exam.id::text,
      exam.completed_at,
      'exam-completed',
      exam_type.name || ' concluído',
      'Responsável: ' || responsible.display_name
        || coalesce(' · Revisor: ' || reviewer.display_name, ''),
      exam.id
    from public.clinical_exams exam
    join public.exam_types exam_type on exam_type.id = exam.exam_type_id
    join public.profiles responsible on responsible.user_id = exam.responsible_professional_id
    left join public.profiles reviewer on reviewer.user_id = exam.reviewed_by
    where exam.patient_id = p_patient_id
      and exam.status = 'completed'
      and exam.completed_at is not null
      and private.has_permission(v_actor, 'exams.view')
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
      'description', limited.description,
      'exam_id', limited.exam_id
    ) order by limited.event_at desc, limited.id desc
  ), '[]'::jsonb)
  into v_result
  from limited;

  return v_result;
end;
$$;

revoke all on function public.patient_timeline(bigint, integer) from public, anon, authenticated;
grant execute on function public.patient_timeline(bigint, integer) to authenticated;

comment on function public.patient_clinical_exam_page(bigint, bigint, bigint, text, date, date, integer, integer)
  is 'Lista clínica paginada e resumida dos exames reais de um paciente; detalhe e imagens permanecem sob demanda.';

notify pgrst, 'reload schema';
