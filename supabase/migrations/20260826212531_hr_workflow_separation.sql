-- HPSM · separação de afastamentos, justificativas de horas e fechamento humano.
-- Reaproveita as estruturas existentes de horas, semanas, advertências,
-- notificações e auditoria sem criar qualquer escala de trabalho.

-- ---------------------------------------------------------------------------
-- Afastamentos preventivos
-- ---------------------------------------------------------------------------

alter table public.rh_absence_requests
  add column if not exists observation text;

alter table public.rh_absence_requests
  drop constraint if exists rh_absence_requests_effect_check,
  drop constraint if exists rh_absence_requests_state_check;

alter table public.rh_absence_requests
  add constraint rh_absence_requests_effect_check
    check (approval_effect is null or approval_effect in ('record_only', 'weekly_exemption', 'weekly_adjustment')),
  add constraint rh_absence_requests_observation_check
    check (observation is null or char_length(btrim(observation)) between 2 and 2000),
  add constraint rh_absence_requests_state_check check (
    (status = 'pending' and approval_effect is null and reviewed_by is null and reviewed_at is null and cancelled_by is null and cancelled_at is null)
    or
    (status = 'approved' and approval_effect is not null and reviewed_by is not null and reviewed_at is not null and cancelled_by is null and cancelled_at is null)
    or
    (status = 'rejected' and approval_effect is null and reviewed_by is not null and reviewed_at is not null and review_note is not null and cancelled_by is null and cancelled_at is null)
    or
    (status = 'cancelled' and approval_effect is null and reviewed_by is null and reviewed_at is null and cancelled_by = employee_id and cancelled_at is not null)
  );

create table public.rh_leave_week_adjustments (
  id bigint generated always as identity primary key,
  leave_request_id bigint not null references public.rh_absence_requests(id) on delete restrict,
  employee_id uuid not null references public.profiles(user_id) on delete restrict,
  week_start date not null,
  deducted_minutes integer not null,
  approved_by uuid not null references public.profiles(user_id) on delete restrict,
  approved_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint rh_leave_week_adjustments_week_check
    check (extract(isodow from week_start) = 1),
  constraint rh_leave_week_adjustments_minutes_check
    check (deducted_minutes between 1 and 600),
  constraint rh_leave_week_adjustments_request_week_unique
    unique (leave_request_id, week_start)
);

create index rh_leave_week_adjustments_employee_week_idx
  on public.rh_leave_week_adjustments (employee_id, week_start);
create index rh_leave_week_adjustments_approved_by_idx
  on public.rh_leave_week_adjustments (approved_by);

-- Preserva eventuais aprovações antigas de isenção integral.
insert into public.rh_leave_week_adjustments (
  leave_request_id, employee_id, week_start, deducted_minutes, approved_by, approved_at
)
select
  request.id,
  request.employee_id,
  generated.week_start::date,
  600,
  request.reviewed_by,
  coalesce(request.reviewed_at, request.updated_at)
from public.rh_absence_requests request
cross join lateral generate_series(
  date_trunc('week', request.start_date)::date,
  date_trunc('week', request.end_date)::date,
  interval '7 days'
) generated(week_start)
where request.status = 'approved'
  and request.approval_effect = 'weekly_exemption'
  and request.reviewed_by is not null
on conflict (leave_request_id, week_start) do nothing;

-- ---------------------------------------------------------------------------
-- Fechamentos coletivos e registros semanais recalculáveis
-- ---------------------------------------------------------------------------

create table public.rh_week_closures (
  id bigint generated always as identity primary key,
  week_start date not null unique,
  week_end date not null,
  status text not null default 'open',
  started_by uuid not null references public.profiles(user_id) on delete restrict,
  started_at timestamptz not null default now(),
  closed_by uuid references public.profiles(user_id) on delete restrict,
  closed_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint rh_week_closures_week_check check (
    extract(isodow from week_start) = 1 and week_end = week_start + 6
  ),
  constraint rh_week_closures_status_check
    check (status in ('open', 'closed', 'reopened')),
  constraint rh_week_closures_state_check check (
    (status in ('open', 'reopened'))
    or (status = 'closed' and closed_by is not null and closed_at is not null)
  )
);

create table public.rh_week_reopen_events (
  id bigint generated always as identity primary key,
  closure_id bigint not null references public.rh_week_closures(id) on delete restrict,
  reason text not null,
  reopened_by uuid not null references public.profiles(user_id) on delete restrict,
  reopened_at timestamptz not null default now(),
  constraint rh_week_reopen_events_reason_check
    check (char_length(btrim(reason)) between 10 and 2000)
);

create index rh_week_reopen_events_closure_idx
  on public.rh_week_reopen_events (closure_id, reopened_at desc);
create index rh_week_reopen_events_actor_idx
  on public.rh_week_reopen_events (reopened_by);

insert into public.rh_week_closures (
  week_start, week_end, status, started_by, started_at, closed_by, closed_at
)
select
  records.week_start,
  max(records.week_end),
  'closed',
  (array_agg(records.closed_by order by records.closed_at asc))[1],
  min(records.closed_at),
  (array_agg(records.closed_by order by records.closed_at desc))[1],
  max(records.closed_at)
from public.rh_weekly_records records
group by records.week_start
on conflict (week_start) do nothing;

alter table public.rh_weekly_records
  add column if not exists closure_id bigint references public.rh_week_closures(id) on delete restrict,
  add column if not exists base_required_minutes integer not null default 600,
  add column if not exists leave_deduction_minutes integer not null default 0,
  add column if not exists deficit_minutes integer not null default 0,
  add column if not exists justification_minutes integer not null default 0,
  add column if not exists remaining_deficit_minutes integer not null default 0,
  add column if not exists closure_status text not null default 'closed';

update public.rh_weekly_records records
set closure_id = closures.id
from public.rh_week_closures closures
where records.closure_id is null
  and closures.week_start = records.week_start;

update public.rh_weekly_records
set base_required_minutes = 600,
    leave_deduction_minutes = case
      when status = 'justified' and absence_request_id is not null then 600
      else greatest(0, 600 - required_minutes)
    end,
    required_minutes = case
      when status = 'justified' and absence_request_id is not null then 0
      else required_minutes
    end;

update public.rh_weekly_records
set deficit_minutes = greatest(0, required_minutes - worked_minutes),
    justification_minutes = 0,
    remaining_deficit_minutes = greatest(0, required_minutes - worked_minutes),
    closure_status = 'closed';

alter table public.rh_weekly_records
  alter column closure_id set not null,
  alter column closed_by drop not null,
  alter column closed_at drop not null,
  drop constraint if exists rh_weekly_records_required_check,
  drop constraint if exists rh_weekly_records_status_check,
  drop constraint if exists rh_weekly_records_absence_state_check;

alter table public.rh_weekly_records
  add constraint rh_weekly_records_required_check
    check (required_minutes between 0 and 60000),
  add constraint rh_weekly_records_base_required_check
    check (base_required_minutes between 0 and 60000),
  add constraint rh_weekly_records_leave_deduction_check
    check (leave_deduction_minutes between 0 and base_required_minutes),
  add constraint rh_weekly_records_deficit_check
    check (deficit_minutes between 0 and 60000),
  add constraint rh_weekly_records_justification_minutes_check
    check (justification_minutes between 0 and deficit_minutes),
  add constraint rh_weekly_records_remaining_deficit_check
    check (remaining_deficit_minutes between 0 and deficit_minutes),
  add constraint rh_weekly_records_calculation_check check (
    required_minutes = greatest(0, base_required_minutes - leave_deduction_minutes)
    and deficit_minutes = greatest(0, required_minutes - worked_minutes)
    and remaining_deficit_minutes = greatest(0, deficit_minutes - justification_minutes)
  ),
  add constraint rh_weekly_records_status_check
    check (status in ('met', 'justified', 'deficit', 'warning_issued', 'warning_annulled')),
  add constraint rh_weekly_records_closure_status_check
    check (closure_status in ('awaiting_justification', 'justification_pending', 'ready', 'closed'));

create index rh_weekly_records_closure_idx
  on public.rh_weekly_records (closure_id, closure_status);
create index rh_weekly_records_pending_justification_idx
  on public.rh_weekly_records (employee_id, week_start)
  where closure_status in ('awaiting_justification', 'justification_pending');

-- ---------------------------------------------------------------------------
-- Justificativas reativas de déficit
-- ---------------------------------------------------------------------------

create table public.rh_hour_justifications (
  id bigint generated always as identity primary key,
  weekly_record_id bigint not null unique references public.rh_weekly_records(id) on delete restrict,
  employee_id uuid not null references public.profiles(user_id) on delete restrict,
  deficit_minutes integer not null,
  reason text not null,
  status text not null default 'pending',
  credited_minutes integer,
  review_note text,
  reviewed_by uuid references public.profiles(user_id) on delete restrict,
  reviewed_at timestamptz,
  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint rh_hour_justifications_deficit_check
    check (deficit_minutes between 1 and 60000),
  constraint rh_hour_justifications_reason_check
    check (char_length(btrim(reason)) between 10 and 2000),
  constraint rh_hour_justifications_status_check
    check (status in ('pending', 'approved', 'rejected')),
  constraint rh_hour_justifications_credit_check
    check (credited_minutes is null or credited_minutes between 0 and deficit_minutes),
  constraint rh_hour_justifications_note_check
    check (review_note is null or char_length(btrim(review_note)) between 2 and 2000),
  constraint rh_hour_justifications_state_check check (
    (status = 'pending' and credited_minutes is null and reviewed_by is null and reviewed_at is null)
    or
    (status = 'approved' and credited_minutes is not null and credited_minutes > 0 and reviewed_by is not null and reviewed_at is not null)
    or
    (status = 'rejected' and credited_minutes = 0 and reviewed_by is not null and reviewed_at is not null and review_note is not null)
  )
);

create index rh_hour_justifications_employee_idx
  on public.rh_hour_justifications (employee_id, submitted_at desc);
create index rh_hour_justifications_pending_idx
  on public.rh_hour_justifications (submitted_at)
  where status = 'pending';
create index rh_hour_justifications_reviewed_by_idx
  on public.rh_hour_justifications (reviewed_by)
  where reviewed_by is not null;

-- ---------------------------------------------------------------------------
-- Advertências originadas do fechamento ou lançadas manualmente
-- ---------------------------------------------------------------------------

alter table public.rh_warnings
  alter column weekly_record_id drop not null,
  add column if not exists origin text not null default 'weekly_closure',
  add column if not exists category text not null default 'weekly_goal';

alter table public.rh_warnings
  add constraint rh_warnings_origin_check
    check (origin in ('weekly_closure', 'manual')),
  add constraint rh_warnings_category_check
    check (category in ('weekly_goal', 'attendance', 'conduct', 'internal_rules', 'other')),
  add constraint rh_warnings_origin_link_check check (
    (origin = 'weekly_closure' and weekly_record_id is not null)
    or (origin = 'manual' and weekly_record_id is null)
  );

-- ---------------------------------------------------------------------------
-- Funções de afastamento
-- ---------------------------------------------------------------------------

create or replace function public.create_hr_leave_request(
  p_start_date date,
  p_end_date date,
  p_reason text,
  p_observation text,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.rh_absence_requests;
begin
  if not exists (
    select 1 from public.profiles
    where user_id = p_actor_id
      and status = 'active'
      and role_code <> 'diretor_geral'
  ) then
    raise exception using errcode = '42501', message = 'Colaborador sem acesso ao controle de afastamentos.';
  end if;
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date
     or p_end_date > p_start_date + 89 then
    raise exception using errcode = '22023', message = 'Informe um período válido de até 90 dias.';
  end if;
  if p_start_date <= (now() at time zone 'America/Sao_Paulo')::date then
    raise exception using errcode = '22023', message = 'O afastamento deve ser solicitado antes do início da ausência.';
  end if;
  if char_length(btrim(coalesce(p_reason, ''))) not between 10 and 2000 then
    raise exception using errcode = '22023', message = 'Informe o motivo entre 10 e 2000 caracteres.';
  end if;
  if p_observation is not null and nullif(btrim(p_observation), '') is not null
     and char_length(btrim(p_observation)) not between 2 and 2000 then
    raise exception using errcode = '22023', message = 'A observação deve ter entre 2 e 2000 caracteres.';
  end if;

  insert into public.rh_absence_requests (
    employee_id, start_date, end_date, reason, observation
  ) values (
    p_actor_id, p_start_date, p_end_date, btrim(p_reason), nullif(btrim(p_observation), '')
  ) returning * into v_row;

  return to_jsonb(v_row);
end;
$$;

create or replace function public.cancel_hr_leave_request(
  p_request_id bigint,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.rh_absence_requests;
begin
  update public.rh_absence_requests
  set status = 'cancelled',
      cancelled_by = p_actor_id,
      cancelled_at = now(),
      updated_at = now()
  where id = p_request_id
    and employee_id = p_actor_id
    and status = 'pending'
  returning * into v_row;

  if not found then
    raise exception using errcode = 'P0002', message = 'A solicitação não está disponível para cancelamento.';
  end if;
  return to_jsonb(v_row);
end;
$$;

create or replace function public.review_hr_leave_request(
  p_request_id bigint,
  p_decision text,
  p_adjustments jsonb,
  p_note text,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.rh_absence_requests;
  v_item jsonb;
  v_week_start date;
  v_minutes integer;
  v_seen_weeks date[] := array[]::date[];
  v_total integer := 0;
begin
  if not private.is_director_user(p_actor_id) then
    raise exception using errcode = '42501', message = 'Apenas a Diretoria pode analisar afastamentos.';
  end if;

  select * into v_request
  from public.rh_absence_requests
  where id = p_request_id
  for update;

  if not found or v_request.status <> 'pending' then
    raise exception using errcode = 'P0002', message = 'Afastamento não encontrado ou já analisado.';
  end if;
  if v_request.employee_id = p_actor_id then
    raise exception using errcode = '42501', message = 'Um diretor não pode analisar o próprio afastamento.';
  end if;
  if p_decision not in ('approved', 'rejected') then
    raise exception using errcode = '22023', message = 'Decisão inválida.';
  end if;

  if p_decision = 'approved' then
    if p_adjustments is null or jsonb_typeof(p_adjustments) <> 'array' or jsonb_array_length(p_adjustments) = 0 then
      raise exception using errcode = '22023', message = 'Informe as horas abatidas em pelo menos uma semana.';
    end if;
    for v_item in select value from jsonb_array_elements(p_adjustments)
    loop
      begin
        v_week_start := (v_item ->> 'week_start')::date;
        v_minutes := (v_item ->> 'deducted_minutes')::integer;
      exception when others then
        raise exception using errcode = '22023', message = 'Um dos abatimentos semanais é inválido.';
      end;
      if extract(isodow from v_week_start) <> 1
         or v_week_start + 6 < v_request.start_date
         or v_week_start > v_request.end_date
         or v_minutes not between 1 and 600
         or v_week_start = any(v_seen_weeks) then
        raise exception using errcode = '22023', message = 'Um dos abatimentos semanais é inválido ou repetido.';
      end if;
      v_seen_weeks := array_append(v_seen_weeks, v_week_start);
      v_total := v_total + v_minutes;
      insert into public.rh_leave_week_adjustments (
        leave_request_id, employee_id, week_start, deducted_minutes, approved_by
      ) values (
        v_request.id, v_request.employee_id, v_week_start, v_minutes, p_actor_id
      );
    end loop;
    if v_total <= 0 then
      raise exception using errcode = '22023', message = 'Informe ao menos um abatimento de horas.';
    end if;
  elsif char_length(btrim(coalesce(p_note, ''))) not between 10 and 2000 then
    raise exception using errcode = '22023', message = 'Informe o motivo da recusa entre 10 e 2000 caracteres.';
  end if;

  update public.rh_absence_requests
  set status = p_decision,
      approval_effect = case when p_decision = 'approved' then 'weekly_adjustment' else null end,
      review_note = nullif(btrim(p_note), ''),
      reviewed_by = p_actor_id,
      reviewed_at = now(),
      updated_at = now()
  where id = p_request_id
  returning * into v_request;

  return jsonb_build_object(
    'leave', to_jsonb(v_request),
    'deducted_minutes', case when p_decision = 'approved' then v_total else 0 end
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Apuração, justificativa e fechamento
-- ---------------------------------------------------------------------------

create or replace function public.close_hr_week(
  p_employee_id uuid,
  p_week_start date,
  p_worked_minutes integer,
  p_calculation_details jsonb,
  p_closure_note text,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles;
  v_week_end date := p_week_start + 6;
  v_cycle_month date := date_trunc('month', p_week_start + 6)::date;
  v_closure public.rh_week_closures;
  v_week public.rh_weekly_records;
  v_deduction integer := 0;
  v_required integer;
  v_deficit integer;
  v_credit integer := 0;
  v_justification_status text;
begin
  if not private.is_director_user(p_actor_id) then
    raise exception using errcode = '42501', message = 'Apenas a Diretoria pode apurar semanas.';
  end if;
  if p_employee_id = p_actor_id then
    raise exception using errcode = '42501', message = 'Um diretor não pode apurar a própria semana.';
  end if;
  if p_week_start is null or extract(isodow from p_week_start) <> 1 then
    raise exception using errcode = '22023', message = 'A semana deve começar em uma segunda-feira.';
  end if;
  if v_week_end > (now() at time zone 'America/Sao_Paulo')::date then
    raise exception using errcode = '22023', message = 'A semana ainda não terminou.';
  end if;
  if p_worked_minutes is null or p_worked_minutes not between 0 and 60000 then
    raise exception using errcode = '22023', message = 'Total semanal inválido.';
  end if;
  if p_closure_note is not null and char_length(p_closure_note) > 1000 then
    raise exception using errcode = '22023', message = 'A observação deve ter até 1000 caracteres.';
  end if;

  select * into v_profile
  from public.profiles
  where user_id = p_employee_id
  for update;
  if not found or v_profile.role_code = 'diretor_geral' or v_profile.status = 'inactive' then
    raise exception using errcode = '22023', message = 'Colaborador indisponível para apuração.';
  end if;

  insert into public.rh_week_closures (week_start, week_end, started_by)
  values (p_week_start, v_week_end, p_actor_id)
  on conflict (week_start) do update set updated_at = now()
  returning * into v_closure;

  if v_closure.status = 'closed' then
    raise exception using errcode = 'P0001', message = 'A semana já foi fechada. Reabra antes de corrigir.';
  end if;

  select least(600, coalesce(sum(adjustment.deducted_minutes), 0))::integer
  into v_deduction
  from public.rh_leave_week_adjustments adjustment
  join public.rh_absence_requests request on request.id = adjustment.leave_request_id
  where adjustment.employee_id = p_employee_id
    and adjustment.week_start = p_week_start
    and request.status = 'approved';

  v_required := greatest(0, 600 - v_deduction);
  v_deficit := greatest(0, v_required - p_worked_minutes);

  insert into public.rh_weekly_records (
    employee_id, week_start, week_end, cycle_month,
    base_required_minutes, leave_deduction_minutes, required_minutes,
    worked_minutes, deficit_minutes, justification_minutes, remaining_deficit_minutes,
    status, closure_status, closure_id, calculation_details, closure_note,
    closed_by, closed_at
  ) values (
    p_employee_id, p_week_start, v_week_end, v_cycle_month,
    600, v_deduction, v_required,
    p_worked_minutes, v_deficit, 0, v_deficit,
    case when v_deficit = 0 then 'met' else 'deficit' end,
    case when v_deficit = 0 then 'ready' else 'awaiting_justification' end,
    v_closure.id, coalesce(p_calculation_details, '{}'::jsonb), nullif(btrim(p_closure_note), ''),
    null, null
  )
  on conflict (employee_id, week_start) do update
  set closure_id = excluded.closure_id,
      week_end = excluded.week_end,
      cycle_month = excluded.cycle_month,
      base_required_minutes = excluded.base_required_minutes,
      leave_deduction_minutes = excluded.leave_deduction_minutes,
      required_minutes = excluded.required_minutes,
      worked_minutes = excluded.worked_minutes,
      deficit_minutes = excluded.deficit_minutes,
      justification_minutes = least(public.rh_weekly_records.justification_minutes, excluded.deficit_minutes),
      remaining_deficit_minutes = greatest(0, excluded.deficit_minutes - least(public.rh_weekly_records.justification_minutes, excluded.deficit_minutes)),
      status = case
        when greatest(0, excluded.deficit_minutes - least(public.rh_weekly_records.justification_minutes, excluded.deficit_minutes)) = 0
          then case when least(public.rh_weekly_records.justification_minutes, excluded.deficit_minutes) > 0 then 'justified' else 'met' end
        else 'deficit'
      end,
      closure_status = case
        when greatest(0, excluded.deficit_minutes - least(public.rh_weekly_records.justification_minutes, excluded.deficit_minutes)) = 0 then 'ready'
        else 'awaiting_justification'
      end,
      calculation_details = excluded.calculation_details,
      closure_note = excluded.closure_note,
      closed_by = null,
      closed_at = null,
      updated_at = now()
  returning * into v_week;

  select justification.status, coalesce(justification.credited_minutes, 0)
  into v_justification_status, v_credit
  from public.rh_hour_justifications justification
  where justification.weekly_record_id = v_week.id;

  if found then
    v_credit := least(v_credit, v_week.deficit_minutes);
    update public.rh_weekly_records
    set justification_minutes = v_credit,
        remaining_deficit_minutes = greatest(0, deficit_minutes - v_credit),
        status = case
          when greatest(0, deficit_minutes - v_credit) = 0 and v_credit > 0 then 'justified'
          when greatest(0, deficit_minutes - v_credit) = 0 then 'met'
          else 'deficit'
        end,
        closure_status = case
          when v_justification_status = 'pending' then 'justification_pending'
          else 'ready'
        end,
        updated_at = now()
    where id = v_week.id
    returning * into v_week;
  end if;

  return jsonb_build_object(
    'weekly_record_id', v_week.id,
    'status', v_week.status,
    'closure_status', v_week.closure_status,
    'base_required_minutes', v_week.base_required_minutes,
    'leave_deduction_minutes', v_week.leave_deduction_minutes,
    'required_minutes', v_week.required_minutes,
    'worked_minutes', v_week.worked_minutes,
    'remaining_deficit_minutes', v_week.remaining_deficit_minutes,
    'warning_id', null,
    'active_warnings', (
      select count(*) from public.rh_warnings warning
      where warning.employee_id = p_employee_id
        and warning.cycle_month = v_cycle_month
        and warning.status = 'active'
    ),
    'suspended', false
  );
end;
$$;

create or replace function public.submit_hr_hour_justification(
  p_weekly_record_id bigint,
  p_reason text,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_week public.rh_weekly_records;
  v_row public.rh_hour_justifications;
begin
  select * into v_week
  from public.rh_weekly_records
  where id = p_weekly_record_id
  for update;

  if not found or v_week.employee_id <> p_actor_id then
    raise exception using errcode = '42501', message = 'Pendência de horas indisponível para este colaborador.';
  end if;
  if v_week.closure_status <> 'awaiting_justification' or v_week.remaining_deficit_minutes <= 0 then
    raise exception using errcode = 'P0001', message = 'Esta semana não está aguardando justificativa.';
  end if;
  if char_length(btrim(coalesce(p_reason, ''))) not between 10 and 2000 then
    raise exception using errcode = '22023', message = 'Informe o motivo entre 10 e 2000 caracteres.';
  end if;

  insert into public.rh_hour_justifications (
    weekly_record_id, employee_id, deficit_minutes, reason
  ) values (
    v_week.id, v_week.employee_id, v_week.remaining_deficit_minutes, btrim(p_reason)
  ) returning * into v_row;

  update public.rh_weekly_records
  set closure_status = 'justification_pending', updated_at = now()
  where id = v_week.id;

  return to_jsonb(v_row);
end;
$$;

create or replace function public.review_hr_hour_justification(
  p_justification_id bigint,
  p_decision text,
  p_credited_minutes integer,
  p_note text,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.rh_hour_justifications;
  v_week public.rh_weekly_records;
  v_credit integer;
begin
  if not private.is_director_user(p_actor_id) then
    raise exception using errcode = '42501', message = 'Apenas a Diretoria pode analisar justificativas de horas.';
  end if;

  select * into v_row
  from public.rh_hour_justifications
  where id = p_justification_id
  for update;
  if not found or v_row.status <> 'pending' then
    raise exception using errcode = 'P0002', message = 'Justificativa não encontrada ou já analisada.';
  end if;
  if v_row.employee_id = p_actor_id then
    raise exception using errcode = '42501', message = 'Um diretor não pode analisar a própria justificativa.';
  end if;
  if p_decision not in ('approved', 'rejected') then
    raise exception using errcode = '22023', message = 'Decisão inválida.';
  end if;

  select * into v_week
  from public.rh_weekly_records
  where id = v_row.weekly_record_id
  for update;
  if not found or v_week.closure_status <> 'justification_pending' then
    raise exception using errcode = 'P0001', message = 'O fechamento não está aguardando esta análise.';
  end if;

  if p_decision = 'approved' then
    v_credit := p_credited_minutes;
    if v_credit is null or v_credit not between 1 and v_row.deficit_minutes then
      raise exception using errcode = '22023', message = 'Informe quantas horas serão abonadas, sem ultrapassar o déficit.';
    end if;
  else
    v_credit := 0;
    if char_length(btrim(coalesce(p_note, ''))) not between 10 and 2000 then
      raise exception using errcode = '22023', message = 'Informe o motivo da recusa entre 10 e 2000 caracteres.';
    end if;
  end if;

  update public.rh_hour_justifications
  set status = p_decision,
      credited_minutes = v_credit,
      review_note = nullif(btrim(p_note), ''),
      reviewed_by = p_actor_id,
      reviewed_at = now(),
      updated_at = now()
  where id = v_row.id
  returning * into v_row;

  update public.rh_weekly_records
  set justification_minutes = least(v_credit, deficit_minutes),
      remaining_deficit_minutes = greatest(0, deficit_minutes - least(v_credit, deficit_minutes)),
      status = case
        when greatest(0, deficit_minutes - least(v_credit, deficit_minutes)) = 0 and v_credit > 0 then 'justified'
        when greatest(0, deficit_minutes - least(v_credit, deficit_minutes)) = 0 then 'met'
        else 'deficit'
      end,
      closure_status = 'ready',
      updated_at = now()
  where id = v_week.id;

  return jsonb_build_object(
    'justification', to_jsonb(v_row),
    'remaining_deficit_minutes', greatest(0, v_week.deficit_minutes - least(v_credit, v_week.deficit_minutes))
  );
end;
$$;

create or replace function public.finalize_hr_week_closure(
  p_week_start date,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_closure public.rh_week_closures;
  v_count integer;
  v_deficits integer;
begin
  if not private.is_director_user(p_actor_id) then
    raise exception using errcode = '42501', message = 'Apenas a Diretoria pode confirmar o fechamento.';
  end if;
  if p_week_start is null or extract(isodow from p_week_start) <> 1 then
    raise exception using errcode = '22023', message = 'Semana inválida.';
  end if;

  select * into v_closure
  from public.rh_week_closures
  where week_start = p_week_start
  for update;
  if not found or v_closure.status not in ('open', 'reopened') then
    raise exception using errcode = 'P0002', message = 'A semana não está disponível para fechamento.';
  end if;
  if v_closure.week_end > (now() at time zone 'America/Sao_Paulo')::date then
    raise exception using errcode = '22023', message = 'A semana ainda não terminou.';
  end if;
  if exists (
    select 1 from public.rh_weekly_records
    where closure_id = v_closure.id and employee_id = p_actor_id
  ) then
    raise exception using errcode = '42501', message = 'Outro diretor deve fechar a sua própria semana.';
  end if;
  if exists (
    select 1 from public.rh_weekly_records
    where closure_id = v_closure.id and closure_status = 'justification_pending'
  ) then
    raise exception using errcode = 'P0001', message = 'Ainda existem justificativas enviadas aguardando análise.';
  end if;

  select count(*)::integer,
         count(*) filter (where remaining_deficit_minutes > 0)::integer
  into v_count, v_deficits
  from public.rh_weekly_records
  where closure_id = v_closure.id;
  if v_count = 0 then
    raise exception using errcode = 'P0001', message = 'Nenhum colaborador foi apurado nesta semana.';
  end if;

  update public.rh_weekly_records
  set closure_status = 'closed',
      closed_by = p_actor_id,
      closed_at = now(),
      updated_at = now()
  where closure_id = v_closure.id;

  update public.rh_week_closures
  set status = 'closed',
      closed_by = p_actor_id,
      closed_at = now(),
      updated_at = now()
  where id = v_closure.id
  returning * into v_closure;

  return jsonb_build_object(
    'closure', to_jsonb(v_closure),
    'records', v_count,
    'deficits', v_deficits
  );
end;
$$;

create or replace function public.reopen_hr_week_closure(
  p_week_start date,
  p_reason text,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_closure public.rh_week_closures;
  v_event public.rh_week_reopen_events;
begin
  if not private.is_director_user(p_actor_id) then
    raise exception using errcode = '42501', message = 'Apenas a Diretoria pode reabrir semanas.';
  end if;
  if char_length(btrim(coalesce(p_reason, ''))) not between 10 and 2000 then
    raise exception using errcode = '22023', message = 'Informe o motivo da reabertura entre 10 e 2000 caracteres.';
  end if;

  select * into v_closure
  from public.rh_week_closures
  where week_start = p_week_start
  for update;
  if not found or v_closure.status <> 'closed' then
    raise exception using errcode = 'P0002', message = 'A semana não está fechada.';
  end if;
  if exists (
    select 1
    from public.rh_warnings warning
    join public.rh_weekly_records record on record.id = warning.weekly_record_id
    where record.closure_id = v_closure.id and warning.status = 'active'
  ) then
    raise exception using errcode = 'P0001', message = 'Anule primeiro as advertências ativas vinculadas a esta semana.';
  end if;

  insert into public.rh_week_reopen_events (closure_id, reason, reopened_by)
  values (v_closure.id, btrim(p_reason), p_actor_id)
  returning * into v_event;

  update public.rh_week_closures
  set status = 'reopened', updated_at = now()
  where id = v_closure.id
  returning * into v_closure;

  update public.rh_weekly_records record
  set closure_status = case
        when exists (
          select 1 from public.rh_hour_justifications justification
          where justification.weekly_record_id = record.id and justification.status = 'pending'
        ) then 'justification_pending'
        when record.remaining_deficit_minutes > 0
             and not exists (
               select 1 from public.rh_hour_justifications justification
               where justification.weekly_record_id = record.id and justification.status in ('approved', 'rejected')
             ) then 'awaiting_justification'
        else 'ready'
      end,
      updated_at = now()
  where record.closure_id = v_closure.id;

  return jsonb_build_object('closure', to_jsonb(v_closure), 'event', to_jsonb(v_event));
end;
$$;

-- ---------------------------------------------------------------------------
-- Importação em lote e advertências explícitas
-- ---------------------------------------------------------------------------

create or replace function public.import_hr_hour_snapshots(
  p_reading_date date,
  p_rows jsonb,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_reference_month date := date_trunc('month', p_reading_date)::date;
  v_item jsonb;
  v_passport text;
  v_total integer;
  v_employee public.profiles;
  v_previous integer;
  v_next integer;
  v_seen text[] := array[]::text[];
  v_count integer := 0;
begin
  if not private.is_director_user(p_actor_id) then
    raise exception using errcode = '42501', message = 'Apenas a Diretoria pode importar horas.';
  end if;
  if p_reading_date is null or p_reading_date > (now() at time zone 'America/Sao_Paulo')::date then
    raise exception using errcode = '22023', message = 'Data da leitura inválida.';
  end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 or jsonb_array_length(p_rows) > 250 then
    raise exception using errcode = '22023', message = 'Nenhuma leitura válida foi informada.';
  end if;

  for v_item in select value from jsonb_array_elements(p_rows)
  loop
    v_passport := btrim(v_item ->> 'passport');
    begin
      v_total := (v_item ->> 'total_minutes')::integer;
    exception when others then
      raise exception using errcode = '22023', message = 'Uma das horas importadas é inválida.';
    end;
    if v_passport is null or v_passport !~ '^[0-9]+$' or v_total not between 0 and 60000 or v_passport = any(v_seen) then
      raise exception using errcode = '22023', message = 'A importação contém passaporte inválido ou repetido.';
    end if;
    v_seen := array_append(v_seen, v_passport);

    select * into v_employee
    from public.profiles
    where passport = v_passport and role_code <> 'diretor_geral' and status <> 'inactive';
    if not found then
      raise exception using errcode = '22023', message = format('Passaporte %s não está disponível para importação.', v_passport);
    end if;

    select total_minutes into v_previous
    from public.rh_hour_snapshots
    where employee_id = v_employee.user_id
      and reference_month = v_reference_month
      and reading_date < p_reading_date
    order by reading_date desc limit 1;
    select total_minutes into v_next
    from public.rh_hour_snapshots
    where employee_id = v_employee.user_id
      and reference_month = v_reference_month
      and reading_date > p_reading_date
    order by reading_date asc limit 1;

    if v_previous is not null and v_total < v_previous then
      raise exception using errcode = '22023', message = format('O acumulado do passaporte %s é menor que a leitura anterior deste mês.', v_passport);
    end if;
    if v_next is not null and v_total > v_next then
      raise exception using errcode = '22023', message = format('O acumulado do passaporte %s ultrapassa uma leitura posterior.', v_passport);
    end if;

    insert into public.rh_hour_snapshots (
      employee_id, reference_month, reading_date, total_minutes, note, created_by, updated_by
    ) values (
      v_employee.user_id, v_reference_month, p_reading_date, v_total,
      'Importação em lote da Diretoria.', p_actor_id, p_actor_id
    )
    on conflict (employee_id, reference_month, reading_date) do update
    set total_minutes = excluded.total_minutes,
        note = excluded.note,
        updated_by = p_actor_id,
        updated_at = now();
    v_count := v_count + 1;
  end loop;

  return jsonb_build_object('saved', v_count, 'reading_date', p_reading_date, 'reference_month', v_reference_month);
end;
$$;

create or replace function public.issue_hr_warning(
  p_employee_id uuid,
  p_weekly_record_id bigint,
  p_cycle_month date,
  p_category text,
  p_reason text,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles;
  v_week public.rh_weekly_records;
  v_cycle date;
  v_origin text;
  v_count integer;
  v_warning public.rh_warnings;
  v_suspended boolean := false;
begin
  if not private.is_director_user(p_actor_id) then
    raise exception using errcode = '42501', message = 'Apenas a Diretoria pode aplicar advertências.';
  end if;
  if p_employee_id = p_actor_id then
    raise exception using errcode = '42501', message = 'Um diretor não pode aplicar advertência a si próprio.';
  end if;
  if p_category not in ('weekly_goal', 'attendance', 'conduct', 'internal_rules', 'other') then
    raise exception using errcode = '22023', message = 'Categoria de advertência inválida.';
  end if;
  if char_length(btrim(coalesce(p_reason, ''))) not between 10 and 1000 then
    raise exception using errcode = '22023', message = 'Informe a ocorrência entre 10 e 1000 caracteres.';
  end if;

  select * into v_profile from public.profiles where user_id = p_employee_id for update;
  if not found or v_profile.role_code = 'diretor_geral' or v_profile.status = 'inactive' then
    raise exception using errcode = '22023', message = 'Colaborador indisponível para advertência.';
  end if;

  if p_weekly_record_id is not null then
    select * into v_week
    from public.rh_weekly_records
    where id = p_weekly_record_id
    for update;
    if not found or v_week.employee_id <> p_employee_id or v_week.closure_status <> 'closed'
       or v_week.remaining_deficit_minutes <= 0 then
      raise exception using errcode = '22023', message = 'O fechamento não possui déficit elegível para advertência.';
    end if;
    if exists (select 1 from public.rh_warnings where weekly_record_id = v_week.id) then
      raise exception using errcode = '23505', message = 'Já existe advertência vinculada a esta semana.';
    end if;
    v_cycle := v_week.cycle_month;
    v_origin := 'weekly_closure';
  else
    if p_cycle_month is null or p_cycle_month <> date_trunc('month', p_cycle_month)::date then
      raise exception using errcode = '22023', message = 'Competência mensal inválida.';
    end if;
    v_cycle := p_cycle_month;
    v_origin := 'manual';
  end if;

  select count(*)::integer into v_count
  from public.rh_warnings
  where employee_id = p_employee_id and cycle_month = v_cycle and status = 'active';
  if v_count >= 3 then
    raise exception using errcode = 'P0001', message = 'O colaborador já possui três advertências ativas neste ciclo.';
  end if;
  v_count := v_count + 1;

  insert into public.rh_warnings (
    employee_id, weekly_record_id, cycle_month, sequence_in_cycle,
    reason, issued_by, origin, category
  ) values (
    p_employee_id, p_weekly_record_id, v_cycle, v_count,
    btrim(p_reason), p_actor_id, v_origin, p_category
  ) returning * into v_warning;

  if p_weekly_record_id is not null then
    update public.rh_weekly_records
    set status = 'warning_issued', updated_at = now()
    where id = p_weekly_record_id;
  end if;

  if v_count = 3 then
    update public.profiles
    set status = 'suspended', updated_by = p_actor_id, updated_at = now()
    where user_id = p_employee_id;

    insert into public.rh_disciplinary_reviews (
      employee_id, cycle_month, triggered_by_warning_id, triggered_by
    ) values (
      p_employee_id, v_cycle, v_warning.id, p_actor_id
    );
    v_suspended := true;
  end if;

  return jsonb_build_object(
    'warning', to_jsonb(v_warning),
    'active_warnings', v_count,
    'suspended', v_suspended
  );
end;
$$;

create or replace function public.annul_hr_warning(
  p_warning_id bigint,
  p_reason text,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_warning public.rh_warnings;
  v_remaining integer;
  v_reactivated boolean := false;
begin
  if not private.is_director_user(p_actor_id) then
    raise exception using errcode = '42501', message = 'Apenas a Diretoria pode anular advertências.';
  end if;
  if char_length(btrim(coalesce(p_reason, ''))) not between 10 and 2000 then
    raise exception using errcode = '22023', message = 'Informe o motivo da anulação entre 10 e 2000 caracteres.';
  end if;

  select * into v_warning from public.rh_warnings where id = p_warning_id for update;
  if not found or v_warning.status <> 'active' then
    raise exception using errcode = 'P0002', message = 'Advertência não encontrada ou já anulada.';
  end if;
  if v_warning.employee_id = p_actor_id then
    raise exception using errcode = '42501', message = 'Um diretor não pode anular a própria advertência.';
  end if;

  perform 1 from public.profiles where user_id = v_warning.employee_id for update;
  update public.rh_warnings
  set status = 'annulled', annulled_by = p_actor_id, annulled_at = now(),
      annulment_reason = btrim(p_reason), updated_at = now()
  where id = p_warning_id
  returning * into v_warning;

  if v_warning.weekly_record_id is not null then
    update public.rh_weekly_records
    set status = 'warning_annulled', updated_at = now()
    where id = v_warning.weekly_record_id;
  end if;

  select count(*)::integer into v_remaining
  from public.rh_warnings
  where employee_id = v_warning.employee_id
    and cycle_month = v_warning.cycle_month
    and status = 'active';

  if v_remaining < 3 and exists (
    select 1 from public.rh_disciplinary_reviews
    where employee_id = v_warning.employee_id
      and cycle_month = v_warning.cycle_month
      and status in ('pending', 'suspension_maintained')
  ) then
    update public.rh_disciplinary_reviews
    set status = 'reactivated', decided_by = p_actor_id, decided_at = now(),
        decision_note = btrim(p_reason), updated_at = now()
    where employee_id = v_warning.employee_id
      and cycle_month = v_warning.cycle_month
      and status in ('pending', 'suspension_maintained');

    update public.profiles
    set status = 'active', updated_by = p_actor_id, updated_at = now()
    where user_id = v_warning.employee_id and status = 'suspended';
    v_reactivated := true;
  end if;

  return jsonb_build_object(
    'warning', to_jsonb(v_warning),
    'active_warnings', v_remaining,
    'reactivated', v_reactivated
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Auditoria, notificações, RLS e privilégios
-- ---------------------------------------------------------------------------

create or replace function private.audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid;
  actor_code text;
  row_id text;
  row_values jsonb;
begin
  actor_id := auth.uid();
  row_values := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  if actor_id is null then
    actor_id := coalesce(
      nullif(row_values ->> 'updated_by', '')::uuid,
      nullif(row_values ->> 'reviewed_by', '')::uuid,
      nullif(row_values ->> 'cancelled_by', '')::uuid,
      nullif(row_values ->> 'annulled_by', '')::uuid,
      nullif(row_values ->> 'decided_by', '')::uuid,
      nullif(row_values ->> 'closed_by', '')::uuid,
      nullif(row_values ->> 'issued_by', '')::uuid,
      nullif(row_values ->> 'triggered_by', '')::uuid,
      nullif(row_values ->> 'approved_by', '')::uuid,
      nullif(row_values ->> 'started_by', '')::uuid,
      nullif(row_values ->> 'reopened_by', '')::uuid,
      nullif(row_values ->> 'created_by', '')::uuid,
      nullif(row_values ->> 'performed_by', '')::uuid,
      nullif(row_values ->> 'password_reset_by', '')::uuid,
      nullif(row_values ->> 'employee_id', '')::uuid
    );
  end if;
  select passport into actor_code from public.profiles where user_id = actor_id;
  row_id := coalesce(row_values ->> 'id', row_values ->> 'key', row_values ->> 'user_id');
  insert into public.audit_logs (
    actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values
  ) values (
    actor_id, actor_code, tg_op, tg_table_name, row_id,
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) else null end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) else null end
  );
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger rh_leave_week_adjustments_touch_updated_at
before update on public.rh_leave_week_adjustments
for each row execute function private.touch_updated_at();
create trigger rh_week_closures_touch_updated_at
before update on public.rh_week_closures
for each row execute function private.touch_updated_at();
create trigger rh_hour_justifications_touch_updated_at
before update on public.rh_hour_justifications
for each row execute function private.touch_updated_at();

create trigger rh_leave_week_adjustments_audit
after insert or update on public.rh_leave_week_adjustments
for each row execute function private.audit_row_change();
create trigger rh_week_closures_audit
after insert or update on public.rh_week_closures
for each row execute function private.audit_row_change();
create trigger rh_week_reopen_events_audit
after insert on public.rh_week_reopen_events
for each row execute function private.audit_row_change();
create trigger rh_hour_justifications_audit
after insert or update on public.rh_hour_justifications
for each row execute function private.audit_row_change();

create or replace function private.notify_absence_workflow()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' and new.status = 'pending' then
    insert into public.notifications (
      kind, audience, priority, title, body, action_url, created_by
    ) values (
      'system', 'directors', 'important', 'Novo afastamento solicitado',
      'Um afastamento preventivo aguarda análise e definição das horas abatidas.',
      '/rh?aba=absences', new.employee_id
    );
  elsif tg_op = 'UPDATE' and old.status = 'pending' and new.status in ('approved', 'rejected') then
    insert into public.notifications (
      kind, recipient_id, priority, title, body, action_url, created_by
    ) values (
      'personal', new.employee_id,
      case when new.status = 'approved' then 'normal' else 'important' end,
      case when new.status = 'approved' then 'Afastamento aprovado' else 'Afastamento recusado' end,
      case when new.status = 'approved'
        then 'Seu afastamento foi aprovado e as horas autorizadas já foram abatidas das metas atingidas.'
        else 'Seu afastamento foi recusado. Consulte o Meu RH para ver a decisão registrada.' end,
      '/meu-rh', new.reviewed_by
    );
  end if;
  return new;
end;
$$;

create or replace function private.notify_hr_week_deficit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.closure_status = 'awaiting_justification'
     and (tg_op = 'INSERT' or old.closure_status is distinct from new.closure_status) then
    insert into public.notifications (
      kind, recipient_id, priority, title, body, action_url, created_by
    ) values (
      'personal', new.employee_id, 'important', 'Justifique as horas da semana',
      format('A apuração de %s a %s identificou déficit de %sh%s. Envie sua justificativa pelo Meu RH.',
        to_char(new.week_start, 'DD/MM'), to_char(new.week_end, 'DD/MM'),
        new.remaining_deficit_minutes / 60, lpad((new.remaining_deficit_minutes % 60)::text, 2, '0')),
      '/meu-rh', new.closed_by
    );
  end if;
  return new;
end;
$$;

create or replace function private.notify_hr_hour_justification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' and new.status = 'pending' then
    insert into public.notifications (
      kind, audience, priority, title, body, action_url, created_by
    ) values (
      'system', 'directors', 'important', 'Justificativa de horas recebida',
      'Um colaborador respondeu a uma pendência semanal e aguarda análise da Diretoria.',
      '/rh?aba=absences', new.employee_id
    );
  elsif tg_op = 'UPDATE' and old.status = 'pending' and new.status in ('approved', 'rejected') then
    insert into public.notifications (
      kind, recipient_id, priority, title, body, action_url, created_by
    ) values (
      'personal', new.employee_id,
      case when new.status = 'approved' then 'normal' else 'important' end,
      case when new.status = 'approved' then 'Justificativa de horas analisada' else 'Justificativa de horas recusada' end,
      case when new.status = 'approved'
        then format('A Diretoria abonou %sh%s do déficit informado. O resultado da semana foi recalculado.',
          new.credited_minutes / 60, lpad((new.credited_minutes % 60)::text, 2, '0'))
        else 'A justificativa foi recusada e o déficit da semana foi mantido.' end,
      '/meu-rh', new.reviewed_by
    );
  end if;
  return new;
end;
$$;

drop trigger if exists notifications_weekly_deficit on public.rh_weekly_records;
create trigger notifications_weekly_deficit
after insert or update on public.rh_weekly_records
for each row execute function private.notify_hr_week_deficit();
create trigger notifications_hour_justification
after insert or update on public.rh_hour_justifications
for each row execute function private.notify_hr_hour_justification();

alter table public.rh_leave_week_adjustments enable row level security;
alter table public.rh_leave_week_adjustments force row level security;
alter table public.rh_week_closures enable row level security;
alter table public.rh_week_closures force row level security;
alter table public.rh_week_reopen_events enable row level security;
alter table public.rh_week_reopen_events force row level security;
alter table public.rh_hour_justifications enable row level security;
alter table public.rh_hour_justifications force row level security;

create policy rh_leave_week_adjustments_read_own_or_director
on public.rh_leave_week_adjustments for select to authenticated
using (
  (employee_id = (select auth.uid()) and (select private.is_active_user()))
  or (select private.is_director())
);
create policy rh_week_closures_read_director
on public.rh_week_closures for select to authenticated
using ((select private.is_director()));
create policy rh_week_reopen_events_read_director
on public.rh_week_reopen_events for select to authenticated
using ((select private.is_director()));
create policy rh_hour_justifications_read_own_or_director
on public.rh_hour_justifications for select to authenticated
using (
  (employee_id = (select auth.uid()) and (select private.is_active_user()))
  or (select private.is_director())
);

revoke all on public.rh_leave_week_adjustments from public, anon, authenticated, service_role;
revoke all on public.rh_week_closures from public, anon, authenticated, service_role;
revoke all on public.rh_week_reopen_events from public, anon, authenticated, service_role;
revoke all on public.rh_hour_justifications from public, anon, authenticated, service_role;
grant select on public.rh_leave_week_adjustments to authenticated, service_role;
grant select on public.rh_week_closures to authenticated, service_role;
grant select on public.rh_week_reopen_events to authenticated, service_role;
grant select on public.rh_hour_justifications to authenticated, service_role;
grant insert, update on public.rh_leave_week_adjustments to service_role;
grant insert, update on public.rh_week_closures to service_role;
grant insert on public.rh_week_reopen_events to service_role;
grant insert, update on public.rh_hour_justifications to service_role;
grant usage, select on sequence public.rh_leave_week_adjustments_id_seq to service_role;
grant usage, select on sequence public.rh_week_closures_id_seq to service_role;
grant usage, select on sequence public.rh_week_reopen_events_id_seq to service_role;
grant usage, select on sequence public.rh_hour_justifications_id_seq to service_role;

revoke all on function public.create_hr_leave_request(date, date, text, text, uuid) from public, anon, authenticated, service_role;
revoke all on function public.cancel_hr_leave_request(bigint, uuid) from public, anon, authenticated, service_role;
revoke all on function public.review_hr_leave_request(bigint, text, jsonb, text, uuid) from public, anon, authenticated, service_role;
revoke all on function public.submit_hr_hour_justification(bigint, text, uuid) from public, anon, authenticated, service_role;
revoke all on function public.review_hr_hour_justification(bigint, text, integer, text, uuid) from public, anon, authenticated, service_role;
revoke all on function public.finalize_hr_week_closure(date, uuid) from public, anon, authenticated, service_role;
revoke all on function public.reopen_hr_week_closure(date, text, uuid) from public, anon, authenticated, service_role;
revoke all on function public.import_hr_hour_snapshots(date, jsonb, uuid) from public, anon, authenticated, service_role;
revoke all on function public.issue_hr_warning(uuid, bigint, date, text, text, uuid) from public, anon, authenticated, service_role;
revoke all on function private.notify_hr_week_deficit() from public, anon, authenticated, service_role;
revoke all on function private.notify_hr_hour_justification() from public, anon, authenticated, service_role;

grant execute on function public.create_hr_leave_request(date, date, text, text, uuid) to service_role;
grant execute on function public.cancel_hr_leave_request(bigint, uuid) to service_role;
grant execute on function public.review_hr_leave_request(bigint, text, jsonb, text, uuid) to service_role;
grant execute on function public.submit_hr_hour_justification(bigint, text, uuid) to service_role;
grant execute on function public.review_hr_hour_justification(bigint, text, integer, text, uuid) to service_role;
grant execute on function public.finalize_hr_week_closure(date, uuid) to service_role;
grant execute on function public.reopen_hr_week_closure(date, text, uuid) to service_role;
grant execute on function public.import_hr_hour_snapshots(date, jsonb, uuid) to service_role;
grant execute on function public.issue_hr_warning(uuid, bigint, date, text, text, uuid) to service_role;

comment on table public.rh_absence_requests is
  'Afastamentos preventivos solicitados antes da ausência e analisados pela Diretoria.';
comment on table public.rh_leave_week_adjustments is
  'Horas abatidas da meta em cada semana afetada por um afastamento aprovado.';
comment on table public.rh_hour_justifications is
  'Justificativas reativas enviadas após a apuração de um déficit semanal.';
comment on table public.rh_week_closures is
  'Controle humano do fechamento coletivo de cada semana de segunda a domingo.';
comment on table public.rh_week_reopen_events is
  'Histórico imutável das reaberturas de semanas e suas fundamentações.';
comment on table public.rh_weekly_records is
  'Apurações semanais com meta original, abatimentos, justificativas e déficit restante.';
comment on table public.rh_warnings is
  'Advertências manuais ou decorrentes de déficit, contabilizadas no ciclo mensal.';

notify pgrst, 'reload schema';
