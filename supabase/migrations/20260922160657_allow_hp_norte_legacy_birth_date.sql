-- Exceção fechada para pacientes legados do HP Norte, cuja origem guarda somente idade.
-- O cadastro operacional continua exigindo nascimento; apenas o importador privado pode omiti-lo.

create table if not exists private.hp_norte_import_context (
  backend_pid integer primary key,
  batch_id uuid not null references public.legacy_import_batches(id) on delete cascade,
  created_at timestamptz not null default now()
);

revoke all on private.hp_norte_import_context from public, anon, authenticated, service_role;

create or replace function private.enforce_patient_birth_date()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_hp_norte_import boolean := exists (
    select 1 from private.hp_norte_import_context context
    where context.backend_pid = pg_backend_pid()
  );
begin
  if new.birth_date is not null and new.birth_date > current_date then
    raise exception 'A data de nascimento não pode estar no futuro.' using errcode = '23514';
  end if;

  if v_hp_norte_import then
    if coalesce(new.created_by, new.updated_by) is not null then
      raise exception 'A exceção de nascimento legado não aceita autoria operacional.' using errcode = '42501';
    end if;
    return new;
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

alter function private.import_hp_norte_chunk(uuid, jsonb)
  rename to import_hp_norte_chunk_unscoped;

create function private.import_hp_norte_chunk(p_batch_id uuid, p_items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_result jsonb;
begin
  insert into private.hp_norte_import_context (backend_pid, batch_id)
  values (pg_backend_pid(), p_batch_id)
  on conflict (backend_pid) do update set batch_id = excluded.batch_id, created_at = now();

  begin
    v_result := private.import_hp_norte_chunk_unscoped(p_batch_id, p_items);
  exception when others then
    delete from private.hp_norte_import_context where backend_pid = pg_backend_pid();
    raise;
  end;

  delete from private.hp_norte_import_context where backend_pid = pg_backend_pid();
  return v_result;
end;
$$;

revoke all on function private.enforce_patient_birth_date() from public, anon, authenticated, service_role;
revoke all on function private.import_hp_norte_chunk_unscoped(uuid, jsonb) from public, anon, authenticated, service_role;
revoke all on function private.import_hp_norte_chunk(uuid, jsonb) from public, anon, authenticated, service_role;
