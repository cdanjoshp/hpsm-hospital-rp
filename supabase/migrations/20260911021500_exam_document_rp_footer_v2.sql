-- Atualiza somente a versão de apresentação do documento final.
-- O snapshot clínico aprovado e as imagens originais permanecem imutáveis.

alter table public.clinical_exam_documents
  drop constraint clinical_exam_documents_render_version_check;

alter table public.clinical_exam_documents
  add constraint clinical_exam_documents_render_version_check
  check (render_version in ('exam-document-png-v1', 'exam-document-png-v2'));

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
    execute replace(
      pg_get_functiondef(v_function),
      'exam-document-png-v1',
      'exam-document-png-v2'
    );
  end loop;
end;
$$;

-- Links da apresentação anterior deixam de servir o documento desatualizado.
-- Uma nova segunda via v2 será criada sob demanda a partir do mesmo snapshot aprovado.
update public.clinical_exam_document_shares share
set revoked_at = clock_timestamp(),
    revoked_by = share.created_by
from public.clinical_exam_documents document
where share.document_id = document.id
  and share.revoked_at is null
  and share.created_by is not null
  and document.render_version = 'exam-document-png-v1';

-- Links emitidos pelo Portal não possuem ator profissional apto a preencher
-- revoked_by; removê-los invalida somente o token público, não o documento.
delete from public.clinical_exam_document_shares share
using public.clinical_exam_documents document
where share.document_id = document.id
  and share.revoked_at is null
  and share.created_by is null
  and document.render_version = 'exam-document-png-v1';

comment on constraint clinical_exam_documents_render_version_check
on public.clinical_exam_documents is
  'Preserva documentos históricos v1 e aceita a apresentação canônica v2 com rodapé exclusivo de RP e sem selo de IA.';
