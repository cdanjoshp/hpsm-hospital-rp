-- Sessões do Portal do Paciente permanecem válidas até logout, reset do PIN
-- ou revogação explícita. O banco não aplica timeout por inatividade ou duração.

alter table public.patient_portal_sessions
  drop constraint if exists patient_portal_sessions_expiry_check;

alter table public.patient_portal_sessions
  alter column expires_at drop not null;

update public.patient_portal_sessions session
set expires_at = null
where session.revoked_at is null
  and session.expires_at > clock_timestamp();

drop index if exists public.patient_portal_sessions_expires_idx;

create or replace function private.patient_portal_session_persistent_expiry()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.expires_at := null;
  return new;
end;
$$;

revoke all on function private.patient_portal_session_persistent_expiry()
from public, anon, authenticated, service_role;

drop trigger if exists patient_portal_sessions_persistent_expiry
on public.patient_portal_sessions;

create trigger patient_portal_sessions_persistent_expiry
before insert or update of expires_at on public.patient_portal_sessions
for each row execute function private.patient_portal_session_persistent_expiry();

-- Mantém integralmente rate limiting, PIN e auditoria das funções vigentes;
-- apenas troca o vencimento calculado pelo marcador persistente NULL.
do $$
declare
  v_definition text;
  v_expiring_assignment constant text := 'v_expires_at := clock_timestamp() + interval ''12 hours'';';
begin
  select pg_catalog.pg_get_functiondef(
    'public.patient_portal_create_pin_session(text,text,text,text,text,text)'::regprocedure
  ) into v_definition;
  if pg_catalog.strpos(v_definition, v_expiring_assignment) = 0 then
    raise exception 'A função patient_portal_create_pin_session mudou; revise a migração persistente.';
  end if;
  execute pg_catalog.replace(v_definition, v_expiring_assignment, 'v_expires_at := null;');

  select pg_catalog.pg_get_functiondef(
    'public.patient_portal_create_session(text,text,text,text,text)'::regprocedure
  ) into v_definition;
  if pg_catalog.strpos(v_definition, v_expiring_assignment) = 0 then
    raise exception 'A função patient_portal_create_session mudou; revise a migração persistente.';
  end if;
  execute pg_catalog.replace(v_definition, v_expiring_assignment, 'v_expires_at := null;');
end;
$$;

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
    and (session.expires_at is null or session.expires_at > clock_timestamp())
  limit 1;
$$;

revoke all on function private.patient_portal_session_record(text)
from public, anon, authenticated, service_role;

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
    and (session.expires_at is null or session.expires_at > clock_timestamp())
  returning session.patient_id into v_patient_id;

  if v_patient_id is null then
    return false;
  end if;

  insert into public.audit_logs (
    actor_user_id, actor_passport, action, entity_name, entity_id, new_values
  ) values (
    null, null, 'PATIENT_PORTAL_LOGOUT', 'patient_portal', v_patient_id::text,
    jsonb_build_object('outcome', 'revoked')
  );

  return true;
end;
$$;

revoke all on function public.patient_portal_revoke_session(text)
from public, anon, authenticated, service_role;
grant execute on function public.patient_portal_revoke_session(text) to service_role;

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
    and (session.expires_at is null or session.expires_at > clock_timestamp());
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

revoke all on function public.reset_patient_portal_pin(bigint)
from public, anon, authenticated, service_role;
grant execute on function public.reset_patient_portal_pin(bigint) to authenticated;

comment on column public.patient_portal_sessions.expires_at is
  'Compatibilidade histórica: NULL representa sessão persistente; sessões legadas expiradas permanecem inválidas.';
comment on function private.patient_portal_session_record(text) is
  'Resolve sessão persistente do Portal até logout, reset de PIN ou revogação explícita.';
comment on function public.patient_portal_create_pin_session(text, text, text, text, text, text) is
  'Cria o primeiro hash bcrypt de PIN e uma sessão opaca persistente. Nunca persiste ou retorna o PIN. Somente service_role.';
comment on function public.patient_portal_create_session(text, text, text, text, text) is
  'Valida passaporte + PIN e cria sessão opaca persistente até revogação. Somente service_role.';
