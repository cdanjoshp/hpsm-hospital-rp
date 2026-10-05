alter table public.attendances
  drop constraint attendances_patient_passport_check;

alter table public.attendances
  add constraint attendances_patient_passport_check
  check (
    (patient_id is null and patient_passport = '—')
    or (patient_id is not null and patient_passport ~ '^[0-9]{1,4}$')
  );
