-- Persistência da assistência por IA é exclusiva da Edge Function. O JWT do
-- profissional continua autorizando a leitura clínica, mas não pode concluir
-- uma geração diretamente pela Data API.

create schema if not exists extensions;
alter extension btree_gist set schema extensions;

create or replace function public.begin_consultation_ai_generation(
  p_consultation_id bigint,
  p_action_type text,
  p_request_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
  v_consultation public.clinical_consultations;
  v_generation public.consultation_ai_generations;
begin
  select * into v_consultation from public.clinical_consultations where id = p_consultation_id for update;
  if v_consultation.id is null then raise exception 'Consulta não localizada.'; end if;
  v_actor := v_consultation.professional_id;
  if v_consultation.status <> 'in_progress'
     or not private.is_hpsm_workforce(v_actor)
     or not private.has_permission(v_actor, 'consultations.complete') then
    raise exception 'A consulta não aceita assistência.' using errcode = '42501';
  end if;
  if p_action_type not in ('ANAMNESIS_REWRITE', 'EXAM_SUGGESTIONS', 'DIAGNOSIS_OPTIONS', 'FINAL_DIAGNOSIS_PLAN', 'ORIENTATION_MEDICATION') then raise exception 'Ação de IA inválida.'; end if;
  if p_request_key is null then raise exception 'Identificador da solicitação ausente.'; end if;
  select * into v_generation from public.consultation_ai_generations
  where consultation_id = p_consultation_id and action_type = p_action_type for update;
  if v_generation.id is null then
    insert into public.consultation_ai_generations (consultation_id, action_type, request_key, requested_by)
    values (p_consultation_id, p_action_type, p_request_key, v_actor)
    returning * into v_generation;
  elsif v_generation.status = 'failed' then
    update public.consultation_ai_generations set
      status = 'pending', request_key = p_request_key, response_payload = null, error_message = null,
      model = null, prompt_version = null, requested_by = v_actor, requested_at = now(), completed_at = null, failed_at = null
    where id = v_generation.id returning * into v_generation;
  end if;
  return jsonb_build_object('id', v_generation.id, 'status', v_generation.status, 'request_key', v_generation.request_key, 'response', v_generation.response_payload);
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
  v_generation public.consultation_ai_generations;
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
  if p_model <> 'gpt-5.6-luna' or p_prompt_version <> 'consultation-assistant-v1' then raise exception 'Origem da assistência inválida.' using errcode = '42501'; end if;
  if p_action_type = 'DIAGNOSIS_OPTIONS' and (
    jsonb_typeof(p_response_payload->'options') <> 'array'
    or jsonb_array_length(p_response_payload->'options') <> 3
    or (select array_agg(option->>'severity' order by option->>'severity') from jsonb_array_elements(p_response_payload->'options') option) <> array['grave', 'gravissimo', 'normal']::text[]
  ) then raise exception 'A IA deve retornar exatamente as opções Normal, Grave e Gravíssimo.'; end if;
  if p_action_type = 'EXAM_SUGGESTIONS' and exists (
    select 1 from jsonb_array_elements(coalesce(p_response_payload->'suggestions', '[]'::jsonb)) suggestion
    where not exists (
      select 1 from public.exam_types exam_type
      join public.exam_categories category on category.id = exam_type.category_id
      where exam_type.id = nullif(suggestion->>'exam_type_id', '')::bigint and exam_type.active and category.active
    )
  ) then raise exception 'A IA sugeriu um tipo de exame indisponível.'; end if;
  update public.consultation_ai_generations set
    status = 'completed', response_payload = p_response_payload, error_message = null,
    model = p_model, prompt_version = p_prompt_version, completed_at = now(), failed_at = null
  where id = v_generation.id;
  return p_response_payload;
end;
$$;

create or replace function public.fail_consultation_ai_generation(
  p_consultation_id bigint,
  p_action_type text,
  p_request_key uuid,
  p_error_message text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.consultation_ai_generations generation set
    status = 'failed', error_message = left(coalesce(nullif(btrim(p_error_message), ''), 'Falha ao gerar assistência.'), 1000), failed_at = now()
  from public.clinical_consultations consultation
  where generation.consultation_id = p_consultation_id
    and generation.action_type = p_action_type
    and generation.request_key = p_request_key
    and generation.status = 'pending'
    and consultation.id = generation.consultation_id
    and consultation.status = 'in_progress';
end;
$$;

revoke all on function public.begin_consultation_ai_generation(bigint, text, uuid) from public, anon, authenticated;
revoke all on function public.complete_consultation_ai_generation(bigint, text, uuid, jsonb, text, text) from public, anon, authenticated;
revoke all on function public.fail_consultation_ai_generation(bigint, text, uuid, text) from public, anon, authenticated;
grant execute on function public.begin_consultation_ai_generation(bigint, text, uuid) to service_role;
grant execute on function public.complete_consultation_ai_generation(bigint, text, uuid, jsonb, text, text) to service_role;
grant execute on function public.fail_consultation_ai_generation(bigint, text, uuid, text) to service_role;
