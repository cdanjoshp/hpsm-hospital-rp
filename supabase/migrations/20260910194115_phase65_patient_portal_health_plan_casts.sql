-- HPSM — Fase 6.5: Plano de Saúde e Controle de Gesso no Portal do Paciente.
-- As duas áreas são somente leitura e sempre derivam o paciente da sessão opaca.

create index if not exists clinical_casts_patient_in_use_due_idx
  on public.clinical_casts (patient_id, expected_removal_at, id)
  where status = 'in_use';

create or replace function private.patient_portal_health_plan_state(p_patient_id bigint)
returns table (
  status text,
  activated_at timestamptz,
  valid_until timestamptz,
  pending_requested_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  with latest_approved as (
    select request.coverage_start, request.coverage_end
    from public.patient_health_plan_requests request
    where request.patient_id = p_patient_id
      and request.status = 'approved'
    order by request.coverage_end desc, request.id desc
    limit 1
  ), latest_pending as (
    select request.requested_at
    from public.patient_health_plan_requests request
    where request.patient_id = p_patient_id
      and request.status = 'pending'
    order by request.requested_at, request.id
    limit 1
  )
  select
    case
      when approved.coverage_end > clock_timestamp() then 'active'
      when approved.coverage_end is not null then 'expired'
      when pending.requested_at is not null then 'awaiting_confirmation'
      else 'none'
    end,
    approved.coverage_start,
    approved.coverage_end,
    pending.requested_at
  from (select true) singleton
  left join latest_approved approved on true
  left join latest_pending pending on true;
$$;

revoke all on function private.patient_portal_health_plan_state(bigint)
from public, anon, authenticated, service_role;

create or replace function public.patient_portal_health_plan_page(
  p_token_hash text,
  p_cursor_at timestamptz default null,
  p_cursor_id bigint default null,
  p_limit integer default 12
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_current record;
  v_has_more boolean;
  v_items jsonb;
  v_limit integer := least(greatest(coalesce(p_limit, 12), 1), 30);
  v_next_at timestamptz;
  v_next_id bigint;
  v_session record;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('authenticated', false);
  end if;
  if (p_cursor_at is null) <> (p_cursor_id is null)
     or (p_cursor_id is not null and p_cursor_id < 1) then
    raise exception 'Cursor inválido.' using errcode = '22023';
  end if;

  select * into v_session
  from private.patient_portal_session_record(p_token_hash);

  if not found then
    return jsonb_build_object('authenticated', false);
  end if;

  select * into v_current
  from private.patient_portal_health_plan_state(v_session.patient_id);

  with plan_events as materialized (
    select
      request.id,
      coalesce(request.reviewed_at, request.requested_at) as event_at,
      request.requested_at,
      request.reviewed_at,
      request.status,
      request.coverage_start,
      request.coverage_end,
      case
        when request.status = 'approved'
          and exists (
            select 1
            from public.patient_health_plan_requests previous
            where previous.patient_id = request.patient_id
              and previous.status = 'approved'
              and previous.id < request.id
          ) then 'renewed'
        when request.status = 'approved' then 'activated'
        when request.status = 'rejected' then 'not_approved'
        else 'requested'
      end as event_type
    from public.patient_health_plan_requests request
    where request.patient_id = v_session.patient_id
  ), page_rows as materialized (
    select event.*
    from plan_events event
    where p_cursor_at is null
      or (event.event_at, event.id) < (p_cursor_at, p_cursor_id)
    order by event.event_at desc, event.id desc
    limit v_limit + 1
  ), visible_rows as materialized (
    select *
    from page_rows
    order by event_at desc, id desc
    limit v_limit
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'key', 'health-plan:' || visible.id::text,
      'status', visible.status,
      'event', visible.event_type,
      'occurred_at', visible.event_at,
      'requested_at', visible.requested_at,
      'reviewed_at', visible.reviewed_at,
      'coverage_start', visible.coverage_start,
      'coverage_end', visible.coverage_end
    ) order by visible.event_at desc, visible.id desc), '[]'::jsonb),
    (select count(*) > v_limit from page_rows),
    (select event_at from visible_rows order by event_at, id limit 1),
    (select id from visible_rows order by event_at, id limit 1)
  into v_items, v_has_more, v_next_at, v_next_id
  from visible_rows visible;

  return jsonb_build_object(
    'authenticated', true,
    'patient', jsonb_build_object(
      'name', v_session.patient_name,
      'passport', v_session.patient_passport
    ),
    'current', jsonb_build_object(
      'status', v_current.status,
      'activated_at', v_current.activated_at,
      'valid_until', v_current.valid_until,
      'pending_requested_at', v_current.pending_requested_at
    ),
    'items', v_items,
    'next_cursor', case
      when v_has_more then jsonb_build_object('occurred_at', v_next_at, 'id', v_next_id)
      else null
    end
  );
end;
$$;

create or replace function public.patient_portal_cast_page(
  p_token_hash text,
  p_cursor_at timestamptz default null,
  p_cursor_id bigint default null,
  p_limit integer default 15
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_active jsonb;
  v_has_more boolean;
  v_history jsonb;
  v_limit integer := least(greatest(coalesce(p_limit, 15), 1), 30);
  v_next_at timestamptz;
  v_next_id bigint;
  v_reference_time timestamptz := clock_timestamp();
  v_session record;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('authenticated', false);
  end if;
  if (p_cursor_at is null) <> (p_cursor_id is null)
     or (p_cursor_id is not null and p_cursor_id < 1) then
    raise exception 'Cursor inválido.' using errcode = '22023';
  end if;

  select * into v_session
  from private.patient_portal_session_record(p_token_hash);

  if not found then
    return jsonb_build_object('authenticated', false);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'key', 'cast:' || active.id::text,
    'body_region', active.body_region,
    'laterality', active.laterality,
    'status', active.status,
    'applied_at', active.applied_at,
    'expected_removal_at', active.expected_removal_at,
    'applied_by_name', active.applied_by_name,
    'applied_by_position', active.applied_by_position
  ) order by active.expected_removal_at, active.id), '[]'::jsonb)
  into v_active
  from (
    select
      cast_record.id,
      cast_record.body_region,
      cast_record.laterality,
      cast_record.status,
      cast_record.applied_at,
      cast_record.expected_removal_at,
      applied.display_name as applied_by_name,
      applied_position.name as applied_by_position
    from public.clinical_casts cast_record
    left join public.profiles applied on applied.user_id = cast_record.applied_by
    left join public.staff_positions applied_position on applied_position.id = applied.position_id
    where cast_record.patient_id = v_session.patient_id
      and cast_record.status = 'in_use'
    order by cast_record.expected_removal_at, cast_record.id
  ) active;

  with page_rows as materialized (
    select
      cast_record.id,
      cast_record.updated_at as event_at,
      cast_record.body_region,
      cast_record.laterality,
      cast_record.status,
      cast_record.applied_at,
      cast_record.expected_removal_at,
      cast_record.removed_at,
      cast_record.cancelled_at,
      applied.display_name as applied_by_name,
      applied_position.name as applied_by_position,
      removed.display_name as removed_by_name,
      removed_position.name as removed_by_position
    from public.clinical_casts cast_record
    left join public.profiles applied on applied.user_id = cast_record.applied_by
    left join public.staff_positions applied_position on applied_position.id = applied.position_id
    left join public.profiles removed on removed.user_id = cast_record.removed_by
    left join public.staff_positions removed_position on removed_position.id = removed.position_id
    where cast_record.patient_id = v_session.patient_id
      and cast_record.status in ('removed', 'cancelled')
      and (
        p_cursor_at is null
        or (cast_record.updated_at, cast_record.id) < (p_cursor_at, p_cursor_id)
      )
    order by cast_record.updated_at desc, cast_record.id desc
    limit v_limit + 1
  ), visible_rows as materialized (
    select *
    from page_rows
    order by event_at desc, id desc
    limit v_limit
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'key', 'cast:' || visible.id::text,
      'body_region', visible.body_region,
      'laterality', visible.laterality,
      'status', visible.status,
      'occurred_at', visible.event_at,
      'applied_at', visible.applied_at,
      'expected_removal_at', visible.expected_removal_at,
      'removed_at', visible.removed_at,
      'cancelled_at', visible.cancelled_at,
      'applied_by_name', visible.applied_by_name,
      'applied_by_position', visible.applied_by_position,
      'removed_by_name', visible.removed_by_name,
      'removed_by_position', visible.removed_by_position
    ) order by visible.event_at desc, visible.id desc), '[]'::jsonb),
    (select count(*) > v_limit from page_rows),
    (select event_at from visible_rows order by event_at, id limit 1),
    (select id from visible_rows order by event_at, id limit 1)
  into v_history, v_has_more, v_next_at, v_next_id
  from visible_rows visible;

  return jsonb_build_object(
    'authenticated', true,
    'patient', jsonb_build_object(
      'name', v_session.patient_name,
      'passport', v_session.patient_passport
    ),
    'reference_time', v_reference_time,
    'active_casts', v_active,
    'history', v_history,
    'next_cursor', case
      when v_has_more then jsonb_build_object('occurred_at', v_next_at, 'id', v_next_id)
      else null
    end
  );
end;
$$;

create or replace function public.patient_portal_summary(p_token_hash text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_metrics record;
  v_result jsonb;
  v_session record;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('authenticated', false);
  end if;

  select * into v_session from private.patient_portal_session_record(p_token_hash);
  if not found then return jsonb_build_object('authenticated', false); end if;
  select * into v_metrics from private.patient_portal_attendance_metrics(v_session.patient_id);

  with last_attendance as (
    select attendance.id, attendance.created_at, attendance.total, professional.display_name as professional_name
    from public.attendances attendance
    left join public.profiles professional on professional.user_id = attendance.performed_by
    where attendance.patient_id = v_session.patient_id and attendance.status = 'completed'
    order by attendance.created_at desc, attendance.id desc limit 1
  ), health_plan_payload as (
    select jsonb_build_object(
      'status', plan.status,
      'valid_until', plan.valid_until
    ) as value
    from private.patient_portal_health_plan_state(v_session.patient_id) plan
  ), recent_exams as materialized (
    select exam.id, exam.requested_at, exam.status, exam_type.name as type_name
    from public.clinical_exams exam
    join public.exam_types exam_type on exam_type.id = exam.exam_type_id
    where exam.patient_id = v_session.patient_id
    order by exam.requested_at desc, exam.id desc limit 3
  ), recent_exams_payload as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', exam.id,
      'type', exam.type_name,
      'occurred_at', exam.requested_at,
      'status', exam.status
    ) order by exam.requested_at desc, exam.id desc), '[]'::jsonb) as value
    from recent_exams exam
  ), active_casts as materialized (
    select cast_record.id, cast_record.body_region, cast_record.laterality,
      cast_record.applied_at, cast_record.expected_removal_at
    from public.clinical_casts cast_record
    where cast_record.patient_id = v_session.patient_id and cast_record.status = 'in_use'
    order by cast_record.expected_removal_at, cast_record.id
  ), active_casts_payload as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'body_region', cast_record.body_region,
      'laterality', cast_record.laterality,
      'applied_at', cast_record.applied_at,
      'expected_removal_at', cast_record.expected_removal_at
    ) order by cast_record.expected_removal_at, cast_record.id), '[]'::jsonb) as value
    from active_casts cast_record
  )
  select jsonb_build_object(
    'authenticated', true,
    'patient', jsonb_build_object('name', v_session.patient_name, 'passport', v_session.patient_passport),
    'summary', jsonb_build_object(
      'total_attendances', v_metrics.total_attendances,
      'lifetime_spent', v_metrics.lifetime_spent,
      'last_attendance', case when latest.id is null then null else jsonb_build_object(
        'occurred_at', latest.created_at, 'total', latest.total, 'professional_name', latest.professional_name
      ) end
    ),
    'health_plan', plan.value,
    'recent_exams', exams.value,
    'active_casts', casts.value
  ) into v_result
  from (select true) singleton
  left join last_attendance latest on true
  cross join health_plan_payload plan
  cross join recent_exams_payload exams
  cross join active_casts_payload casts;

  return v_result;
end;
$$;

revoke all on function public.patient_portal_health_plan_page(text, timestamptz, bigint, integer)
from public, anon, authenticated, service_role;
revoke all on function public.patient_portal_cast_page(text, timestamptz, bigint, integer)
from public, anon, authenticated, service_role;
revoke all on function public.patient_portal_summary(text)
from public, anon, authenticated, service_role;

grant execute on function public.patient_portal_health_plan_page(text, timestamptz, bigint, integer)
to service_role;
grant execute on function public.patient_portal_cast_page(text, timestamptz, bigint, integer)
to service_role;
grant execute on function public.patient_portal_summary(text)
to service_role;

comment on function public.patient_portal_health_plan_page(text, timestamptz, bigint, integer) is
  'Entrega estado e histórico sanitizado do Plano do paciente derivado da sessão opaca. Somente service_role.';
comment on function public.patient_portal_cast_page(text, timestamptz, bigint, integer) is
  'Entrega gessos clínicos ativos e histórico sanitizado do paciente derivado da sessão opaca. Somente service_role.';
