-- HPSM — Fase 6.3: histórico consolidado, atendimentos e gastos do Portal do Paciente.
-- Todas as leituras derivam o paciente exclusivamente da sessão opaca do Portal.

create or replace function private.patient_portal_attendance_metrics(p_patient_id bigint)
returns table (
  total_attendances integer,
  lifetime_spent numeric(18, 2)
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    count(*)::integer,
    coalesce(sum(attendance.total), 0)::numeric(18, 2)
  from public.attendances attendance
  where attendance.patient_id = p_patient_id
    and attendance.status = 'completed';
$$;

revoke all on function private.patient_portal_attendance_metrics(bigint)
from public, anon, authenticated, service_role;

create index if not exists attendances_patient_completed_created_idx
  on public.attendances (patient_id, created_at desc, id desc)
  where status = 'completed';

create index if not exists clinical_exams_patient_completed_at_idx
  on public.clinical_exams (patient_id, completed_at desc, id desc)
  where status = 'completed' and completed_at is not null;

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

  select *
  into v_session
  from private.patient_portal_session_record(p_token_hash);

  if not found then
    return jsonb_build_object('authenticated', false);
  end if;

  select *
  into v_metrics
  from private.patient_portal_attendance_metrics(v_session.patient_id);

  with last_attendance as (
    select
      attendance.id,
      attendance.created_at,
      attendance.total,
      professional.display_name as professional_name
    from public.attendances attendance
    left join public.profiles professional on professional.user_id = attendance.performed_by
    where attendance.patient_id = v_session.patient_id
      and attendance.status = 'completed'
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
    select exam.id, exam.requested_at, exam.status, exam_type.name as type_name
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
      'total_attendances', v_metrics.total_attendances,
      'lifetime_spent', v_metrics.lifetime_spent,
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
  from (select true) singleton
  left join last_attendance latest on true
  cross join health_plan_payload plan
  cross join recent_exams_payload exams
  cross join active_casts_payload casts;

  return v_result;
end;
$$;

create or replace function public.patient_portal_history_page(
  p_token_hash text,
  p_cursor_at timestamptz default null,
  p_cursor_key text default null,
  p_limit integer default 20
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_has_more boolean;
  v_items jsonb;
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_next_at timestamptz;
  v_next_key text;
  v_session record;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('authenticated', false);
  end if;
  if (p_cursor_at is null) <> (p_cursor_key is null)
     or (p_cursor_key is not null and char_length(p_cursor_key) > 128) then
    raise exception 'Cursor inválido.' using errcode = '22023';
  end if;

  select *
  into v_session
  from private.patient_portal_session_record(p_token_hash);

  if not found then
    return jsonb_build_object('authenticated', false);
  end if;

  with events as (
    select
      attendance.created_at as event_at,
      'attendance:' || attendance.id::text as event_key,
      'attendance'::text as event_type,
      'Atendimento realizado'::text as title,
      coalesce(professional.display_name, 'Profissional')::text as description,
      professional.display_name as professional_name,
      position.name as professional_position,
      attendance.total as amount,
      attendance.id as attendance_id
    from public.attendances attendance
    left join public.profiles professional on professional.user_id = attendance.performed_by
    left join public.staff_positions position on position.id = professional.position_id
    where attendance.patient_id = v_session.patient_id
      and attendance.status = 'completed'

    union all

    select
      exam.completed_at,
      'exam:' || exam.id::text,
      'exam',
      exam_type.name || ' concluído',
      coalesce(responsible.display_name, 'Profissional responsável'),
      responsible.display_name,
      position.name,
      null::numeric,
      null::bigint
    from public.clinical_exams exam
    join public.exam_types exam_type on exam_type.id = exam.exam_type_id
    left join public.profiles responsible on responsible.user_id = exam.responsible_professional_id
    left join public.staff_positions position on position.id = responsible.position_id
    where exam.patient_id = v_session.patient_id
      and exam.status = 'completed'
      and exam.completed_at is not null

    union all

    select
      cast_record.applied_at,
      'cast-applied:' || cast_record.id::text,
      'cast',
      'Gesso aplicado — ' || private.clinical_cast_location_label(cast_record.body_region, cast_record.laterality),
      coalesce(applied.display_name, 'Profissional responsável'),
      applied.display_name,
      position.name,
      null::numeric,
      null::bigint
    from public.clinical_casts cast_record
    left join public.profiles applied on applied.user_id = cast_record.applied_by
    left join public.staff_positions position on position.id = applied.position_id
    where cast_record.patient_id = v_session.patient_id
      and cast_record.status in ('in_use', 'removed')

    union all

    select
      cast_record.removed_at,
      'cast-removed:' || cast_record.id::text,
      'cast',
      'Gesso retirado — ' || private.clinical_cast_location_label(cast_record.body_region, cast_record.laterality),
      coalesce(removed.display_name, 'Profissional responsável'),
      removed.display_name,
      position.name,
      null::numeric,
      null::bigint
    from public.clinical_casts cast_record
    left join public.profiles removed on removed.user_id = cast_record.removed_by
    left join public.staff_positions position on position.id = removed.position_id
    where cast_record.patient_id = v_session.patient_id
      and cast_record.status = 'removed'
      and cast_record.removed_at is not null

    union all

    select
      request.reviewed_at,
      'health-plan:' || request.id::text,
      'health_plan',
      case
        when request.coverage_start > request.reviewed_at + interval '1 minute'
          then 'Plano de Saúde renovado'
        else 'Plano de Saúde ativado'
      end,
      'Cobertura até ' || to_char(request.coverage_end at time zone 'America/Sao_Paulo', 'DD/MM/YYYY'),
      null::text,
      null::text,
      null::numeric,
      null::bigint
    from public.patient_health_plan_requests request
    where request.patient_id = v_session.patient_id
      and request.status = 'approved'
      and request.reviewed_at is not null
  ), page_rows as materialized (
    select event.*
    from events event
    where event.event_at is not null
      and (
        p_cursor_at is null
        or (event.event_at, event.event_key) < (p_cursor_at, p_cursor_key)
      )
    order by event.event_at desc, event.event_key desc
    limit v_limit + 1
  ), visible_rows as materialized (
    select *
    from page_rows
    order by event_at desc, event_key desc
    limit v_limit
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'key', visible.event_key,
          'occurred_at', visible.event_at,
          'type', visible.event_type,
          'title', visible.title,
          'description', visible.description,
          'professional_name', visible.professional_name,
          'professional_position', visible.professional_position,
          'amount', visible.amount,
          'attendance_id', visible.attendance_id
        ) order by visible.event_at desc, visible.event_key desc
      ),
      '[]'::jsonb
    ),
    (select count(*) > v_limit from page_rows),
    (select event_at from visible_rows order by event_at, event_key limit 1),
    (select event_key from visible_rows order by event_at, event_key limit 1)
  into v_items, v_has_more, v_next_at, v_next_key
  from visible_rows visible;

  return jsonb_build_object(
    'authenticated', true,
    'patient', jsonb_build_object(
      'name', v_session.patient_name,
      'passport', v_session.patient_passport
    ),
    'items', v_items,
    'next_cursor', case
      when v_has_more then jsonb_build_object('occurred_at', v_next_at, 'key', v_next_key)
      else null
    end
  );
end;
$$;

create or replace function public.patient_portal_attendance_page(
  p_token_hash text,
  p_cursor_at timestamptz default null,
  p_cursor_id bigint default null,
  p_limit integer default 20
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_has_more boolean;
  v_items jsonb;
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_metrics record;
  v_next_at timestamptz;
  v_next_id bigint;
  v_session record;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('authenticated', false);
  end if;
  if (p_cursor_at is null) <> (p_cursor_id is null) or p_cursor_id is not null and p_cursor_id < 1 then
    raise exception 'Cursor inválido.' using errcode = '22023';
  end if;

  select *
  into v_session
  from private.patient_portal_session_record(p_token_hash);

  if not found then
    return jsonb_build_object('authenticated', false);
  end if;

  select *
  into v_metrics
  from private.patient_portal_attendance_metrics(v_session.patient_id);

  with page_rows as materialized (
    select
      attendance.id,
      attendance.created_at,
      attendance.plan_code,
      attendance.plan_name,
      attendance.total,
      professional.display_name as professional_name,
      position.name as professional_position
    from public.attendances attendance
    left join public.profiles professional on professional.user_id = attendance.performed_by
    left join public.staff_positions position on position.id = professional.position_id
    where attendance.patient_id = v_session.patient_id
      and attendance.status = 'completed'
      and (
        p_cursor_at is null
        or (attendance.created_at, attendance.id) < (p_cursor_at, p_cursor_id)
      )
    order by attendance.created_at desc, attendance.id desc
    limit v_limit + 1
  ), visible_rows as materialized (
    select * from page_rows order by created_at desc, id desc limit v_limit
  ), item_counts as (
    select item.attendance_id, sum(item.quantity)::integer as item_count
    from public.attendance_items item
    join visible_rows visible on visible.id = item.attendance_id
    group by item.attendance_id
  )
  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', visible.id,
          'occurred_at', visible.created_at,
          'professional_name', visible.professional_name,
          'professional_position', visible.professional_position,
          'item_count', coalesce(item_counts.item_count, 0),
          'benefit_code', visible.plan_code,
          'benefit_name', visible.plan_name,
          'total', visible.total
        ) order by visible.created_at desc, visible.id desc
      ),
      '[]'::jsonb
    ),
    (select count(*) > v_limit from page_rows),
    (select created_at from visible_rows order by created_at, id limit 1),
    (select id from visible_rows order by created_at, id limit 1)
  into v_items, v_has_more, v_next_at, v_next_id
  from visible_rows visible
  left join item_counts on item_counts.attendance_id = visible.id;

  return jsonb_build_object(
    'authenticated', true,
    'patient', jsonb_build_object(
      'name', v_session.patient_name,
      'passport', v_session.patient_passport
    ),
    'summary', jsonb_build_object(
      'total_attendances', v_metrics.total_attendances,
      'lifetime_spent', v_metrics.lifetime_spent
    ),
    'items', v_items,
    'next_cursor', case
      when v_has_more then jsonb_build_object('occurred_at', v_next_at, 'id', v_next_id)
      else null
    end
  );
end;
$$;

create or replace function public.patient_portal_attendance_detail(
  p_token_hash text,
  p_attendance_id bigint
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_items jsonb;
  v_session record;
  v_target record;
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

  select
    attendance.id,
    attendance.created_at,
    attendance.plan_code,
    attendance.plan_name,
    attendance.subtotal,
    attendance.discount,
    attendance.total,
    professional.display_name as professional_name,
    position.name as professional_position
  into v_target
  from public.attendances attendance
  left join public.profiles professional on professional.user_id = attendance.performed_by
  left join public.staff_positions position on position.id = professional.position_id
  where attendance.id = p_attendance_id
    and attendance.patient_id = v_session.patient_id
    and attendance.status = 'completed';

  if not found then
    return jsonb_build_object('authenticated', true, 'found', false);
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'name', item.service_name,
        'unit_price', item.unit_price,
        'quantity', item.quantity,
        'discount_percent', item.discount_percent,
        'discount_amount', item.discount_amount,
        'line_total', item.line_total
      ) order by item.id
    ),
    '[]'::jsonb
  )
  into v_items
  from public.attendance_items item
  where item.attendance_id = v_target.id;

  return jsonb_build_object(
    'authenticated', true,
    'found', true,
    'patient', jsonb_build_object(
      'name', v_session.patient_name,
      'passport', v_session.patient_passport
    ),
    'attendance', jsonb_build_object(
      'id', v_target.id,
      'occurred_at', v_target.created_at,
      'professional_name', v_target.professional_name,
      'professional_position', v_target.professional_position,
      'benefit_code', v_target.plan_code,
      'benefit_name', v_target.plan_name,
      'subtotal', v_target.subtotal,
      'discount', v_target.discount,
      'total', v_target.total,
      'items', v_items
    )
  );
end;
$$;

revoke all on function public.patient_portal_summary(text)
from public, anon, authenticated, service_role;
revoke all on function public.patient_portal_history_page(text, timestamptz, text, integer)
from public, anon, authenticated, service_role;
revoke all on function public.patient_portal_attendance_page(text, timestamptz, bigint, integer)
from public, anon, authenticated, service_role;
revoke all on function public.patient_portal_attendance_detail(text, bigint)
from public, anon, authenticated, service_role;

grant execute on function public.patient_portal_summary(text)
to service_role;
grant execute on function public.patient_portal_history_page(text, timestamptz, text, integer)
to service_role;
grant execute on function public.patient_portal_attendance_page(text, timestamptz, bigint, integer)
to service_role;
grant execute on function public.patient_portal_attendance_detail(text, bigint)
to service_role;

comment on function private.patient_portal_attendance_metrics(bigint) is
  'Fonte canônica compartilhada de contagem e gasto total dos atendimentos concluídos do paciente.';
comment on function public.patient_portal_history_page(text, timestamptz, text, integer) is
  'Timeline clínica/financeira paginada, derivada exclusivamente da sessão do Portal. Somente service_role.';
comment on function public.patient_portal_attendance_page(text, timestamptz, bigint, integer) is
  'Atendimentos concluídos e totais históricos paginados, derivados da sessão do Portal. Somente service_role.';
comment on function public.patient_portal_attendance_detail(text, bigint) is
  'Detalhe financeiro histórico de atendimento pertencente ao paciente da sessão. Somente service_role.';

notify pgrst, 'reload schema';
