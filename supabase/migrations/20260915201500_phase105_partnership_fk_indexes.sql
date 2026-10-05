-- HPSM — Fase 10.5
-- Índices de cobertura para todas as chaves estrangeiras introduzidas pelo
-- módulo de Parcerias. Além de manter exclusões/atualizações previsíveis em
-- escala, estes índices eliminam varreduras integrais nas trilhas de auditoria.

create index if not exists partnerships_responsible_assigned_by_idx
  on public.partnerships (responsible_assigned_by)
  where responsible_assigned_by is not null;

create index if not exists partnerships_created_by_idx
  on public.partnerships (created_by);

create index if not exists partnerships_updated_by_idx
  on public.partnerships (updated_by);

create index if not exists partnerships_deactivated_by_idx
  on public.partnerships (deactivated_by)
  where deactivated_by is not null;

create index if not exists partnership_responsible_history_previous_patient_idx
  on public.partnership_responsible_history (previous_patient_id)
  where previous_patient_id is not null;

create index if not exists partnership_responsible_history_responsible_patient_idx
  on public.partnership_responsible_history (responsible_patient_id)
  where responsible_patient_id is not null;

create index if not exists partnership_responsible_history_changed_by_idx
  on public.partnership_responsible_history (changed_by);

create index if not exists partnership_status_history_changed_by_idx
  on public.partnership_status_history (changed_by);

create index if not exists patient_partnerships_linked_by_user_idx
  on public.patient_partnerships (linked_by_user_id)
  where linked_by_user_id is not null;

create index if not exists patient_partnerships_linked_by_patient_idx
  on public.patient_partnerships (linked_by_patient_id)
  where linked_by_patient_id is not null;

create index if not exists patient_partnerships_unlinked_by_user_idx
  on public.patient_partnerships (unlinked_by_user_id)
  where unlinked_by_user_id is not null;

create index if not exists patient_partnerships_unlinked_by_patient_idx
  on public.patient_partnerships (unlinked_by_patient_id)
  where unlinked_by_patient_id is not null;

create index if not exists partnership_pending_created_by_user_idx
  on public.partnership_pending_beneficiaries (created_by_user_id)
  where created_by_user_id is not null;

create index if not exists partnership_pending_created_by_patient_idx
  on public.partnership_pending_beneficiaries (created_by_patient_id)
  where created_by_patient_id is not null;

create index if not exists partnership_pending_resolved_patient_idx
  on public.partnership_pending_beneficiaries (resolved_patient_id)
  where resolved_patient_id is not null;

create index if not exists partnership_pending_canceled_by_user_idx
  on public.partnership_pending_beneficiaries (canceled_by_user_id)
  where canceled_by_user_id is not null;

create index if not exists partnership_pending_canceled_by_patient_idx
  on public.partnership_pending_beneficiaries (canceled_by_patient_id)
  where canceled_by_patient_id is not null;
