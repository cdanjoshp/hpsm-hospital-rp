-- HP Sul — Fase 2.1: formato único para todos os telefones de pacientes.

alter table public.patients
  drop constraint patients_phone_check,
  drop constraint patients_emergency_contact_phone_check,
  add constraint patients_phone_check
    check (phone ~ '^\([0-9]{3}\) [0-9]{3}-[0-9]{3}$'),
  add constraint patients_emergency_contact_phone_check
    check (emergency_contact_phone ~ '^\([0-9]{3}\) [0-9]{3}-[0-9]{3}$');

comment on column public.patients.phone is
  'Telefone principal no formato obrigatório (055) 123-456.';
comment on column public.patients.emergency_contact_phone is
  'Telefone de emergência no formato obrigatório (055) 123-456.';

notify pgrst, 'reload schema';
