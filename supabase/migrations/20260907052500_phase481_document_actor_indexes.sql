-- HPSM Fase 4.8.1 · índices das referências de autoria do documento PNG

create index clinical_exam_documents_created_by_idx
on public.clinical_exam_documents (created_by);

create index clinical_exam_document_shares_created_by_idx
on public.clinical_exam_document_shares (created_by);

create index clinical_exam_document_shares_revoked_by_idx
on public.clinical_exam_document_shares (revoked_by)
where revoked_by is not null;
