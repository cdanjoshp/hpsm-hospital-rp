-- Índices de suporte às chaves estrangeiras do prontuário PNG.
create index consultation_documents_created_by_idx
  on public.consultation_documents (created_by);

create index consultation_document_shares_created_by_idx
  on public.consultation_document_shares (created_by);

create index consultation_document_shares_revoked_by_idx
  on public.consultation_document_shares (revoked_by)
  where revoked_by is not null;
