-- HPSM Fase 4.8.1 · o link só nasce depois do objeto PNG existir no Storage

create or replace function public.register_clinical_exam_document(
  p_exam_id bigint,
  p_document_id uuid,
  p_storage_path text,
  p_file_size bigint,
  p_pixel_width integer,
  p_pixel_height integer,
  p_render_version text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_exam public.clinical_exams;
  v_document public.clinical_exam_documents;
  v_share public.clinical_exam_document_shares;
  v_inserted_id uuid;
begin
  if not private.has_permission(v_actor, 'exams.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  select exam.* into v_exam
  from public.clinical_exams exam
  where exam.id = p_exam_id
  for update;

  if v_exam.id is null then raise exception 'Exame não localizado.'; end if;
  if v_exam.status <> 'completed' or v_exam.final_report_snapshot is null then
    raise exception 'A imagem compartilhável está disponível somente para exames concluídos.';
  end if;
  if p_document_id is null
     or p_render_version <> 'exam-document-png-v1'
     or p_storage_path <> format('clinical-exams/%s/documents/%s.png', p_exam_id, p_document_id)
     or p_file_size not between 1 and 12582912
     or p_pixel_width not between 900 and 1400
     or p_pixel_height not between 400 and 14000 then
    raise exception 'Metadados inválidos para a imagem do documento.';
  end if;

  if not exists (
    select 1
    from storage.objects object
    where object.bucket_id = 'clinical-exam-documents'
      and object.name = p_storage_path
      and lower(coalesce(object.metadata ->> 'mimetype', '')) = 'image/png'
      and coalesce((object.metadata ->> 'size')::bigint, 0) = p_file_size
  ) then
    raise exception 'A imagem do documento ainda não foi confirmada no Storage.';
  end if;

  insert into public.clinical_exam_documents (
    id, exam_id, storage_path, mime_type, file_size, pixel_width, pixel_height, render_version, created_by
  ) values (
    p_document_id, p_exam_id, p_storage_path, 'image/png', p_file_size, p_pixel_width, p_pixel_height, p_render_version, v_actor
  )
  on conflict (exam_id, render_version) do nothing
  returning id into v_inserted_id;

  select document.* into v_document
  from public.clinical_exam_documents document
  where document.exam_id = p_exam_id
    and document.render_version = p_render_version
  limit 1;

  if v_document.id is null then raise exception 'Não foi possível registrar a imagem do documento.'; end if;

  if v_inserted_id is not null then
    perform private.audit_exam_action(
      v_actor,
      'clinical_exam.document_png_generated',
      'clinical_exam_documents',
      v_document.id::text,
      null,
      jsonb_build_object(
        'exam_id', p_exam_id,
        'render_version', v_document.render_version,
        'file_size', v_document.file_size,
        'pixel_width', v_document.pixel_width,
        'pixel_height', v_document.pixel_height
      )
    );
  end if;

  select share.* into v_share
  from public.clinical_exam_document_shares share
  where share.exam_id = p_exam_id and share.revoked_at is null
  limit 1;

  if v_share.id is null then
    insert into public.clinical_exam_document_shares (exam_id, document_id, created_by)
    values (p_exam_id, v_document.id, v_actor)
    returning * into v_share;

    perform private.audit_exam_action(
      v_actor,
      'clinical_exam.document_link_created',
      'clinical_exam_document_shares',
      v_share.id::text,
      null,
      jsonb_build_object('exam_id', p_exam_id, 'document_id', v_document.id)
    );
  end if;

  return private.clinical_exam_document_state_json(p_exam_id);
end;
$$;

revoke all on function public.register_clinical_exam_document(bigint, uuid, text, bigint, integer, integer, text)
from public, anon, authenticated, service_role;
grant execute on function public.register_clinical_exam_document(bigint, uuid, text, bigint, integer, integer, text)
to authenticated;

notify pgrst, 'reload schema';
