-- Corrige o contrato de persistência da assistência de consultas.
-- A Edge Function consultation-ai já emite consultation-assistant-v6; o RPC
-- ainda aceitava apenas v5 e descartava respostas válidas após a geração.

create or replace function public.complete_consultation_ai_generation_v3(
  p_consultation_id bigint,
  p_action_type text,
  p_request_key uuid,
  p_response_payload jsonb,
  p_model text,
  p_prompt_version text,
  p_input_tokens integer,
  p_output_tokens integer,
  p_cached_input_tokens integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_generation public.consultation_ai_generations;
  v_signature jsonb;
  v_passport text;
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
  if v_generation.id is null or v_generation.request_key <> p_request_key then
    raise exception 'Solicitação de IA inválida.' using errcode = '42501';
  end if;
  if v_generation.status = 'completed' then return v_generation.response_payload; end if;
  if v_generation.status <> 'pending' or p_response_payload is null or jsonb_typeof(p_response_payload) <> 'object' then
    raise exception 'Resposta de IA inválida.';
  end if;
  if p_model <> 'gpt-5.6-luna' or p_prompt_version <> 'consultation-assistant-v6' then
    raise exception 'Origem da assistência inválida.' using errcode = '42501';
  end if;
  if p_action_type not in ('ANAMNESIS_REWRITE', 'EXAM_SUGGESTIONS', 'CLINICAL_SYNTHESIS') then
    raise exception 'Ação de IA inválida.';
  end if;
  if coalesce(p_input_tokens, -1) < 0 or coalesce(p_output_tokens, -1) < 0
     or coalesce(p_cached_input_tokens, -1) < 0 or p_cached_input_tokens > p_input_tokens then
    raise exception 'Telemetria de IA inválida.';
  end if;
  if p_action_type = 'ANAMNESIS_REWRITE' and char_length(btrim(coalesce(p_response_payload->>'text', ''))) < 3 then
    raise exception 'A reescrita da anamnese está vazia.';
  end if;
  if p_action_type in ('EXAM_SUGGESTIONS', 'CLINICAL_SYNTHESIS') then
    v_signature := p_response_payload->'case_signature';
    if jsonb_typeof(v_signature) is distinct from 'object'
       or coalesce(v_signature->>'body_system', '') !~ '^[a-z0-9_]{2,60}$'
       or jsonb_typeof(v_signature->'case_tags') is distinct from 'array'
       or jsonb_array_length(v_signature->'case_tags') > 12
       or jsonb_typeof(v_signature->'vital_flags') is distinct from 'array'
       or jsonb_array_length(v_signature->'vital_flags') > 8
       or exists (select 1 from jsonb_array_elements_text(v_signature->'case_tags') value where value !~ '^[a-z0-9_]{2,60}$')
       or exists (select 1 from jsonb_array_elements_text(v_signature->'vital_flags') value where value !~ '^[a-z0-9_]{2,60}$') then
      raise exception 'A assinatura clínica retornou um formato inválido.';
    end if;
  end if;
  if p_action_type = 'EXAM_SUGGESTIONS' then
    if jsonb_typeof(p_response_payload->'no_exam_needed') is distinct from 'boolean'
       or jsonb_typeof(p_response_payload->'exam_suggestions') is distinct from 'array'
       or jsonb_array_length(p_response_payload->'exam_suggestions') > 5
       or ((p_response_payload->>'no_exam_needed')::boolean and jsonb_array_length(p_response_payload->'exam_suggestions') <> 0)
       or (not (p_response_payload->>'no_exam_needed')::boolean and jsonb_array_length(p_response_payload->'exam_suggestions') = 0) then
      raise exception 'A análise de exames retornou um formato inválido.';
    end if;
    if exists (
      select 1 from jsonb_array_elements(p_response_payload->'exam_suggestions') suggestion
      where not exists (
        select 1 from public.exam_types exam_type
        join public.exam_categories category on category.id = exam_type.category_id
        where exam_type.id = nullif(suggestion->>'exam_type_id', '')::bigint
          and exam_type.active and category.active
      )
    ) then raise exception 'A IA sugeriu um tipo de exame indisponível.'; end if;
  end if;
  if p_action_type = 'CLINICAL_SYNTHESIS' then
    if jsonb_typeof(p_response_payload->'options') is distinct from 'array'
       or jsonb_array_length(p_response_payload->'options') <> 3
       or (select array_agg(option->>'severity' order by option->>'severity')
           from jsonb_array_elements(p_response_payload->'options') option)
          <> array['grave', 'gravissimo', 'normal']::text[]
       or exists (
         select 1 from jsonb_array_elements(p_response_payload->'options') option
         where char_length(btrim(coalesce(option->>'diagnosis', ''))) < 3
            or char_length(btrim(coalesce(option->>'reasoning_summary', ''))) < 3
            or char_length(btrim(coalesce(option->>'final_plan', ''))) < 3
            or option->>'complementary_action' not in ('NONE', 'CAST', 'HOSPITALIZATION')
            or char_length(btrim(coalesce(option->>'orientation', ''))) < 3
            or jsonb_typeof(option->'medication_suggestions') is distinct from 'array'
            or jsonb_array_length(option->'medication_suggestions') > 5
       ) then raise exception 'A síntese deve retornar exatamente Normal, Grave e Gravíssimo com diagnóstico, plano, conduta, orientação e medicações válidas.';
    end if;
    if exists (
      select 1
      from jsonb_array_elements(p_response_payload->'options') option
      cross join lateral jsonb_array_elements(option->'medication_suggestions') suggestion
      where char_length(btrim(coalesce(suggestion->>'reason', ''))) < 3
         or not exists (
           select 1 from public.rp_medications medication
           where medication.id = suggestion->>'medication_id' and medication.active
         )
         or not private.rp_medication_context_compatible(p_consultation_id, suggestion->>'medication_id')
    ) then raise exception 'A síntese sugeriu um medicamento inexistente, inativo, incompatível ou contraindicado por alergia.'; end if;
    if exists (
      select 1 from jsonb_array_elements(p_response_payload->'options') option
      where (select count(*) from jsonb_array_elements(option->'medication_suggestions'))
        <> (select count(distinct suggestion->>'medication_id') from jsonb_array_elements(option->'medication_suggestions') suggestion)
    ) then raise exception 'A síntese repetiu um medicamento na mesma opção.'; end if;
  end if;
  update public.consultation_ai_generations set
    status = 'completed', response_payload = p_response_payload, error_message = null,
    model = btrim(p_model), prompt_version = btrim(p_prompt_version), completed_at = now(), failed_at = null,
    input_tokens = p_input_tokens, output_tokens = p_output_tokens,
    cached_input_tokens = p_cached_input_tokens
  where id = v_generation.id;
  if p_action_type = 'CLINICAL_SYNTHESIS' then
    select passport into v_passport from public.profiles where user_id = v_generation.requested_by;
    insert into public.audit_logs (actor_user_id, actor_passport, action, entity_name, entity_id, new_values)
    select v_generation.requested_by, v_passport, 'MEDICATION_SUGGESTED', 'clinical_consultations', p_consultation_id::text,
      jsonb_build_object('severity', option->>'severity', 'medication_id', suggestion->>'medication_id', 'reason', suggestion->>'reason')
    from jsonb_array_elements(p_response_payload->'options') option
    cross join lateral jsonb_array_elements(option->'medication_suggestions') suggestion;
  end if;
  return p_response_payload;
end;
$$;

revoke all on function public.complete_consultation_ai_generation_v3(bigint, text, uuid, jsonb, text, text, integer, integer, integer)
from public, anon, authenticated, service_role;
grant execute on function public.complete_consultation_ai_generation_v3(bigint, text, uuid, jsonb, text, text, integer, integer, integer)
to service_role;

comment on function public.complete_consultation_ai_generation_v3(bigint, text, uuid, jsonb, text, text, integer, integer, integer)
is 'Persiste exclusivamente respostas válidas do contrato consultation-assistant-v6 emitido pela Edge Function consultation-ai.';

notify pgrst, 'reload schema';
