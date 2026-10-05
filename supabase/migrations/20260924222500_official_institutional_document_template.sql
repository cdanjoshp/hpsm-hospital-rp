-- HPSM · template institucional oficial único para laudos, atestados, receitas e prontuários.
-- As versões anteriores permanecem privadas; novas emissões usam a apresentação paginada.

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
    'exam-document-png-v5',
    'exam-document-png-v6'
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
    execute replace(pg_get_functiondef(v_function), 'exam-document-png-v5', 'exam-document-png-v6');
  end loop;
end;
$$;

update public.clinical_exam_document_shares share
set revoked_at = clock_timestamp(), revoked_by = share.created_by
from public.clinical_exam_documents document
where share.document_id = document.id
  and share.revoked_at is null
  and share.created_by is not null
  and document.render_version = 'exam-document-png-v5';

delete from public.clinical_exam_document_shares share
using public.clinical_exam_documents document
where share.document_id = document.id
  and share.revoked_at is null
  and share.created_by is null
  and document.render_version = 'exam-document-png-v5';

alter table public.consultation_documents
  drop constraint consultation_documents_state_check;

alter table public.consultation_documents
  add constraint consultation_documents_state_check check (
    (status = 'pending' and storage_path is null and mime_type is null and file_size is null
      and pixel_width is null and pixel_height is null and render_version is null and completed_at is null)
    or
    (status = 'completed' and storage_path is not null and mime_type = 'image/png'
      and file_size between 32 and 12582912 and pixel_width between 900 and 1400
      and pixel_height between 400 and 14000 and render_version in (
        'consultation-document-png-v1', 'consultation-document-png-v2', 'consultation-document-png-v3'
      )
      and completed_at is not null)
  );

-- A relação possui uma linha por consulta/prescrição. Remover o metadado antigo
-- faz a próxima abertura criar um novo UUID e impede a reutilização do layout anterior.
delete from public.consultation_documents
where render_version is distinct from 'consultation-document-png-v3';

delete from public.prescription_documents
where render_version is distinct from 'prescription-document-png-v2';

update public.medical_certificates
set final_png_path = null,
    final_png_file_size = null,
    final_png_width = null,
    final_png_height = null,
    final_png_render_version = null
where final_png_render_version is distinct from 'medical-certificate-png-v3';

do $$
declare
  v_definition text;
begin
  v_definition := pg_get_functiondef('public.complete_consultation_document(bigint,uuid,text,integer,integer,integer,text)'::regprocedure);
  execute replace(v_definition, 'consultation-document-png-v2', 'consultation-document-png-v3');

  v_definition := pg_get_functiondef('public.complete_prescription_document(bigint,uuid,text,integer,integer,integer,text)'::regprocedure);
  execute replace(v_definition, 'prescription-document-png-v1', 'prescription-document-png-v2');

  v_definition := pg_get_functiondef('public.register_medical_certificate_document(bigint,text,integer,integer,integer,text)'::regprocedure);
  execute replace(
    v_definition,
    'or nullif(btrim(p_render_version), '''') is null',
    'or p_render_version <> ''medical-certificate-png-v3'''
  );

  v_definition := pg_get_functiondef('public.patient_portal_register_medical_certificate_document(text,bigint,text,integer,integer,integer,text)'::regprocedure);
  execute replace(
    v_definition,
    'or nullif(btrim(p_render_version), '''') is null',
    'or p_render_version <> ''medical-certificate-png-v3'''
  );
end;
$$;

comment on constraint clinical_exam_documents_render_version_check
on public.clinical_exam_documents is
  'Preserva laudos v1-v5 e aceita v6 no template institucional oficial paginado.';

comment on constraint consultation_documents_state_check
on public.consultation_documents is
  'Prontuário concluído usa exclusivamente o template institucional oficial v3.';

notify pgrst, 'reload schema';
