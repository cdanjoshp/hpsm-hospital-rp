-- HPSM — simplificação das Fases 4.6/4.7.
-- A imagem fictícia e o laudo curto passam a formar um fluxo único, ainda sujeito à decisão humana.

alter table public.exam_ai_generations
  add column source_image_generation_id uuid,
  add column source_image_id uuid references public.clinical_exam_images(id) on delete restrict,
  add constraint exam_ai_generations_source_image_generation_fkey
    foreign key (source_image_generation_id) references public.exam_ai_generations(id) on delete restrict;

alter table public.exam_ai_generations drop constraint exam_ai_generations_prompt_check;
alter table public.exam_ai_generations add constraint exam_ai_generations_prompt_check check (
  (generation_type = 'generate_image' and prompt_version in ('exam-image-rp-v1', 'exam-image-rp-v2'))
  or (generation_type <> 'generate_image' and prompt_version in ('exam-rp-luna-v1', 'exam-rp-luna-v2'))
);
alter table public.exam_ai_generations add constraint exam_ai_generations_source_image_check check (
  not (source_image_generation_id is not null and source_image_id is not null)
  and (generation_type = 'generate_report' or (source_image_generation_id is null and source_image_id is null))
);

create or replace function private.protect_exam_ai_generation_update()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.id is distinct from old.id or new.exam_id is distinct from old.exam_id
     or new.generation_type is distinct from old.generation_type or new.requested_by is distinct from old.requested_by
     or new.model is distinct from old.model or new.reasoning_effort is distinct from old.reasoning_effort
     or new.prompt_version is distinct from old.prompt_version or new.source_exam_updated_at is distinct from old.source_exam_updated_at
     or new.source_image_generation_id is distinct from old.source_image_generation_id
     or new.source_image_id is distinct from old.source_image_id
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
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.clinical_exam_ai_context(p_exam_id bigint, p_generation_type text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_exam public.clinical_exams;
  v_category_code text;
  v_category_name text;
  v_type_code text;
  v_type_name text;
  v_report_config jsonb;
  v_lab_template jsonb;
  v_result_context jsonb := '{}'::jsonb;
begin
  if p_generation_type not in ('generate_lab_results', 'generate_report') then raise exception 'Operação de IA inválida.'; end if;
  select * into v_exam from public.clinical_exams exam where exam.id = p_exam_id;
  if v_exam.id is null then raise exception 'Exame não localizado.'; end if;
  if v_exam.status <> 'in_progress' then raise exception 'A IA só pode auxiliar exames em execução.'; end if;
  if not private.can_access_clinical_exam_ai(v_actor, p_exam_id) then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;

  select category.code, category.name, exam_type.code, exam_type.name
  into v_category_code, v_category_name, v_type_code, v_type_name
  from public.exam_types exam_type
  join public.exam_categories category on category.id = exam_type.category_id
  where exam_type.id = v_exam.exam_type_id;

  v_report_config := coalesce(v_exam.result_data->'report_config_snapshot', private.clinical_exam_report_config(v_exam.exam_type_id));
  if p_generation_type = 'generate_lab_results' then
    if v_exam.result_data->>'schema' <> 'hpsm.lab_result.v1' then raise exception 'A geração de resultados está disponível apenas para exames laboratoriais.'; end if;
    v_lab_template := jsonb_build_object(
      'schema', v_exam.result_data#>>'{template_snapshot,schema}',
      'version', v_exam.result_data->'template_version',
      'parameters', coalesce(v_exam.result_data#>'{template_snapshot,parameters}', '[]'::jsonb)
    );
  elsif v_exam.result_data->>'schema' = 'hpsm.lab_result.v1' then
    select jsonb_build_object(
      'kind', 'laboratory',
      'parameters', coalesce(jsonb_agg(jsonb_build_object(
        'key', parameter->>'key', 'label', parameter->>'label', 'value', parameter->>'value',
        'unit', parameter->>'unit', 'reference', parameter->>'reference', 'flag', parameter->'flag'
      ) order by (parameter->>'sort_order')::integer, parameter->>'label'), '[]'::jsonb),
      'notes', left(coalesce(v_exam.result_data->>'notes', ''), 4000)
    ) into v_result_context
    from jsonb_array_elements(v_exam.result_data->'parameters') parameter;
  elsif v_exam.result_data->>'schema' = 'hpsm.image_result.v1' then
    v_result_context := jsonb_build_object(
      'kind', 'imaging',
      'region', case when v_exam.result_data->>'region' = 'Outra região' then v_exam.result_data->>'other_region' else v_exam.result_data->>'region' end,
      'laterality', v_exam.result_data->>'laterality',
      'contrast', v_exam.result_data->>'contrast',
      'observation', left(coalesce(v_exam.result_data->>'notes', ''), 4000),
      'current_findings', left(coalesce(v_exam.findings, ''), 4000)
    );
  else
    v_result_context := jsonb_build_object('kind', 'generic', 'observation', left(coalesce(v_exam.result_data->>'notes', ''), 4000));
  end if;

  return jsonb_build_object(
    'actor_id', v_actor,
    'exam_id', v_exam.id,
    'generation_type', p_generation_type,
    'patient_context', 'Paciente fictício do RP',
    'exam', jsonb_build_object('category_code', v_category_code, 'category_name', v_category_name, 'type_code', v_type_code, 'type_name', v_type_name),
    'case_context', jsonb_build_object(
      'short_context', left(coalesce(v_exam.clinical_context, ''), 4000),
      'main_suspicion', left(v_exam.indication, 2000)
    ),
    'report_config', v_report_config,
    'lab_template', v_lab_template,
    'result_context', v_result_context
  );
end;
$$;

create or replace function public.clinical_exam_ai_visual_input(
  p_exam_id bigint,
  p_requested_by uuid,
  p_draft_generation_id uuid
)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_exam public.clinical_exams;
  v_generation public.exam_ai_generations;
  v_image public.clinical_exam_images;
begin
  select * into v_exam from public.clinical_exams where id = p_exam_id;
  if v_exam.id is null or v_exam.status <> 'in_progress' then raise exception 'O exame não aceita geração de laudo.'; end if;
  if not private.can_access_clinical_exam_ai(p_requested_by, p_exam_id) then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;

  if p_draft_generation_id is not null then
    select * into v_generation from public.exam_ai_generations
    where id = p_draft_generation_id and exam_id = p_exam_id and generation_type = 'generate_image'
      and status = 'completed' and draft_storage_path is not null;
    if v_generation.id is null then raise exception 'O rascunho de imagem selecionado não está disponível.'; end if;
  else
    select * into v_generation from public.exam_ai_generations
    where exam_id = p_exam_id and generation_type = 'generate_image' and status = 'completed' and draft_storage_path is not null
    order by completed_at desc nulls last, created_at desc, id desc limit 1;
  end if;

  if v_generation.id is not null then
    return jsonb_build_object(
      'source', 'draft', 'storage_path', v_generation.draft_storage_path, 'mime_type', v_generation.draft_mime_type,
      'source_image_generation_id', v_generation.id, 'source_image_id', null
    );
  end if;

  select * into v_image from public.clinical_exam_images
  where exam_id = p_exam_id and removed_at is null
  order by created_at desc, id desc limit 1;
  if v_image.id is null then return null; end if;
  return jsonb_build_object(
    'source', 'official', 'storage_path', v_image.storage_path, 'mime_type', v_image.mime_type,
    'source_image_generation_id', null, 'source_image_id', v_image.id
  );
end;
$$;

create or replace function public.begin_clinical_exam_ai_generation(
  p_exam_id bigint,
  p_generation_type text,
  p_requested_by uuid,
  p_idempotency_key uuid,
  p_source_image_generation_id uuid,
  p_source_image_id uuid
)
returns jsonb language plpgsql security definer set search_path = '' as $$
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
    p_exam_id, p_generation_type, p_requested_by, 'gpt-5.6-luna', 'low', 'exam-rp-luna-v2', v_exam.updated_at,
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

create or replace function private.validate_exam_ai_suggestion(p_exam_id bigint, p_generation_type text, p_payload jsonb)
returns void language plpgsql stable security definer set search_path = '' as $$
declare
  v_exam public.clinical_exams;
  v_candidate jsonb;
  v_config jsonb;
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
  elsif p_generation_type = 'generate_report' and p_payload->>'schema' = 'hpsm.ai.simple_report.v1' then
    if exists (select 1 from jsonb_object_keys(p_payload) key where key not in ('schema', 'summary', 'findings', 'conclusion', 'rp_note'))
       or coalesce(jsonb_typeof(p_payload->'summary'), '') <> 'string'
       or coalesce(jsonb_typeof(p_payload->'findings'), '') <> 'array'
       or coalesce(jsonb_typeof(p_payload->'conclusion'), '') <> 'string'
       or coalesce(jsonb_typeof(p_payload->'rp_note'), '') <> 'string'
       or jsonb_array_length(p_payload->'findings') not between 1 and 4
       or char_length(p_payload->>'summary') > 1200
       or char_length(p_payload->>'conclusion') > 1200
       or char_length(p_payload->>'rp_note') > 600
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
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_generation public.exam_ai_generations;
  v_exam public.clinical_exams;
  v_parameters jsonb;
  v_candidate jsonb;
  v_result_data jsonb;
  v_config jsonb;
  v_fields jsonb;
  v_technique text;
  v_findings text;
  v_conclusion text;
  v_observations text;
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
    if v_generation.suggestion_payload->>'schema' = 'hpsm.ai.simple_report.v1' then
      select string_agg('- ' || item, E'\n') into v_findings from jsonb_array_elements_text(v_generation.suggestion_payload->'findings') item;
      v_technique := nullif(btrim(v_generation.suggestion_payload->>'summary'), '');
      v_conclusion := nullif(btrim(v_generation.suggestion_payload->>'conclusion'), '');
      v_observations := btrim(v_generation.suggestion_payload->>'rp_note');
    else
      v_fields := v_generation.suggestion_payload->'fields';
      v_technique := nullif(btrim(v_fields->>'technique'), '');
      v_findings := nullif(btrim(v_fields->>'findings'), '');
      v_conclusion := nullif(btrim(v_fields->>'conclusion'), '');
      v_observations := coalesce(v_fields->>'observations', '');
    end if;
    v_result_data := case when coalesce((v_config#>>'{fields,observations,visible}')::boolean, false)
      then jsonb_set(v_exam.result_data, '{notes}', to_jsonb(v_observations), true) else v_exam.result_data end;
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
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_image_generation public.exam_ai_generations;
  v_report_generation public.exam_ai_generations;
  v_exam public.clinical_exams;
  v_count integer;
  v_config jsonb;
  v_fields jsonb;
  v_findings text;
  v_technique text;
  v_conclusion text;
  v_observations text;
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
  if v_report_generation.generation_type <> 'generate_report' or v_report_generation.status <> 'completed' then raise exception 'Sugestão de laudo indisponível.'; end if;
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
  if v_report_generation.suggestion_payload->>'schema' = 'hpsm.ai.simple_report.v1' then
    select string_agg('- ' || item, E'\n') into v_findings from jsonb_array_elements_text(v_report_generation.suggestion_payload->'findings') item;
    v_technique := nullif(btrim(v_report_generation.suggestion_payload->>'summary'), '');
    v_conclusion := nullif(btrim(v_report_generation.suggestion_payload->>'conclusion'), '');
    v_observations := btrim(v_report_generation.suggestion_payload->>'rp_note');
  else
    v_fields := v_report_generation.suggestion_payload->'fields';
    v_technique := nullif(btrim(v_fields->>'technique'), '');
    v_findings := nullif(btrim(v_fields->>'findings'), '');
    v_conclusion := nullif(btrim(v_fields->>'conclusion'), '');
    v_observations := coalesce(v_fields->>'observations', '');
  end if;
  v_result_data := case when coalesce((v_config#>>'{fields,observations,visible}')::boolean, false)
    then jsonb_set(v_exam.result_data, '{notes}', to_jsonb(v_observations), true) else v_exam.result_data end;
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
      'image_id', p_image_id, 'image_model', v_image_generation.model, 'report_model', v_report_generation.model));
  return jsonb_build_object('exam_id', v_exam.id, 'image_id', p_image_id, 'draft_path', v_image_generation.draft_storage_path);
end;
$$;

create or replace function public.clinical_exam_ai_generations(p_exam_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_actor uuid := private.hpsm_current_actor(); v_result jsonb;
begin
  if not private.has_permission(v_actor, 'exams.view') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if not exists (select 1 from public.clinical_exams exam where exam.id = p_exam_id) then raise exception 'Exame não localizado.'; end if;
  if not private.can_access_clinical_exam_ai(v_actor, p_exam_id) then return '[]'::jsonb; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', generation.id, 'generation_type', generation.generation_type, 'status', generation.status,
    'model', generation.model, 'reasoning_effort', generation.reasoning_effort, 'prompt_version', generation.prompt_version,
    'suggestion_payload', generation.suggestion_payload, 'source_image_generation_id', generation.source_image_generation_id,
    'source_image_id', generation.source_image_id, 'created_at', generation.created_at,
    'completed_at', generation.completed_at, 'applied_at', generation.applied_at
  ) order by generation.generation_type, generation.state_rank), '[]'::jsonb) into v_result
  from (
    select distinct on (item.generation_type, case when item.status = 'applied' then 1 else 0 end)
      item.*, case when item.status = 'applied' then 1 else 0 end as state_rank
    from public.exam_ai_generations item
    where item.exam_id = p_exam_id and item.status in ('requested', 'completed', 'applied')
    order by item.generation_type, case when item.status = 'applied' then 1 else 0 end, item.created_at desc, item.id desc
  ) generation;
  return v_result;
end;
$$;

create or replace function public.clinical_exam_ai_image_context(p_exam_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_actor uuid := private.hpsm_current_actor(); v_exam public.clinical_exams; v_type_code text; v_type_name text;
begin
  select exam.* into v_exam from public.clinical_exams exam where exam.id = p_exam_id;
  if v_exam.id is null then raise exception 'Exame não localizado.'; end if;
  select exam_type.code, exam_type.name into v_type_code, v_type_name from public.exam_types exam_type where exam_type.id = v_exam.exam_type_id;
  if v_exam.status <> 'in_progress' then raise exception 'A imagem por IA só pode ser gerada em exame em andamento.'; end if;
  if v_exam.responsible_professional_id is distinct from v_actor or not private.has_permission(v_actor, 'exams.perform') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if v_exam.result_data->>'schema' <> 'hpsm.image_result.v1' or v_type_code not in ('raio_x', 'tomografia', 'ressonancia_magnetica', 'ultrassom') then raise exception 'Este tipo de exame não aceita geração de imagem por IA.'; end if;
  if nullif(btrim(case when v_exam.result_data->>'region' = 'Outra região' then v_exam.result_data->>'other_region' else v_exam.result_data->>'region' end), '') is null
     or nullif(btrim(v_exam.indication), '') is null or nullif(btrim(coalesce(v_exam.clinical_context, '')), '') is null
  then raise exception 'Preencha e salve a região, o contexto curto e a suspeita principal antes de gerar.'; end if;
  if coalesce((v_exam.result_data#>>'{template_snapshot,supports_laterality}')::boolean, false)
     and nullif(v_exam.result_data->>'laterality', '') is null then raise exception 'Selecione e salve a lateralidade antes de gerar.'; end if;
  return jsonb_build_object(
    'actor_id', v_actor, 'exam_id', v_exam.id, 'type_code', v_type_code, 'type_name', v_type_name,
    'region', case when v_exam.result_data->>'region' = 'Outra região' then v_exam.result_data->>'other_region' else v_exam.result_data->>'region' end,
    'laterality', v_exam.result_data->>'laterality', 'contrast', v_exam.result_data->>'contrast',
    'findings', left(coalesce(v_exam.findings, ''), 4000), 'indication', left(v_exam.indication, 2000),
    'clinical_context', left(v_exam.clinical_context, 4000), 'observation', left(coalesce(v_exam.result_data->>'notes', ''), 4000)
  );
end;
$$;

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
  if v_generation.id is not null then update public.exam_ai_generations set status = 'failed', failed_at = now(), error_code = 'stale_request' where id = v_generation.id; end if;
  select count(*) into v_recent from public.exam_ai_generations where requested_by = p_requested_by and generation_type = 'generate_image' and created_at >= now() - interval '10 minutes';
  if v_recent >= 4 then raise exception 'Limite temporário de imagens atingido. Aguarde alguns minutos.'; end if;
  insert into public.exam_ai_generations(exam_id, generation_type, requested_by, model, reasoning_effort, prompt_version, source_exam_updated_at, idempotency_key, image_quality, image_size, image_count)
  values(p_exam_id, 'generate_image', p_requested_by, 'gpt-image-2', 'low', 'exam-image-rp-v2', v_exam.updated_at, p_idempotency_key, 'low', '1024x1024', 1) returning * into v_generation;
  perform private.audit_exam_action(p_requested_by, 'clinical_exam.ai_image_requested', 'exam_ai_generations', v_generation.id::text, null,
    jsonb_build_object('exam_id', p_exam_id, 'model', 'gpt-image-2', 'quality', 'low', 'size', '1024x1024', 'image_count', 1, 'prompt_version', 'exam-image-rp-v2'));
  return jsonb_build_object('generation_id', v_generation.id, 'status', 'requested', 'replayed', false);
end;
$$;

revoke all on function public.clinical_exam_ai_visual_input(bigint, uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public.begin_clinical_exam_ai_generation(bigint, text, uuid, uuid, uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public.apply_clinical_exam_ai_bundle(uuid, uuid, uuid, uuid, text, bigint) from public, anon, authenticated, service_role;
grant execute on function public.clinical_exam_ai_visual_input(bigint, uuid, uuid) to service_role;
grant execute on function public.begin_clinical_exam_ai_generation(bigint, text, uuid, uuid, uuid, uuid) to service_role;
grant execute on function public.apply_clinical_exam_ai_bundle(uuid, uuid, uuid, uuid, text, bigint) to service_role;

comment on function public.clinical_exam_ai_visual_input(bigint, uuid, uuid) is 'Seleciona no backend uma única imagem privada para a Luna: rascunho recente, depois imagem oficial mais nova.';
comment on column public.exam_ai_generations.source_image_generation_id is 'Rascunho privado efetivamente analisado pela Luna, quando aplicável.';
comment on column public.exam_ai_generations.source_image_id is 'Imagem clínica oficial efetivamente analisada pela Luna, quando aplicável.';
notify pgrst, 'reload schema';
