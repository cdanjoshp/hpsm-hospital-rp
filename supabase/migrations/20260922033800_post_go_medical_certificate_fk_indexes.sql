-- HPSM · Pós-GO · Cobertura das FKs de Atestados Médicos

create index medical_certificates_finalized_by_idx
  on public.medical_certificates (finalized_by)
  where finalized_by is not null;

create index medical_certificates_cancelled_by_idx
  on public.medical_certificates (cancelled_by)
  where cancelled_by is not null;

create index medical_certificate_exams_linked_by_idx
  on public.medical_certificate_exams (linked_by);

create index medical_certificate_casts_linked_by_idx
  on public.medical_certificate_casts (linked_by);
