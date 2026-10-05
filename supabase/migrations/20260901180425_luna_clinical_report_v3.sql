-- HPSM · Luna como redatora de laudo clínico fictício v3.
-- Preserva os schemas históricos, a imagem-fonte e a decisão humana.

alter table public.exam_ai_generations drop constraint exam_ai_generations_prompt_check;
alter table public.exam_ai_generations add constraint exam_ai_generations_prompt_check check (
  (generation_type = 'generate_image' and prompt_version in ('exam-image-rp-v1', 'exam-image-rp-v2'))
  or (generation_type <> 'generate_image' and prompt_version in ('exam-rp-luna-v1', 'exam-rp-luna-v2', 'exam-rp-luna-v3'))
);

create or replace function public.begin_clinical_exam_ai_generation(
  p_exam_id bigint,
  p_generation_type text,
  p_requested_by uuid,
  p_idempotency_key uuid,
  p_source_image_generation_id uuid,
  p_source_image_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_exam public.clinical_exams;
  v_generation public.exam_ai_generations;
  v_recent_count integer;
begin
  if p_requested_by is null or p_idempotency_key is null then raise exception 'Requisição de IA inválida.'; end if;
  if p_generation_type not in ('generate_lab_results', 'generate_report') then raise exception 'Operação de IA inválida.'; end if;
  if p_source_image_generation_id is not null and p_source_image_id is not null then raise exception 'Referência de imagem inválida.'; end if;
  if p_generation_type <> 'generate_report' and (p_source_image_generation_id is not null or p_source_image_id is not null) then raise exception 'Esta operação não aceita imagem.'; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_exam_id::text || ':' || p_generation_type, 0));
  select * into v_generation from public.exam_ai_generations where idempotency_key = p_idempotency_key for update;
  if v_generation.id is not null then
    if v_generation.exam_id <> p_exam_id or v_generation.generation_type <> p_generation_type or v_generation.requested_by <> p_requested_by
       or v_generation.source_image_generation_id is distinct from p_source_image_generation_id
       or v_generation.source_image_id is distinct from p_source_image_id then raise exception 'Chave de idempotência inválida.'; end if;
    return jsonb_build_object('generation_id', v_generation.id, 'status', v_generation.status, 'suggestion', v_generation.suggestion_payload, 'replayed', true);
  end if;

  select * into v_exam from public.clinical_exams where id = p_exam_id for update;
  if v_exam.id is null then raise exception 'Exame não localizado.'; end if;
  if v_exam.status <> 'in_progress' then raise exception 'A IA só pode auxiliar exames em execução.'; end if;
  if not private.can_access_clinical_exam_ai(p_requested_by, p_exam_id) then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if p_generation_type = 'generate_lab_results' and v_exam.result_data->>'schema' <> 'hpsm.lab_result.v1' then raise exception 'A geração de resultados está disponível apenas para exames laboratoriais.'; end if;
  if p_source_image_generation_id is not null and not exists (
    select 1 from public.exam_ai_generations source
    where source.id = p_source_image_generation_id and source.exam_id = p_exam_id
      and source.generation_type = 'generate_image' and source.status = 'completed' and source.draft_storage_path is not null
  ) then raise exception 'O rascunho de imagem selecionado não está disponível.'; end if;
  if p_source_image_id is not null and not exists (
    select 1 from public.clinical_exam_images image where image.id = p_source_image_id and image.exam_id = p_exam_id and image.removed_at is null
  ) then raise exception 'A imagem selecionada não está disponível.'; end if;

  select * into v_generation from public.exam_ai_generations
  where exam_id = p_exam_id and generation_type = p_generation_type and status = 'requested'
  order by created_at desc limit 1 for update;
  if v_generation.id is not null and v_generation.created_at >= now() - interval '2 minutes' then
    return jsonb_build_object('generation_id', v_generation.id, 'status', 'requested', 'suggestion', null, 'replayed', true);
  elsif v_generation.id is not null then
    update public.exam_ai_generations set status = 'failed', failed_at = now(), error_code = 'stale_request' where id = v_generation.id;
  end if;

  select count(*)::integer into v_recent_count from public.exam_ai_generations
  where requested_by = p_requested_by and created_at >= now() - interval '10 minutes';
  if v_recent_count >= 6 then raise exception 'Limite temporário de gerações atingido. Aguarde alguns minutos.'; end if;

  insert into public.exam_ai_generations (
    exam_id, generation_type, requested_by, model, reasoning_effort, prompt_version, source_exam_updated_at,
    source_image_generation_id, source_image_id, idempotency_key
  ) values (
    p_exam_id, p_generation_type, p_requested_by, 'gpt-5.6-luna', 'low', 'exam-rp-luna-v3', v_exam.updated_at,
    p_source_image_generation_id, p_source_image_id, p_idempotency_key
  ) returning * into v_generation;

  perform private.audit_exam_action(
    p_requested_by, 'clinical_exam.ai_requested', 'exam_ai_generations', v_generation.id::text, null,
    jsonb_build_object(
      'exam_id', p_exam_id, 'generation_type', p_generation_type, 'model', v_generation.model,
      'prompt_version', v_generation.prompt_version, 'source_image_generation_id', p_source_image_generation_id,
      'source_image_id', p_source_image_id
    )
  );
  return jsonb_build_object('generation_id', v_generation.id, 'status', v_generation.status, 'suggestion', null, 'replayed', false);
end;
$$;

create or replace function private.clinical_exam_ai_report_values(p_payload jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_findings text;
begin
  if p_payload->>'schema' = 'hpsm.ai.clinical_report.v3' then
    select string_agg('- ' || btrim(item), E'\n') into v_findings
    from jsonb_array_elements_text(p_payload->'findings') item;
    return jsonb_build_object(
      'technique', nullif(btrim(p_payload->>'technique'), ''),
      'findings', nullif(v_findings, ''),
      'conclusion', nullif(btrim(p_payload->>'conclusion'), ''),
      'conduct', nullif(btrim(p_payload->>'conduct'), '')
    );
  elsif p_payload->>'schema' in ('hpsm.ai.simple_report.v1', 'hpsm.ai.simple_report.v2') then
    select string_agg('- ' || btrim(item), E'\n') into v_findings
    from jsonb_array_elements_text(p_payload->'findings') item;
    return jsonb_build_object(
      'technique', nullif(btrim(p_payload->>'summary'), ''),
      'findings', nullif(v_findings, ''),
      'conclusion', nullif(btrim(p_payload->>'conclusion'), ''),
      'conduct', case when p_payload->>'schema' = 'hpsm.ai.simple_report.v1' then nullif(btrim(p_payload->>'rp_note'), '') else null end
    );
  elsif p_payload->>'schema' = 'hpsm.ai.report_suggestion.v1' then
    return jsonb_build_object(
      'technique', nullif(btrim(p_payload#>>'{fields,technique}'), ''),
      'findings', nullif(btrim(p_payload#>>'{fields,findings}'), ''),
      'conclusion', nullif(btrim(p_payload#>>'{fields,conclusion}'), ''),
      'conduct', nullif(btrim(p_payload#>>'{fields,observations}'), '')
    );
  end if;
  raise exception 'Schema de laudo de IA incompatível.';
end;
$$;

revoke all on function private.clinical_exam_ai_report_values(jsonb) from public, anon, authenticated, service_role;

create or replace function private.validate_exam_ai_suggestion(p_exam_id bigint, p_generation_type text, p_payload jsonb)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_exam public.clinical_exams;
  v_candidate jsonb;
  v_config jsonb;
  v_report_text text;
begin
  select * into v_exam from public.clinical_exams where id = p_exam_id;
  if v_exam.id is null or v_exam.status <> 'in_progress' then raise exception 'O exame não aceita mais sugestões de IA.'; end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then raise exception 'Sugestão de IA inválida.'; end if;

  if p_generation_type = 'generate_lab_results' then
    if p_payload->>'schema' <> 'hpsm.ai.lab_suggestion.v1'
       or coalesce(jsonb_typeof(p_payload->'parameters'), '') <> 'array'
       or coalesce(jsonb_typeof(p_payload->'notes'), '') <> 'string'
       or exists (select 1 from jsonb_object_keys(p_payload) key where key not in ('schema', 'parameters', 'notes'))
       or jsonb_array_length(p_payload->'parameters') <> (
         select count(*) from jsonb_array_elements(v_exam.result_data#>'{template_snapshot,parameters}') parameter
         where coalesce((parameter->>'active')::boolean, false)
       )
       or (select count(*) <> count(distinct parameter->>'key') from jsonb_array_elements(p_payload->'parameters') parameter)
       or exists (
         select 1 from jsonb_array_elements(v_exam.result_data#>'{template_snapshot,parameters}') snapshot
         where coalesce((snapshot->>'active')::boolean, false)
           and not exists (select 1 from jsonb_array_elements(p_payload->'parameters') suggestion where suggestion->>'key' = snapshot->>'key')
       ) then raise exception 'Sugestão laboratorial incompatível com o template.'; end if;
    v_candidate := v_exam.result_data || jsonb_build_object('parameters', p_payload->'parameters', 'notes', left(p_payload->>'notes', 12000));
    perform private.normalize_lab_result(v_exam.result_data, v_candidate);
  elsif p_generation_type = 'generate_report' and p_payload->>'schema' = 'hpsm.ai.clinical_report.v3' then
    if exists (select 1 from jsonb_object_keys(p_payload) key where key not in ('schema', 'technique', 'findings', 'conclusion', 'conduct'))
       or coalesce(jsonb_typeof(p_payload->'technique'), '') <> 'string'
       or coalesce(jsonb_typeof(p_payload->'findings'), '') <> 'array'
       or coalesce(jsonb_typeof(p_payload->'conclusion'), '') <> 'string'
       or coalesce(jsonb_typeof(p_payload->'conduct'), '') <> 'string' then
      raise exception 'Laudo clínico gerado por IA inválido.';
    end if;
    if jsonb_array_length(p_payload->'findings') not between 1 and 4
       or char_length(btrim(p_payload->>'technique')) not between 1 and 600
       or char_length(btrim(p_payload->>'conclusion')) not between 1 and 1000
       or char_length(btrim(p_payload->>'conduct')) not between 1 and 1200
       or exists (
         select 1 from jsonb_array_elements(p_payload->'findings') item
         where jsonb_typeof(item) <> 'string' or char_length(btrim(item#>>'{}')) not between 1 and 1200
       ) then raise exception 'Laudo clínico gerado por IA fora dos limites permitidos.'; end if;
    select lower(concat_ws(' ', p_payload->>'technique', p_payload->>'conclusion', p_payload->>'conduct', string_agg(item, ' ')))
    into v_report_text from jsonb_array_elements_text(p_payload->'findings') item;
    if v_report_text ~ '(sugest|possível|possivelmente|provavelmente|pode[[:space:]]+(ser|representar|indicar)|recomenda-se[[:space:]]+avaliação[[:space:]]+profissional|procure[[:space:]]+um[[:space:]]+médico|necessita[[:space:]]+avaliação[[:space:]]+especializada)' then
      raise exception 'O laudo deve declarar diretamente os achados do exame fictício.';
    end if;
  elsif p_generation_type = 'generate_report' and p_payload->>'schema' in ('hpsm.ai.simple_report.v1', 'hpsm.ai.simple_report.v2') then
    if exists (
         select 1 from jsonb_object_keys(p_payload) key
         where key not in ('schema', 'summary', 'findings', 'conclusion', 'rp_note')
       )
       or coalesce(jsonb_typeof(p_payload->'summary'), '') <> 'string'
       or coalesce(jsonb_typeof(p_payload->'findings'), '') <> 'array'
       or coalesce(jsonb_typeof(p_payload->'conclusion'), '') <> 'string'
       or (p_payload->>'schema' = 'hpsm.ai.simple_report.v1' and coalesce(jsonb_typeof(p_payload->'rp_note'), '') <> 'string')
       or (p_payload->>'schema' = 'hpsm.ai.simple_report.v2' and p_payload ? 'rp_note')
       or jsonb_array_length(p_payload->'findings') not between 1 and 4
       or char_length(p_payload->>'summary') > 1200
       or char_length(p_payload->>'conclusion') > 1200
       or char_length(coalesce(p_payload->>'rp_note', '')) > 600
       or exists (select 1 from jsonb_array_elements(p_payload->'findings') item where jsonb_typeof(item) <> 'string' or char_length(item#>>'{}') > 1200)
    then raise exception 'Sugestão de laudo simplificado inválida.'; end if;
  elsif p_generation_type = 'generate_report' then
    v_config := coalesce(v_exam.result_data->'report_config_snapshot', private.clinical_exam_report_config(v_exam.exam_type_id));
    if p_payload->>'schema' <> 'hpsm.ai.report_suggestion.v1'
       or coalesce(jsonb_typeof(p_payload->'fields'), '') <> 'object'
       or exists (select 1 from jsonb_object_keys(p_payload) key where key not in ('schema', 'fields'))
       or exists (
         select 1 from jsonb_object_keys(p_payload->'fields') key
         where key not in ('technique', 'findings', 'conclusion', 'observations')
            or coalesce((v_config#>>array['fields', key, 'visible'])::boolean, false) is false
            or jsonb_typeof(p_payload->'fields'->key) <> 'string'
            or char_length(p_payload->'fields'->>key) > case key when 'findings' then 8000 when 'observations' then 12000 else 4000 end
       )
       or exists (
         select 1 from jsonb_object_keys(v_config->'fields') key
         where coalesce((v_config#>>array['fields', key, 'visible'])::boolean, false) and not (p_payload->'fields' ? key)
       ) then raise exception 'Sugestão de laudo incompatível com a configuração do exame.'; end if;
  else
    raise exception 'Operação de IA inválida.';
  end if;
end;
$$;

create or replace function public.apply_clinical_exam_ai_generation(p_generation_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_generation public.exam_ai_generations;
  v_exam public.clinical_exams;
  v_parameters jsonb;
  v_candidate jsonb;
  v_result_data jsonb;
  v_config jsonb;
  v_report_values jsonb;
  v_technique text;
  v_findings text;
  v_conclusion text;
  v_conduct text;
begin
  select * into v_generation from public.exam_ai_generations where id = p_generation_id;
  if v_generation.id is null then raise exception 'Sugestão de IA não localizada.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_generation.exam_id::text || ':' || v_generation.generation_type, 0));
  select * into v_exam from public.clinical_exams where id = v_generation.exam_id for update;
  select * into v_generation from public.exam_ai_generations where id = p_generation_id for update;
  if v_exam.status <> 'in_progress' then raise exception 'O exame não aceita mais alterações.'; end if;
  if not private.can_access_clinical_exam_ai(v_actor, v_exam.id) then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if v_generation.status <> 'completed' then raise exception 'A sugestão de IA não está disponível para aplicação.'; end if;
  if v_exam.updated_at is distinct from v_generation.source_exam_updated_at then raise exception 'O exame foi atualizado após a geração. Gere uma nova sugestão para comparar com o rascunho atual.'; end if;
  perform private.validate_exam_ai_suggestion(v_exam.id, v_generation.generation_type, v_generation.suggestion_payload);

  if v_generation.generation_type = 'generate_lab_results' then
    select jsonb_agg(parameter || jsonb_build_object('value', suggestion.item->>'value', 'flag', suggestion.item->'flag')
      order by (parameter->>'sort_order')::integer, parameter->>'label') into v_parameters
    from jsonb_array_elements(v_exam.result_data->'parameters') parameter
    join lateral (select item from jsonb_array_elements(v_generation.suggestion_payload->'parameters') item where item->>'key' = parameter->>'key' limit 1) suggestion on true;
    v_candidate := v_exam.result_data || jsonb_build_object('parameters', v_parameters, 'notes', v_generation.suggestion_payload->>'notes');
    v_result_data := private.normalize_lab_result(v_exam.result_data, v_candidate)
      || jsonb_build_object('report_config_snapshot', v_exam.result_data->'report_config_snapshot', 'exam_type_snapshot', v_exam.result_data->'exam_type_snapshot');
    update public.clinical_exams set result_data = v_result_data where id = v_exam.id;
  else
    v_config := coalesce(v_exam.result_data->'report_config_snapshot', private.clinical_exam_report_config(v_exam.exam_type_id));
    v_report_values := private.clinical_exam_ai_report_values(v_generation.suggestion_payload);
    v_technique := v_report_values->>'technique';
    v_findings := v_report_values->>'findings';
    v_conclusion := v_report_values->>'conclusion';
    v_conduct := v_report_values->>'conduct';
    v_result_data := case
      when v_generation.suggestion_payload->>'schema' = 'hpsm.ai.clinical_report.v3'
        then jsonb_set(v_exam.result_data, '{notes}', to_jsonb(v_conduct), true)
      when v_exam.result_data->>'schema' = 'hpsm.image_result.v1' then v_exam.result_data
      when v_conduct is not null and coalesce((v_config#>>'{fields,observations,visible}')::boolean, false)
        then jsonb_set(v_exam.result_data, '{notes}', to_jsonb(v_conduct), true)
      else v_exam.result_data
    end;
    update public.clinical_exams set
      technique = case when coalesce((v_config#>>'{fields,technique,visible}')::boolean, false) then v_technique else technique end,
      findings = case when coalesce((v_config#>>'{fields,findings,visible}')::boolean, false) then v_findings else findings end,
      conclusion = case when coalesce((v_config#>>'{fields,conclusion,visible}')::boolean, false) then v_conclusion else conclusion end,
      result_data = v_result_data
    where id = v_exam.id;
  end if;

  update public.exam_ai_generations set status = 'applied', applied_at = now() where id = p_generation_id;
  perform private.audit_exam_action(v_actor, 'clinical_exam.ai_applied', 'exam_ai_generations', p_generation_id::text,
    jsonb_build_object('status', 'completed'),
    jsonb_build_object('status', 'applied', 'exam_id', v_exam.id, 'generation_type', v_generation.generation_type,
      'model', v_generation.model, 'prompt_version', v_generation.prompt_version,
      'source_image_generation_id', v_generation.source_image_generation_id, 'source_image_id', v_generation.source_image_id));
end;
$$;

create or replace function public.apply_clinical_exam_ai_bundle(
  p_image_generation_id uuid,
  p_report_generation_id uuid,
  p_actor uuid,
  p_image_id uuid,
  p_storage_path text,
  p_file_size bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_image_generation public.exam_ai_generations;
  v_report_generation public.exam_ai_generations;
  v_exam public.clinical_exams;
  v_count integer;
  v_config jsonb;
  v_report_values jsonb;
  v_findings text;
  v_technique text;
  v_conclusion text;
  v_conduct text;
  v_result_data jsonb;
begin
  select * into v_image_generation from public.exam_ai_generations where id = p_image_generation_id;
  select * into v_report_generation from public.exam_ai_generations where id = p_report_generation_id;
  if v_image_generation.id is null or v_report_generation.id is null or v_image_generation.exam_id <> v_report_generation.exam_id then raise exception 'Prévia de IA incompleta.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_image_generation.exam_id::text || ':ai_bundle', 0));
  select * into v_exam from public.clinical_exams where id = v_image_generation.exam_id for update;
  select * into v_image_generation from public.exam_ai_generations where id = p_image_generation_id for update;
  select * into v_report_generation from public.exam_ai_generations where id = p_report_generation_id for update;

  if v_exam.status <> 'in_progress' or v_exam.responsible_professional_id is distinct from p_actor or not private.has_permission(p_actor, 'exams.perform') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if v_image_generation.generation_type <> 'generate_image' or v_image_generation.status <> 'completed' or v_image_generation.requested_by is distinct from p_actor then raise exception 'Rascunho de imagem indisponível.'; end if;
  if v_report_generation.generation_type <> 'generate_report' or v_report_generation.status <> 'completed' then raise exception 'Laudo gerado por IA indisponível.'; end if;
  if v_report_generation.source_image_generation_id is distinct from p_image_generation_id then raise exception 'O laudo não corresponde à imagem desta prévia.'; end if;
  if v_exam.updated_at is distinct from v_report_generation.source_exam_updated_at then raise exception 'O exame foi atualizado após a geração. Gere uma nova prévia.'; end if;
  if p_storage_path <> 'clinical-exams/' || v_exam.id::text || '/' || p_image_id::text || '.png'
     or p_file_size <> v_image_generation.draft_file_size then raise exception 'Imagem final inválida.'; end if;
  perform private.validate_exam_ai_suggestion(v_exam.id, 'generate_report', v_report_generation.suggestion_payload);

  select count(*) into v_count from public.clinical_exam_images where exam_id = v_exam.id and removed_at is null;
  if not (v_exam.result_data#>>'{template_snapshot,allows_multiple_images}')::boolean and v_count > 0 then raise exception 'Este tipo de exame aceita somente uma imagem.'; end if;
  insert into public.clinical_exam_images(id, exam_id, storage_path, original_filename, mime_type, file_size, sort_order, caption, source, uploaded_by)
  values(p_image_id, v_exam.id, p_storage_path, 'imagem-ficticia-ia.png', 'image/png', p_file_size, (v_count + 1) * 10,
    'Imagem fictícia gerada por IA para fins de RP.', 'ai_generated', p_actor);

  v_config := coalesce(v_exam.result_data->'report_config_snapshot', private.clinical_exam_report_config(v_exam.exam_type_id));
  v_report_values := private.clinical_exam_ai_report_values(v_report_generation.suggestion_payload);
  v_technique := v_report_values->>'technique';
  v_findings := v_report_values->>'findings';
  v_conclusion := v_report_values->>'conclusion';
  v_conduct := v_report_values->>'conduct';
  v_result_data := case
    when v_report_generation.suggestion_payload->>'schema' = 'hpsm.ai.clinical_report.v3'
      then jsonb_set(v_exam.result_data, '{notes}', to_jsonb(v_conduct), true)
    when v_exam.result_data->>'schema' = 'hpsm.image_result.v1' then v_exam.result_data
    when v_conduct is not null and coalesce((v_config#>>'{fields,observations,visible}')::boolean, false)
      then jsonb_set(v_exam.result_data, '{notes}', to_jsonb(v_conduct), true)
    else v_exam.result_data
  end;
  update public.clinical_exams set
    technique = case when coalesce((v_config#>>'{fields,technique,visible}')::boolean, false) then v_technique else technique end,
    findings = case when coalesce((v_config#>>'{fields,findings,visible}')::boolean, false) then v_findings else findings end,
    conclusion = case when coalesce((v_config#>>'{fields,conclusion,visible}')::boolean, false) then v_conclusion else conclusion end,
    result_data = v_result_data
  where id = v_exam.id;

  update public.exam_ai_generations set status = 'applied', applied_at = now(), official_image_id = p_image_id where id = p_image_generation_id;
  update public.exam_ai_generations set status = 'applied', applied_at = now() where id = p_report_generation_id;
  perform private.audit_exam_action(p_actor, 'clinical_exam.ai_bundle_applied', 'clinical_exams', v_exam.id::text, null,
    jsonb_build_object('image_generation_id', p_image_generation_id, 'report_generation_id', p_report_generation_id,
      'image_id', p_image_id, 'image_model', v_image_generation.model, 'report_model', v_report_generation.model,
      'report_prompt_version', v_report_generation.prompt_version));
  return jsonb_build_object('exam_id', v_exam.id, 'image_id', p_image_id, 'draft_path', v_image_generation.draft_storage_path);
end;
$$;

revoke all on function public.begin_clinical_exam_ai_generation(bigint, text, uuid, uuid, uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function private.validate_exam_ai_suggestion(bigint, text, jsonb) from public, anon, authenticated, service_role;
revoke all on function public.apply_clinical_exam_ai_generation(uuid) from public, anon, authenticated, service_role;
revoke all on function public.apply_clinical_exam_ai_bundle(uuid, uuid, uuid, uuid, text, bigint) from public, anon, authenticated, service_role;

grant execute on function public.begin_clinical_exam_ai_generation(bigint, text, uuid, uuid, uuid, uuid) to service_role;
grant execute on function public.apply_clinical_exam_ai_generation(uuid) to authenticated;
grant execute on function public.apply_clinical_exam_ai_bundle(uuid, uuid, uuid, uuid, text, bigint) to service_role;

comment on function public.begin_clinical_exam_ai_generation(bigint, text, uuid, uuid, uuid, uuid) is
  'Inicia geração textual Luna v3, preservando idempotência, limite de taxa e a imagem efetivamente analisada.';
comment on function private.clinical_exam_ai_report_values(jsonb) is
  'Normaliza laudos históricos v1/v2 e o laudo clínico v3 para os campos canônicos do exame.';

notify pgrst, 'reload schema';
