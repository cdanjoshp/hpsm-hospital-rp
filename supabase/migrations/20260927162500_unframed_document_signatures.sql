-- Assinaturas sem moldura nem corte, com fundo transparente no documento.
-- Os snapshots clínicos e as imagens antigas permanecem preservados.
set lock_timeout = '5s';
set statement_timeout = '120s';

alter table public.clinical_exam_documents drop constraint clinical_exam_documents_render_version_check;
alter table public.clinical_exam_documents add constraint clinical_exam_documents_render_version_check
  check (render_version in (
    'exam-document-png-v1', 'exam-document-png-v2', 'exam-document-png-v3',
    'exam-document-png-v4', 'exam-document-png-v5', 'exam-document-png-v6',
    'exam-document-png-v7', 'exam-document-png-v8'
  ));

alter table public.consultation_documents drop constraint consultation_documents_state_check;
alter table public.consultation_documents add constraint consultation_documents_state_check check (
  (status = 'pending' and storage_path is null and mime_type is null and file_size is null
    and pixel_width is null and pixel_height is null and render_version is null and completed_at is null)
  or
  (status = 'completed' and storage_path is not null and mime_type = 'image/png'
    and file_size between 32 and 12582912 and pixel_width between 900 and 1400
    and pixel_height between 400 and 14000 and render_version in (
      'consultation-document-png-v1', 'consultation-document-png-v2',
      'consultation-document-png-v3', 'consultation-document-png-v4', 'consultation-document-png-v5'
    ) and completed_at is not null)
);

do $$
declare
  v_function regprocedure;
  v_old_version text;
  v_new_version text;
  v_definition text;
begin
  for v_function, v_old_version, v_new_version in
    select * from (values
      ('private.clinical_exam_document_state_json(bigint)'::regprocedure, 'exam-document-png-v7', 'exam-document-png-v8'),
      ('public.register_clinical_exam_document(bigint,uuid,text,bigint,integer,integer,text)'::regprocedure, 'exam-document-png-v7', 'exam-document-png-v8'),
      ('public.create_clinical_exam_document_share(bigint)'::regprocedure, 'exam-document-png-v7', 'exam-document-png-v8'),
      ('public.patient_portal_register_clinical_exam_document(text,bigint,uuid,text,bigint,integer,integer,text)'::regprocedure, 'exam-document-png-v7', 'exam-document-png-v8'),
      ('public.patient_portal_create_clinical_exam_document_share(text,bigint)'::regprocedure, 'exam-document-png-v7', 'exam-document-png-v8'),
      ('public.complete_consultation_document(bigint,uuid,text,integer,integer,integer,text)'::regprocedure, 'consultation-document-png-v4', 'consultation-document-png-v5'),
      ('public.complete_prescription_document(bigint,uuid,text,integer,integer,integer,text)'::regprocedure, 'prescription-document-png-v3', 'prescription-document-png-v4'),
      ('public.register_medical_certificate_document(bigint,text,integer,integer,integer,text)'::regprocedure, 'medical-certificate-png-v4', 'medical-certificate-png-v5'),
      ('public.patient_portal_register_medical_certificate_document(text,bigint,text,integer,integer,integer,text)'::regprocedure, 'medical-certificate-png-v4', 'medical-certificate-png-v5')
    ) as versions(function_name, old_version, new_version)
  loop
    v_definition := pg_get_functiondef(v_function);
    if position(v_old_version in v_definition) = 0 then
      raise exception 'Versão esperada ausente em %.', v_function;
    end if;
    execute replace(v_definition, v_old_version, v_new_version);
  end loop;

  -- Links já compartilhados continuam servindo o documento histórico;
  -- os novos links aceitam a versão atual sem revogar os anteriores.
  v_definition := pg_get_functiondef('public.resolve_clinical_exam_document_share(uuid)'::regprocedure);
  if position('document.render_version = ''exam-document-png-v7''' in v_definition) = 0 then
    raise exception 'Validador do link de exame foi alterado.';
  end if;
  execute replace(v_definition,
    'document.render_version = ''exam-document-png-v7''',
    'document.render_version in (''exam-document-png-v7'', ''exam-document-png-v8'')');
end;
$$;

-- Próxima emissão refaz os PNGs mantendo os registros e as fontes originais.
update public.consultation_documents
set status = 'pending', storage_path = null, mime_type = null, file_size = null,
    pixel_width = null, pixel_height = null, render_version = null, completed_at = null
where status = 'completed' and render_version = 'consultation-document-png-v4';

update public.prescription_documents
set status = 'pending', storage_path = null, mime_type = null, file_size = null,
    pixel_width = null, pixel_height = null, render_version = null, completed_at = null
where status = 'completed' and render_version = 'prescription-document-png-v3';

update public.medical_certificates
set final_png_path = null, final_png_file_size = null, final_png_width = null,
    final_png_height = null, final_png_render_version = null
where final_png_render_version = 'medical-certificate-png-v4';

notify pgrst, 'reload schema';
