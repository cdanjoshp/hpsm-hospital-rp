-- Rollup pós-GO: Portal do Paciente por passaporte + PIN e autogestão cadastral.
-- O PIN existe somente como hash bcrypt no schema privado. Data de nascimento deixa
-- de ser credencial e passa a ser um dado cadastral opcional.

set lock_timeout = '5s';
set statement_timeout = '120s';

-- Data de nascimento é opcional em todos os fluxos canônicos; datas futuras
-- continuam estruturalmente proibidas.
create or replace function private.enforce_patient_birth_date()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.birth_date is not null and new.birth_date > current_date then
    raise exception 'A data de nascimento não pode estar no futuro.' using errcode = '23514';
  end if;
  return new;
end;
$$;

revoke all on function private.enforce_patient_birth_date()
from public, anon, authenticated, service_role;

comment on function private.enforce_patient_birth_date() is
  'Trigger privado que aceita nascimento nulo e impede exclusivamente datas futuras.';
comment on column public.patients.birth_date is
  'Data de nascimento opcional do paciente; não participa da autenticação do Portal.';

-- Contextualiza a auditoria de atualizações feitas pelo próprio paciente sem
-- confiar nesse contexto para autorização. A autorização continua sendo feita
-- exclusivamente pela sessão opaca dentro da RPC de atualização.
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
  v_portal_patient_id bigint;
begin
  begin
    v_portal_patient_id := nullif(current_setting('hpsm.patient_portal_patient_id', true), '')::bigint;
  exception when invalid_text_representation then
    v_portal_patient_id := null;
  end;

  if tg_op = 'UPDATE' and v_portal_patient_id = new.id then
    v_old_values := jsonb_build_object(
      'name', old.name,
      'phone', old.phone,
      'emergency_contact_name', old.emergency_contact_name,
      'emergency_contact_phone', old.emergency_contact_phone,
      'allergies', old.allergies
    );
    v_new_values := jsonb_build_object(
      'name', new.name,
      'phone', new.phone,
      'emergency_contact_name', new.emergency_contact_name,
      'emergency_contact_phone', new.emergency_contact_phone,
      'allergies', new.allergies,
      'origin', 'patient_portal'
    );
    if new.birth_date is distinct from old.birth_date then
      v_old_values := v_old_values || jsonb_build_object('birth_date_changed', true);
      v_new_values := v_new_values || jsonb_build_object('birth_date_changed', true);
    end if;

    insert into public.audit_logs (
      actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values
    ) values (
      null, null, 'PATIENT_PORTAL_PROFILE_UPDATED', 'patients', new.id::text,
      v_old_values, v_new_values
    );
    return new;
  end if;

  v_actor_id := coalesce(
    (select auth.uid()),
    case when tg_op = 'DELETE' then old.updated_by else new.updated_by end,
    case when tg_op = 'DELETE' then old.created_by else new.created_by end
  );

  if v_actor_id is not null then
    select profile.passport into v_actor_passport
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
    actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values
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

create table private.patient_portal_credentials (
  patient_id bigint primary key references public.patients(id) on delete cascade,
  pin_hash text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint patient_portal_credentials_pin_hash_check
    check (char_length(pin_hash) = 60 and pin_hash like '$2%')
);

alter table private.patient_portal_credentials enable row level security;
alter table private.patient_portal_credentials force row level security;
revoke all on private.patient_portal_credentials
from public, anon, authenticated, service_role;

comment on table private.patient_portal_credentials is
  'Credencial privada do Portal: armazena somente hash bcrypt do PIN, nunca o valor em texto.';

alter table public.patient_portal_login_attempts
  add column event_type text not null default 'legacy_login';

alter table public.patient_portal_login_attempts
  add constraint patient_portal_login_attempts_event_type_check
  check (event_type in ('legacy_login', 'access_check', 'pin_create', 'pin_login'));

create index patient_portal_attempts_event_passport_idx
  on public.patient_portal_login_attempts (event_type, passport_hash, attempted_at desc);
create index patient_portal_attempts_event_origin_idx
  on public.patient_portal_login_attempts (event_type, origin_hash, attempted_at desc);

-- Nenhuma sessão criada pelo antigo fator data de nascimento permanece válida.
update public.patient_portal_sessions
set revoked_at = greatest(created_at, clock_timestamp())
where revoked_at is null and expires_at > clock_timestamp();

-- O endpoint de descoberta informa somente existência e estado de primeiro acesso.
create or replace function public.patient_portal_access_state(
  p_passport text,
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
  v_origin_checks integer;
  v_passport text;
  v_passport_checks integer;
  v_passport_hash text;
  v_patient_id bigint;
begin
  begin
    v_passport := private.normalize_patient_passport(p_passport);
  exception when others then
    return jsonb_build_object('found', false, 'has_pin', false, 'blocked', false);
  end;

  if p_origin_hash is null or p_origin_hash !~ '^[0-9a-f]{64}$'
     or (p_client_hash is not null and p_client_hash !~ '^[0-9a-f]{64}$') then
    return jsonb_build_object('found', false, 'has_pin', false, 'blocked', false);
  end if;

  v_passport_hash := encode(extensions.digest('patient-portal:' || v_passport, 'sha256'), 'hex');
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_passport_hash, 0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_origin_hash, 1));

  select count(*)::integer into v_passport_checks
  from public.patient_portal_login_attempts attempt
  where attempt.event_type = 'access_check'
    and attempt.passport_hash = v_passport_hash
    and attempt.attempted_at >= clock_timestamp() - interval '15 minutes';

  select count(*)::integer into v_origin_checks
  from public.patient_portal_login_attempts attempt
  where attempt.event_type = 'access_check'
    and attempt.origin_hash = p_origin_hash
    and attempt.attempted_at >= clock_timestamp() - interval '15 minutes';

  if v_passport_checks >= 20 or v_origin_checks >= 60 then
    v_block_scope := case
      when v_passport_checks >= 20 and v_origin_checks >= 60 then 'both'
      when v_passport_checks >= 20 then 'passport'
      else 'origin'
    end;
    insert into public.patient_portal_login_attempts (
      passport_hash, origin_hash, client_hash, blocked, block_scope, event_type
    ) values (
      v_passport_hash, p_origin_hash, p_client_hash, true, v_block_scope, 'access_check'
    );
    return jsonb_build_object('found', false, 'has_pin', false, 'blocked', true);
  end if;

  select patient.id into v_patient_id
  from public.patients patient
  where patient.passport = v_passport;

  insert into public.patient_portal_login_attempts (
    patient_id, passport_hash, origin_hash, client_hash, succeeded, event_type
  ) values (
    v_patient_id, v_passport_hash, p_origin_hash, p_client_hash, v_patient_id is not null, 'access_check'
  );

  return jsonb_build_object(
    'found', v_patient_id is not null,
    'has_pin', v_patient_id is not null and exists (
      select 1 from private.patient_portal_credentials credential
      where credential.patient_id = v_patient_id
    ),
    'blocked', false
  );
end;
$$;

create or replace function public.patient_portal_create_pin_session(
  p_passport text,
  p_pin text,
  p_pin_confirmation text,
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
  v_passport text;
  v_passport_failures integer;
  v_passport_hash text;
  v_patient public.patients%rowtype;
begin
  begin
    v_passport := private.normalize_patient_passport(p_passport);
  exception when others then
    return jsonb_build_object('ok', false, 'blocked', false, 'code', 'patient_not_found');
  end;

  if p_pin is null or p_pin !~ '^[0-9]{4}$'
     or p_pin_confirmation is distinct from p_pin
     or p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$'
     or p_origin_hash is null or p_origin_hash !~ '^[0-9a-f]{64}$'
     or (p_client_hash is not null and p_client_hash !~ '^[0-9a-f]{64}$') then
    return jsonb_build_object(
      'ok', false,
      'blocked', false,
      'code', case when p_pin_confirmation is distinct from p_pin then 'pin_mismatch' else 'invalid_pin_format' end
    );
  end if;

  v_passport_hash := encode(extensions.digest('patient-portal:' || v_passport, 'sha256'), 'hex');
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_passport_hash, 0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_origin_hash, 1));

  select count(*)::integer into v_passport_failures
  from public.patient_portal_login_attempts attempt
  where attempt.passport_hash = v_passport_hash
    and attempt.event_type in ('pin_create', 'pin_login')
    and not attempt.succeeded and not attempt.blocked
    and attempt.attempted_at >= clock_timestamp() - interval '15 minutes';

  select count(*)::integer into v_origin_failures
  from public.patient_portal_login_attempts attempt
  where attempt.origin_hash = p_origin_hash
    and attempt.event_type in ('pin_create', 'pin_login')
    and not attempt.succeeded and not attempt.blocked
    and attempt.attempted_at >= clock_timestamp() - interval '15 minutes';

  if v_passport_failures >= 5 or v_origin_failures >= 20 then
    v_block_scope := case
      when v_passport_failures >= 5 and v_origin_failures >= 20 then 'both'
      when v_passport_failures >= 5 then 'passport'
      else 'origin'
    end;
    insert into public.patient_portal_login_attempts (
      passport_hash, origin_hash, client_hash, blocked, block_scope, event_type
    ) values (
      v_passport_hash, p_origin_hash, p_client_hash, true, v_block_scope, 'pin_create'
    );
    return jsonb_build_object('ok', false, 'blocked', true, 'code', 'rate_limited');
  end if;

  select patient.* into v_patient
  from public.patients patient
  where patient.passport = v_passport
  for update;

  if not found then
    insert into public.patient_portal_login_attempts (
      passport_hash, origin_hash, client_hash, event_type
    ) values (v_passport_hash, p_origin_hash, p_client_hash, 'pin_create');
    return jsonb_build_object('ok', false, 'blocked', false, 'code', 'patient_not_found');
  end if;

  if exists (
    select 1 from private.patient_portal_credentials credential
    where credential.patient_id = v_patient.id
  ) then
    return jsonb_build_object('ok', false, 'blocked', false, 'code', 'pin_exists');
  end if;

  insert into private.patient_portal_credentials (patient_id, pin_hash)
  values (v_patient.id, extensions.crypt(p_pin, extensions.gen_salt('bf', 12)));

  v_expires_at := clock_timestamp() + interval '12 hours';
  insert into public.patient_portal_sessions (patient_id, token_hash, expires_at)
  values (v_patient.id, p_token_hash, v_expires_at);

  insert into public.patient_portal_login_attempts (
    patient_id, passport_hash, origin_hash, client_hash, succeeded, event_type
  ) values (
    v_patient.id, v_passport_hash, p_origin_hash, p_client_hash, true, 'pin_create'
  );

  insert into public.audit_logs (
    actor_user_id, actor_passport, action, entity_name, entity_id, new_values
  ) values
    (null, null, 'PATIENT_PORTAL_PIN_CREATED', 'patient_portal_credentials', v_patient.id::text,
      jsonb_build_object('origin', 'patient_portal', 'outcome', 'created')),
    (null, null, 'PATIENT_PORTAL_LOGIN', 'patient_portal', v_patient.id::text,
      jsonb_build_object('origin', 'patient_portal', 'outcome', 'success', 'method', 'pin_first_access'));

  return jsonb_build_object('ok', true, 'blocked', false, 'expires_at', v_expires_at);
end;
$$;

-- A nova assinatura substitui definitivamente passaporte + nascimento.
drop function if exists public.patient_portal_create_session(text, date, text, text, text);
drop function if exists public.patient_portal_create_session_pre_canonical(text, date, text, text, text);

create function public.patient_portal_create_session(
  p_passport text,
  p_pin text,
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
  v_passport text;
  v_passport_failures integer;
  v_passport_hash text;
  v_patient_id bigint;
  v_pin_hash text;
begin
  begin
    v_passport := private.normalize_patient_passport(p_passport);
  exception when others then
    return jsonb_build_object('ok', false, 'blocked', false, 'code', 'patient_not_found');
  end;

  if p_pin is null or p_pin !~ '^[0-9]{4}$'
     or p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$'
     or p_origin_hash is null or p_origin_hash !~ '^[0-9a-f]{64}$'
     or (p_client_hash is not null and p_client_hash !~ '^[0-9a-f]{64}$') then
    return jsonb_build_object('ok', false, 'blocked', false, 'code', 'invalid_pin');
  end if;

  v_passport_hash := encode(extensions.digest('patient-portal:' || v_passport, 'sha256'), 'hex');
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_passport_hash, 0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_origin_hash, 1));

  select count(*)::integer into v_passport_failures
  from public.patient_portal_login_attempts attempt
  where attempt.passport_hash = v_passport_hash
    and attempt.event_type in ('pin_create', 'pin_login')
    and not attempt.succeeded and not attempt.blocked
    and attempt.attempted_at >= clock_timestamp() - interval '15 minutes';

  select count(*)::integer into v_origin_failures
  from public.patient_portal_login_attempts attempt
  where attempt.origin_hash = p_origin_hash
    and attempt.event_type in ('pin_create', 'pin_login')
    and not attempt.succeeded and not attempt.blocked
    and attempt.attempted_at >= clock_timestamp() - interval '15 minutes';

  if v_passport_failures >= 5 or v_origin_failures >= 20 then
    v_block_scope := case
      when v_passport_failures >= 5 and v_origin_failures >= 20 then 'both'
      when v_passport_failures >= 5 then 'passport'
      else 'origin'
    end;
    insert into public.patient_portal_login_attempts (
      passport_hash, origin_hash, client_hash, blocked, block_scope, event_type
    ) values (
      v_passport_hash, p_origin_hash, p_client_hash, true, v_block_scope, 'pin_login'
    );
    return jsonb_build_object('ok', false, 'blocked', true, 'code', 'rate_limited');
  end if;

  select patient.id, credential.pin_hash into v_patient_id, v_pin_hash
  from public.patients patient
  left join private.patient_portal_credentials credential on credential.patient_id = patient.id
  where patient.passport = v_passport
  for update of patient;

  if not found then
    insert into public.patient_portal_login_attempts (
      passport_hash, origin_hash, client_hash, event_type
    ) values (v_passport_hash, p_origin_hash, p_client_hash, 'pin_login');
    return jsonb_build_object('ok', false, 'blocked', false, 'code', 'patient_not_found');
  end if;

  if v_pin_hash is null then
    return jsonb_build_object('ok', false, 'blocked', false, 'code', 'first_access');
  end if;

  if v_pin_hash <> extensions.crypt(p_pin, v_pin_hash) then
    insert into public.patient_portal_login_attempts (
      patient_id, passport_hash, origin_hash, client_hash, event_type
    ) values (v_patient_id, v_passport_hash, p_origin_hash, p_client_hash, 'pin_login');
    return jsonb_build_object('ok', false, 'blocked', false, 'code', 'invalid_pin');
  end if;

  v_expires_at := clock_timestamp() + interval '12 hours';
  insert into public.patient_portal_sessions (patient_id, token_hash, expires_at)
  values (v_patient_id, p_token_hash, v_expires_at);

  insert into public.patient_portal_login_attempts (
    patient_id, passport_hash, origin_hash, client_hash, succeeded, event_type
  ) values (
    v_patient_id, v_passport_hash, p_origin_hash, p_client_hash, true, 'pin_login'
  );

  insert into public.audit_logs (
    actor_user_id, actor_passport, action, entity_name, entity_id, new_values
  ) values (
    null, null, 'PATIENT_PORTAL_LOGIN', 'patient_portal', v_patient_id::text,
    jsonb_build_object('origin', 'patient_portal', 'outcome', 'success', 'method', 'pin')
  );

  return jsonb_build_object('ok', true, 'blocked', false, 'expires_at', v_expires_at);
end;
$$;

create or replace function public.patient_portal_profile(p_token_hash text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_session record;
  v_patient public.patients%rowtype;
begin
  select * into v_session from private.patient_portal_session_record(p_token_hash);
  if not found then return jsonb_build_object('authenticated', false); end if;

  select * into strict v_patient from public.patients where id = v_session.patient_id;
  return jsonb_build_object(
    'authenticated', true,
    'patient', jsonb_build_object(
      'name', v_patient.name,
      'passport', v_patient.passport,
      'phone', v_patient.phone,
      'birth_date', v_patient.birth_date,
      'emergency_contact_name', v_patient.emergency_contact_name,
      'emergency_contact_phone', v_patient.emergency_contact_phone,
      'allergies', v_patient.allergies
    )
  );
end;
$$;

create or replace function public.patient_portal_update_profile(
  p_token_hash text,
  p_name text,
  p_phone text,
  p_birth_date date,
  p_emergency_contact_name text,
  p_emergency_contact_phone text,
  p_allergies text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_allergies text := btrim(coalesce(p_allergies, ''));
  v_emergency_name text := nullif(btrim(coalesce(p_emergency_contact_name, '')), '');
  v_emergency_phone text := nullif(btrim(coalesce(p_emergency_contact_phone, '')), '');
  v_name text := btrim(coalesce(p_name, ''));
  v_patient public.patients%rowtype;
  v_phone text := nullif(btrim(coalesce(p_phone, '')), '');
  v_session record;
begin
  select * into v_session from private.patient_portal_session_record(p_token_hash);
  if not found then return jsonb_build_object('authenticated', false); end if;

  if char_length(v_name) not between 2 and 100 then
    raise exception 'Informe o nome completo do paciente.' using errcode = '22023';
  end if;
  if char_length(v_allergies) not between 1 and 1000 then
    raise exception 'Informe suas alergias ou registre “Não possui”.' using errcode = '22023';
  end if;
  if v_phone is not null and v_phone !~ '^\(055\) [0-9]{3}-[0-9]{3}$' then
    raise exception 'Informe o telefone no formato (055) 123-456 ou deixe o campo em branco.' using errcode = '22023';
  end if;
  if (v_emergency_name is null) <> (v_emergency_phone is null) then
    raise exception 'Informe o nome e o telefone do contato de emergência ou deixe os dois campos em branco.' using errcode = '22023';
  end if;
  if v_emergency_name is not null and char_length(v_emergency_name) not between 2 and 100 then
    raise exception 'O nome do contato de emergência deve ter entre 2 e 100 caracteres.' using errcode = '22023';
  end if;
  if v_emergency_phone is not null and v_emergency_phone !~ '^\(055\) [0-9]{3}-[0-9]{3}$' then
    raise exception 'Informe o telefone de emergência no formato (055) 123-456 ou deixe o contato em branco.' using errcode = '22023';
  end if;
  if p_birth_date is not null and p_birth_date > current_date then
    raise exception 'A data de nascimento não pode estar no futuro.' using errcode = '22023';
  end if;

  select * into strict v_patient
  from public.patients patient
  where patient.id = v_session.patient_id
  for update;

  if row(v_patient.name, v_patient.phone, v_patient.birth_date, v_patient.emergency_contact_name,
         v_patient.emergency_contact_phone, v_patient.allergies)
     is distinct from
     row(v_name, v_phone, p_birth_date, v_emergency_name, v_emergency_phone, v_allergies) then
    perform set_config('hpsm.patient_portal_patient_id', v_patient.id::text, true);
    update public.patients patient set
      name = v_name,
      phone = v_phone,
      birth_date = p_birth_date,
      emergency_contact_name = v_emergency_name,
      emergency_contact_phone = v_emergency_phone,
      allergies = v_allergies
    where patient.id = v_patient.id
    returning patient.* into v_patient;
  end if;

  return jsonb_build_object(
    'authenticated', true,
    'patient', jsonb_build_object(
      'name', v_patient.name,
      'passport', v_patient.passport,
      'phone', v_patient.phone,
      'birth_date', v_patient.birth_date,
      'emergency_contact_name', v_patient.emergency_contact_name,
      'emergency_contact_phone', v_patient.emergency_contact_phone,
      'allergies', v_patient.allergies
    )
  );
end;
$$;

create or replace function public.reset_patient_portal_pin(p_patient_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_actor_passport text;
  v_credential_removed boolean := false;
  v_patient_name text;
  v_revoked integer := 0;
begin
  if coalesce(private.current_position_level(v_actor), 0) not between 11 and 14 then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  select patient.name into v_patient_name
  from public.patients patient
  where patient.id = p_patient_id
  for update;
  if not found then raise exception 'Paciente não localizado.' using errcode = '22023'; end if;

  delete from private.patient_portal_credentials credential
  where credential.patient_id = p_patient_id;
  v_credential_removed := found;

  update public.patient_portal_sessions session
  set revoked_at = greatest(session.created_at, clock_timestamp())
  where session.patient_id = p_patient_id
    and session.revoked_at is null
    and session.expires_at > clock_timestamp();
  get diagnostics v_revoked = row_count;

  select profile.passport into v_actor_passport
  from public.profiles profile where profile.user_id = v_actor;

  insert into public.audit_logs (
    actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values
  ) values (
    v_actor, v_actor_passport, 'PATIENT_PORTAL_PIN_RESET', 'patient_portal_credentials', p_patient_id::text,
    jsonb_build_object('credential_present', v_credential_removed),
    jsonb_build_object('origin', 'professional', 'sessions_revoked', v_revoked, 'next_access', 'create_pin')
  );

  return jsonb_build_object(
    'ok', true,
    'credential_removed', v_credential_removed,
    'sessions_revoked', v_revoked,
    'patient_name', v_patient_name
  );
end;
$$;

-- Parcerias aceitam qualquer paciente canônico, independentemente dos campos
-- opcionais. Pré-beneficiários sem patient_id continuam pendentes.
create or replace function private.partnership_patient_can_use_portal(p_patient_id bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.patients patient
    where patient.id = p_patient_id and patient.passport ~ '^[0-9]{4}$'
  );
$$;

create or replace function public.hpsm_partnership_patient_lookup(p_search text, p_limit integer default 8)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    jsonb_agg(entry.value || jsonb_build_object('portal_ready', true) order by entry.ordinality),
    '[]'::jsonb
  )
  from jsonb_array_elements(
    public.hpsm_partnership_patient_lookup_pre_canonical(
      private.normalize_patient_search(p_search), p_limit
    )
  ) with ordinality as entry(value, ordinality);
$$;

create or replace function private.partnership_portal_actor(
  p_token_hash text,
  p_partnership_id bigint,
  p_require_active boolean default false
)
returns bigint
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_patient_id bigint;
  v_status text;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'Sessão do Portal inválida.' using errcode = '42501';
  end if;

  select session.patient_id, partnership.status
  into v_patient_id, v_status
  from private.patient_portal_session_record(p_token_hash) session
  join private.patient_portal_credentials credential on credential.patient_id = session.patient_id
  join public.partnerships partnership
    on partnership.id = p_partnership_id
   and partnership.responsible_patient_id = session.patient_id;

  if not found then
    raise exception 'Parceria não localizada para esta sessão.' using errcode = '42501';
  end if;
  if p_require_active and v_status <> 'active' then
    raise exception 'Esta parceria está inativa e não permite alterações.' using errcode = '22023';
  end if;
  return v_patient_id;
end;
$$;

revoke all on function public.patient_portal_access_state(text, text, text)
from public, anon, authenticated, service_role;
revoke all on function public.patient_portal_create_pin_session(text, text, text, text, text, text)
from public, anon, authenticated, service_role;
revoke all on function public.patient_portal_create_session(text, text, text, text, text)
from public, anon, authenticated, service_role;
revoke all on function public.patient_portal_profile(text)
from public, anon, authenticated, service_role;
revoke all on function public.patient_portal_update_profile(text, text, text, date, text, text, text)
from public, anon, authenticated, service_role;
revoke all on function public.reset_patient_portal_pin(bigint)
from public, anon, authenticated, service_role;
revoke all on function private.partnership_patient_can_use_portal(bigint)
from public, anon, authenticated, service_role;
revoke all on function private.partnership_portal_actor(text, bigint, boolean)
from public, anon, authenticated, service_role;
revoke all on function public.hpsm_partnership_patient_lookup(text, integer)
from public, anon, authenticated, service_role;

grant execute on function public.patient_portal_access_state(text, text, text) to service_role;
grant execute on function public.patient_portal_create_pin_session(text, text, text, text, text, text) to service_role;
grant execute on function public.patient_portal_create_session(text, text, text, text, text) to service_role;
grant execute on function public.patient_portal_profile(text) to service_role;
grant execute on function public.patient_portal_update_profile(text, text, text, date, text, text, text) to service_role;
grant execute on function public.reset_patient_portal_pin(bigint) to authenticated;
grant execute on function public.hpsm_partnership_patient_lookup(text, integer) to authenticated;

comment on function public.patient_portal_access_state(text, text, text) is
  'Localiza o paciente por passaporte canônico e informa se há PIN, sem retornar dados pessoais. Somente service_role.';
comment on function public.patient_portal_create_pin_session(text, text, text, text, text, text) is
  'Cria o primeiro hash bcrypt de PIN e autentica imediatamente. Nunca persiste ou retorna o PIN. Somente service_role.';
comment on function public.patient_portal_create_session(text, text, text, text, text) is
  'Valida passaporte + PIN e cria sessão opaca de 12 horas. Somente service_role.';
comment on function public.patient_portal_update_profile(text, text, text, date, text, text, text) is
  'Atualiza somente os campos cadastrais permitidos do próprio paciente resolvido pela sessão opaca.';
comment on function public.reset_patient_portal_pin(bigint) is
  'Remove o hash do PIN e revoga todas as sessões do paciente. Restrito aos níveis 11–14.';

notify pgrst, 'reload schema';
