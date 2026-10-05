-- A Diretoria pode remover exames concluídos de teste pelo fluxo auditado.
-- A exclusão de exames em andamento mantém as regras já existentes.

set lock_timeout = '5s';
set statement_timeout = '30s';

update public.system_permissions
set description = 'Exclui exames em andamento; cargos de Diretoria também podem excluir exames concluídos.'
where code = 'exams.delete';

insert into public.staff_position_permissions (position_id, permission_code, granted_by)
select position.id, 'exams.delete',
  coalesce(
    (select profile.user_id from public.profiles profile
      join public.staff_positions director on director.id = profile.position_id
      where profile.status = 'active' and director.official and director.level = 14
      order by profile.created_at, profile.user_id limit 1),
    position.updated_by, position.created_by
  )
from public.staff_positions position
where position.official and position.active and position.level between 12 and 14
on conflict (position_id, permission_code) do nothing;

create or replace function public.delete_clinical_exam(p_exam_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_exam public.clinical_exams;
  v_storage_paths jsonb;
  v_document_storage_paths jsonb;
  v_image_ids text[];
  v_generation_ids text[];
  v_document_ids text[];
  v_share_ids text[];
  v_image_count integer;
  v_generation_count integer;
  v_report_version_count integer;
  v_history_count integer;
  v_document_count integer;
  v_share_count integer;
  v_page_count integer;
  v_certificate_link_count integer;
begin
  if v_actor is null then raise exception 'Sessão inválida.' using errcode = '42501'; end if;
  select * into v_exam from public.clinical_exams where id = p_exam_id for update;
  if v_exam.id is null then raise exception 'Exame não localizado.'; end if;

  if v_exam.status = 'completed' then
    if not private.has_permission(v_actor, 'exams.delete') or not exists (
      select 1 from public.profiles profile
      join public.staff_positions position on position.id = profile.position_id
      where profile.user_id = v_actor and profile.status = 'active'
        and position.official and position.active and position.level between 12 and 14
    ) then
      raise exception 'Somente diretores podem excluir exames concluídos.' using errcode = '42501';
    end if;
  elsif v_exam.responsible_professional_id is distinct from v_actor
    and not private.has_permission(v_actor, 'exams.delete') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(path order by path), '[]'::jsonb) into v_storage_paths
  from (
    select image.storage_path as path from public.clinical_exam_images image where image.exam_id = p_exam_id
    union
    select generation.draft_storage_path as path from public.exam_ai_generations generation
    where generation.exam_id = p_exam_id and generation.draft_storage_path is not null
  ) paths;
  select coalesce(jsonb_agg(document.storage_path order by document.storage_path), '[]'::jsonb)
  into v_document_storage_paths
  from public.clinical_exam_documents document where document.exam_id = p_exam_id;

  select coalesce(array_agg(image.id::text), array[]::text[]), count(*)::integer
  into v_image_ids, v_image_count
  from public.clinical_exam_images image where image.exam_id = p_exam_id;
  select coalesce(array_agg(generation.id::text), array[]::text[]), count(*)::integer
  into v_generation_ids, v_generation_count
  from public.exam_ai_generations generation where generation.exam_id = p_exam_id;
  select coalesce(array_agg(document.id::text), array[]::text[]), count(*)::integer
  into v_document_ids, v_document_count
  from public.clinical_exam_documents document where document.exam_id = p_exam_id;
  select coalesce(array_agg(share.id::text), array[]::text[]), count(*)::integer
  into v_share_ids, v_share_count
  from public.clinical_exam_document_shares share where share.exam_id = p_exam_id;
  select count(*)::integer into v_report_version_count
  from public.clinical_exam_report_versions version where version.exam_id = p_exam_id;
  select count(*)::integer into v_history_count
  from public.clinical_exam_status_history history where history.exam_id = p_exam_id;
  select count(*)::integer into v_page_count
  from public.clinical_exam_page_publications page where page.exam_id = p_exam_id;
  select count(*)::integer into v_certificate_link_count
  from public.medical_certificate_exams link where link.exam_id = p_exam_id;

  delete from public.audit_logs audit
  where (audit.entity_name = 'clinical_exams' and audit.entity_id = p_exam_id::text)
     or (audit.entity_name = 'clinical_exam_images' and audit.entity_id = any(v_image_ids))
     or (audit.entity_name = 'exam_ai_generations' and audit.entity_id = any(v_generation_ids))
     or (audit.entity_name = 'clinical_exam_documents' and audit.entity_id = any(v_document_ids))
     or (audit.entity_name = 'clinical_exam_document_shares' and audit.entity_id = any(v_share_ids));

  -- Os atestados permanecem; apenas a referência ao exame excluído é retirada.
  delete from public.medical_certificate_exams where exam_id = p_exam_id;
  delete from public.clinical_exam_document_shares where exam_id = p_exam_id;
  delete from public.clinical_exam_page_publications where exam_id = p_exam_id;
  delete from public.clinical_exam_documents where exam_id = p_exam_id;
  delete from public.document_media_publications where document_type = 'EXAM' and document_id = p_exam_id;
  delete from public.exam_result_choices where exam_id = p_exam_id;
  delete from public.exam_ai_generations where exam_id = p_exam_id;
  delete from public.clinical_exam_images where exam_id = p_exam_id;
  delete from public.clinical_exam_report_versions where exam_id = p_exam_id;
  delete from public.clinical_exam_status_history where exam_id = p_exam_id;
  delete from public.clinical_exams where id = p_exam_id;

  perform private.audit_exam_action(
    v_actor, 'DELETE', 'clinical_exams', p_exam_id::text,
    jsonb_build_object(
      'status', v_exam.status, 'exam_type_id', v_exam.exam_type_id,
      'patient_id', v_exam.patient_id,
      'responsible_professional_id', v_exam.responsible_professional_id
    ),
    jsonb_build_object(
      'deleted', true, 'images', v_image_count,
      'ai_generations', v_generation_count,
      'report_versions', v_report_version_count,
      'status_events', v_history_count,
      'documents', v_document_count, 'shares', v_share_count,
      'published_pages', v_page_count,
      'certificate_links', v_certificate_link_count
    )
  );
  return jsonb_build_object(
    'exam_id', p_exam_id,
    'storage_paths', v_storage_paths,
    'document_storage_paths', v_document_storage_paths
  );
end;
$$;

revoke all on function public.delete_clinical_exam(bigint) from public, anon, authenticated, service_role;
grant execute on function public.delete_clinical_exam(bigint) to authenticated;

comment on function public.delete_clinical_exam(bigint) is
  'Exclusão auditada de exames em andamento pelo responsável ou permissão; concluídos exigem permissão exams.delete e cargo oficial de Diretoria (12 a 14).';
