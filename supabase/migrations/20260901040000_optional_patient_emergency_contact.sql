-- HPSM — contato de emergência opcional e identidade única por passaporte.

alter table public.patients
  alter column emergency_contact_name drop not null,
  alter column emergency_contact_phone drop not null,
  drop constraint if exists patients_emergency_contact_name_check,
  drop constraint if exists patients_emergency_contact_phone_check,
  drop constraint if exists patients_emergency_contact_pair_check,
  add constraint patients_emergency_contact_name_check
    check (
      emergency_contact_name is null
      or char_length(btrim(emergency_contact_name)) between 2 and 100
    ),
  add constraint patients_emergency_contact_phone_check
    check (
      emergency_contact_phone is null
      or emergency_contact_phone ~ '^\(055\) [0-9]{3}-[0-9]{3}$'
    ),
  add constraint patients_emergency_contact_pair_check
    check ((emergency_contact_name is null) = (emergency_contact_phone is null));

-- As migrations de fundação já criam unicidade em ambos os cadastros.
-- Estas verificações tornam a invariável explícita e impedem que esta migration
-- seja aplicada sobre uma base que tenha perdido a proteção estrutural.
do $$
begin
  if exists (
    select 1 from public.patients group by passport having count(*) > 1
  ) then
    raise exception 'Existem pacientes com passaporte duplicado.';
  end if;

  if exists (
    select 1 from public.profiles group by passport having count(*) > 1
  ) then
    raise exception 'Existem profissionais com passaporte duplicado.';
  end if;

  if not exists (
    select 1
    from pg_index index_definition
    join pg_attribute column_definition
      on column_definition.attrelid = index_definition.indrelid
     and column_definition.attname = 'passport'
    where index_definition.indrelid = 'public.patients'::regclass
      and index_definition.indisunique
      and index_definition.indisvalid
      and index_definition.indexprs is null
      and index_definition.indpred is null
      and index_definition.indnkeyatts = 1
      and index_definition.indkey::text = column_definition.attnum::text
  ) then
    raise exception 'A unicidade de patients.passport não está protegida por índice único.';
  end if;

  if not exists (
    select 1
    from pg_index index_definition
    join pg_attribute column_definition
      on column_definition.attrelid = index_definition.indrelid
     and column_definition.attname = 'passport'
    where index_definition.indrelid = 'public.profiles'::regclass
      and index_definition.indisunique
      and index_definition.indisvalid
      and index_definition.indexprs is null
      and index_definition.indpred is null
      and index_definition.indnkeyatts = 1
      and index_definition.indkey::text = column_definition.attnum::text
  ) then
    raise exception 'A unicidade de profiles.passport não está protegida por índice único.';
  end if;
end;
$$;

comment on column public.patients.emergency_contact_name is
  'Nome opcional do contato de emergência; deve ser informado junto com o telefone.';
comment on column public.patients.emergency_contact_phone is
  'Telefone opcional do contato de emergência no formato (055) 123-456; deve ser informado junto com o nome.';
comment on column public.patients.passport is
  'Passaporte único do paciente, preservado como texto para manter zeros à esquerda.';
comment on column public.profiles.passport is
  'Passaporte único do usuário/profissional, preservado como texto para manter zeros à esquerda.';

notify pgrst, 'reload schema';
