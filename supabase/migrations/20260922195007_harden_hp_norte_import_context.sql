-- Endurece o contexto transitório usado exclusivamente pelo importador privado HP Norte.
-- A importação concluída permanece auditável; não há exposição pela Data API.

set lock_timeout = '5s';
set statement_timeout = '30s';

alter table private.hp_norte_import_context enable row level security;
alter table private.hp_norte_import_context force row level security;

revoke all on private.hp_norte_import_context from public, anon, authenticated, service_role;

create index if not exists hp_norte_import_context_batch_idx
  on private.hp_norte_import_context (batch_id);

create index if not exists legacy_import_batches_executed_by_idx
  on public.legacy_import_batches (executed_by)
  where executed_by is not null;

create index if not exists legacy_import_conflicts_resolved_by_idx
  on public.legacy_import_conflicts (resolved_by)
  where resolved_by is not null;

comment on table private.hp_norte_import_context is
  'Contexto transitório do importador HP Norte; sem acesso direto e protegido por RLS deny-all.';
