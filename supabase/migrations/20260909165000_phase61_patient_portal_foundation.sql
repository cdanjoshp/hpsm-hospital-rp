-- HPSM — Fase 6.1: data de nascimento e fundação segura do Portal do Paciente.
-- Pacientes históricos permanecem compatíveis; novas fichas exigem birth_date.

alter table public.patients
  add column if not exists birth_date date;

comment on column public.patients.birth_date is
  'Data de nascimento canônica do paciente. Nullable apenas para cadastros históricos anteriores à Fase 6.1.';

create or replace function private.enforce_patient_birth_date()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.birth_date is not null and new.birth_date > current_date then
    raise exception 'A data de nascimento não pode estar no futuro.' using errcode = '23514';
  end if;

  if tg_op = 'INSERT' and new.birth_date is null then
    raise exception 'Informe a data de nascimento do paciente.' using errcode = '23514';
  end if;

  if tg_op = 'UPDATE'
     and new.birth_date is null
     and row(
       new.passport,
       new.name,
       new.phone,
       new.emergency_contact_name,
       new.emergency_contact_phone
     ) is distinct from row(
       old.passport,
       old.name,
       old.phone,
       old.emergency_contact_name,
       old.emergency_contact_phone
     ) then
    raise exception 'Informe a data de nascimento antes de alterar o cadastro.' using errcode = '23514';
  end if;

  return new;
end;
$$;

revoke all on function private.enforce_patient_birth_date()
from public, anon, authenticated, service_role;

drop trigger if exists patients_guard_birth_date on public.patients;
create trigger patients_guard_birth_date
before insert or update on public.patients
for each row execute function private.enforce_patient_birth_date();

-- A auditoria cadastral preserva a existência da alteração sem copiar a data
-- de nascimento para audit_logs.
create or replace function private.audit_patient_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;
  v_actor_passport text;
  v_old_values jsonb;
  v_new_values jsonb;
begin
  v_actor_id := coalesce(
    (select auth.uid()),
    case when tg_op = 'DELETE' then old.updated_by else new.updated_by end,
    case when tg_op = 'DELETE' then old.created_by else new.created_by end
  );

  if v_actor_id is not null then
    select profile.passport
    into v_actor_passport
    from public.profiles profile
    where profile.user_id = v_actor_id;
  end if;

  if tg_op in ('UPDATE', 'DELETE') then
    v_old_values := to_jsonb(old) - 'birth_date';
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    v_new_values := to_jsonb(new) - 'birth_date';
  end if;

  if tg_op = 'INSERT' then
    v_new_values := v_new_values || jsonb_build_object('birth_date_present', new.birth_date is not null);
  elsif tg_op = 'UPDATE' and new.birth_date is distinct from old.birth_date then
    v_old_values := v_old_values || jsonb_build_object('birth_date_changed', true);
    v_new_values := v_new_values || jsonb_build_object('birth_date_changed', true);
  end if;

  insert into public.audit_logs (
    actor_user_id,
    actor_passport,
    action,
    entity_name,
    entity_id,
    old_values,
    new_values
  ) values (
    v_actor_id,
    v_actor_passport,
    tg_op,
    tg_table_name,
    coalesce(case when tg_op = 'DELETE' then old.id else new.id end, 0)::text,
    v_old_values,
    v_new_values
  );

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function private.audit_patient_change()
from public, anon, authenticated, service_role;

drop trigger if exists patients_audit on public.patients;
create trigger patients_audit
after insert or update or delete on public.patients
for each row execute function private.audit_patient_change();

create table if not exists public.patient_portal_sessions (
  id uuid primary key default gen_random_uuid(),
  patient_id bigint not null references public.patients(id) on delete restrict,
  token_hash text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  constraint patient_portal_sessions_token_hash_check
    check (token_hash ~ '^[0-9a-f]{64}$'),
  constraint patient_portal_sessions_expiry_check
    check (expires_at > created_at),
  constraint patient_portal_sessions_revocation_check
    check (revoked_at is null or revoked_at >= created_at)
);

create unique index if not exists patient_portal_sessions_token_hash_idx
  on public.patient_portal_sessions (token_hash);
create index if not exists patient_portal_sessions_patient_idx
  on public.patient_portal_sessions (patient_id, created_at desc);
create index if not exists patient_portal_sessions_expires_idx
  on public.patient_portal_sessions (expires_at)
  where revoked_at is null;

create table if not exists public.patient_portal_login_attempts (
  id bigint generated always as identity primary key,
  patient_id bigint references public.patients(id) on delete set null,
  passport_hash text not null,
  origin_hash text not null,
  client_hash text,
  succeeded boolean not null default false,
  blocked boolean not null default false,
  block_scope text,
  attempted_at timestamptz not null default now(),
  constraint patient_portal_attempts_passport_hash_check
    check (passport_hash ~ '^[0-9a-f]{64}$'),
  constraint patient_portal_attempts_origin_hash_check
    check (origin_hash ~ '^[0-9a-f]{64}$'),
  constraint patient_portal_attempts_client_hash_check
    check (client_hash is null or client_hash ~ '^[0-9a-f]{64}$'),
  constraint patient_portal_attempts_outcome_check
    check (not (succeeded and blocked)),
  constraint patient_portal_attempts_block_scope_check
    check (
      (blocked and block_scope in ('passport', 'origin', 'both'))
      or (not blocked and block_scope is null)
    )
);

create index if not exists patient_portal_attempts_patient_idx
  on public.patient_portal_login_attempts (patient_id, attempted_at desc)
  where patient_id is not null;
create index if not exists patient_portal_attempts_passport_failed_idx
  on public.patient_portal_login_attempts (passport_hash, attempted_at desc)
  where not succeeded and not blocked;
create index if not exists patient_portal_attempts_origin_failed_idx
  on public.patient_portal_login_attempts (origin_hash, attempted_at desc)
  where not succeeded and not blocked;
create index if not exists patient_portal_attempts_cleanup_idx
  on public.patient_portal_login_attempts (attempted_at);

alter table public.patient_portal_sessions enable row level security;
alter table public.patient_portal_sessions force row level security;
alter table public.patient_portal_login_attempts enable row level security;
alter table public.patient_portal_login_attempts force row level security;

revoke all on public.patient_portal_sessions
from public, anon, authenticated, service_role;
revoke all on public.patient_portal_login_attempts
from public, anon, authenticated, service_role;

create or replace function private.patient_portal_session_record(p_token_hash text)
returns table (
  patient_id bigint,
  patient_name text,
  patient_passport text,
  expires_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    session.patient_id,
    patient.name,
    patient.passport,
    session.expires_at
  from public.patient_portal_sessions session
  join public.patients patient on patient.id = session.patient_id
  where session.token_hash = p_token_hash
    and session.revoked_at is null
    and session.expires_at > clock_timestamp()
  limit 1;
$$;

revoke all on function private.patient_portal_session_record(text)
from public, anon, authenticated, service_role;

create or replace function public.patient_portal_create_session(
  p_passport text,
  p_birth_date date,
  p_token_hash text,
  p_origin_hash text,
  p_client_hash text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_block_scope text;
  v_expires_at timestamptz;
  v_origin_failures integer;
  v_passport text := btrim(coalesce(p_passport, ''));
  v_passport_failures integer;
  v_passport_hash text;
  v_patient public.patients%rowtype;
begin
  if v_passport !~ '^[0-9]{1,4}$'
     or p_birth_date is null
     or p_birth_date > current_date
     or p_token_hash is null
     or p_token_hash !~ '^[0-9a-f]{64}$'
     or p_origin_hash is null
     or p_origin_hash !~ '^[0-9a-f]{64}$'
     or (p_client_hash is not null and p_client_hash !~ '^[0-9a-f]{64}$') then
    return jsonb_build_object('ok', false, 'blocked', false);
  end if;

  v_passport_hash := encode(
    extensions.digest('patient-portal:' || v_passport, 'sha256'),
    'hex'
  );

  -- Serializa tentativas do mesmo passaporte antes de contar e gravar.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_passport_hash, 0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_origin_hash, 1));

  select count(*)::integer
  into v_passport_failures
  from public.patient_portal_login_attempts attempt
  where attempt.passport_hash = v_passport_hash
    and not attempt.succeeded
    and not attempt.blocked
    and attempt.attempted_at >= clock_timestamp() - interval '15 minutes';

  select count(*)::integer
  into v_origin_failures
  from public.patient_portal_login_attempts attempt
  where attempt.origin_hash = p_origin_hash
    and not attempt.succeeded
    and not attempt.blocked
    and attempt.attempted_at >= clock_timestamp() - interval '15 minutes';

  if v_passport_failures >= 5 or v_origin_failures >= 20 then
    v_block_scope := case
      when v_passport_failures >= 5 and v_origin_failures >= 20 then 'both'
      when v_passport_failures >= 5 then 'passport'
      else 'origin'
    end;

    if not exists (
      select 1
      from public.patient_portal_login_attempts attempt
      where attempt.blocked
        and attempt.attempted_at >= clock_timestamp() - interval '15 minutes'
        and (
          (v_block_scope = 'passport' and attempt.passport_hash = v_passport_hash and attempt.block_scope = 'passport')
          or (v_block_scope = 'origin' and attempt.origin_hash = p_origin_hash and attempt.block_scope = 'origin')
          or (v_block_scope = 'both' and attempt.passport_hash = v_passport_hash and attempt.origin_hash = p_origin_hash and attempt.block_scope = 'both')
        )
    ) then
      insert into public.patient_portal_login_attempts (
        passport_hash,
        origin_hash,
        client_hash,
        blocked,
        block_scope
      ) values (
        v_passport_hash,
        p_origin_hash,
        p_client_hash,
        true,
        v_block_scope
      );

      insert into public.audit_logs (
        actor_user_id,
        actor_passport,
        action,
        entity_name,
        entity_id,
        new_values
      ) values (
        null,
        null,
        'PATIENT_PORTAL_RATE_LIMITED',
        'patient_portal',
        null,
        jsonb_build_object('scope', v_block_scope)
      );
    end if;

    return jsonb_build_object('ok', false, 'blocked', true);
  end if;

  select patient.*
  into v_patient
  from public.patients patient
  where patient.passport = v_passport
    and patient.birth_date = p_birth_date
  limit 1;

  if not found then
    insert into public.patient_portal_login_attempts (
      passport_hash,
      origin_hash,
      client_hash
    ) values (
      v_passport_hash,
      p_origin_hash,
      p_client_hash
    );

    return jsonb_build_object('ok', false, 'blocked', false);
  end if;

  v_expires_at := clock_timestamp() + interval '12 hours';

  insert into public.patient_portal_sessions (
    patient_id,
    token_hash,
    expires_at
  ) values (
    v_patient.id,
    p_token_hash,
    v_expires_at
  );

  insert into public.patient_portal_login_attempts (
    patient_id,
    passport_hash,
    origin_hash,
    client_hash,
    succeeded
  ) values (
    v_patient.id,
    v_passport_hash,
    p_origin_hash,
    p_client_hash,
    true
  );

  insert into public.audit_logs (
    actor_user_id,
    actor_passport,
    action,
    entity_name,
    entity_id,
    new_values
  ) values (
    null,
    null,
    'PATIENT_PORTAL_LOGIN',
    'patient_portal',
    v_patient.id::text,
    jsonb_build_object('outcome', 'success')
  );

  return jsonb_build_object(
    'ok', true,
    'blocked', false,
    'expires_at', v_expires_at
  );
end;
$$;

create or replace function public.patient_portal_session_me(p_token_hash text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
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

  return jsonb_build_object(
    'authenticated', true,
    'name', v_session.patient_name,
    'passport', v_session.patient_passport,
    'expires_at', v_session.expires_at
  );
end;
$$;

create or replace function public.patient_portal_revoke_session(p_token_hash text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_patient_id bigint;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    return false;
  end if;

  update public.patient_portal_sessions session
  set revoked_at = clock_timestamp()
  where session.token_hash = p_token_hash
    and session.revoked_at is null
    and session.expires_at > clock_timestamp()
  returning session.patient_id into v_patient_id;

  if v_patient_id is null then
    return false;
  end if;

  insert into public.audit_logs (
    actor_user_id,
    actor_passport,
    action,
    entity_name,
    entity_id,
    new_values
  ) values (
    null,
    null,
    'PATIENT_PORTAL_LOGOUT',
    'patient_portal',
    v_patient_id::text,
    jsonb_build_object('outcome', 'revoked')
  );

  return true;
end;
$$;

revoke all on function public.patient_portal_create_session(text, date, text, text, text)
from public, anon, authenticated;
revoke all on function public.patient_portal_session_me(text)
from public, anon, authenticated;
revoke all on function public.patient_portal_revoke_session(text)
from public, anon, authenticated;

grant execute on function public.patient_portal_create_session(text, date, text, text, text)
to service_role;
grant execute on function public.patient_portal_session_me(text)
to service_role;
grant execute on function public.patient_portal_revoke_session(text)
to service_role;

comment on function public.patient_portal_create_session(text, date, text, text, text) is
  'Valida passaporte + nascimento, aplica rate limit agregado e cria sessão opaca de 12 horas. Somente service_role.';
comment on function public.patient_portal_session_me(text) is
  'Resolve identidade mínima exclusivamente pelo hash de uma sessão válida do Portal. Somente service_role.';
comment on function public.patient_portal_revoke_session(text) is
  'Revoga uma sessão válida do Portal e registra logout sem token ou data de nascimento. Somente service_role.';

-- birth_date é adicionado ao final para preservar os nomes/ordem já publicados
-- pelo CREATE OR REPLACE VIEW.
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
  order by request.coverage_end desc, request.id desc
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
    select
      patient.id,
      patient.passport,
      patient.name,
      patient.phone,
      patient.birth_date,
      patient.emergency_contact_name,
      patient.emergency_contact_phone,
      patient.created_at,
      patient.updated_at
    from public.patients patient
    where patient.passport like v_passport || '%'
    order by (patient.passport = v_passport) desc, patient.passport asc
    limit v_limit
  ), plan_states as materialized (
    select state.*
    from public.get_patient_health_plan_states(
      coalesce((select array_agg(matching.id) from matching), array[]::bigint[])
    ) state
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
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
          'status', coalesce(plan_states.status, 'none'),
          'activated_at', plan_states.activated_at,
          'valid_until', plan_states.valid_until,
          'authorized_by', plan_states.authorized_by,
          'authorized_by_name', plan_states.authorized_by_name,
          'pending_request_id', plan_states.pending_request_id,
          'pending_requested_at', plan_states.pending_requested_at
        )
      )
      order by (matching.passport = v_passport) desc, matching.passport asc
    ),
    '[]'::jsonb
  )
  into v_result
  from matching
  left join plan_states on plan_states.patient_id = matching.id;

  return v_result;
end;
$$;

revoke all on function public.hpsm_patient_quick_lookup(text, integer)
from public, anon, authenticated, service_role;
grant execute on function public.hpsm_patient_quick_lookup(text, integer)
to authenticated;
