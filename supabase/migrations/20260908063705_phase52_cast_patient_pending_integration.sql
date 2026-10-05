-- HPSM · Fase 5.2 · Integração de gessos com Perfil do Paciente e Pendências
-- Versão registrada no banco remoto: 20260908063705.
-- clinical_casts permanece como a única fonte clínica. Pendências são derivadas e não persistidas.

create or replace function private.clinical_cast_location_label(
  p_body_region text,
  p_laterality text
)
returns text
language sql
immutable
set search_path = ''
as $$
  select
    case p_body_region
      when 'hand' then 'Mão'
      when 'wrist' then 'Punho'
      when 'forearm' then 'Antebraço'
      when 'elbow' then 'Cotovelo'
      when 'arm' then 'Braço'
      when 'foot' then 'Pé'
      when 'ankle' then 'Tornozelo'
      when 'leg' then 'Perna'
      when 'knee' then 'Joelho'
      else 'Outro local'
    end
    || case p_laterality
      when 'right' then case when p_body_region in ('hand', 'leg') then ' direita' else ' direito' end
      when 'left' then case when p_body_region in ('hand', 'leg') then ' esquerda' else ' esquerdo' end
      when 'bilateral' then ' bilateral'
      else ''
    end;
$$;

revoke all on function private.clinical_cast_location_label(text, text)
from public, anon, authenticated, service_role;

create or replace function public.patient_active_clinical_casts(p_patient_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
begin
  if not private.has_permission(v_actor, 'patients.view')
     or not private.has_permission(v_actor, 'casts.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.patients patient where patient.id = p_patient_id) then
    raise exception 'Paciente não localizado.';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', cast_record.id,
      'patient_id', cast_record.patient_id,
      'body_region', cast_record.body_region,
      'laterality', cast_record.laterality,
      'status', cast_record.status,
      'applied_at', cast_record.applied_at,
      'expected_removal_at', cast_record.expected_removal_at,
      'applied_by', cast_record.applied_by,
      'applied_by_name', applied.display_name,
      'applied_by_position', applied_position.name
    ) order by cast_record.expected_removal_at, cast_record.id)
    from public.clinical_casts cast_record
    join public.profiles applied on applied.user_id = cast_record.applied_by
    left join public.staff_positions applied_position on applied_position.id = applied.position_id
    where cast_record.patient_id = p_patient_id
      and cast_record.status = 'in_use'
  ), '[]'::jsonb);
end;
$$;

create or replace function public.clinical_cast_overdue_page(p_limit integer default 250)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_limit integer := least(greatest(coalesce(p_limit, 250), 1), 250);
begin
  if not private.has_permission(v_actor, 'casts.view')
     or not private.has_permission(v_actor, 'casts.manage') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', due.id,
      'patient_id', due.patient_id,
      'patient_name', due.patient_name,
      'patient_passport', due.patient_passport,
      'body_region', due.body_region,
      'laterality', due.laterality,
      'status', due.status,
      'applied_at', due.applied_at,
      'expected_removal_at', due.expected_removal_at,
      'applied_by', due.applied_by,
      'applied_by_name', due.applied_by_name,
      'applied_by_position', due.applied_by_position
    ) order by due.expected_removal_at, due.id)
    from (
      select
        cast_record.id,
        cast_record.patient_id,
        patient.name as patient_name,
        patient.passport as patient_passport,
        cast_record.body_region,
        cast_record.laterality,
        cast_record.status,
        cast_record.applied_at,
        cast_record.expected_removal_at,
        cast_record.applied_by,
        applied.display_name as applied_by_name,
        applied_position.name as applied_by_position
      from public.clinical_casts cast_record
      join public.patients patient on patient.id = cast_record.patient_id
      join public.profiles applied on applied.user_id = cast_record.applied_by
      left join public.staff_positions applied_position on applied_position.id = applied.position_id
      where cast_record.status = 'in_use'
        and cast_record.expected_removal_at <= now()
      order by cast_record.expected_removal_at, cast_record.id
      limit v_limit
    ) due
  ), '[]'::jsonb);
end;
$$;

create index if not exists audit_logs_clinical_cast_forecast_idx
  on public.audit_logs (entity_id, created_at desc)
  where entity_name = 'clinical_casts'
    and action = 'CAST_EXPECTED_REMOVAL_CHANGED';

create or replace function public.patient_timeline(p_patient_id bigint, p_limit integer default 50)
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
  if not private.has_permission(v_actor, 'patients.view') then
    raise exception 'Você não possui permissão para consultar pacientes.' using errcode = '42501';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception 'Limite inválido.';
  end if;

  with events as (
    select
      'patient-created-' || patient.id::text as id,
      patient.created_at as event_at,
      'cadastro'::text as event_type,
      'Paciente cadastrado no HPSM'::text as title,
      'Passaporte ' || patient.passport as description,
      null::bigint as exam_id,
      null::bigint as cast_id
    from public.patients as patient
    where patient.id = p_patient_id

    union all

    select
      'attendance-' || attendance.id::text,
      attendance.created_at,
      'attendance',
      case when attendance.status = 'cancelled' then 'Atendimento cancelado' else 'Atendimento realizado' end,
      coalesce(professional.display_name, 'Profissional') || ' · atendimento #' || attendance.id::text,
      null::bigint,
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
      null::bigint,
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
      null::bigint,
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
      exam.id,
      null::bigint
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
      exam.id,
      null::bigint
    from public.clinical_exams exam
    join public.exam_types exam_type on exam_type.id = exam.exam_type_id
    join public.profiles responsible on responsible.user_id = exam.responsible_professional_id
    left join public.profiles reviewer on reviewer.user_id = exam.reviewed_by
    where exam.patient_id = p_patient_id
      and exam.status = 'completed'
      and exam.completed_at is not null
      and private.has_permission(v_actor, 'exams.view')

    union all

    select
      'cast-applied-' || cast_record.id::text,
      cast_record.applied_at,
      'cast-applied',
      'Gesso aplicado — ' || private.clinical_cast_location_label(cast_record.body_region, cast_record.laterality),
      'Profissional: ' || applied.display_name
        || coalesce(' · ' || applied_position.name, '')
        || coalesce(' · Atendimento #' || cast_record.attendance_id::text, ''),
      null::bigint,
      cast_record.id
    from public.clinical_casts cast_record
    join public.profiles applied on applied.user_id = cast_record.applied_by
    left join public.staff_positions applied_position on applied_position.id = applied.position_id
    where cast_record.patient_id = p_patient_id
      and private.has_permission(v_actor, 'casts.view')

    union all

    select
      'cast-forecast-' || audit.id::text,
      audit.created_at,
      'cast-forecast-changed',
      'Previsão de retirada do gesso alterada',
      'De ' || to_char((audit.old_values->>'expected_removal_at')::timestamptz at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI')
        || ' para ' || to_char((audit.new_values->>'expected_removal_at')::timestamptz at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI')
        || ' · Responsável: ' || coalesce(actor.display_name, 'Profissional'),
      null::bigint,
      cast_record.id
    from public.audit_logs audit
    join public.clinical_casts cast_record on cast_record.id::text = audit.entity_id
    left join public.profiles actor on actor.user_id = audit.actor_user_id
    where audit.entity_name = 'clinical_casts'
      and audit.action = 'CAST_EXPECTED_REMOVAL_CHANGED'
      and audit.old_values ? 'expected_removal_at'
      and audit.new_values ? 'expected_removal_at'
      and cast_record.patient_id = p_patient_id
      and private.has_permission(v_actor, 'casts.view')

    union all

    select
      'cast-removed-' || cast_record.id::text,
      cast_record.removed_at,
      'cast-removed',
      'Gesso retirado — ' || private.clinical_cast_location_label(cast_record.body_region, cast_record.laterality),
      'Profissional: ' || removed.display_name
        || coalesce(' · ' || removed_position.name, '')
        || coalesce(' · ' || cast_record.removal_notes, ''),
      null::bigint,
      cast_record.id
    from public.clinical_casts cast_record
    join public.profiles removed on removed.user_id = cast_record.removed_by
    left join public.staff_positions removed_position on removed_position.id = removed.position_id
    where cast_record.patient_id = p_patient_id
      and cast_record.status = 'removed'
      and cast_record.removed_at is not null
      and private.has_permission(v_actor, 'casts.view')

    union all

    select
      'cast-cancelled-' || cast_record.id::text,
      cast_record.cancelled_at,
      'cast-cancelled',
      'Registro de gesso cancelado',
      private.clinical_cast_location_label(cast_record.body_region, cast_record.laterality)
        || coalesce(' · Motivo: ' || cast_record.cancellation_reason, '')
        || ' · Responsável: ' || cancelled.display_name,
      null::bigint,
      cast_record.id
    from public.clinical_casts cast_record
    join public.profiles cancelled on cancelled.user_id = cast_record.cancelled_by
    where cast_record.patient_id = p_patient_id
      and cast_record.status = 'cancelled'
      and cast_record.cancelled_at is not null
      and private.has_permission(v_actor, 'casts.view')
  ), limited as (
    select *
    from events
    where event_at is not null
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
      'exam_id', limited.exam_id,
      'cast_id', limited.cast_id
    ) order by limited.event_at desc, limited.id desc
  ), '[]'::jsonb)
  into v_result
  from limited;

  return v_result;
end;
$$;

create or replace function public.hpsm_shell_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_permissions text[] := public.effective_permission_codes(v_actor);
  v_role_code text;
  v_notifications jsonb := '[]'::jsonb;
  v_unread_count integer := 0;
  v_pending_count integer := 0;
  v_weekly_inputs jsonb := null;
  v_today date := timezone('America/Sao_Paulo', now())::date;
  v_week_start date;
  v_cycle_month date;
begin
  select profile.role_code into v_role_code
  from public.profiles profile
  where profile.user_id = v_actor;

  with visible as materialized (
    select
      notification.id,
      notification.kind,
      notification.recipient_id,
      notification.audience,
      notification.priority,
      notification.title,
      notification.body,
      notification.action_url,
      notification.created_by,
      notification.created_at,
      notification.expires_at,
      notification.archived_at,
      notification.source_type,
      notification.source_id,
      notification.required_permission,
      notification.resolved_at,
      notification.resolved_by,
      read.read_at,
      coalesce(author.display_name, 'Sistema HPSM') as author_name,
      author.passport as author_passport
    from public.notifications notification
    left join public.notification_reads read
      on read.notification_id = notification.id and read.user_id = v_actor
    left join public.profiles author on author.user_id = notification.created_by
    where notification.archived_at is null
      and (notification.expires_at is null or notification.expires_at > now())
      and (
        notification.recipient_id = v_actor
        or notification.audience = 'all'
        or (
          notification.audience = 'directors'
          and case
            when notification.required_permission is not null
              then notification.required_permission = any(v_permissions)
            else 'hr.team.view' = any(v_permissions)
          end
        )
        or (
          notification.audience = 'employees'
          and not ('hr.team.view' = any(v_permissions))
        )
      )
  ), picked_ids as (
    (
      select visible.id
      from visible
      where visible.read_at is null and visible.resolved_at is null
      order by visible.created_at desc, visible.id desc
      limit 8
    )
    union
    (
      select visible.id
      from visible
      where visible.kind = 'announcement'
      order by (visible.read_at is null) desc, visible.created_at desc, visible.id desc
      limit 3
    )
  )
  select
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', visible.id,
        'kind', visible.kind,
        'recipient_id', visible.recipient_id,
        'audience', visible.audience,
        'priority', visible.priority,
        'title', visible.title,
        'body', visible.body,
        'action_url', visible.action_url,
        'created_by', visible.created_by,
        'created_at', visible.created_at,
        'expires_at', visible.expires_at,
        'archived_at', visible.archived_at,
        'source_type', visible.source_type,
        'source_id', visible.source_id,
        'required_permission', visible.required_permission,
        'resolved_at', visible.resolved_at,
        'resolved_by', visible.resolved_by,
        'read_at', visible.read_at,
        'author_name', visible.author_name,
        'author_passport', visible.author_passport
      ) order by visible.created_at desc, visible.id desc)
      from visible
      join picked_ids on picked_ids.id = visible.id
    ), '[]'::jsonb),
    (select count(*)::integer from visible where visible.read_at is null and visible.resolved_at is null)
  into v_notifications, v_unread_count;

  select
    (case when 'recruitment.manage' = any(v_permissions)
      then (select count(*) from public.recruitment_applications where status in ('submitted', 'under_review', 'interview')) else 0 end)
    + (case when 'hr.absences.review' = any(v_permissions)
      then (select count(*) from public.rh_absence_requests where status = 'pending') else 0 end)
    + (case when 'hr.justifications.review' = any(v_permissions)
      then (select count(*) from public.rh_hour_justifications where status = 'pending') else 0 end)
    + (case when 'hr.discipline.manage' = any(v_permissions) or 'hr.discipline.review' = any(v_permissions)
      then (select count(*) from public.rh_disciplinary_reviews where status = 'pending') else 0 end)
    + (case when 'progression.review' = any(v_permissions)
      then (select count(*) from public.staff_promotion_reviews where status = 'pending') else 0 end)
    + (case when 'tcc.vote' = any(v_permissions)
      then (select count(*) from public.tcc_submissions where status = 'submitted') else 0 end)
    + (case when 'healthplans.review' = any(v_permissions)
      then (select count(*) from public.patient_health_plan_requests where status = 'pending') else 0 end)
    + (case when 'casts.view' = any(v_permissions) and 'casts.manage' = any(v_permissions)
      then (select count(*) from public.clinical_casts where status = 'in_use' and expected_removal_at <= now()) else 0 end)
  into v_pending_count;

  if v_role_code <> 'diretor_geral' then
    v_week_start := v_today - (extract(isodow from v_today)::integer - 1);
    v_cycle_month := date_trunc('month', v_week_start + 6)::date;
    select jsonb_build_object(
      'snapshots', (
        select coalesce(jsonb_agg(to_jsonb(snapshot) order by snapshot.reading_date), '[]'::jsonb)
        from public.rh_hour_snapshots snapshot
        where snapshot.employee_id = v_actor
          and snapshot.reading_date >= date_trunc('month', v_week_start - 1)::date
          and snapshot.reading_date <= v_today
      ),
      'leaveAdjustments', (
        select coalesce(jsonb_agg(to_jsonb(adjustment) order by adjustment.week_start desc), '[]'::jsonb)
        from public.rh_leave_week_adjustments adjustment
        where adjustment.employee_id = v_actor
          and adjustment.week_start = v_week_start
      ),
      'weeklyRecords', (
        select coalesce(jsonb_agg(to_jsonb(record) order by record.week_start desc), '[]'::jsonb)
        from public.rh_weekly_records record
        where record.employee_id = v_actor
          and record.week_start = v_week_start
      ),
      'warnings', (
        select coalesce(jsonb_agg(to_jsonb(warning) order by warning.issued_at desc), '[]'::jsonb)
        from public.rh_warnings warning
        where warning.employee_id = v_actor
          and warning.cycle_month = v_cycle_month
      )
    ) into v_weekly_inputs;
  end if;

  return jsonb_build_object(
    'notifications', v_notifications,
    'unread_count', v_unread_count,
    'pending_count', v_pending_count,
    'weekly_inputs', v_weekly_inputs
  );
end;
$$;

revoke all on function public.patient_active_clinical_casts(bigint)
from public, anon, authenticated, service_role;
revoke all on function public.clinical_cast_overdue_page(integer)
from public, anon, authenticated, service_role;
revoke all on function public.patient_timeline(bigint, integer)
from public, anon, authenticated, service_role;
revoke all on function public.hpsm_shell_snapshot()
from public, anon, authenticated, service_role;

grant execute on function public.patient_active_clinical_casts(bigint) to authenticated;
grant execute on function public.clinical_cast_overdue_page(integer) to authenticated;
grant execute on function public.patient_timeline(bigint, integer) to authenticated;
grant execute on function public.hpsm_shell_snapshot() to authenticated;

comment on function public.patient_active_clinical_casts(bigint) is
  'Gessos em uso de um único paciente, ordenados pela previsão mais próxima e autorizados por patients.view + casts.view.';
comment on function public.clinical_cast_overdue_page(integer) is
  'Pendências clínicas derivadas dos gessos em uso cuja previsão já venceu; não cria registros paralelos.';
comment on function public.patient_timeline(bigint, integer) is
  'Timeline consolidada do paciente, incluindo eventos reais de exames e gessos conforme permissões clínicas.';
comment on function public.hpsm_shell_snapshot() is
  'Dados secundários compactos do App Shell, incluindo a contagem derivada de retiradas de gesso vencidas para gestores clínicos.';

notify pgrst, 'reload schema';
