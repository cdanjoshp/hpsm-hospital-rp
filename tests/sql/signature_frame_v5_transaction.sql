begin;

do $$
declare
  v_definition text;
  v_function regprocedure;
begin
  select pg_get_constraintdef(constraint_row.oid)
  into v_definition
  from pg_constraint constraint_row
  where constraint_row.conrelid = 'public.clinical_exam_documents'::regclass
    and constraint_row.conname = 'clinical_exam_documents_render_version_check';

  if v_definition is null or position('exam-document-png-v5' in v_definition) = 0 then
    raise exception 'A apresentação v5 não está autorizada no banco.';
  end if;

  foreach v_function in array array[
    'private.clinical_exam_document_state_json(bigint)'::regprocedure,
    'public.register_clinical_exam_document(bigint,uuid,text,bigint,integer,integer,text)'::regprocedure,
    'public.create_clinical_exam_document_share(bigint)'::regprocedure,
    'public.resolve_clinical_exam_document_share(uuid)'::regprocedure,
    'public.patient_portal_register_clinical_exam_document(text,bigint,uuid,text,bigint,integer,integer,text)'::regprocedure,
    'public.patient_portal_create_clinical_exam_document_share(text,bigint)'::regprocedure
  ] loop
    if position('exam-document-png-v5' in pg_get_functiondef(v_function)) = 0 then
      raise exception 'A função % não usa a apresentação v5.', v_function;
    end if;
  end loop;
end;
$$;

rollback;

select jsonb_build_object(
  'feature', 'signature_frame_v5',
  'constraint_accepts_v5', true,
  'document_functions_use_v5', true,
  'clinical_content_changed', false,
  'residue', false
) as result;
