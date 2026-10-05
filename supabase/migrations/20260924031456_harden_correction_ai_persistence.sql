-- AI persistence remains Edge-only. The clinical owner is derived from the locked record.

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
declare v_generation public.consultation_ai_generations;
begin
  select generation.* into v_generation
  from public.consultation_ai_generations generation
  join public.clinical_consultations consultation on consultation.id = generation.consultation_id
  where generation.consultation_id = p_consultation_id
    and generation.action_type = p_action_type
    and consultation.status = 'in_progress'
    and private.is_hpsm_workforce(consultation.professional_id)
    and private.has_permission(consultation.professional_id, 'consultations.complete')
  for update of generation;
  if v_generation.id is null or v_generation.request_key <> p_request_key then raise exception 'Solicitação de IA inválida.' using errcode = '42501'; end if;
  if v_generation.status = 'completed' then return v_generation.response_payload; end if;
  if v_generation.status <> 'pending' or p_response_payload is null or jsonb_typeof(p_response_payload) <> 'object' then raise exception 'Resposta de IA inválida.'; end if;
  if p_model <> 'gpt-5.6-luna' or p_prompt_version <> 'consultation-assistant-v2' then raise exception 'Origem da assistência inválida.' using errcode = '42501'; end if;
  if p_action_type = 'DIAGNOSIS_OPTIONS' and (
    jsonb_typeof(p_response_payload->'options') <> 'array'
    or jsonb_array_length(p_response_payload->'options') <> 3
    or (select array_agg(option->>'severity' order by option->>'severity') from jsonb_array_elements(p_response_payload->'options') option) <> array['grave', 'gravissimo', 'normal']::text[]
  ) then raise exception 'A IA deve retornar exatamente as opções Normal, Grave e Gravíssimo.'; end if;
  if p_action_type = 'EXAM_SUGGESTIONS' and exists (
    select 1 from jsonb_array_elements(coalesce(p_response_payload->'suggestions', '[]'::jsonb)) suggestion
    where not exists (select 1 from public.exam_types exam_type join public.exam_categories category on category.id = exam_type.category_id where exam_type.id = nullif(suggestion->>'exam_type_id', '')::bigint and exam_type.active and category.active)
  ) then raise exception 'A IA sugeriu um tipo de exame indisponível.'; end if;
  update public.consultation_ai_generations set status = 'completed', response_payload = p_response_payload, error_message = null, model = p_model, prompt_version = p_prompt_version, completed_at = now(), failed_at = null where id = v_generation.id;
  return p_response_payload;
end;
$$;

create or replace function public.apply_medical_certificate_ai_result(
  p_certificate_id bigint,
  p_text text,
  p_diagnosis_text text,
  p_cid_code text,
  p_model text,
  p_prompt_version text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_certificate public.medical_certificates;
  v_text text := btrim(coalesce(p_text, ''));
  v_diagnosis text := nullif(btrim(coalesce(p_diagnosis_text, '')), '');
  v_cid text := upper(nullif(btrim(coalesce(p_cid_code, '')), ''));
begin
  select * into v_certificate from public.medical_certificates where id = p_certificate_id for update;
  if v_certificate.id is null then raise exception 'Atestado não localizado.'; end if;
  if v_certificate.status <> 'draft' or not private.is_hpsm_workforce(v_certificate.created_by) or not private.has_permission(v_certificate.created_by, 'atestados.create') then raise exception 'Este atestado não aceita geração de texto.' using errcode = '42501'; end if;
  if p_model <> 'gpt-5.6-luna' or p_prompt_version <> 'medical-certificate-v2' then raise exception 'Modelo de assistência incompatível.' using errcode = '42501'; end if;
  if v_diagnosis is null or char_length(v_diagnosis) > 500 then raise exception 'A sugestão não retornou um diagnóstico válido.'; end if;
  if v_cid is null or not exists (select 1 from public.medical_cid10_catalog where code = v_cid and active) then raise exception 'A sugestão não retornou um CID-10 do catálogo. Nada foi alterado.'; end if;
  if not private.medical_certificate_text_matches_days(v_text, v_certificate.leave_days) or strpos(lower(v_text), lower(v_diagnosis)) = 0 or strpos(upper(v_text), v_cid) = 0 then raise exception 'A sugestão não preservou dias, diagnóstico e CID-10. Nada foi alterado.'; end if;
  update public.medical_certificates set generated_text = v_text, final_text = v_text, diagnosis_text = v_diagnosis, cid_code = v_cid, ai_model = p_model, ai_prompt_version = p_prompt_version, ai_generated_at = now() where id = p_certificate_id;
  perform private.audit_medical_certificate_action(v_certificate.created_by, 'MEDICAL_CERTIFICATE_AI_GENERATED', p_certificate_id, null, jsonb_build_object('model', p_model, 'prompt_version', p_prompt_version, 'leave_days', v_certificate.leave_days, 'diagnosis_text', v_diagnosis, 'cid_code', v_cid));
end;
$$;

revoke all on function public.complete_consultation_ai_generation(bigint, text, uuid, jsonb, text, text) from public, anon, authenticated;
revoke all on function public.apply_medical_certificate_ai_result(bigint, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.complete_consultation_ai_generation(bigint, text, uuid, jsonb, text, text) to service_role;
grant execute on function public.apply_medical_certificate_ai_result(bigint, text, text, text, text, text) to service_role;
