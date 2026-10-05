-- HPSM — módulo de Recursos Humanos.
-- Semanas de segunda a domingo, meta padrão de 600 minutos e ciclo disciplinar mensal.

create table public.rh_hour_snapshots (
  id bigint generated always as identity primary key,
  employee_id uuid not null references public.profiles(user_id) on delete restrict,
  reference_month date not null,
  reading_date date not null,
  total_minutes integer not null,
  note text,
  created_by uuid not null references public.profiles(user_id) on delete restrict,
  updated_by uuid not null references public.profiles(user_id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint rh_hour_snapshots_reference_month_check
    check (reference_month = date_trunc('month', reference_month)::date),
  constraint rh_hour_snapshots_reading_month_check
    check (reading_date >= reference_month and reading_date < (reference_month + interval '1 month')::date),
  constraint rh_hour_snapshots_total_check check (total_minutes between 0 and 60000),
  constraint rh_hour_snapshots_note_check check (note is null or char_length(note) <= 500),
  constraint rh_hour_snapshots_employee_day_unique unique (employee_id, reference_month, reading_date)
);

create index rh_hour_snapshots_employee_date_idx
  on public.rh_hour_snapshots (employee_id, reading_date desc);
create index rh_hour_snapshots_created_by_idx
  on public.rh_hour_snapshots (created_by);
create index rh_hour_snapshots_updated_by_idx
  on public.rh_hour_snapshots (updated_by);

create table public.rh_absence_requests (
  id bigint generated always as identity primary key,
  employee_id uuid not null references public.profiles(user_id) on delete restrict,
  start_date date not null,
  end_date date not null,
  reason text not null,
  status text not null default 'pending',
  approval_effect text,
  review_note text,
  reviewed_by uuid references public.profiles(user_id) on delete restrict,
  reviewed_at timestamptz,
  cancelled_by uuid references public.profiles(user_id) on delete restrict,
  cancelled_at timestamptz,
  requested_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint rh_absence_requests_period_check
    check (end_date >= start_date and end_date <= start_date + 89),
  constraint rh_absence_requests_reason_check
    check (char_length(btrim(reason)) between 10 and 2000),
  constraint rh_absence_requests_status_check
    check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  constraint rh_absence_requests_effect_check
    check (approval_effect is null or approval_effect in ('record_only', 'weekly_exemption')),
  constraint rh_absence_requests_review_note_check
    check (review_note is null or char_length(btrim(review_note)) between 2 and 2000),
  constraint rh_absence_requests_state_check check (
    (status = 'pending' and approval_effect is null and reviewed_by is null and reviewed_at is null and cancelled_by is null and cancelled_at is null)
    or
    (status = 'approved' and approval_effect is not null and reviewed_by is not null and reviewed_at is not null and cancelled_by is null and cancelled_at is null)
    or
    (status = 'rejected' and approval_effect is null and reviewed_by is not null and reviewed_at is not null and review_note is not null and cancelled_by is null and cancelled_at is null)
    or
    (status = 'cancelled' and approval_effect is null and reviewed_by is null and reviewed_at is null and cancelled_by = employee_id and cancelled_at is not null)
  )
);

create index rh_absence_requests_employee_period_idx
  on public.rh_absence_requests (employee_id, start_date desc, end_date desc);
create index rh_absence_requests_pending_idx
  on public.rh_absence_requests (requested_at)
  where status = 'pending';
create index rh_absence_requests_reviewed_by_idx
  on public.rh_absence_requests (reviewed_by)
  where reviewed_by is not null;

create table public.rh_weekly_records (
  id bigint generated always as identity primary key,
  employee_id uuid not null references public.profiles(user_id) on delete restrict,
  week_start date not null,
  week_end date not null,
  cycle_month date not null,
  required_minutes integer not null default 600,
  worked_minutes integer not null,
  status text not null,
  absence_request_id bigint references public.rh_absence_requests(id) on delete restrict,
  calculation_details jsonb not null default '{}'::jsonb,
  closure_note text,
  closed_by uuid not null references public.profiles(user_id) on delete restrict,
  closed_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint rh_weekly_records_week_check check (
    extract(isodow from week_start) = 1
    and week_end = week_start + 6
  ),
  constraint rh_weekly_records_cycle_check check (
    cycle_month = date_trunc('month', week_end)::date
  ),
  constraint rh_weekly_records_required_check check (required_minutes between 1 and 60000),
  constraint rh_weekly_records_worked_check check (worked_minutes between 0 and 60000),
  constraint rh_weekly_records_status_check
    check (status in ('met', 'justified', 'warning_issued', 'warning_annulled')),
  constraint rh_weekly_records_note_check
    check (closure_note is null or char_length(closure_note) <= 1000),
  constraint rh_weekly_records_absence_state_check check (
    (status = 'justified' and absence_request_id is not null)
    or (status <> 'justified')
  ),
  constraint rh_weekly_records_employee_week_unique unique (employee_id, week_start)
);

create index rh_weekly_records_employee_cycle_idx
  on public.rh_weekly_records (employee_id, cycle_month, week_start desc);
create index rh_weekly_records_status_cycle_idx
  on public.rh_weekly_records (status, cycle_month);
create index rh_weekly_records_absence_request_idx
  on public.rh_weekly_records (absence_request_id)
  where absence_request_id is not null;
create index rh_weekly_records_closed_by_idx
  on public.rh_weekly_records (closed_by);

create table public.rh_warnings (
  id bigint generated always as identity primary key,
  employee_id uuid not null references public.profiles(user_id) on delete restrict,
  weekly_record_id bigint not null unique references public.rh_weekly_records(id) on delete restrict,
  cycle_month date not null,
  sequence_in_cycle smallint not null,
  reason text not null,
  status text not null default 'active',
  issued_by uuid not null references public.profiles(user_id) on delete restrict,
  issued_at timestamptz not null default now(),
  annulled_by uuid references public.profiles(user_id) on delete restrict,
  annulled_at timestamptz,
  annulment_reason text,
  updated_at timestamptz not null default now(),
  constraint rh_warnings_cycle_check
    check (cycle_month = date_trunc('month', cycle_month)::date),
  constraint rh_warnings_sequence_check check (sequence_in_cycle between 1 and 3),
  constraint rh_warnings_reason_check check (char_length(btrim(reason)) between 10 and 1000),
  constraint rh_warnings_status_check check (status in ('active', 'annulled')),
  constraint rh_warnings_annulment_reason_check
    check (annulment_reason is null or char_length(btrim(annulment_reason)) between 10 and 2000),
  constraint rh_warnings_state_check check (
    (status = 'active' and annulled_by is null and annulled_at is null and annulment_reason is null)
    or
    (status = 'annulled' and annulled_by is not null and annulled_at is not null and annulment_reason is not null)
  )
);

create index rh_warnings_employee_cycle_idx
  on public.rh_warnings (employee_id, cycle_month, issued_at desc);
create index rh_warnings_active_cycle_idx
  on public.rh_warnings (cycle_month, employee_id)
  where status = 'active';
create index rh_warnings_issued_by_idx
  on public.rh_warnings (issued_by);
create index rh_warnings_annulled_by_idx
  on public.rh_warnings (annulled_by)
  where annulled_by is not null;

create table public.rh_disciplinary_reviews (
  id bigint generated always as identity primary key,
  employee_id uuid not null references public.profiles(user_id) on delete restrict,
  cycle_month date not null,
  triggered_by_warning_id bigint not null unique references public.rh_warnings(id) on delete restrict,
  status text not null default 'pending',
  triggered_by uuid not null references public.profiles(user_id) on delete restrict,
  triggered_at timestamptz not null default now(),
  decided_by uuid references public.profiles(user_id) on delete restrict,
  decided_at timestamptz,
  decision_note text,
  updated_at timestamptz not null default now(),
  constraint rh_disciplinary_reviews_cycle_check
    check (cycle_month = date_trunc('month', cycle_month)::date),
  constraint rh_disciplinary_reviews_status_check
    check (status in ('pending', 'suspension_maintained', 'dismissed', 'reactivated')),
  constraint rh_disciplinary_reviews_note_check
    check (decision_note is null or char_length(btrim(decision_note)) between 10 and 2000),
  constraint rh_disciplinary_reviews_state_check check (
    (status = 'pending' and decided_by is null and decided_at is null and decision_note is null)
    or
    (status <> 'pending' and decided_by is not null and decided_at is not null and decision_note is not null)
  )
);

create index rh_disciplinary_reviews_employee_cycle_idx
  on public.rh_disciplinary_reviews (employee_id, cycle_month, triggered_at desc);
create index rh_disciplinary_reviews_pending_idx
  on public.rh_disciplinary_reviews (triggered_at)
  where status = 'pending';
create index rh_disciplinary_reviews_triggered_by_idx
  on public.rh_disciplinary_reviews (triggered_by);
create index rh_disciplinary_reviews_decided_by_idx
  on public.rh_disciplinary_reviews (decided_by)
  where decided_by is not null;

create or replace function private.is_director_user(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_user_id is not null and exists (
    select 1
    from public.profiles
    where user_id = p_user_id
      and status = 'active'
      and role_code in ('diretor_geral', 'diretoria')
  );
$$;

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
      nullif(row_values ->> 'created_by', '')::uuid,
      nullif(row_values ->> 'performed_by', '')::uuid,
      nullif(row_values ->> 'password_reset_by', '')::uuid,
      nullif(row_values ->> 'employee_id', '')::uuid
    );
  end if;

  select passport into actor_code
  from public.profiles
  where user_id = actor_id;

  row_id := coalesce(
    row_values ->> 'id',
    row_values ->> 'key',
    row_values ->> 'user_id'
  );

  insert into public.audit_logs (
    actor_user_id,
    actor_passport,
    action,
    entity_name,
    entity_id,
    old_values,
    new_values
  ) values (
    actor_id,
    actor_code,
    tg_op,
    tg_table_name,
    row_id,
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) else null end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) else null end
  );

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create function public.record_hr_hour_snapshot(
  p_employee_id uuid,
  p_reference_month date,
  p_reading_date date,
  p_total_minutes integer,
  p_note text,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.rh_hour_snapshots;
  v_previous integer;
  v_next integer;
begin
  if not private.is_director_user(p_actor_id) then
    raise exception using errcode = '42501', message = 'Apenas a Diretoria pode lançar horas.';
  end if;

  if not exists (
    select 1 from public.profiles
    where user_id = p_employee_id and role_code <> 'diretor_geral'
  ) then
    raise exception using errcode = '22023', message = 'Colaborador inválido para o controle de horas.';
  end if;

  if p_reference_month is null
     or p_reading_date is null
     or p_total_minutes is null
     or p_reference_month <> date_trunc('month', p_reference_month)::date
     or p_reading_date < p_reference_month
     or p_reading_date >= (p_reference_month + interval '1 month')::date
     or p_total_minutes not between 0 and 60000 then
    raise exception using errcode = '22023', message = 'Competência, data ou total de horas inválido.';
  end if;

  if p_note is not null and char_length(p_note) > 500 then
    raise exception using errcode = '22023', message = 'A observação deve ter até 500 caracteres.';
  end if;

  select total_minutes into v_previous
  from public.rh_hour_snapshots
  where employee_id = p_employee_id
    and reference_month = p_reference_month
    and reading_date < p_reading_date
  order by reading_date desc
  limit 1;

  select total_minutes into v_next
  from public.rh_hour_snapshots
  where employee_id = p_employee_id
    and reference_month = p_reference_month
    and reading_date > p_reading_date
  order by reading_date asc
  limit 1;

  if v_previous is not null and p_total_minutes < v_previous then
    raise exception using errcode = '22023', message = 'O acumulado não pode ser menor que a leitura anterior do mês.';
  end if;
  if v_next is not null and p_total_minutes > v_next then
    raise exception using errcode = '22023', message = 'O acumulado não pode ultrapassar uma leitura posterior já registrada.';
  end if;

  insert into public.rh_hour_snapshots (
    employee_id, reference_month, reading_date, total_minutes, note, created_by, updated_by
  ) values (
    p_employee_id, p_reference_month, p_reading_date, p_total_minutes, nullif(btrim(p_note), ''), p_actor_id, p_actor_id
  )
  on conflict (employee_id, reference_month, reading_date) do update
  set total_minutes = excluded.total_minutes,
      note = excluded.note,
      updated_by = p_actor_id,
      updated_at = now()
  returning * into v_row;

  return to_jsonb(v_row);
end;
$$;

create function public.review_hr_absence(
  p_request_id bigint,
  p_decision text,
  p_effect text,
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
begin
  if not private.is_director_user(p_actor_id) then
    raise exception using errcode = '42501', message = 'Apenas a Diretoria pode analisar justificativas.';
  end if;

  select * into v_request
  from public.rh_absence_requests
  where id = p_request_id
  for update;

  if not found or v_request.status <> 'pending' then
    raise exception using errcode = 'P0002', message = 'Justificativa não encontrada ou já analisada.';
  end if;
  if v_request.employee_id = p_actor_id then
    raise exception using errcode = '42501', message = 'Um diretor não pode analisar a própria justificativa.';
  end if;
  if p_decision not in ('approved', 'rejected') then
    raise exception using errcode = '22023', message = 'Decisão inválida.';
  end if;
  if p_decision = 'approved' and (p_effect is null or p_effect not in ('record_only', 'weekly_exemption')) then
    raise exception using errcode = '22023', message = 'Defina o efeito da justificativa aprovada.';
  end if;
  if p_decision = 'rejected' and char_length(btrim(coalesce(p_note, ''))) not between 10 and 2000 then
    raise exception using errcode = '22023', message = 'Informe o motivo da recusa entre 10 e 2000 caracteres.';
  end if;
  if p_decision = 'approved' and p_note is not null and char_length(btrim(p_note)) > 2000 then
    raise exception using errcode = '22023', message = 'A observação deve ter até 2000 caracteres.';
  end if;

  update public.rh_absence_requests
  set status = p_decision,
      approval_effect = case when p_decision = 'approved' then p_effect else null end,
      review_note = case when nullif(btrim(p_note), '') is not null then btrim(p_note) else null end,
      reviewed_by = p_actor_id,
      reviewed_at = now(),
      updated_at = now()
  where id = p_request_id
  returning * into v_request;

  return to_jsonb(v_request);
end;
$$;

create function public.close_hr_week(
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
  v_absence_id bigint;
  v_status text;
  v_week_id bigint;
  v_warning_id bigint;
  v_active_count integer;
  v_suspended boolean := false;
begin
  if not private.is_director_user(p_actor_id) then
    raise exception using errcode = '42501', message = 'Apenas a Diretoria pode fechar semanas.';
  end if;
  if p_employee_id = p_actor_id then
    raise exception using errcode = '42501', message = 'Um diretor não pode fechar a própria semana.';
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

  if not found or v_profile.role_code = 'diretor_geral' or v_profile.status <> 'active' then
    raise exception using errcode = '22023', message = 'Colaborador não está disponível para fechamento.';
  end if;

  if exists (
    select 1 from public.rh_weekly_records
    where employee_id = p_employee_id and week_start = p_week_start
  ) then
    raise exception using errcode = '23505', message = 'Esta semana já foi fechada para o colaborador.';
  end if;

  if p_worked_minutes >= 600 then
    v_status := 'met';
  else
    select id into v_absence_id
    from public.rh_absence_requests
    where employee_id = p_employee_id
      and status = 'approved'
      and approval_effect = 'weekly_exemption'
      and start_date <= v_week_end
      and end_date >= p_week_start
    order by reviewed_at desc
    limit 1;

    if v_absence_id is not null then
      v_status := 'justified';
    elsif exists (
      select 1 from public.rh_absence_requests
      where employee_id = p_employee_id
        and status = 'pending'
        and start_date <= v_week_end
        and end_date >= p_week_start
    ) then
      raise exception using errcode = 'P0001', message = 'Existe uma justificativa pendente para esta semana.';
    else
      v_status := 'warning_issued';
    end if;
  end if;

  insert into public.rh_weekly_records (
    employee_id, week_start, week_end, cycle_month, required_minutes, worked_minutes,
    status, absence_request_id, calculation_details, closure_note, closed_by
  ) values (
    p_employee_id, p_week_start, v_week_end, v_cycle_month, 600, p_worked_minutes,
    v_status, v_absence_id, coalesce(p_calculation_details, '{}'::jsonb),
    nullif(btrim(p_closure_note), ''), p_actor_id
  ) returning id into v_week_id;

  if v_status = 'warning_issued' then
    select count(*)::integer into v_active_count
    from public.rh_warnings
    where employee_id = p_employee_id
      and cycle_month = v_cycle_month
      and status = 'active';

    if v_active_count >= 3 then
      raise exception using errcode = 'P0001', message = 'O colaborador já possui três advertências ativas neste ciclo.';
    end if;

    v_active_count := v_active_count + 1;
    insert into public.rh_warnings (
      employee_id, weekly_record_id, cycle_month, sequence_in_cycle, reason, issued_by
    ) values (
      p_employee_id,
      v_week_id,
      v_cycle_month,
      v_active_count,
      format('Meta semanal de 10h não cumprida: %s registradas.',
        trim(to_char((p_worked_minutes / 60), 'FM999990')) || 'h' || lpad((p_worked_minutes % 60)::text, 2, '0')),
      p_actor_id
    ) returning id into v_warning_id;

    if v_active_count = 3 then
      update public.profiles
      set status = 'suspended', updated_by = p_actor_id, updated_at = now()
      where user_id = p_employee_id;

      insert into public.rh_disciplinary_reviews (
        employee_id, cycle_month, triggered_by_warning_id, triggered_by
      ) values (
        p_employee_id, v_cycle_month, v_warning_id, p_actor_id
      );
      v_suspended := true;
    end if;
  else
    select count(*)::integer into v_active_count
    from public.rh_warnings
    where employee_id = p_employee_id
      and cycle_month = v_cycle_month
      and status = 'active';
  end if;

  return jsonb_build_object(
    'weekly_record_id', v_week_id,
    'warning_id', v_warning_id,
    'status', v_status,
    'active_warnings', coalesce(v_active_count, 0),
    'suspended', v_suspended
  );
end;
$$;

create function public.annul_hr_warning(
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

  select * into v_warning
  from public.rh_warnings
  where id = p_warning_id
  for update;

  if not found or v_warning.status <> 'active' then
    raise exception using errcode = 'P0002', message = 'Advertência não encontrada ou já anulada.';
  end if;
  if v_warning.employee_id = p_actor_id then
    raise exception using errcode = '42501', message = 'Um diretor não pode anular a própria advertência.';
  end if;

  perform 1 from public.profiles where user_id = v_warning.employee_id for update;

  update public.rh_warnings
  set status = 'annulled',
      annulled_by = p_actor_id,
      annulled_at = now(),
      annulment_reason = btrim(p_reason),
      updated_at = now()
  where id = p_warning_id
  returning * into v_warning;

  update public.rh_weekly_records
  set status = 'warning_annulled', updated_at = now()
  where id = v_warning.weekly_record_id;

  select count(*)::integer into v_remaining
  from public.rh_warnings
  where employee_id = v_warning.employee_id
    and cycle_month = v_warning.cycle_month
    and status = 'active';

  if v_remaining < 3 and exists (
    select 1 from public.rh_disciplinary_reviews
    where triggered_by_warning_id = p_warning_id and status = 'pending'
  ) then
    update public.rh_disciplinary_reviews
    set status = 'reactivated',
        decided_by = p_actor_id,
        decided_at = now(),
        decision_note = btrim(p_reason),
        updated_at = now()
    where triggered_by_warning_id = p_warning_id and status = 'pending';

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

create function public.decide_hr_disciplinary_review(
  p_review_id bigint,
  p_decision text,
  p_note text,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_review public.rh_disciplinary_reviews;
  v_status text;
begin
  if not private.is_director_user(p_actor_id) then
    raise exception using errcode = '42501', message = 'Apenas a Diretoria pode concluir análises disciplinares.';
  end if;
  if p_decision not in ('maintain_suspension', 'dismiss') then
    raise exception using errcode = '22023', message = 'Decisão disciplinar inválida.';
  end if;
  if char_length(btrim(coalesce(p_note, ''))) not between 10 and 2000 then
    raise exception using errcode = '22023', message = 'Informe a fundamentação entre 10 e 2000 caracteres.';
  end if;

  select * into v_review
  from public.rh_disciplinary_reviews
  where id = p_review_id
  for update;

  if not found or v_review.status <> 'pending' then
    raise exception using errcode = 'P0002', message = 'Análise não encontrada ou já concluída.';
  end if;
  if v_review.employee_id = p_actor_id then
    raise exception using errcode = '42501', message = 'Um diretor não pode decidir a própria análise.';
  end if;

  perform 1 from public.profiles where user_id = v_review.employee_id for update;
  v_status := case when p_decision = 'dismiss' then 'dismissed' else 'suspension_maintained' end;

  update public.rh_disciplinary_reviews
  set status = v_status,
      decided_by = p_actor_id,
      decided_at = now(),
      decision_note = btrim(p_note),
      updated_at = now()
  where id = p_review_id
  returning * into v_review;

  update public.profiles
  set status = case when p_decision = 'dismiss' then 'inactive' else 'suspended' end,
      updated_by = p_actor_id,
      updated_at = now()
  where user_id = v_review.employee_id;

  return to_jsonb(v_review);
end;
$$;

create or replace function private.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger rh_hour_snapshots_touch_updated_at
before update on public.rh_hour_snapshots
for each row execute function private.touch_updated_at();
create trigger rh_absence_requests_touch_updated_at
before update on public.rh_absence_requests
for each row execute function private.touch_updated_at();
create trigger rh_weekly_records_touch_updated_at
before update on public.rh_weekly_records
for each row execute function private.touch_updated_at();
create trigger rh_warnings_touch_updated_at
before update on public.rh_warnings
for each row execute function private.touch_updated_at();
create trigger rh_disciplinary_reviews_touch_updated_at
before update on public.rh_disciplinary_reviews
for each row execute function private.touch_updated_at();

create trigger rh_hour_snapshots_audit
after insert or update on public.rh_hour_snapshots
for each row execute function private.audit_row_change();
create trigger rh_absence_requests_audit
after insert or update on public.rh_absence_requests
for each row execute function private.audit_row_change();
create trigger rh_weekly_records_audit
after insert or update on public.rh_weekly_records
for each row execute function private.audit_row_change();
create trigger rh_warnings_audit
after insert or update on public.rh_warnings
for each row execute function private.audit_row_change();
create trigger rh_disciplinary_reviews_audit
after insert or update on public.rh_disciplinary_reviews
for each row execute function private.audit_row_change();

alter table public.rh_hour_snapshots enable row level security;
alter table public.rh_hour_snapshots force row level security;
alter table public.rh_absence_requests enable row level security;
alter table public.rh_absence_requests force row level security;
alter table public.rh_weekly_records enable row level security;
alter table public.rh_weekly_records force row level security;
alter table public.rh_warnings enable row level security;
alter table public.rh_warnings force row level security;
alter table public.rh_disciplinary_reviews enable row level security;
alter table public.rh_disciplinary_reviews force row level security;

create policy rh_hour_snapshots_read_own_or_director
on public.rh_hour_snapshots for select to authenticated
using (
  (employee_id = (select auth.uid()) and (select private.is_active_user()))
  or (select private.is_director())
);
create policy rh_absence_requests_read_own_or_director
on public.rh_absence_requests for select to authenticated
using (
  (employee_id = (select auth.uid()) and (select private.is_active_user()))
  or (select private.is_director())
);
create policy rh_weekly_records_read_own_or_director
on public.rh_weekly_records for select to authenticated
using (
  (employee_id = (select auth.uid()) and (select private.is_active_user()))
  or (select private.is_director())
);
create policy rh_warnings_read_own_or_director
on public.rh_warnings for select to authenticated
using (
  (employee_id = (select auth.uid()) and (select private.is_active_user()))
  or (select private.is_director())
);
create policy rh_disciplinary_reviews_read_own_or_director
on public.rh_disciplinary_reviews for select to authenticated
using (
  (employee_id = (select auth.uid()) and (select private.is_active_user()))
  or (select private.is_director())
);

revoke all on public.rh_hour_snapshots from public, anon, authenticated, service_role;
revoke all on public.rh_absence_requests from public, anon, authenticated, service_role;
revoke all on public.rh_weekly_records from public, anon, authenticated, service_role;
revoke all on public.rh_warnings from public, anon, authenticated, service_role;
revoke all on public.rh_disciplinary_reviews from public, anon, authenticated, service_role;

grant select on public.rh_hour_snapshots to authenticated, service_role;
grant select on public.rh_absence_requests to authenticated, service_role;
grant select on public.rh_weekly_records to authenticated, service_role;
grant select on public.rh_warnings to authenticated, service_role;
grant select on public.rh_disciplinary_reviews to authenticated, service_role;
grant insert, update on public.rh_hour_snapshots to service_role;
grant insert, update on public.rh_absence_requests to service_role;
grant insert, update on public.rh_weekly_records to service_role;
grant insert, update on public.rh_warnings to service_role;
grant insert, update on public.rh_disciplinary_reviews to service_role;
grant usage, select on sequence public.rh_hour_snapshots_id_seq to service_role;
grant usage, select on sequence public.rh_absence_requests_id_seq to service_role;
grant usage, select on sequence public.rh_weekly_records_id_seq to service_role;
grant usage, select on sequence public.rh_warnings_id_seq to service_role;
grant usage, select on sequence public.rh_disciplinary_reviews_id_seq to service_role;

revoke all on function private.is_director_user(uuid) from public, anon, authenticated, service_role;
revoke all on function public.record_hr_hour_snapshot(uuid, date, date, integer, text, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.review_hr_absence(bigint, text, text, text, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.close_hr_week(uuid, date, integer, jsonb, text, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.annul_hr_warning(bigint, text, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.decide_hr_disciplinary_review(bigint, text, text, uuid)
  from public, anon, authenticated, service_role;

grant execute on function public.record_hr_hour_snapshot(uuid, date, date, integer, text, uuid) to service_role;
grant execute on function public.review_hr_absence(bigint, text, text, text, uuid) to service_role;
grant execute on function public.close_hr_week(uuid, date, integer, jsonb, text, uuid) to service_role;
grant execute on function public.annul_hr_warning(bigint, text, uuid) to service_role;
grant execute on function public.decide_hr_disciplinary_review(bigint, text, text, uuid) to service_role;

comment on table public.rh_hour_snapshots is
  'Leituras manuais do acumulado mensal de horas informado pelo sistema da cidade.';
comment on table public.rh_absence_requests is
  'Justificativas de ausência submetidas pelos colaboradores e analisadas pela Diretoria.';
comment on table public.rh_weekly_records is
  'Fechamentos semanais de segunda a domingo com meta padrão de 600 minutos.';
comment on table public.rh_warnings is
  'Advertências disciplinares que contam apenas dentro de sua competência mensal.';
comment on table public.rh_disciplinary_reviews is
  'Análises abertas automaticamente quando o colaborador atinge três advertências ativas no mês.';

notify pgrst, 'reload schema';
