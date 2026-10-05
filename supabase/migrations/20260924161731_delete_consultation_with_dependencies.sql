-- HPSM · Exclusão excepcional de consultas pela Diretoria
-- Remove atomicamente a consulta e todos os registros clínicos produzidos por ela.

insert into public.system_permissions (code, module, label, description, sort_order)
values (
  'consultations.delete',
  'Consultas e Agendamentos',
  'Excluir consultas',
  'Exclui permanentemente uma consulta e todas as dependências clínicas geradas por ela.',
  58
)
on conflict (code) do update set
  module = excluded.module,
  label = excluded.label,
  description = excluded.description,
  sort_order = excluded.sort_order;

insert into public.staff_position_permissions (position_id, permission_code, granted_by)
select
  position.id,
  'consultations.delete',
  coalesce(
    (
      select profile.user_id
      from public.profiles profile
      join public.staff_positions actor_position on actor_position.id = profile.position_id
      where profile.status = 'active'
        and actor_position.official
        and actor_position.level = 14
      order by profile.created_at, profile.user_id
      limit 1
    ),
    position.updated_by,
    position.created_by
  )
from public.staff_positions position
where position.official
  and position.active
  and position.level in (13, 14)
on conflict (position_id, permission_code) do update
set granted_by = excluded.granted_by,
    granted_at = now();

delete from public.staff_position_permissions grant_row
using public.staff_positions position
where grant_row.position_id = position.id
  and grant_row.permission_code = 'consultations.delete'
  and not (position.official and position.active and position.level in (13, 14));

create or replace function private.guard_completed_consultation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if current_setting('hpsm.consultation_delete_id', true) = old.id::text then
      return old;
    end if;
    raise exception 'Consultas clínicas não podem ser excluídas fora do fluxo protegido.' using errcode = '42501';
  end if;
  if old.status = 'completed' and new is distinct from old then
    raise exception 'Uma consulta concluída é imutável.' using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke all on function private.guard_completed_consultation()
from public, anon, authenticated, service_role;

create or replace function public.delete_clinical_consultation(p_consultation_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_actor_passport text;
  v_consultation public.clinical_consultations;
  v_exam_ids bigint[] := array[]::bigint[];
  v_cast_ids bigint[] := array[]::bigint[];
  v_hospitalization_ids bigint[] := array[]::bigint[];
  v_certificate_ids bigint[] := array[]::bigint[];
  v_consultation_generation_ids bigint[] := array[]::bigint[];
  v_exam_image_ids uuid[] := array[]::uuid[];
  v_exam_generation_ids uuid[] := array[]::uuid[];
  v_exam_document_ids uuid[] := array[]::uuid[];
  v_exam_share_ids uuid[] := array[]::uuid[];
  v_deleted_follow_up_ids bigint[] := array[]::bigint[];
  v_preserved_follow_up_ids bigint[] := array[]::bigint[];
  v_exam_image_paths jsonb := '[]'::jsonb;
  v_clinical_document_paths jsonb := '[]'::jsonb;
begin
  if p_consultation_id is null or p_consultation_id < 1 then
    raise exception 'Consulta inválida.';
  end if;

  if not private.has_permission(v_actor, 'consultations.delete') or not exists (
    select 1
    from public.profiles profile
    join public.staff_positions position on position.id = profile.position_id
    where profile.user_id = v_actor
      and profile.status = 'active'
      and position.official
      and position.active
      and position.level in (13, 14)
  ) then
    raise exception 'A exclusão de consultas é exclusiva dos cargos de Diretoria.' using errcode = '42501';
  end if;

  select profile.passport into v_actor_passport
  from public.profiles profile
  where profile.user_id = v_actor and profile.status = 'active';

  select * into v_consultation
  from public.clinical_consultations consultation
  where consultation.id = p_consultation_id
  for update;

  if v_consultation.id is null then
    raise exception 'Consulta não localizada.';
  end if;

  perform exam.id from public.clinical_exams exam
  where exam.consultation_id = p_consultation_id for update;
  perform cast_record.id from public.clinical_casts cast_record
  where cast_record.consultation_id = p_consultation_id for update;
  perform hospitalization.id from public.hospitalizations hospitalization
  where hospitalization.consultation_id = p_consultation_id for update;
  perform certificate.id from public.medical_certificates certificate
  where certificate.consultation_id = p_consultation_id for update;
  perform appointment.id from public.patient_appointments appointment
  where appointment.follow_up_of_consultation_id = p_consultation_id for update;
  if v_consultation.appointment_id is not null then
    perform appointment.id from public.patient_appointments appointment
    where appointment.id = v_consultation.appointment_id for update;
  end if;

  select coalesce(array_agg(exam.id order by exam.id), array[]::bigint[])
  into v_exam_ids
  from public.clinical_exams exam
  where exam.consultation_id = p_consultation_id;

  select coalesce(array_agg(cast_record.id order by cast_record.id), array[]::bigint[])
  into v_cast_ids
  from public.clinical_casts cast_record
  where cast_record.consultation_id = p_consultation_id;

  select coalesce(array_agg(hospitalization.id order by hospitalization.id), array[]::bigint[])
  into v_hospitalization_ids
  from public.hospitalizations hospitalization
  where hospitalization.consultation_id = p_consultation_id;

  select coalesce(array_agg(certificate.id order by certificate.id), array[]::bigint[])
  into v_certificate_ids
  from public.medical_certificates certificate
  where certificate.consultation_id = p_consultation_id;

  select coalesce(array_agg(generation.id order by generation.id), array[]::bigint[])
  into v_consultation_generation_ids
  from public.consultation_ai_generations generation
  where generation.consultation_id = p_consultation_id;

  select coalesce(array_agg(image.id order by image.id), array[]::uuid[])
  into v_exam_image_ids
  from public.clinical_exam_images image
  where image.exam_id = any(v_exam_ids);

  select coalesce(array_agg(generation.id order by generation.id), array[]::uuid[])
  into v_exam_generation_ids
  from public.exam_ai_generations generation
  where generation.exam_id = any(v_exam_ids);

  select coalesce(array_agg(document.id order by document.id), array[]::uuid[])
  into v_exam_document_ids
  from public.clinical_exam_documents document
  where document.exam_id = any(v_exam_ids);

  select coalesce(array_agg(share.id order by share.id), array[]::uuid[])
  into v_exam_share_ids
  from public.clinical_exam_document_shares share
  where share.exam_id = any(v_exam_ids);

  select
    coalesce(array_agg(appointment.id order by appointment.id) filter (where child_consultation.id is null), array[]::bigint[]),
    coalesce(array_agg(appointment.id order by appointment.id) filter (where child_consultation.id is not null), array[]::bigint[])
  into v_deleted_follow_up_ids, v_preserved_follow_up_ids
  from public.patient_appointments appointment
  left join public.clinical_consultations child_consultation on child_consultation.appointment_id = appointment.id
  where appointment.follow_up_of_consultation_id = p_consultation_id;

  select coalesce(jsonb_agg(path order by path), '[]'::jsonb)
  into v_exam_image_paths
  from (
    select image.storage_path as path
    from public.clinical_exam_images image
    where image.exam_id = any(v_exam_ids)
    union
    select generation.draft_storage_path as path
    from public.exam_ai_generations generation
    where generation.exam_id = any(v_exam_ids)
      and generation.draft_storage_path is not null
  ) stored_paths;

  select coalesce(jsonb_agg(path order by path), '[]'::jsonb)
  into v_clinical_document_paths
  from (
    select document.storage_path as path
    from public.clinical_exam_documents document
    where document.exam_id = any(v_exam_ids)
    union
    select certificate.final_png_path as path
    from public.medical_certificates certificate
    where certificate.id = any(v_certificate_ids)
      and certificate.final_png_path is not null
  ) stored_paths;

  delete from public.medical_certificate_exams link
  where link.certificate_id = any(v_certificate_ids)
     or link.exam_id = any(v_exam_ids);

  delete from public.medical_certificate_casts link
  where link.certificate_id = any(v_certificate_ids)
     or link.cast_id = any(v_cast_ids);

  delete from public.medical_certificates certificate
  where certificate.id = any(v_certificate_ids);

  delete from public.clinical_exam_document_shares share
  where share.exam_id = any(v_exam_ids);
  delete from public.clinical_exam_documents document
  where document.exam_id = any(v_exam_ids);
  delete from public.exam_ai_generations generation
  where generation.exam_id = any(v_exam_ids);
  delete from public.clinical_exam_images image
  where image.exam_id = any(v_exam_ids);
  delete from public.clinical_exam_report_versions version
  where version.exam_id = any(v_exam_ids);
  delete from public.clinical_exam_status_history history
  where history.exam_id = any(v_exam_ids);
  delete from public.clinical_exams exam
  where exam.id = any(v_exam_ids);

  delete from public.clinical_casts cast_record
  where cast_record.id = any(v_cast_ids);
  delete from public.hospitalizations hospitalization
  where hospitalization.id = any(v_hospitalization_ids);
  delete from public.consultation_ai_generations generation
  where generation.id = any(v_consultation_generation_ids);

  update public.patient_appointments appointment
  set follow_up_of_consultation_id = null
  where appointment.id = any(v_preserved_follow_up_ids);

  delete from public.patient_appointments appointment
  where appointment.id = any(v_deleted_follow_up_ids);

  perform set_config('hpsm.consultation_delete_id', p_consultation_id::text, true);
  delete from public.clinical_consultations consultation
  where consultation.id = p_consultation_id;

  if v_consultation.appointment_id is not null then
    delete from public.patient_appointments appointment
    where appointment.id = v_consultation.appointment_id;
  end if;

  delete from public.audit_logs audit
  where (audit.entity_name = 'clinical_consultations' and audit.entity_id = p_consultation_id::text)
     or (audit.entity_name = 'patient_appointments' and (
       audit.entity_id = coalesce(v_consultation.appointment_id::text, '')
       or audit.entity_id = any(v_deleted_follow_up_ids::text[])
     ))
     or (audit.entity_name = 'consultation_ai_generations' and audit.entity_id = any(v_consultation_generation_ids::text[]))
     or (audit.entity_name = 'clinical_exams' and audit.entity_id = any(v_exam_ids::text[]))
     or (audit.entity_name = 'clinical_exam_images' and audit.entity_id = any(v_exam_image_ids::text[]))
     or (audit.entity_name = 'exam_ai_generations' and audit.entity_id = any(v_exam_generation_ids::text[]))
     or (audit.entity_name = 'clinical_exam_documents' and audit.entity_id = any(v_exam_document_ids::text[]))
     or (audit.entity_name = 'clinical_exam_document_shares' and audit.entity_id = any(v_exam_share_ids::text[]))
     or (audit.entity_name = 'medical_certificates' and audit.entity_id = any(v_certificate_ids::text[]))
     or (audit.entity_name = 'clinical_casts' and audit.entity_id = any(v_cast_ids::text[]))
     or (audit.entity_name = 'hospitalizations' and audit.entity_id = any(v_hospitalization_ids::text[]));

  insert into public.audit_logs (
    actor_user_id,
    actor_passport,
    action,
    entity_name,
    entity_id,
    old_values,
    new_values
  ) values (
    v_actor,
    v_actor_passport,
    'DELETE',
    'clinical_consultations',
    p_consultation_id::text,
    jsonb_build_object(
      'patient_id', v_consultation.patient_id,
      'professional_id', v_consultation.professional_id,
      'appointment_id', v_consultation.appointment_id,
      'status', v_consultation.status,
      'started_at', v_consultation.started_at,
      'completed_at', v_consultation.completed_at
    ),
    jsonb_build_object(
      'deleted', true,
      'exams', cardinality(v_exam_ids),
      'casts', cardinality(v_cast_ids),
      'hospitalizations', cardinality(v_hospitalization_ids),
      'medical_certificates', cardinality(v_certificate_ids),
      'ai_generations', cardinality(v_consultation_generation_ids),
      'source_appointment_deleted', v_consultation.appointment_id is not null,
      'pending_follow_ups_deleted', cardinality(v_deleted_follow_up_ids),
      'started_follow_ups_preserved', cardinality(v_preserved_follow_up_ids)
    )
  );

  return jsonb_build_object(
    'consultation_id', p_consultation_id,
    'source_appointment_deleted', v_consultation.appointment_id is not null,
    'deleted', jsonb_build_object(
      'exams', cardinality(v_exam_ids),
      'casts', cardinality(v_cast_ids),
      'hospitalizations', cardinality(v_hospitalization_ids),
      'medical_certificates', cardinality(v_certificate_ids),
      'ai_generations', cardinality(v_consultation_generation_ids),
      'pending_follow_ups', cardinality(v_deleted_follow_up_ids)
    ),
    'preserved_started_follow_ups', cardinality(v_preserved_follow_up_ids),
    'storage', jsonb_build_object(
      'clinical_exam_images', v_exam_image_paths,
      'clinical_exam_documents', v_clinical_document_paths
    )
  );
end;
$$;

revoke all on function public.delete_clinical_consultation(bigint)
from public, anon, authenticated, service_role;
grant execute on function public.delete_clinical_consultation(bigint) to authenticated;

comment on function public.delete_clinical_consultation(bigint) is
  'Exclusão transacional restrita aos níveis oficiais 13–14; remove a consulta e dependências clínicas e devolve paths privados para limpeza pela Edge Function.';
