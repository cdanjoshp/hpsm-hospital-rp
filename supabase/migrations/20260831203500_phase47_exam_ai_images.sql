-- HPSM — Fase 4.7: imagens clínicas fictícias geradas por IA.
-- O arquivo nasce como rascunho privado e só entra na galeria após aprovação humana.

alter table public.exam_ai_generations
  add column image_quality text,
  add column image_size text,
  add column image_count integer,
  add column draft_storage_path text,
  add column draft_mime_type text,
  add column draft_file_size bigint,
  add column official_image_id uuid references public.clinical_exam_images(id) on delete restrict;

alter table public.exam_ai_generations drop constraint exam_ai_generations_type_check;
alter table public.exam_ai_generations drop constraint exam_ai_generations_model_check;
alter table public.exam_ai_generations drop constraint exam_ai_generations_prompt_check;
alter table public.exam_ai_generations add constraint exam_ai_generations_type_check
  check (generation_type in ('generate_lab_results', 'generate_report', 'generate_image'));
alter table public.exam_ai_generations add constraint exam_ai_generations_model_check
  check ((generation_type = 'generate_image' and model = 'gpt-image-2') or (generation_type <> 'generate_image' and model = 'gpt-5.6-luna'));
alter table public.exam_ai_generations add constraint exam_ai_generations_prompt_check
  check ((generation_type = 'generate_image' and prompt_version = 'exam-image-rp-v1') or (generation_type <> 'generate_image' and prompt_version = 'exam-rp-luna-v1'));
alter table public.exam_ai_generations add constraint exam_ai_generations_image_config_check check (
  (generation_type <> 'generate_image' and image_quality is null and image_size is null and image_count is null and draft_storage_path is null and draft_mime_type is null and draft_file_size is null and official_image_id is null)
  or (generation_type = 'generate_image'
      and image_quality = 'low' and image_size = '1024x1024' and image_count = 1
      and (draft_storage_path is null or draft_storage_path ~ ('^clinical-exams/' || exam_id::text || '/ai-drafts/[0-9a-f-]{36}\.png$'))
      and (draft_mime_type is null or draft_mime_type = 'image/png')
      and (draft_file_size is null or draft_file_size between 1 and 10485760))
);

create or replace function private.protect_exam_ai_generation_update()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.id is distinct from old.id or new.exam_id is distinct from old.exam_id
     or new.generation_type is distinct from old.generation_type or new.requested_by is distinct from old.requested_by
     or new.model is distinct from old.model or new.reasoning_effort is distinct from old.reasoning_effort
     or new.prompt_version is distinct from old.prompt_version or new.source_exam_updated_at is distinct from old.source_exam_updated_at
     or new.idempotency_key is distinct from old.idempotency_key or new.created_at is distinct from old.created_at
     or (old.status <> 'requested' and (new.image_quality is distinct from old.image_quality or new.image_size is distinct from old.image_size
       or new.image_count is distinct from old.image_count or new.draft_storage_path is distinct from old.draft_storage_path
       or new.draft_mime_type is distinct from old.draft_mime_type or new.draft_file_size is distinct from old.draft_file_size))
     or (old.status <> 'completed' and new.official_image_id is distinct from old.official_image_id) then
    raise exception 'Os metadados da geração de IA são imutáveis.';
  end if;
  if not ((old.status = 'requested' and new.status in ('completed', 'failed')) or (old.status = 'completed' and new.status in ('applied', 'discarded'))) then
    raise exception 'Transição inválida da geração de IA.';
  end if;
  new.updated_at := now(); return new;
end; $$;

create or replace function public.clinical_exam_ai_image_context(p_exam_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_actor uuid := private.hpsm_current_actor(); v_exam public.clinical_exams; v_type_code text; v_type_name text;
begin
  select exam.* into v_exam from public.clinical_exams exam where exam.id = p_exam_id;
  if v_exam.id is null then raise exception 'Exame não localizado.'; end if;
  select exam_type.code, exam_type.name into v_type_code, v_type_name from public.exam_types exam_type where exam_type.id = v_exam.exam_type_id;
  if v_exam.status <> 'in_progress' then raise exception 'A imagem por IA só pode ser gerada em exame em andamento.'; end if;
  if v_exam.responsible_professional_id is distinct from v_actor or not private.has_permission(v_actor, 'exams.perform') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if v_exam.result_data->>'schema' <> 'hpsm.image_result.v1' or v_type_code not in ('raio_x','tomografia','ressonancia_magnetica','ultrassom') then
    raise exception 'Este tipo de exame não aceita geração de imagem por IA.';
  end if;
  if nullif(btrim(v_exam.result_data->>'region'), '') is null or nullif(btrim(coalesce(v_exam.findings, '')), '') is null then
    raise exception 'Preencha e salve a região e os Achados antes de gerar a imagem.';
  end if;
  if coalesce((v_exam.result_data#>>'{template_snapshot,supports_laterality}')::boolean, false)
     and nullif(v_exam.result_data->>'laterality', '') is null then raise exception 'Selecione e salve a lateralidade antes de gerar.'; end if;
  return jsonb_build_object('actor_id', v_actor, 'exam_id', v_exam.id, 'type_code', v_type_code, 'type_name', v_type_name,
    'region', case when v_exam.result_data->>'region' = 'Outra região' then v_exam.result_data->>'other_region' else v_exam.result_data->>'region' end,
    'laterality', v_exam.result_data->>'laterality', 'contrast', v_exam.result_data->>'contrast',
    'findings', left(v_exam.findings, 8000), 'indication', left(v_exam.indication, 4000),
    'clinical_context', left(coalesce(v_exam.clinical_context, ''), 4000));
end; $$;

create or replace function public.begin_clinical_exam_ai_image(p_exam_id bigint, p_requested_by uuid, p_idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_exam public.clinical_exams; v_generation public.exam_ai_generations; v_recent integer;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_exam_id::text || ':generate_image', 0));
  select * into v_generation from public.exam_ai_generations where idempotency_key = p_idempotency_key for update;
  if v_generation.id is not null then
    if v_generation.exam_id <> p_exam_id or v_generation.requested_by <> p_requested_by or v_generation.generation_type <> 'generate_image' then raise exception 'Chave de idempotência inválida.'; end if;
    return jsonb_build_object('generation_id', v_generation.id, 'status', v_generation.status, 'replayed', true);
  end if;
  select * into v_exam from public.clinical_exams where id = p_exam_id for update;
  if v_exam.id is null or v_exam.status <> 'in_progress' or v_exam.result_data->>'schema' <> 'hpsm.image_result.v1' then raise exception 'O exame não aceita geração de imagem.'; end if;
  if v_exam.responsible_professional_id is distinct from p_requested_by or not private.has_permission(p_requested_by, 'exams.perform') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  select * into v_generation from public.exam_ai_generations where exam_id = p_exam_id and generation_type = 'generate_image' and status = 'requested' order by created_at desc limit 1 for update;
  if v_generation.id is not null and v_generation.created_at >= now() - interval '2 minutes' then return jsonb_build_object('generation_id', v_generation.id, 'status', 'requested', 'replayed', true); end if;
  if v_generation.id is not null then update public.exam_ai_generations set status='failed', failed_at=now(), error_code='stale_request' where id=v_generation.id; end if;
  select count(*) into v_recent from public.exam_ai_generations where requested_by=p_requested_by and generation_type='generate_image' and created_at >= now()-interval '10 minutes';
  if v_recent >= 4 then raise exception 'Limite temporário de imagens atingido. Aguarde alguns minutos.'; end if;
  insert into public.exam_ai_generations(exam_id,generation_type,requested_by,model,reasoning_effort,prompt_version,source_exam_updated_at,idempotency_key,image_quality,image_size,image_count)
  values(p_exam_id,'generate_image',p_requested_by,'gpt-image-2','low','exam-image-rp-v1',v_exam.updated_at,p_idempotency_key,'low','1024x1024',1) returning * into v_generation;
  perform private.audit_exam_action(p_requested_by,'clinical_exam.ai_image_requested','exam_ai_generations',v_generation.id::text,null,
    jsonb_build_object('exam_id',p_exam_id,'model','gpt-image-2','quality','low','size','1024x1024','image_count',1,'prompt_version','exam-image-rp-v1'));
  return jsonb_build_object('generation_id',v_generation.id,'status','requested','replayed',false);
end; $$;

create or replace function public.complete_clinical_exam_ai_image(p_generation_id uuid,p_openai_request_id text,p_storage_path text,p_file_size bigint,p_usage jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_generation public.exam_ai_generations; v_old_paths jsonb;
begin
  select * into v_generation from public.exam_ai_generations where id=p_generation_id for update;
  if v_generation.id is null or v_generation.generation_type <> 'generate_image' or v_generation.status <> 'requested' then raise exception 'Geração de imagem indisponível.'; end if;
  if p_storage_path !~ ('^clinical-exams/' || v_generation.exam_id::text || '/ai-drafts/[0-9a-f-]{36}\.png$') or p_file_size not between 1 and 10485760 then raise exception 'Rascunho de imagem inválido.'; end if;
  select coalesce(jsonb_agg(draft_storage_path),'[]'::jsonb) into v_old_paths from public.exam_ai_generations
    where exam_id=v_generation.exam_id and generation_type='generate_image' and status='completed' and draft_storage_path is not null;
  update public.exam_ai_generations set status='discarded',discarded_at=now() where exam_id=v_generation.exam_id and generation_type='generate_image' and status='completed';
  update public.exam_ai_generations set status='completed',openai_response_id=left(coalesce(nullif(btrim(p_openai_request_id),''),'request-unavailable'),200),
    input_tokens=greatest(coalesce((p_usage->>'input_tokens')::integer,0),0),output_tokens=greatest(coalesce((p_usage->>'output_tokens')::integer,0),0),
    total_tokens=greatest(coalesce((p_usage->>'total_tokens')::integer,0),0),suggestion_payload=jsonb_build_object('schema','hpsm.ai.image_draft.v1','storage_path',p_storage_path),
    draft_storage_path=p_storage_path,draft_mime_type='image/png',draft_file_size=p_file_size,completed_at=now() where id=p_generation_id;
  perform private.audit_exam_action(v_generation.requested_by,'clinical_exam.ai_image_completed','exam_ai_generations',p_generation_id::text,jsonb_build_object('status','requested'),jsonb_build_object('status','completed','exam_id',v_generation.exam_id));
  return jsonb_build_object('old_paths',v_old_paths);
end; $$;

create or replace function public.clinical_exam_ai_image_draft(p_exam_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_actor uuid := private.hpsm_current_actor(); v_generation public.exam_ai_generations;
begin
  if not private.has_permission(v_actor,'exams.view') then raise exception 'Acesso não autorizado.' using errcode='42501'; end if;
  select generation.* into v_generation from public.exam_ai_generations generation join public.clinical_exams exam on exam.id=generation.exam_id
  where generation.exam_id=p_exam_id and generation.generation_type='generate_image' and generation.status in ('requested','completed')
    and exam.status='in_progress' and exam.responsible_professional_id=v_actor and private.has_permission(v_actor,'exams.perform')
  order by generation.created_at desc limit 1;
  if v_generation.id is null then return null; end if;
  return jsonb_build_object('id',v_generation.id,'status',v_generation.status,'model',v_generation.model,'prompt_version',v_generation.prompt_version,
    'quality',v_generation.image_quality,'size',v_generation.image_size,'image_count',v_generation.image_count,'storage_path',v_generation.draft_storage_path,
    'file_size',v_generation.draft_file_size,'created_at',v_generation.created_at,'completed_at',v_generation.completed_at);
end; $$;

create or replace function public.apply_clinical_exam_ai_image(p_generation_id uuid,p_actor uuid,p_image_id uuid,p_storage_path text,p_file_size bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_generation public.exam_ai_generations; v_exam public.clinical_exams; v_count integer; v_image public.clinical_exam_images;
begin
  select * into v_generation from public.exam_ai_generations where id=p_generation_id for update;
  if v_generation.id is null or v_generation.generation_type<>'generate_image' or v_generation.status<>'completed' then raise exception 'Rascunho de imagem indisponível.'; end if;
  select * into v_exam from public.clinical_exams where id=v_generation.exam_id for update;
  if v_exam.status<>'in_progress' or v_exam.responsible_professional_id is distinct from p_actor or not private.has_permission(p_actor,'exams.perform') then raise exception 'Acesso não autorizado.' using errcode='42501'; end if;
  if p_actor is distinct from v_generation.requested_by then raise exception 'Somente o solicitante pode aplicar este rascunho.'; end if;
  if p_storage_path <> 'clinical-exams/'||v_exam.id::text||'/'||p_image_id::text||'.png' or p_file_size<>v_generation.draft_file_size then raise exception 'Imagem final inválida.'; end if;
  select count(*) into v_count from public.clinical_exam_images where exam_id=v_exam.id and removed_at is null;
  if not (v_exam.result_data#>>'{template_snapshot,allows_multiple_images}')::boolean and v_count>0 then raise exception 'Este tipo de exame aceita somente uma imagem.'; end if;
  insert into public.clinical_exam_images(id,exam_id,storage_path,original_filename,mime_type,file_size,sort_order,caption,source,uploaded_by)
  values(p_image_id,v_exam.id,p_storage_path,'imagem-ficticia-ia.png','image/png',p_file_size,(v_count+1)*10,'Imagem fictícia gerada por IA para fins de RP.','ai_generated',p_actor) returning * into v_image;
  update public.exam_ai_generations set status='applied',applied_at=now(),official_image_id=p_image_id where id=p_generation_id;
  update public.clinical_exams set updated_at=now() where id=v_exam.id;
  perform private.audit_exam_action(p_actor,'clinical_exam.ai_image_applied','clinical_exam_images',p_image_id::text,null,jsonb_build_object('exam_id',v_exam.id,'source','ai_generated','generation_id',p_generation_id));
  return jsonb_build_object('image_id',p_image_id,'draft_path',v_generation.draft_storage_path);
end; $$;

create or replace function public.discard_clinical_exam_ai_image(p_generation_id uuid,p_actor uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare v_generation public.exam_ai_generations; v_exam public.clinical_exams;
begin
  select * into v_generation from public.exam_ai_generations where id=p_generation_id for update;
  if v_generation.id is null or v_generation.generation_type<>'generate_image' or v_generation.status<>'completed' then raise exception 'Rascunho de imagem indisponível.'; end if;
  select * into v_exam from public.clinical_exams where id=v_generation.exam_id for update;
  if v_exam.status<>'in_progress' or v_exam.responsible_professional_id is distinct from p_actor or not private.has_permission(p_actor,'exams.perform') then raise exception 'Acesso não autorizado.' using errcode='42501'; end if;
  update public.exam_ai_generations set status='discarded',discarded_at=now() where id=p_generation_id;
  perform private.audit_exam_action(p_actor,'clinical_exam.ai_image_discarded','exam_ai_generations',p_generation_id::text,jsonb_build_object('status','completed'),jsonb_build_object('status','discarded','exam_id',v_exam.id));
  return v_generation.draft_storage_path;
end; $$;

create or replace function private.discard_exam_ai_image_drafts_on_lock()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status = 'in_progress' and new.status in ('awaiting_review','completed') then
    update public.exam_ai_generations set status='discarded',discarded_at=now()
    where exam_id=new.id and generation_type='generate_image' and status='completed';
  end if;
  return new;
end; $$;
drop trigger if exists clinical_exams_discard_ai_image_drafts on public.clinical_exams;
create trigger clinical_exams_discard_ai_image_drafts after update of status on public.clinical_exams
for each row execute function private.discard_exam_ai_image_drafts_on_lock();
revoke all on function private.discard_exam_ai_image_drafts_on_lock() from public,anon,authenticated,service_role;

revoke all on function public.clinical_exam_ai_image_context(bigint) from public,anon,authenticated,service_role;
revoke all on function public.begin_clinical_exam_ai_image(bigint,uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function public.complete_clinical_exam_ai_image(uuid,text,text,bigint,jsonb) from public,anon,authenticated,service_role;
revoke all on function public.clinical_exam_ai_image_draft(bigint) from public,anon,authenticated,service_role;
revoke all on function public.apply_clinical_exam_ai_image(uuid,uuid,uuid,text,bigint) from public,anon,authenticated,service_role;
revoke all on function public.discard_clinical_exam_ai_image(uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function public.clinical_exam_ai_image_context(bigint) to authenticated;
grant execute on function public.clinical_exam_ai_image_draft(bigint) to authenticated;
grant execute on function public.begin_clinical_exam_ai_image(bigint,uuid,uuid) to service_role;
grant execute on function public.complete_clinical_exam_ai_image(uuid,text,text,bigint,jsonb) to service_role;
grant execute on function public.apply_clinical_exam_ai_image(uuid,uuid,uuid,text,bigint) to service_role;
grant execute on function public.discard_clinical_exam_ai_image(uuid,uuid) to service_role;

comment on column public.exam_ai_generations.draft_storage_path is 'Path privado temporário; nunca contém dados pessoais nem signed URL.';
comment on function public.clinical_exam_ai_image_context(bigint) is 'Contexto mínimo sem identificação do paciente para geração fictícia da Fase 4.7.';
notify pgrst, 'reload schema';
