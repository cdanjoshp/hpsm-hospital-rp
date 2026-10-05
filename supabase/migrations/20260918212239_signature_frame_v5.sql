-- Mantém documentos históricos e atualiza somente o enquadramento visual das assinaturas.
-- A versão v5 usa uma moldura menor e centralizada, sem alterar identidade ou conteúdo clínico.

set lock_timeout = '5s';
set statement_timeout = '120s';

alter table public.clinical_exam_documents
  drop constraint clinical_exam_documents_render_version_check;

alter table public.clinical_exam_documents
  add constraint clinical_exam_documents_render_version_check
  check (render_version in (
    'exam-document-png-v1',
    'exam-document-png-v2',
    'exam-document-png-v3',
    'exam-document-png-v4',
    'exam-document-png-v5'
  ));

do $$
declare
  v_function regprocedure;
begin
  foreach v_function in array array[
    'private.clinical_exam_document_state_json(bigint)'::regprocedure,
    'public.register_clinical_exam_document(bigint,uuid,text,bigint,integer,integer,text)'::regprocedure,
    'public.create_clinical_exam_document_share(bigint)'::regprocedure,
    'public.resolve_clinical_exam_document_share(uuid)'::regprocedure,
    'public.patient_portal_register_clinical_exam_document(text,bigint,uuid,text,bigint,integer,integer,text)'::regprocedure,
    'public.patient_portal_create_clinical_exam_document_share(text,bigint)'::regprocedure
  ] loop
    execute replace(pg_get_functiondef(v_function), 'exam-document-png-v4', 'exam-document-png-v5');
  end loop;
end;
$$;

update public.clinical_exam_document_shares share
set revoked_at = clock_timestamp(), revoked_by = share.created_by
from public.clinical_exam_documents document
where share.document_id = document.id
  and share.revoked_at is null
  and share.created_by is not null
  and document.render_version = 'exam-document-png-v4';

delete from public.clinical_exam_document_shares share
using public.clinical_exam_documents document
where share.document_id = document.id
  and share.revoked_at is null
  and share.created_by is null
  and document.render_version = 'exam-document-png-v4';

comment on constraint clinical_exam_documents_render_version_check
on public.clinical_exam_documents is
  'Preserva documentos v1-v4 e aceita a apresentação v5 com assinaturas compactas e centralizadas.';

notify pgrst, 'reload schema';
