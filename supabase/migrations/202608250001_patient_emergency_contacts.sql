-- HP Sul — Fase 2.1: contatos obrigatórios e busca incremental de pacientes.

alter table public.patients
  alter column phone set not null,
  add column emergency_contact_name text not null
    constraint patients_emergency_contact_name_check
    check (char_length(btrim(emergency_contact_name)) between 2 and 100),
  add column emergency_contact_phone text not null
    constraint patients_emergency_contact_phone_check
    check (char_length(btrim(emergency_contact_phone)) between 3 and 24);

create index patients_passport_prefix_idx
  on public.patients (passport text_pattern_ops);

comment on column public.patients.phone is
  'Telefone principal de contato do paciente.';
comment on column public.patients.emergency_contact_name is
  'Nome completo do contato de emergência.';
comment on column public.patients.emergency_contact_phone is
  'Telefone do contato de emergência.';

notify pgrst, 'reload schema';
