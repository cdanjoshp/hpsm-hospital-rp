-- Segundo rollup de correções de consultas: contratos de IA e template institucional de atestados.

alter table public.exam_ai_generations drop constraint exam_ai_generations_prompt_check;
alter table public.exam_ai_generations add constraint exam_ai_generations_prompt_check check (
  (generation_type = 'generate_image' and prompt_version in ('exam-image-rp-v1', 'exam-image-rp-v2', 'exam-image-clinical-v3'))
  or (generation_type = 'generate_exam' and prompt_version in ('exam-rp-luna-v4', 'exam-clinical-exam-v5', 'exam-clinical-exam-v6', 'exam-clinical-exam-v7'))
  or (generation_type = 'generate_report' and prompt_version in ('exam-rp-luna-v1', 'exam-rp-luna-v2', 'exam-rp-luna-v3', 'exam-clinical-report-v4'))
  or (generation_type = 'generate_lab_results' and prompt_version in ('exam-rp-luna-v1', 'exam-rp-luna-v2', 'exam-rp-luna-v3', 'exam-clinical-lab-v3', 'exam-clinical-lab-v4'))
);

create or replace function private.assign_current_exam_ai_prompt_version()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.prompt_version := case new.generation_type
    when 'generate_image' then 'exam-image-clinical-v3'
    when 'generate_lab_results' then 'exam-clinical-lab-v4'
    when 'generate_report' then 'exam-clinical-report-v4'
    when 'generate_exam' then 'exam-clinical-exam-v7'
    else new.prompt_version
  end;
  return new;
end;
$$;

create or replace function public.complete_consultation_ai_generation(
  p_consultation_id bigint,
  p_action_type text,
  p_request_key uuid,
  p_response_payload jsonb,
  p_model text,
  p_prompt_version text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_generation public.consultation_ai_generations;
begin
  select generation.* into v_generation
  from public.consultation_ai_generations generation
  join public.clinical_consultations consultation on consultation.id = generation.consultation_id
  where generation.consultation_id = p_consultation_id and generation.action_type = p_action_type
    and private.can_edit_consultation(v_actor, consultation.professional_id)
  for update of generation;
  if v_generation.id is null or v_generation.request_key <> p_request_key then raise exception 'Solicitação de IA inválida.' using errcode = '42501'; end if;
  if v_generation.status = 'completed' then return v_generation.response_payload; end if;
  if v_generation.status <> 'pending' or p_response_payload is null or jsonb_typeof(p_response_payload) <> 'object' then raise exception 'Resposta de IA inválida.'; end if;
  if p_model <> 'gpt-5.6-luna' or p_prompt_version <> 'consultation-assistant-v3' then raise exception 'Modelo de assistência incompatível.'; end if;
  if p_action_type = 'DIAGNOSIS_OPTIONS' and (
    jsonb_typeof(p_response_payload->'options') <> 'array'
    or jsonb_array_length(p_response_payload->'options') <> 3
    or (select array_agg(option->>'severity' order by option->>'severity') from jsonb_array_elements(p_response_payload->'options') option) <> array['grave', 'gravissimo', 'normal']::text[]
  ) then raise exception 'A IA deve retornar exatamente as opções Normal, Grave e Gravíssimo.'; end if;
  if p_action_type = 'EXAM_SUGGESTIONS' and exists (
    select 1 from jsonb_array_elements(coalesce(p_response_payload->'suggestions', '[]'::jsonb)) suggestion
    where not exists (select 1 from public.exam_types exam_type join public.exam_categories category on category.id = exam_type.category_id where exam_type.id = nullif(suggestion->>'exam_type_id', '')::bigint and exam_type.active and category.active)
  ) then raise exception 'A IA sugeriu um tipo de exame indisponível.'; end if;
  update public.consultation_ai_generations set status = 'completed', response_payload = p_response_payload, error_message = null, model = btrim(p_model), prompt_version = btrim(p_prompt_version), completed_at = now(), failed_at = null where id = v_generation.id;
  return p_response_payload;
end;
$$;

create or replace function public.register_medical_certificate_document(p_certificate_id bigint, p_storage_path text, p_file_size integer, p_width integer, p_height integer, p_render_version text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_actor uuid := private.hpsm_current_actor(); v_certificate public.medical_certificates;
begin
  if not private.has_permission(v_actor, 'atestados.view') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  select * into v_certificate from public.medical_certificates where id = p_certificate_id for update;
  if v_certificate.id is null then raise exception 'Atestado não localizado.'; end if;
  if v_certificate.status <> 'finalized' then raise exception 'O documento está disponível somente para atestados finalizados.'; end if;
  if p_storage_path !~ ('^medical-certificates/' || p_certificate_id::text || '/documents/[0-9a-f-]{36}[.]png$') then raise exception 'Caminho de documento inválido.'; end if;
  if p_file_size not between 32 and 12582912 or p_width not between 900 and 1400 or p_height not between 400 and 14000 or nullif(btrim(p_render_version), '') is null then raise exception 'Metadados do documento inválidos.'; end if;
  if v_certificate.final_png_path is null or v_certificate.final_png_render_version is distinct from p_render_version then
    update public.medical_certificates set final_png_path = p_storage_path, final_png_file_size = p_file_size, final_png_width = p_width, final_png_height = p_height, final_png_render_version = p_render_version where id = p_certificate_id;
    perform private.audit_medical_certificate_action(v_actor, 'MEDICAL_CERTIFICATE_DOCUMENT_GENERATED', p_certificate_id, jsonb_build_object('render_version', v_certificate.final_png_render_version), jsonb_build_object('render_version', p_render_version, 'file_size', p_file_size));
  end if;
  return public.medical_certificate_document_state(p_certificate_id);
end;
$$;

create or replace function public.patient_portal_register_medical_certificate_document(p_token_hash text, p_certificate_id bigint, p_storage_path text, p_file_size integer, p_width integer, p_height integer, p_render_version text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_session record; v_certificate public.medical_certificates;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then return jsonb_build_object('authenticated', false, 'found', false); end if;
  select * into v_session from private.patient_portal_session_record(p_token_hash);
  if v_session.patient_id is null then return jsonb_build_object('authenticated', false, 'found', false); end if;
  select * into v_certificate from public.medical_certificates where id = p_certificate_id and patient_id = v_session.patient_id and status = 'finalized' for update;
  if v_certificate.id is null then return jsonb_build_object('authenticated', true, 'found', false); end if;
  if p_storage_path !~ ('^medical-certificates/' || p_certificate_id::text || '/documents/[0-9a-f-]{36}[.]png$') or p_file_size not between 32 and 12582912 or p_width not between 900 and 1400 or p_height not between 400 and 14000 or nullif(btrim(p_render_version), '') is null then raise exception 'Metadados do documento inválidos.'; end if;
  if v_certificate.final_png_path is null or v_certificate.final_png_render_version is distinct from p_render_version then
    update public.medical_certificates set final_png_path = p_storage_path, final_png_file_size = p_file_size, final_png_width = p_width, final_png_height = p_height, final_png_render_version = p_render_version where id = p_certificate_id;
    insert into public.audit_logs (actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values) values (null, v_session.patient_passport, 'MEDICAL_CERTIFICATE_DOCUMENT_GENERATED', 'medical_certificates', p_certificate_id::text, jsonb_build_object('render_version', v_certificate.final_png_render_version), jsonb_build_object('channel', 'patient_portal', 'render_version', p_render_version));
  end if;
  return public.patient_portal_medical_certificate_detail(p_token_hash, p_certificate_id);
end;
$$;

revoke all on function private.assign_current_exam_ai_prompt_version() from public, anon, authenticated, service_role;
revoke all on function public.complete_consultation_ai_generation(bigint, text, uuid, jsonb, text, text) from public, anon, authenticated, service_role;
revoke all on function public.register_medical_certificate_document(bigint, text, integer, integer, integer, text) from public, anon, authenticated, service_role;
revoke all on function public.patient_portal_register_medical_certificate_document(text, bigint, text, integer, integer, integer, text) from public, anon, authenticated, service_role;
grant execute on function public.complete_consultation_ai_generation(bigint, text, uuid, jsonb, text, text) to service_role;
grant execute on function public.register_medical_certificate_document(bigint, text, integer, integer, integer, text) to authenticated, service_role;
grant execute on function public.patient_portal_register_medical_certificate_document(text, bigint, text, integer, integer, integer, text) to service_role;

comment on function private.assign_current_exam_ai_prompt_version() is 'Seleciona os contratos atuais de IA, incluindo schemas laboratoriais tipados por modelo de exame.';
comment on function public.complete_consultation_ai_generation(bigint, text, uuid, jsonb, text, text) is 'Persiste assistência de consulta v3; a anamnese usa sinais vitais e permanece limitada ao contexto clínico registrado.';
comment on function public.register_medical_certificate_document(bigint, text, integer, integer, integer, text) is 'Registra ou atualiza o PNG imutável do atestado quando a versão do template institucional evolui.';

notify pgrst, 'reload schema';
