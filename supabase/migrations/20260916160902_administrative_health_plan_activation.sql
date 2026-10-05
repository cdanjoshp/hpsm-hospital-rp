-- HPSM pós-1.0: concessão e ajuste administrativo do Plano de Saúde.
-- O fluxo é separado de vendas, não gera valor e permanece no histórico canônico.

alter table public.patient_health_plan_requests
  alter column attendance_id drop not null,
  add column origin text not null default 'sale',
  add column administrative_action text;

alter table public.patient_health_plan_requests
  add constraint patient_health_plan_requests_origin_check check (
    (
      origin = 'sale'
      and attendance_id is not null
      and administrative_action is null
    )
    or
    (
      origin = 'administrative'
      and attendance_id is null
      and status = 'approved'
      and administrative_action in ('grant', 'expiry_adjustment')
    )
  );

comment on column public.patient_health_plan_requests.origin is
  'Origem financeira (sale) ou concessão/ajuste administrativo sem cobrança.';
comment on column public.patient_health_plan_requests.administrative_action is
  'Ação administrativa append-only: grant ou expiry_adjustment.';

-- Renovações financeiras passam a partir da cobertura efetiva mais recente,
-- inclusive quando a Diretoria ajustou a data após uma venda anterior.
create or replace function private.review_patient_health_plan_request(
  p_request_id bigint,
  p_decision text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_current_end timestamptz;
  v_decided_at timestamptz := now();
  v_request public.patient_health_plan_requests%rowtype;
  v_start timestamptz;
begin
  if v_actor_id is null or not private.has_permission(v_actor_id, 'healthplans.review') then
    raise exception 'Você não possui permissão para analisar planos de saúde.' using errcode = '42501';
  end if;

  if p_decision not in ('approved', 'rejected') then
    raise exception 'Decisão inválida.' using errcode = '22023';
  end if;

  select request.*
  into v_request
  from public.patient_health_plan_requests request
  where request.id = p_request_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Solicitação não localizada.';
  end if;

  if v_request.status <> 'pending' then
    if v_request.status = p_decision then
      return jsonb_build_object(
        'id', v_request.id,
        'status', v_request.status,
        'valid_until', v_request.coverage_end,
        'already_reviewed', true
      );
    end if;
    raise exception using errcode = 'P0001', message = 'A solicitação já possui uma decisão diferente.';
  end if;

  perform 1
  from public.patients patient
  where patient.id = v_request.patient_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Paciente não localizado.';
  end if;

  if p_decision = 'approved' then
    select request.coverage_end
    into v_current_end
    from public.patient_health_plan_requests request
    where request.patient_id = v_request.patient_id
      and request.status = 'approved'
    order by request.reviewed_at desc nulls last, request.id desc
    limit 1;

    v_start := greatest(v_decided_at, coalesce(v_current_end, v_decided_at));

    update public.patient_health_plan_requests
    set status = 'approved',
        reviewed_by = v_actor_id,
        reviewed_at = v_decided_at,
        rejection_reason = null,
        coverage_start = v_start,
        coverage_end = v_start + interval '30 days'
    where id = v_request.id
    returning * into v_request;
  else
    if char_length(btrim(coalesce(p_reason, ''))) < 10 then
      raise exception 'Informe o motivo da recusa com pelo menos 10 caracteres.' using errcode = '22023';
    end if;
    if char_length(btrim(p_reason)) > 2000 then
      raise exception 'O motivo da recusa deve ter no máximo 2000 caracteres.' using errcode = '22023';
    end if;

    update public.patient_health_plan_requests
    set status = 'rejected',
        reviewed_by = v_actor_id,
        reviewed_at = v_decided_at,
        rejection_reason = btrim(p_reason),
        coverage_start = null,
        coverage_end = null
    where id = v_request.id
    returning * into v_request;
  end if;

  return jsonb_build_object(
    'id', v_request.id,
    'status', v_request.status,
    'valid_until', v_request.coverage_end,
    'already_reviewed', false
  );
end;
$$;

-- A rotina privilegiada grava na tabela protegida, mas deriva o ator da sessão
-- e exige simultaneamente a permissão e um cargo oficial de nível 11–14.
create or replace function private.admin_set_patient_health_plan(
  p_patient_id bigint,
  p_valid_until date
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_action text;
  v_actor uuid := private.hpsm_current_actor();
  v_actor_name text;
  v_current public.patient_health_plan_requests%rowtype;
  v_end timestamptz;
  v_now timestamptz := now();
  v_request public.patient_health_plan_requests%rowtype;
  v_start timestamptz;
  v_today date := timezone('America/Sao_Paulo', now())::date;
begin
  if not private.has_permission(v_actor, 'healthplans.review')
     or coalesce(private.current_position_level(v_actor), 0) not between 11 and 14 then
    raise exception 'Somente os cargos 11 a 14 podem conceder ou ajustar o Plano de Saúde.' using errcode = '42501';
  end if;

  if p_patient_id is null or p_patient_id < 1 then
    raise exception 'Selecione um paciente válido.' using errcode = '22023';
  end if;
  if p_valid_until is null or p_valid_until < v_today or p_valid_until > v_today + 3650 then
    raise exception 'Informe uma data de vencimento entre hoje e os próximos 10 anos.' using errcode = '22023';
  end if;

  perform 1
  from public.patients patient
  where patient.id = p_patient_id
  for update;
  if not found then
    raise exception 'Paciente não localizado.' using errcode = 'P0002';
  end if;

  select request.*
  into v_current
  from public.patient_health_plan_requests request
  where request.patient_id = p_patient_id
    and request.status = 'approved'
  order by request.reviewed_at desc nulls last, request.id desc
  limit 1;

  v_action := case
    when v_current.id is not null and v_current.coverage_end > v_now then 'expiry_adjustment'
    else 'grant'
  end;

  if v_action = 'grant' and exists (
    select 1
    from public.patient_health_plan_requests pending
    where pending.patient_id = p_patient_id
      and pending.status = 'pending'
  ) then
    raise exception 'Este paciente possui uma solicitação aguardando confirmação. Analise a pendência antes de conceder o plano sem cobrança.' using errcode = 'P0001';
  end if;

  v_end := ((p_valid_until + 1)::timestamp at time zone 'America/Sao_Paulo') - interval '1 microsecond';
  v_start := case when v_action = 'expiry_adjustment' then v_current.coverage_start else v_now end;

  if v_end <= v_start then
    raise exception 'A data de vencimento deve ser posterior ao início da cobertura.' using errcode = '22023';
  end if;

  insert into public.patient_health_plan_requests (
    patient_id,
    attendance_id,
    status,
    requested_at,
    reviewed_by,
    reviewed_at,
    coverage_start,
    coverage_end,
    origin,
    administrative_action
  ) values (
    p_patient_id,
    null,
    'approved',
    v_now,
    v_actor,
    v_now,
    v_start,
    v_end,
    'administrative',
    v_action
  )
  returning * into v_request;

  select profile.display_name into v_actor_name
  from public.profiles profile
  where profile.user_id = v_actor;

  return jsonb_build_object(
    'id', v_request.id,
    'action', v_action,
    'status', 'active',
    'activated_at', v_request.coverage_start,
    'valid_until', v_request.coverage_end,
    'authorized_by', v_actor,
    'authorized_by_name', v_actor_name,
    'financial_value', 0
  );
end;
$$;

revoke all on function private.admin_set_patient_health_plan(bigint, date)
from public, anon, authenticated, service_role;
grant execute on function private.admin_set_patient_health_plan(bigint, date)
to authenticated;

create or replace function public.admin_set_patient_health_plan(
  p_patient_id bigint,
  p_valid_until date
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.admin_set_patient_health_plan(p_patient_id, p_valid_until);
$$;

revoke all on function public.admin_set_patient_health_plan(bigint, date)
from public, anon, authenticated, service_role;
grant execute on function public.admin_set_patient_health_plan(bigint, date)
to authenticated;

comment on function public.admin_set_patient_health_plan(bigint, date) is
  'Cargos oficiais 11–14 concedem ou ajustam a validade do plano sem criar venda, atendimento ou valor financeiro.';

-- Estado canônico: o último evento aprovado prevalece, inclusive quando a
-- Diretoria reduz uma validade que antes era maior.
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
    order by request.reviewed_at desc nulls last, request.id desc
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
  patient.birth_date
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
      patient.emergency_contact_name, patient.emergency_contact_phone, patient.created_at, patient.updated_at
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

create or replace function public.patient_plan_history_page(
  p_patient_id bigint,
  p_limit integer default 10,
  p_offset integer default 0
)
returns table (total_count bigint, records jsonb)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.has_permission((select auth.uid()), 'patients.view') then
    raise exception 'Você não possui permissão para consultar pacientes.';
  end if;
  if p_limit < 1 or p_limit > 50 or p_offset < 0 then
    raise exception 'Paginação inválida.';
  end if;

  return query
  with matching as materialized (
    select request.*
    from public.patient_health_plan_requests request
    where request.patient_id = p_patient_id
  ), page as (
    select matching.*
    from matching
    order by matching.requested_at desc, matching.id desc
    limit p_limit offset p_offset
  ), rendered as (
    select
      page.requested_at,
      page.id,
      jsonb_build_object(
        'id', page.id,
        'attendance_id', page.attendance_id,
        'status', page.status,
        'requested_at', page.requested_at,
        'reviewed_at', page.reviewed_at,
        'rejection_reason', page.rejection_reason,
        'coverage_start', page.coverage_start,
        'coverage_end', page.coverage_end,
        'authorized_by_name', reviewer.display_name,
        'seller_name', seller.display_name,
        'seller_passport', seller.passport,
        'attendance_total', attendance.total,
        'origin', page.origin,
        'administrative_action', page.administrative_action,
        'plan_value', coalesce((
          select sum(item.line_total)
          from public.attendance_items item
          join public.service_catalog service on service.id = item.service_id
          where item.attendance_id = page.attendance_id
            and service.code = 'plano_saude_convenio'
        ), 0)
      ) as record
    from page
    left join public.attendances attendance on attendance.id = page.attendance_id
    left join public.profiles seller on seller.user_id = attendance.performed_by
    left join public.profiles reviewer on reviewer.user_id = page.reviewed_by
  )
  select
    (select count(*) from matching)::bigint,
    coalesce(jsonb_agg(rendered.record order by rendered.requested_at desc, rendered.id desc), '[]'::jsonb)
  from rendered;
end;
$$;

-- A timeline profissional não cria uma falsa solicitação financeira para o
-- evento administrativo e informa claramente se houve concessão ou ajuste.
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
    from public.patients patient
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
    from public.attendances attendance
    left join public.profiles professional on professional.user_id = attendance.performed_by
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
    from public.patient_health_plan_requests request
    where request.patient_id = p_patient_id
      and request.origin = 'sale'

    union all

    select
      'plan-review-' || request.id::text,
      request.reviewed_at,
      'health-plan-review',
      case
        when request.status = 'rejected' then 'Ativação do plano recusada'
        when request.administrative_action = 'grant' then 'Plano de Saúde concedido sem cobrança'
        when request.administrative_action = 'expiry_adjustment' then 'Vencimento do Plano de Saúde ajustado'
        when request.coverage_start > request.reviewed_at + interval '1 minute' then 'Plano de Saúde renovado'
        else 'Plano de Saúde ativado'
      end,
      case
        when request.status = 'rejected' then coalesce(request.rejection_reason, 'Solicitação recusada')
        when request.origin = 'administrative' then 'Sem cobrança · validade até ' || to_char(request.coverage_end at time zone 'America/Sao_Paulo', 'DD/MM/YYYY')
        else 'Validade até ' || to_char(request.coverage_end at time zone 'America/Sao_Paulo', 'DD/MM/YYYY')
      end,
      null::bigint,
      null::bigint
    from public.patient_health_plan_requests request
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
      'Responsável: ' || responsible.display_name || coalesce(' · Revisor: ' || reviewer.display_name, ''),
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

revoke all on function public.admin_set_patient_health_plan(bigint, date)
from public, anon, authenticated, service_role;
grant execute on function public.admin_set_patient_health_plan(bigint, date)
to authenticated;

notify pgrst, 'reload schema';
