-- HPSM - passaportes sao identificadores numericos de ate quatro digitos.
-- Zeros a esquerda continuam preservados porque as colunas permanecem text.

do $$
begin
  if exists (select 1 from public.profiles where passport !~ '^[0-9]{1,4}$')
    or exists (select 1 from public.patients where passport !~ '^[0-9]{1,4}$')
    or exists (select 1 from public.recruitment_applications where passport !~ '^[0-9]{1,4}$')
    or exists (select 1 from public.attendances where patient_passport !~ '^[0-9]{1,4}$')
    or exists (
      select 1 from public.audit_logs
      where actor_passport is not null and actor_passport !~ '^[0-9]{1,4}$'
    ) then
    raise exception 'Existem passaportes incompatíveis com o padrão numérico de até quatro dígitos.';
  end if;
end;
$$;

alter table public.profiles
  drop constraint if exists profiles_passport_format;
alter table public.profiles
  add constraint profiles_passport_format
  check (passport ~ '^[0-9]{1,4}$') not valid;

alter table public.patients
  drop constraint if exists patients_passport_check;
alter table public.patients
  add constraint patients_passport_check
  check (passport ~ '^[0-9]{1,4}$') not valid;

alter table public.recruitment_applications
  drop constraint if exists recruitment_passport_format;
alter table public.recruitment_applications
  add constraint recruitment_passport_format
  check (passport ~ '^[0-9]{1,4}$') not valid;

alter table public.attendances
  drop constraint if exists attendances_patient_passport_check;
alter table public.attendances
  add constraint attendances_patient_passport_check
  check (patient_passport ~ '^[0-9]{1,4}$') not valid;

alter table public.audit_logs
  drop constraint if exists audit_logs_actor_passport_format;
alter table public.audit_logs
  add constraint audit_logs_actor_passport_format
  check (actor_passport is null or actor_passport ~ '^[0-9]{1,4}$') not valid;

alter table public.profiles validate constraint profiles_passport_format;
alter table public.patients validate constraint patients_passport_check;
alter table public.recruitment_applications validate constraint recruitment_passport_format;
alter table public.attendances validate constraint attendances_patient_passport_check;
alter table public.audit_logs validate constraint audit_logs_actor_passport_format;

comment on column public.profiles.passport is
  'Identificador numerico de um a quatro digitos. Zeros a esquerda sao preservados.';
comment on column public.patients.passport is
  'Passaporte numerico do personagem, limitado a quatro digitos.';

notify pgrst, 'reload schema';
