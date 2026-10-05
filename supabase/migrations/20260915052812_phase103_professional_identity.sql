-- HPSM Fase 10.3: identidade profissional institucional.
-- CRM imutavel, assinatura/rubrica privadas, geracao idempotente e auditoria semantica.

create table public.professional_identities (
  user_id uuid primary key references public.profiles(user_id) on update cascade on delete cascade,
  crm_code text not null unique,
  registration_date date not null,
  signature_image_path text,
  rubric_image_path text,
  signature_file_size integer,
  rubric_file_size integer,
  signature_generated_at timestamptz,
  signature_generated_by uuid references public.profiles(user_id) on update cascade on delete set null,
  signature_regenerated_at timestamptz,
  signature_regenerated_by uuid references public.profiles(user_id) on update cascade on delete set null,
  signature_regeneration_reason text,
  identity_locked boolean not null default true,
  status text not null default 'pending',
  generation_version integer not null default 0,
  current_generation_id uuid,
  generation_operation text,
  generation_started_at timestamptz,
  last_failure_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint professional_identities_crm_format check (crm_code ~ '^[0-9]{8}$'),
  constraint professional_identities_status check (status in ('pending', 'generating', 'active', 'failed')),
  constraint professional_identities_generation_operation check (generation_operation is null or generation_operation in ('initial', 'regenerate', 'reprocess')),
  constraint professional_identities_generation_version check (generation_version >= 0),
  constraint professional_identities_paths check (
    (status = 'active' and signature_image_path is not null and rubric_image_path is not null and signature_file_size is not null and rubric_file_size is not null)
    or status <> 'active'
  ),
  constraint professional_identities_signature_size check (signature_file_size is null or signature_file_size between 32 and 5242880),
  constraint professional_identities_rubric_size check (rubric_file_size is null or rubric_file_size between 32 and 5242880),
  constraint professional_identities_reason_check check (signature_regeneration_reason is null or char_length(btrim(signature_regeneration_reason)) between 5 and 500),
  constraint professional_identities_failure_code_check check (last_failure_code is null or char_length(last_failure_code) between 1 and 80)
);

create index professional_identities_status_idx
  on public.professional_identities (status, updated_at desc);
create index professional_identities_generated_by_idx
  on public.professional_identities (signature_generated_by)
  where signature_generated_by is not null;
create index professional_identities_regenerated_by_idx
  on public.professional_identities (signature_regenerated_by)
  where signature_regenerated_by is not null;

create or replace function private.hpsm_build_internal_crm(p_passport text, p_registration_date date)
returns text
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_passport is null or p_passport !~ '^[0-9]{1,4}$' or p_registration_date is null then
    raise exception 'Dados insuficientes para gerar o CRM interno.' using errcode = '22023';
  end if;
  return lpad(p_passport, 4, '0') || to_char(p_registration_date, 'DDMM');
end;
$$;

create or replace function private.hpsm_identity_is_director_general(p_actor uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles profile
    join public.staff_positions position on position.id = profile.position_id
    where profile.user_id = p_actor
      and profile.status = 'active'
      and profile.must_change_password = false
      and position.active
      and position.official
      and position.level = 14
  );
$$;

create or replace function private.hpsm_professional_registration_date(p_user_id uuid)
returns date
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select (min(history.effective_at) at time zone 'America/Sao_Paulo')::date
       from public.staff_position_history history
      where history.employee_id = profile.user_id
        and history.event_type = 'initial_assignment'),
    (profile.created_at at time zone 'America/Sao_Paulo')::date
  )
  from public.profiles profile
  where profile.user_id = p_user_id;
$$;

create or replace function private.provision_professional_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_registration_date date := (new.created_at at time zone 'America/Sao_Paulo')::date;
begin
  insert into public.professional_identities (user_id, crm_code, registration_date)
  values (new.user_id, private.hpsm_build_internal_crm(new.passport, v_registration_date), v_registration_date)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

create trigger profiles_provision_professional_identity
after insert on public.profiles
for each row execute function private.provision_professional_identity();

insert into public.professional_identities (user_id, crm_code, registration_date)
select profile.user_id,
       private.hpsm_build_internal_crm(profile.passport, private.hpsm_professional_registration_date(profile.user_id)),
       private.hpsm_professional_registration_date(profile.user_id)
from public.profiles profile
on conflict (user_id) do nothing;

create or replace function public.professional_identity_generation_context(
  p_target_user_id uuid default null,
  p_operation text default 'initial'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_is_director boolean := private.hpsm_identity_is_director_general(v_actor);
  v_target uuid := coalesce(p_target_user_id, v_actor);
  v_result jsonb;
begin
  if p_operation not in ('initial', 'regenerate', 'reprocess', 'status') then
    raise exception 'Operacao de identidade invalida.' using errcode = '22023';
  end if;
  if v_target <> v_actor and not v_is_director then
    raise exception 'Acesso nao autorizado.' using errcode = '42501';
  end if;
  if p_operation in ('regenerate', 'reprocess') and not v_is_director then
    raise exception 'Acesso nao autorizado.' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'actor_id', v_actor,
    'target_user_id', profile.user_id,
    'display_name', profile.display_name,
    'passport', profile.passport,
    'profile_status', profile.status,
    'must_change_password', profile.must_change_password,
    'crm_code', identity.crm_code,
    'registration_date', identity.registration_date,
    'status', identity.status,
    'generation_version', identity.generation_version,
    'signature_image_path', identity.signature_image_path,
    'rubric_image_path', identity.rubric_image_path,
    'is_director_general', v_is_director
  ) into v_result
  from public.profiles profile
  join public.professional_identities identity on identity.user_id = profile.user_id
  where profile.user_id = v_target;

  if v_result is null then
    raise exception 'Profissional nao localizado.' using errcode = 'P0002';
  end if;
  return v_result;
end;
$$;

create or replace function public.begin_professional_identity_generation(
  p_target_user_id uuid,
  p_actor_id uuid,
  p_operation text,
  p_idempotency_key uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_identity public.professional_identities;
  v_is_director boolean := private.hpsm_identity_is_director_general(p_actor_id);
  v_profile public.profiles;
  v_operation text := case when p_operation = 'initial' then 'initial' else p_operation end;
  v_reason text := nullif(btrim(p_reason), '');
begin
  if p_target_user_id is null or p_actor_id is null or p_idempotency_key is null
     or v_operation not in ('initial', 'regenerate', 'reprocess') then
    raise exception 'Solicitacao de identidade invalida.' using errcode = '22023';
  end if;
  select * into v_profile from public.profiles where user_id = p_target_user_id;
  if not found then raise exception 'Profissional nao localizado.' using errcode = 'P0002'; end if;
  if v_profile.status <> 'active' and not v_is_director then
    raise exception 'Acesso nao autorizado.' using errcode = '42501';
  end if;
  if v_profile.must_change_password then
    raise exception 'Conclua a troca obrigatoria de senha antes da identidade.' using errcode = '42501';
  end if;
  if p_actor_id <> p_target_user_id and not v_is_director then
    raise exception 'Acesso nao autorizado.' using errcode = '42501';
  end if;
  if v_operation in ('regenerate', 'reprocess') and not v_is_director then
    raise exception 'Acesso nao autorizado.' using errcode = '42501';
  end if;
  if v_operation in ('regenerate', 'reprocess') and (v_reason is null or char_length(v_reason) not between 5 and 500) then
    raise exception 'Informe o motivo da regeneracao.' using errcode = '22023';
  end if;

  select * into v_identity
  from public.professional_identities
  where user_id = p_target_user_id
  for update;
  if not found then raise exception 'Identidade profissional nao localizada.' using errcode = 'P0002'; end if;

  if v_operation = 'initial' and v_identity.status = 'active' then
    return jsonb_build_object('generation_id', null, 'replayed', true, 'status', 'active');
  end if;
  if v_identity.status = 'generating'
     and v_identity.generation_started_at > now() - interval '5 minutes' then
    return jsonb_build_object('generation_id', v_identity.current_generation_id, 'replayed', true, 'status', 'generating');
  end if;
  if v_operation = 'regenerate' and (v_identity.signature_image_path is null or v_identity.rubric_image_path is null) then
    raise exception 'Use o reprocessamento para uma identidade ainda incompleta.' using errcode = '22023';
  end if;

  update public.professional_identities
  set status = 'generating',
      current_generation_id = p_idempotency_key,
      generation_operation = v_operation,
      generation_started_at = now(),
      signature_regeneration_reason = case when v_operation = 'initial' then signature_regeneration_reason else v_reason end,
      last_failure_code = null,
      updated_at = now()
  where user_id = p_target_user_id;

  return jsonb_build_object(
    'generation_id', p_idempotency_key,
    'replayed', false,
    'status', 'generating',
    'generation_version', v_identity.generation_version
  );
end;
$$;

create or replace function public.complete_professional_identity_generation(
  p_target_user_id uuid,
  p_actor_id uuid,
  p_generation_id uuid,
  p_signature_path text,
  p_signature_file_size integer,
  p_rubric_path text,
  p_rubric_file_size integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_identity public.professional_identities;
  v_actor_passport text;
  v_initial boolean;
  v_now timestamptz := now();
begin
  select * into v_identity from public.professional_identities
  where user_id = p_target_user_id for update;
  if not found or v_identity.status <> 'generating' or v_identity.current_generation_id is distinct from p_generation_id then
    raise exception 'Geracao de identidade nao esta mais ativa.' using errcode = '40001';
  end if;
  if p_signature_path <> format('professionals/%s/%s/signature.png', p_target_user_id, p_generation_id)
     or p_rubric_path <> format('professionals/%s/%s/rubric.png', p_target_user_id, p_generation_id)
     or p_signature_file_size not between 32 and 5242880
     or p_rubric_file_size not between 32 and 5242880 then
    raise exception 'Arquivos de identidade invalidos.' using errcode = '22023';
  end if;

  v_initial := v_identity.generation_version = 0;
  select passport into v_actor_passport from public.profiles where user_id = p_actor_id;

  update public.professional_identities
  set signature_image_path = p_signature_path,
      rubric_image_path = p_rubric_path,
      signature_file_size = p_signature_file_size,
      rubric_file_size = p_rubric_file_size,
      signature_generated_at = coalesce(signature_generated_at, v_now),
      signature_generated_by = coalesce(signature_generated_by, p_actor_id),
      signature_regenerated_at = case when v_initial then signature_regenerated_at else v_now end,
      signature_regenerated_by = case when v_initial then signature_regenerated_by else p_actor_id end,
      signature_regeneration_reason = case when v_initial then signature_regeneration_reason else v_identity.signature_regeneration_reason end,
      identity_locked = true,
      status = 'active',
      generation_version = generation_version + 1,
      current_generation_id = null,
      generation_operation = null,
      generation_started_at = null,
      last_failure_code = null,
      updated_at = v_now
  where user_id = p_target_user_id;

  if v_initial then
    insert into public.audit_logs (actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values)
    values
      (p_actor_id, v_actor_passport, 'IDENTITY_CRM_CREATED', 'professional_identities', p_target_user_id::text, null, jsonb_build_object('crm_code', v_identity.crm_code, 'registration_date', v_identity.registration_date)),
      (p_actor_id, v_actor_passport, 'IDENTITY_SIGNATURE_CREATED', 'professional_identities', p_target_user_id::text, null, jsonb_build_object('generation_version', 1)),
      (p_actor_id, v_actor_passport, 'IDENTITY_RUBRIC_CREATED', 'professional_identities', p_target_user_id::text, null, jsonb_build_object('generation_version', 1));
  else
    insert into public.audit_logs (actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values)
    values
      (p_actor_id, v_actor_passport, 'IDENTITY_SIGNATURE_REGENERATED', 'professional_identities', p_target_user_id::text, jsonb_build_object('generation_version', v_identity.generation_version), jsonb_build_object('generation_version', v_identity.generation_version + 1, 'reason', v_identity.signature_regeneration_reason)),
      (p_actor_id, v_actor_passport, 'IDENTITY_RUBRIC_REGENERATED', 'professional_identities', p_target_user_id::text, jsonb_build_object('generation_version', v_identity.generation_version), jsonb_build_object('generation_version', v_identity.generation_version + 1, 'reason', v_identity.signature_regeneration_reason));
  end if;

  return jsonb_build_object('status', 'active', 'crm_code', v_identity.crm_code, 'generation_version', v_identity.generation_version + 1);
end;
$$;

create or replace function public.fail_professional_identity_generation(
  p_target_user_id uuid,
  p_generation_id uuid,
  p_error_code text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.professional_identities
  set status = case when signature_image_path is not null and rubric_image_path is not null then 'active' else 'failed' end,
      identity_locked = true,
      current_generation_id = null,
      generation_operation = null,
      generation_started_at = null,
      last_failure_code = left(coalesce(nullif(btrim(p_error_code), ''), 'generation_failed'), 80),
      updated_at = now()
  where user_id = p_target_user_id
    and status = 'generating'
    and current_generation_id = p_generation_id;
end;
$$;

create or replace function public.correct_professional_identity_crm(
  p_target_user_id uuid,
  p_registration_date date,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_identity public.professional_identities;
  v_passport text;
  v_actor_passport text;
  v_new_crm text;
  v_reason text := nullif(btrim(p_reason), '');
begin
  if not private.hpsm_identity_is_director_general(v_actor) then
    raise exception 'Acesso nao autorizado.' using errcode = '42501';
  end if;
  if p_registration_date is null or v_reason is null or char_length(v_reason) not between 5 and 500 then
    raise exception 'Informe a data e o motivo da correcao.' using errcode = '22023';
  end if;
  select * into v_identity from public.professional_identities where user_id = p_target_user_id for update;
  if not found then raise exception 'Identidade profissional nao localizada.' using errcode = 'P0002'; end if;
  select passport into v_passport from public.profiles where user_id = p_target_user_id;
  v_new_crm := private.hpsm_build_internal_crm(v_passport, p_registration_date);
  if v_new_crm = v_identity.crm_code and p_registration_date = v_identity.registration_date then
    return jsonb_build_object('crm_code', v_identity.crm_code, 'registration_date', v_identity.registration_date, 'changed', false);
  end if;
  update public.professional_identities
  set crm_code = v_new_crm, registration_date = p_registration_date, updated_at = now()
  where user_id = p_target_user_id;
  select passport into v_actor_passport from public.profiles where user_id = v_actor;
  insert into public.audit_logs (actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values)
  values (v_actor, v_actor_passport, 'IDENTITY_CRM_CORRECTED', 'professional_identities', p_target_user_id::text,
    jsonb_build_object('crm_code', v_identity.crm_code, 'registration_date', v_identity.registration_date),
    jsonb_build_object('crm_code', v_new_crm, 'registration_date', p_registration_date, 'reason', v_reason));
  return jsonb_build_object('crm_code', v_new_crm, 'registration_date', p_registration_date, 'changed', true);
end;
$$;

create or replace function public.unlock_professional_identity_reprocess(
  p_target_user_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_actor_passport text;
  v_reason text := nullif(btrim(p_reason), '');
begin
  if not private.hpsm_identity_is_director_general(v_actor) then
    raise exception 'Acesso nao autorizado.' using errcode = '42501';
  end if;
  if v_reason is null or char_length(v_reason) not between 5 and 500 then
    raise exception 'Informe o motivo do reprocessamento.' using errcode = '22023';
  end if;
  update public.professional_identities
  set identity_locked = false,
      signature_regeneration_reason = v_reason,
      last_failure_code = null,
      updated_at = now()
  where user_id = p_target_user_id;
  if not found then raise exception 'Identidade profissional nao localizada.' using errcode = 'P0002'; end if;
  select passport into v_actor_passport from public.profiles where user_id = v_actor;
  insert into public.audit_logs (actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values)
  values (v_actor, v_actor_passport, 'IDENTITY_UNLOCKED', 'professional_identities', p_target_user_id::text,
    jsonb_build_object('identity_locked', true), jsonb_build_object('identity_locked', false, 'reason', v_reason));
end;
$$;

create or replace function public.prepare_professional_identity_regeneration(
  p_target_user_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_reason text := nullif(btrim(p_reason), '');
begin
  if not private.hpsm_identity_is_director_general(v_actor) then
    raise exception 'Acesso nao autorizado.' using errcode = '42501';
  end if;
  if v_reason is null or char_length(v_reason) not between 5 and 500 then
    raise exception 'Informe o motivo da regeneracao.' using errcode = '22023';
  end if;
  update public.professional_identities
  set signature_regeneration_reason = v_reason, updated_at = now()
  where user_id = p_target_user_id;
  if not found then raise exception 'Identidade profissional nao localizada.' using errcode = 'P0002'; end if;
end;
$$;

create or replace function private.build_clinical_exam_report_snapshot(p_exam_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  select jsonb_build_object(
    'schema', 'hpsm.exam_report_snapshot.v1',
    'exam', coalesce(exam.result_data->'exam_type_snapshot', jsonb_build_object(
      'id', exam_type.id, 'code', exam_type.code, 'name', exam_type.name,
      'category_id', category.id, 'category_code', category.code, 'category_name', category.name,
      'result_config', exam_type.result_config
    )),
    'patient', jsonb_build_object('id', patient.id, 'name', patient.name, 'passport', patient.passport),
    'indication', exam.indication,
    'clinical_context', exam.clinical_context,
    'report_config', coalesce(exam.result_data->'report_config_snapshot', private.clinical_exam_report_config(exam.exam_type_id)),
    'content', jsonb_build_object(
      'technique', exam.technique, 'findings', exam.findings, 'conclusion', exam.conclusion,
      'observations', nullif(exam.result_data->>'notes', ''),
      'result_data', exam.result_data - 'report_config_snapshot' - 'exam_type_snapshot'
    ),
    'images', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', image.id, 'caption', image.caption, 'mime_type', image.mime_type,
        'original_filename', image.original_filename, 'sort_order', image.sort_order,
        'source', image.source, 'uploaded_by', image.uploaded_by, 'created_at', image.created_at
      ) order by image.sort_order, image.created_at, image.id)
      from public.clinical_exam_images image
      where image.exam_id = exam.id and image.removed_at is null
    ), '[]'::jsonb),
    'requested_by', jsonb_build_object(
      'id', requester.user_id, 'name', requester.display_name, 'position', requester_position.name,
      'identity', case when requester_identity.status = 'active' then jsonb_build_object(
        'crm_code', requester_identity.crm_code, 'registration_date', requester_identity.registration_date,
        'signature_image_path', requester_identity.signature_image_path, 'rubric_image_path', requester_identity.rubric_image_path
      ) else null end
    ),
    'executed_by', jsonb_build_object(
      'id', responsible.user_id, 'name', responsible.display_name, 'position', responsible_position.name,
      'identity', case when responsible_identity.status = 'active' then jsonb_build_object(
        'crm_code', responsible_identity.crm_code, 'registration_date', responsible_identity.registration_date,
        'signature_image_path', responsible_identity.signature_image_path, 'rubric_image_path', responsible_identity.rubric_image_path
      ) else null end
    ),
    'reviewed_by', case when reviewer.user_id is null then null else jsonb_build_object(
      'id', reviewer.user_id, 'name', reviewer.display_name, 'position', reviewer_position.name,
      'identity', case when reviewer_identity.status = 'active' then jsonb_build_object(
        'crm_code', reviewer_identity.crm_code, 'registration_date', reviewer_identity.registration_date,
        'signature_image_path', reviewer_identity.signature_image_path, 'rubric_image_path', reviewer_identity.rubric_image_path
      ) else null end
    ) end,
    'dates', jsonb_build_object(
      'requested_at', exam.requested_at, 'started_at', exam.started_at,
      'submitted_for_review_at', exam.submitted_for_review_at, 'completed_at', exam.completed_at
    )
  ) into v_result
  from public.clinical_exams exam
  join public.patients patient on patient.id = exam.patient_id
  join public.exam_types exam_type on exam_type.id = exam.exam_type_id
  join public.exam_categories category on category.id = exam_type.category_id
  join public.profiles requester on requester.user_id = exam.requested_by
  left join public.staff_positions requester_position on requester_position.id = requester.position_id
  left join public.professional_identities requester_identity on requester_identity.user_id = requester.user_id
  join public.profiles responsible on responsible.user_id = exam.responsible_professional_id
  left join public.staff_positions responsible_position on responsible_position.id = responsible.position_id
  left join public.professional_identities responsible_identity on responsible_identity.user_id = responsible.user_id
  left join public.profiles reviewer on reviewer.user_id = exam.reviewed_by
  left join public.staff_positions reviewer_position on reviewer_position.id = reviewer.position_id
  left join public.professional_identities reviewer_identity on reviewer_identity.user_id = reviewer.user_id
  where exam.id = p_exam_id;
  if v_result is null then raise exception 'Exame nao localizado.'; end if;
  return v_result;
end;
$$;

-- A identidade altera somente a camada de apresentacao do PNG. Snapshots e
-- documentos v1/v2 continuam preservados, enquanto novas segundas vias usam v3.
alter table public.clinical_exam_documents
  drop constraint clinical_exam_documents_render_version_check;
alter table public.clinical_exam_documents
  add constraint clinical_exam_documents_render_version_check
  check (render_version in ('exam-document-png-v1', 'exam-document-png-v2', 'exam-document-png-v3'));

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
    execute replace(pg_get_functiondef(v_function), 'exam-document-png-v2', 'exam-document-png-v3');
  end loop;
end;
$$;

update public.clinical_exam_document_shares share
set revoked_at = clock_timestamp(), revoked_by = share.created_by
from public.clinical_exam_documents document
where share.document_id = document.id
  and share.revoked_at is null
  and share.created_by is not null
  and document.render_version = 'exam-document-png-v2';

delete from public.clinical_exam_document_shares share
using public.clinical_exam_documents document
where share.document_id = document.id
  and share.revoked_at is null
  and share.created_by is null
  and document.render_version = 'exam-document-png-v2';

comment on constraint clinical_exam_documents_render_version_check
on public.clinical_exam_documents is
  'Preserva documentos v1/v2 e aceita a apresentacao v3 com identidade profissional institucional.';

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('professional-identities', 'professional-identities', false, 5242880, array['image/png']::text[])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

alter table public.professional_identities enable row level security;
alter table public.professional_identities force row level security;

create policy professional_identities_read_own_or_director
on public.professional_identities for select to authenticated
using (user_id = (select auth.uid()) or private.hpsm_identity_is_director_general((select auth.uid())));

create policy phase103_valid_session
on public.professional_identities as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

revoke all on table public.professional_identities from public, anon, authenticated, service_role;
grant select on table public.professional_identities to authenticated, service_role;

revoke all on function private.hpsm_build_internal_crm(text, date) from public, anon, authenticated;
revoke all on function private.hpsm_identity_is_director_general(uuid) from public, anon;
grant execute on function private.hpsm_identity_is_director_general(uuid) to authenticated;
revoke all on function private.hpsm_professional_registration_date(uuid) from public, anon, authenticated;
revoke all on function private.provision_professional_identity() from public, anon, authenticated;

revoke all on function public.professional_identity_generation_context(uuid, text) from public, anon, authenticated;
grant execute on function public.professional_identity_generation_context(uuid, text) to authenticated;

revoke all on function public.begin_professional_identity_generation(uuid, uuid, text, uuid, text) from public, anon, authenticated, service_role;
grant execute on function public.begin_professional_identity_generation(uuid, uuid, text, uuid, text) to service_role;
revoke all on function public.complete_professional_identity_generation(uuid, uuid, uuid, text, integer, text, integer) from public, anon, authenticated, service_role;
grant execute on function public.complete_professional_identity_generation(uuid, uuid, uuid, text, integer, text, integer) to service_role;
revoke all on function public.fail_professional_identity_generation(uuid, uuid, text) from public, anon, authenticated, service_role;
grant execute on function public.fail_professional_identity_generation(uuid, uuid, text) to service_role;

revoke all on function public.correct_professional_identity_crm(uuid, date, text) from public, anon, authenticated;
grant execute on function public.correct_professional_identity_crm(uuid, date, text) to authenticated;
revoke all on function public.unlock_professional_identity_reprocess(uuid, text) from public, anon, authenticated;
grant execute on function public.unlock_professional_identity_reprocess(uuid, text) to authenticated;
revoke all on function public.prepare_professional_identity_regeneration(uuid, text) from public, anon, authenticated;
grant execute on function public.prepare_professional_identity_regeneration(uuid, text) to authenticated;

comment on table public.professional_identities is 'Identidade institucional de todos os profissionais HPSM: CRM interno, assinatura e rubrica privadas.';
comment on column public.professional_identities.crm_code is 'Passaporte com quatro digitos seguido de DDMM da admissao; alteravel somente por correcao auditada do Diretor Geral.';
comment on column public.professional_identities.registration_date is 'Data canonica de admissao usada na composicao do CRM interno.';
comment on column public.professional_identities.identity_locked is 'Bloqueio institucional; somente o fluxo administrativo do Diretor Geral pode abrir reprocessamento.';
comment on function public.professional_identity_generation_context(uuid, text) is 'Entrega ao backend de IA somente o contexto minimo autorizado da identidade profissional.';
comment on function private.build_clinical_exam_report_snapshot(bigint) is 'Snapshot final do laudo com identidade profissional vigente e cargo da conclusao; a exibicao pode atualizar apenas o cargo atual.';
