-- Torna opcional apenas o telefone principal do paciente.
-- Quando preenchido, o formato institucional permanece obrigatório.

set lock_timeout = '5s';
set statement_timeout = '120s';

alter table public.patients
  alter column phone drop not null,
  drop constraint if exists patients_phone_check,
  add constraint patients_phone_check
    check (
      phone is null
      or phone ~ '^\(055\) [0-9]{3}-[0-9]{3}$'
    );

comment on column public.patients.phone is
  'Telefone principal opcional; quando informado, usa o formato (055) 123-456.';

notify pgrst, 'reload schema';
