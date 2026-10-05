-- HPSM · IA gera o exame completo e o encaminha automaticamente à revisão humana.
-- Remove upload manual de imagem e restringe a decisão final ao solicitante/responsável ou cargos 11–14.

alter table public.exam_ai_generations drop constraint exam_ai_generations_type_check;
alter table public.exam_ai_generations drop constraint exam_ai_generations_prompt_check;
alter table public.exam_ai_generations add constraint exam_ai_generations_type_check check (
  generation_type in ('generate_lab_results', 'generate_report', 'generate_image', 'generate_exam')
);
alter table public.exam_ai_generations add constraint exam_ai_generations_prompt_check check (
  (generation_type = 'generate_image' and prompt_version in ('exam-image-rp-v1', 'exam-image-rp-v2'))
  or (generation_type = 'generate_exam' and prompt_version = 'exam-rp-luna-v4')
  or (generation_type in ('generate_lab_results', 'generate_report') and prompt_version in ('exam-rp-luna-v1', 'exam-rp-luna-v2', 'exam-rp-luna-v3'))
);

create or replace function public.hpsm_session_bootstrap()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_permissions text[];
  v_result jsonb;
begin
  v_permissions := public.effective_permission_codes(v_actor);
  select jsonb_build_object(
    'profile', jsonb_build_object(
      'user_id', profile.user_id,
      'passport', profile.passport,
      'display_name', profile.display_name,
      'role_code', profile.role_code,
      'status', profile.status,
      'must_change_password', profile.must_change_password,
      'position_id', profile.position_id
    ),
    'permissionCodes', to_jsonb(coalesce(v_permissions, array[]::text[])),
    'positionDisplayName', position.name,
    'positionLevel', position.level
  ) into v_result
  from public.profiles profile
  left join public.staff_positions position on position.id = profile.position_id
  where profile.user_id = v_actor and profile.status = 'active';
  if v_result is null then raise exception 'Perfil ativo não localizado.' using errcode = '42501'; end if;
  return v_result;
end;
$$;

create or replace function public.clinical_exam_ai_context(p_exam_id bigint, p_generation_type text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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
  if p_generation_type not in ('generate_lab_results', 'generate_report', 'generate_exam') then raise exception 'Operação de IA inválida.'; end if;
  select * into v_exam from public.clinical_exams exam where exam.id = p_exam_id;
  if v_exam.id is null then raise exception 'Exame não localizado.'; end if;
  if v_exam.status <> 'in_progress' then raise exception 'A IA só pode auxiliar exames em execução.'; end if;
  if not private.can_access_clinical_exam_ai(v_actor, p_exam_id) then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;

  select category.code, category.name, exam_type.code, exam_type.name
  into v_category_code, v_category_name, v_type_code, v_type_name
  from public.exam_types exam_type
  join public.exam_categories category on category.id = exam_type.category_id
  where exam_type.id = v_exam.exam_type_id;

  if p_generation_type = 'generate_exam' and v_exam.result_data->>'schema' = 'hpsm.image_result.v1' then
    raise exception 'Exames de imagem usam a geração visual completa.';
  end if;
  v_report_config := coalesce(v_exam.result_data->'report_config_snapshot', private.clinical_exam_report_config(v_exam.exam_type_id));
  if p_generation_type in ('generate_lab_results', 'generate_exam') and v_exam.result_data->>'schema' = 'hpsm.lab_result.v1' then
    v_lab_template := jsonb_build_object(
      'schema', v_exam.result_data#>>'{template_snapshot,schema}',
      'version', v_exam.result_data->'template_version',
      'parameters', coalesce(v_exam.result_data#>'{template_snapshot,parameters}', '[]'::jsonb)
    );
  elsif p_generation_type = 'generate_lab_results' then
    raise exception 'A geração de resultados está disponível apenas para exames laboratoriais.';
  end if;

  if p_generation_type = 'generate_report' and v_exam.result_data->>'schema' = 'hpsm.lab_result.v1' then
    select jsonb_build_object(
      'kind', 'laboratory',
      'parameters', coalesce(jsonb_agg(jsonb_build_object(
        'key', parameter->>'key', 'label', parameter->>'label', 'value', parameter->>'value',
        'unit', parameter->>'unit', 'reference', parameter->>'reference', 'flag', parameter->'flag'
      ) order by (parameter->>'sort_order')::integer, parameter->>'label'), '[]'::jsonb),
      'notes', left(coalesce(v_exam.result_data->>'notes', ''), 4000)
    ) into v_result_context
    from jsonb_array_elements(v_exam.result_data->'parameters') parameter;
  elsif p_generation_type = 'generate_report' and v_exam.result_data->>'schema' = 'hpsm.image_result.v1' then
    v_result_context := jsonb_build_object(
      'kind', 'imaging',
      'region', case when v_exam.result_data->>'region' = 'Outra região' then v_exam.result_data->>'other_region' else v_exam.result_data->>'region' end,
      'laterality', v_exam.result_data->>'laterality',
      'contrast', v_exam.result_data->>'contrast',
      'current_findings', left(coalesce(v_exam.findings, ''), 4000)
    );
  elsif p_generation_type = 'generate_report' then
    v_result_context := jsonb_build_object('kind', 'generic', 'observation', left(coalesce(v_exam.result_data->>'notes', ''), 4000));
  end if;

  return jsonb_build_object(
    'actor_id', v_actor,
    'exam_id', v_exam.id,
    'generation_type', p_generation_type,
    'patient_context', 'Paciente fictício do RP',
    'exam', jsonb_build_object('category_code', v_category_code, 'category_name', v_category_name, 'type_code', v_type_code, 'type_name', v_type_name),
    'case_context', jsonb_build_object('summary', private.clinical_exam_case_summary(v_exam.indication, v_exam.clinical_context)),
    'report_config', v_report_config,
    'lab_template', v_lab_template,
    'result_context', v_result_context
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
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_exam public.clinical_exams;
  v_generation public.exam_ai_generations;
  v_recent_count integer;
  v_prompt_version text;
begin
  if p_requested_by is null or p_idempotency_key is null then raise exception 'Requisição de IA inválida.'; end if;
  if p_generation_type not in ('generate_lab_results', 'generate_report', 'generate_exam') then raise exception 'Operação de IA inválida.'; end if;
  if p_source_image_generation_id is not null and p_source_image_id is not null then raise exception 'Referência de imagem inválida.'; end if;
  if p_generation_type <> 'generate_report' and (p_source_image_generation_id is not null or p_source_image_id is not null) then raise exception 'Esta operação não aceita imagem.'; end if;
  v_prompt_version := case when p_generation_type = 'generate_exam' then 'exam-rp-luna-v4' else 'exam-rp-luna-v3' end;

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
  if p_generation_type = 'generate_exam' and v_exam.result_data->>'schema' = 'hpsm.image_result.v1' then raise exception 'Exames de imagem usam a geração visual completa.'; end if;
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
    p_exam_id, p_generation_type, p_requested_by, 'gpt-5.6-luna', 'low', v_prompt_version, v_exam.updated_at,
    p_source_image_generation_id, p_source_image_id, p_idempotency_key
  ) returning * into v_generation;

  perform private.audit_exam_action(
    p_requested_by, 'clinical_exam.ai_requested', 'exam_ai_generations', v_generation.id::text, null,
    jsonb_build_object('exam_id', p_exam_id, 'generation_type', p_generation_type, 'model', v_generation.model,
      'prompt_version', v_generation.prompt_version, 'source_image_generation_id', p_source_image_generation_id, 'source_image_id', p_source_image_id)
  );
  return jsonb_build_object('generation_id', v_generation.id, 'status', v_generation.status, 'suggestion', null, 'replayed', false);
end;
$$;

alter function private.validate_exam_ai_suggestion(bigint, text, jsonb)
  rename to validate_exam_ai_suggestion_legacy_v3;

create or replace function private.clinical_exam_ai_report_values(p_payload jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_findings text;
begin
  if p_payload->>'schema' = 'hpsm.ai.exam_bundle.v4' then
    p_payload := p_payload->'report' || jsonb_build_object('schema', 'hpsm.ai.clinical_report.v3');
  end if;
  if p_payload->>'schema' = 'hpsm.ai.clinical_report.v3' then
    select string_agg('- ' || btrim(item), E'\n') into v_findings from jsonb_array_elements_text(p_payload->'findings') item;
    return jsonb_build_object(
      'technique', nullif(btrim(p_payload->>'technique'), ''),
      'findings', nullif(v_findings, ''),
      'conclusion', nullif(btrim(p_payload->>'conclusion'), ''),
      'conduct', nullif(btrim(p_payload->>'conduct'), '')
    );
  elsif p_payload->>'schema' in ('hpsm.ai.simple_report.v1', 'hpsm.ai.simple_report.v2') then
    select string_agg('- ' || btrim(item), E'\n') into v_findings from jsonb_array_elements_text(p_payload->'findings') item;
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
  v_report jsonb;
  v_report_text text;
begin
  if p_generation_type <> 'generate_exam' then
    perform private.validate_exam_ai_suggestion_legacy_v3(p_exam_id, p_generation_type, p_payload);
    return;
  end if;
  select * into v_exam from public.clinical_exams where id = p_exam_id;
  if v_exam.id is null or v_exam.status <> 'in_progress' then raise exception 'O exame não aceita mais sugestões de IA.'; end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' or p_payload->>'schema' <> 'hpsm.ai.exam_bundle.v4'
     or coalesce(jsonb_typeof(p_payload->'parameters'), '') <> 'array'
     or coalesce(jsonb_typeof(p_payload->'report'), '') <> 'object'
     or exists (select 1 from jsonb_object_keys(p_payload) key where key not in ('schema', 'parameters', 'report')) then
    raise exception 'Exame completo gerado por IA inválido.';
  end if;
  if v_exam.result_data->>'schema' = 'hpsm.image_result.v1' then raise exception 'Exames de imagem usam a geração visual completa.'; end if;

  v_report := p_payload->'report';
  if exists (select 1 from jsonb_object_keys(v_report) key where key not in ('technique', 'findings', 'conclusion', 'conduct'))
     or coalesce(jsonb_typeof(v_report->'technique'), '') <> 'string'
     or coalesce(jsonb_typeof(v_report->'findings'), '') <> 'array'
     or coalesce(jsonb_typeof(v_report->'conclusion'), '') <> 'string'
     or coalesce(jsonb_typeof(v_report->'conduct'), '') <> 'string'
     or jsonb_array_length(v_report->'findings') not between 1 and 4
     or char_length(btrim(v_report->>'technique')) not between 1 and 600
     or char_length(btrim(v_report->>'conclusion')) not between 1 and 1000
     or char_length(btrim(v_report->>'conduct')) not between 1 and 1200
     or exists (select 1 from jsonb_array_elements(v_report->'findings') item where jsonb_typeof(item) <> 'string' or char_length(btrim(item#>>'{}')) not between 1 and 1200) then
    raise exception 'Laudo completo gerado por IA fora dos limites permitidos.';
  end if;
  select lower(concat_ws(' ', v_report->>'technique', v_report->>'conclusion', v_report->>'conduct', string_agg(item, ' ')))
  into v_report_text from jsonb_array_elements_text(v_report->'findings') item;
  if v_report_text ~ '(sugest|possível|possivelmente|provavelmente|pode[[:space:]]+(ser|representar|indicar)|recomenda-se[[:space:]]+avaliação[[:space:]]+profissional|procure[[:space:]]+um[[:space:]]+médico|necessita[[:space:]]+avaliação[[:space:]]+especializada)' then
    raise exception 'O laudo deve declarar diretamente os achados do exame fictício.';
  end if;

  if v_exam.result_data->>'schema' = 'hpsm.lab_result.v1' then
    if jsonb_array_length(p_payload->'parameters') <> (
         select count(*) from jsonb_array_elements(v_exam.result_data#>'{template_snapshot,parameters}') parameter
         where coalesce((parameter->>'active')::boolean, false)
       )
       or (select count(*) <> count(distinct parameter->>'key') from jsonb_array_elements(p_payload->'parameters') parameter)
       or exists (
         select 1 from jsonb_array_elements(v_exam.result_data#>'{template_snapshot,parameters}') snapshot
         where coalesce((snapshot->>'active')::boolean, false) and not exists (
           select 1 from jsonb_array_elements(p_payload->'parameters') suggestion
           where suggestion->>'key' = snapshot->>'key' and nullif(btrim(suggestion->>'value'), '') is not null
         )
       ) then raise exception 'Resultados gerados incompatíveis com o template laboratorial.'; end if;
    v_candidate := v_exam.result_data || jsonb_build_object('parameters', p_payload->'parameters', 'notes', left(v_report->>'conduct', 12000));
    perform private.normalize_lab_result(v_exam.result_data, v_candidate);
  elsif jsonb_array_length(p_payload->'parameters') <> 0 then
    raise exception 'Este exame não utiliza parâmetros laboratoriais.';
  end if;
end;
$$;

create or replace function private.submit_clinical_exam_review_as(p_exam_id bigint, p_actor uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old public.clinical_exams;
  v_new public.clinical_exams;
  v_missing text;
  v_missing_report text[] := array[]::text[];
  v_report_config jsonb;
  v_version integer;
  v_note text;
begin
  select * into v_old from public.clinical_exams where id = p_exam_id for update;
  if v_old.id is null then raise exception 'Exame não localizado.'; end if;
  if p_actor is null or v_old.responsible_professional_id is distinct from p_actor or not private.has_permission(p_actor, 'exams.perform') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if v_old.status <> 'in_progress' then raise exception 'Este exame foi atualizado por outro profissional. Recarregue os dados para continuar.'; end if;

  v_report_config := coalesce(v_old.result_data->'report_config_snapshot', private.clinical_exam_report_config(v_old.exam_type_id));
  if coalesce((v_report_config#>>'{fields,technique,required}')::boolean, false) and v_old.technique is null then v_missing_report := array_append(v_missing_report, v_report_config#>>'{fields,technique,label}'); end if;
  if coalesce((v_report_config#>>'{fields,findings,required}')::boolean, false) and v_old.findings is null then v_missing_report := array_append(v_missing_report, v_report_config#>>'{fields,findings,label}'); end if;
  if coalesce((v_report_config#>>'{fields,conclusion,required}')::boolean, false) and v_old.conclusion is null then v_missing_report := array_append(v_missing_report, v_report_config#>>'{fields,conclusion,label}'); end if;
  if coalesce((v_report_config#>>'{fields,observations,required}')::boolean, false) and nullif(btrim(v_old.result_data->>'notes'), '') is null then v_missing_report := array_append(v_missing_report, v_report_config#>>'{fields,observations,label}'); end if;
  if cardinality(v_missing_report) > 0 then raise exception 'Preencha os campos obrigatórios do laudo: %.', array_to_string(v_missing_report, ', '); end if;

  if v_old.result_data->>'schema' = 'hpsm.lab_result.v1' then
    select string_agg(snapshot->>'label', ', ' order by (snapshot->>'sort_order')::integer) into v_missing
    from jsonb_array_elements(v_old.result_data#>'{template_snapshot,parameters}') snapshot
    where (snapshot->>'active')::boolean and (snapshot->>'required')::boolean
      and not exists (select 1 from jsonb_array_elements(v_old.result_data->'parameters') result_parameter where result_parameter->>'key' = snapshot->>'key' and nullif(btrim(result_parameter->>'value'), '') is not null);
    if v_missing is not null then raise exception 'Preencha os parâmetros obrigatórios: %.', v_missing; end if;
  elsif v_old.result_data->>'schema' = 'hpsm.image_result.v1' then
    if (v_old.result_data#>>'{template_snapshot,region,required}')::boolean and nullif(btrim(v_old.result_data->>'region'), '') is null then raise exception 'Selecione a região examinada.'; end if;
    if v_old.result_data->>'region' = 'Outra região' and nullif(btrim(v_old.result_data->>'other_region'), '') is null then raise exception 'Informe a outra região examinada.'; end if;
    if (v_old.result_data#>>'{template_snapshot,supports_laterality}')::boolean and nullif(v_old.result_data->>'laterality', '') is null then raise exception 'Selecione a lateralidade.'; end if;
    if (v_old.result_data#>>'{template_snapshot,supports_contrast}')::boolean and nullif(v_old.result_data->>'contrast', '') is null then raise exception 'Informe o uso de contraste.'; end if;
    if (v_old.result_data#>>'{template_snapshot,requires_image}')::boolean and not exists (select 1 from public.clinical_exam_images image where image.exam_id = p_exam_id and image.removed_at is null) then raise exception 'Gere a imagem por IA antes do envio.'; end if;
  end if;

  v_note := case when exists (select 1 from public.clinical_exam_status_history history where history.exam_id = p_exam_id and history.to_status = 'awaiting_review') then 'Exame corrigido e reenviado para revisão.' else 'Exame gerado por IA e enviado para revisão humana.' end;
  update public.clinical_exams set status = 'awaiting_review', submitted_for_review_at = now(), correction_reason = null where id = p_exam_id returning * into v_new;
  insert into public.clinical_exam_status_history (exam_id, from_status, to_status, changed_by, note) values (p_exam_id, 'in_progress', 'awaiting_review', p_actor, v_note);
  select coalesce(max(version.version_number), 0) + 1 into v_version from public.clinical_exam_report_versions version where version.exam_id = p_exam_id;
  insert into public.clinical_exam_report_versions (exam_id, version_number, snapshot, submitted_by, submitted_at)
  values (p_exam_id, v_version, private.build_clinical_exam_report_snapshot(p_exam_id), p_actor, v_new.submitted_for_review_at);
  perform private.audit_exam_action(p_actor, 'clinical_exam.submitted_for_review', 'clinical_exams', p_exam_id::text, to_jsonb(v_old), to_jsonb(v_new));
end;
$$;

create or replace function public.apply_and_submit_clinical_exam_ai_generation(p_generation_id uuid, p_actor uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_generation public.exam_ai_generations;
  v_exam public.clinical_exams;
  v_parameters jsonb;
  v_candidate jsonb;
  v_result_data jsonb;
  v_config jsonb;
  v_report_values jsonb;
begin
  select * into v_generation from public.exam_ai_generations where id = p_generation_id;
  if v_generation.id is null then raise exception 'Geração de IA não localizada.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_generation.exam_id::text || ':complete_exam', 0));
  select * into v_exam from public.clinical_exams where id = v_generation.exam_id for update;
  select * into v_generation from public.exam_ai_generations where id = p_generation_id for update;
  if v_exam.status <> 'in_progress' or v_exam.responsible_professional_id is distinct from p_actor or not private.has_permission(p_actor, 'exams.perform') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if v_generation.generation_type <> 'generate_exam' or v_generation.status <> 'completed' or v_generation.requested_by is distinct from p_actor then raise exception 'Exame gerado por IA indisponível.'; end if;
  if v_exam.updated_at is distinct from v_generation.source_exam_updated_at then raise exception 'O exame foi atualizado durante a geração. Gere novamente.'; end if;
  perform private.validate_exam_ai_suggestion(v_exam.id, 'generate_exam', v_generation.suggestion_payload);

  v_report_values := private.clinical_exam_ai_report_values(v_generation.suggestion_payload);
  v_config := coalesce(v_exam.result_data->'report_config_snapshot', private.clinical_exam_report_config(v_exam.exam_type_id));
  if v_exam.result_data->>'schema' = 'hpsm.lab_result.v1' then
    select jsonb_agg(parameter || jsonb_build_object('value', suggestion.item->>'value', 'flag', suggestion.item->'flag') order by (parameter->>'sort_order')::integer, parameter->>'label') into v_parameters
    from jsonb_array_elements(v_exam.result_data->'parameters') parameter
    join lateral (select item from jsonb_array_elements(v_generation.suggestion_payload->'parameters') item where item->>'key' = parameter->>'key' limit 1) suggestion on true;
    v_candidate := v_exam.result_data || jsonb_build_object('parameters', v_parameters, 'notes', v_report_values->>'conduct');
    v_result_data := private.normalize_lab_result(v_exam.result_data, v_candidate)
      || jsonb_build_object('report_config_snapshot', v_exam.result_data->'report_config_snapshot', 'exam_type_snapshot', v_exam.result_data->'exam_type_snapshot');
  else
    v_result_data := jsonb_set(v_exam.result_data, '{notes}', to_jsonb(v_report_values->>'conduct'), true);
  end if;

  update public.clinical_exams set
    technique = case when coalesce((v_config#>>'{fields,technique,visible}')::boolean, false) then v_report_values->>'technique' else technique end,
    findings = case when coalesce((v_config#>>'{fields,findings,visible}')::boolean, false) then v_report_values->>'findings' else findings end,
    conclusion = case when coalesce((v_config#>>'{fields,conclusion,visible}')::boolean, false) then v_report_values->>'conclusion' else conclusion end,
    result_data = v_result_data
  where id = v_exam.id;
  update public.exam_ai_generations set status = 'applied', applied_at = now() where id = p_generation_id;
  perform private.audit_exam_action(p_actor, 'clinical_exam.ai_complete_exam_applied', 'exam_ai_generations', p_generation_id::text,
    jsonb_build_object('status', 'completed'), jsonb_build_object('status', 'applied', 'exam_id', v_exam.id, 'model', v_generation.model, 'prompt_version', v_generation.prompt_version));
  perform private.submit_clinical_exam_review_as(v_exam.id, p_actor);
  return jsonb_build_object('exam_id', v_exam.id, 'status', 'awaiting_review');
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
  v_result_data jsonb;
begin
  select * into v_image_generation from public.exam_ai_generations where id = p_image_generation_id;
  select * into v_report_generation from public.exam_ai_generations where id = p_report_generation_id;
  if v_image_generation.id is null or v_report_generation.id is null or v_image_generation.exam_id <> v_report_generation.exam_id then raise exception 'Geração de IA incompleta.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_image_generation.exam_id::text || ':ai_bundle', 0));
  select * into v_exam from public.clinical_exams where id = v_image_generation.exam_id for update;
  select * into v_image_generation from public.exam_ai_generations where id = p_image_generation_id for update;
  select * into v_report_generation from public.exam_ai_generations where id = p_report_generation_id for update;
  if v_exam.status <> 'in_progress' or v_exam.responsible_professional_id is distinct from p_actor or not private.has_permission(p_actor, 'exams.perform') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if v_image_generation.generation_type <> 'generate_image' or v_image_generation.status <> 'completed' or v_image_generation.requested_by is distinct from p_actor then raise exception 'Rascunho de imagem indisponível.'; end if;
  if v_report_generation.generation_type <> 'generate_report' or v_report_generation.status <> 'completed' then raise exception 'Laudo gerado por IA indisponível.'; end if;
  if v_report_generation.source_image_generation_id is distinct from p_image_generation_id then raise exception 'O laudo não corresponde à imagem gerada.'; end if;
  if v_exam.updated_at is distinct from v_report_generation.source_exam_updated_at then raise exception 'O exame foi atualizado durante a geração. Gere novamente.'; end if;
  if p_storage_path <> 'clinical-exams/' || v_exam.id::text || '/' || p_image_id::text || '.png' or p_file_size <> v_image_generation.draft_file_size then raise exception 'Imagem final inválida.'; end if;
  perform private.validate_exam_ai_suggestion(v_exam.id, 'generate_report', v_report_generation.suggestion_payload);

  select count(*) into v_count from public.clinical_exam_images where exam_id = v_exam.id and removed_at is null;
  if not (v_exam.result_data#>>'{template_snapshot,allows_multiple_images}')::boolean and v_count > 0 then raise exception 'Este tipo de exame aceita somente uma imagem.'; end if;
  insert into public.clinical_exam_images(id, exam_id, storage_path, original_filename, mime_type, file_size, sort_order, caption, source, uploaded_by)
  values(p_image_id, v_exam.id, p_storage_path, 'imagem-ficticia-ia.png', 'image/png', p_file_size, (v_count + 1) * 10, 'Imagem fictícia gerada por IA para fins de RP.', 'ai_generated', p_actor);

  v_config := coalesce(v_exam.result_data->'report_config_snapshot', private.clinical_exam_report_config(v_exam.exam_type_id));
  v_report_values := private.clinical_exam_ai_report_values(v_report_generation.suggestion_payload);
  v_result_data := jsonb_set(v_exam.result_data, '{notes}', to_jsonb(v_report_values->>'conduct'), true);
  update public.clinical_exams set
    technique = case when coalesce((v_config#>>'{fields,technique,visible}')::boolean, false) then v_report_values->>'technique' else technique end,
    findings = case when coalesce((v_config#>>'{fields,findings,visible}')::boolean, false) then v_report_values->>'findings' else findings end,
    conclusion = case when coalesce((v_config#>>'{fields,conclusion,visible}')::boolean, false) then v_report_values->>'conclusion' else conclusion end,
    result_data = v_result_data
  where id = v_exam.id;
  update public.exam_ai_generations set status = 'applied', applied_at = now(), official_image_id = p_image_id where id = p_image_generation_id;
  update public.exam_ai_generations set status = 'applied', applied_at = now() where id = p_report_generation_id;
  perform private.audit_exam_action(p_actor, 'clinical_exam.ai_bundle_applied', 'clinical_exams', v_exam.id::text, null,
    jsonb_build_object('image_generation_id', p_image_generation_id, 'report_generation_id', p_report_generation_id, 'image_id', p_image_id,
      'image_model', v_image_generation.model, 'report_model', v_report_generation.model, 'report_prompt_version', v_report_generation.prompt_version));
  perform private.submit_clinical_exam_review_as(v_exam.id, p_actor);
  return jsonb_build_object('exam_id', v_exam.id, 'image_id', p_image_id, 'status', 'awaiting_review', 'draft_path', v_image_generation.draft_storage_path);
end;
$$;

create or replace function public.review_clinical_exam(p_exam_id bigint, p_decision text, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_old public.clinical_exams;
  v_new public.clinical_exams;
  v_version public.clinical_exam_report_versions;
  v_reviewed_at timestamptz := now();
  v_reviewer jsonb;
  v_final_snapshot jsonb;
  v_is_authority boolean;
begin
  select * into v_old from public.clinical_exams where id = p_exam_id for update;
  if v_old.id is null then raise exception 'Exame não localizado.'; end if;
  v_is_authority := coalesce(private.current_position_level(v_actor) between 11 and 14, false) and private.has_permission(v_actor, 'exams.review');
  if p_decision = 'approve' then
    if not v_is_authority and v_actor not in (v_old.requested_by, v_old.responsible_professional_id) then
      raise exception 'Acesso não autorizado.' using errcode = '42501';
    end if;
  elsif p_decision = 'return' then
    if not v_is_authority then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  else
    raise exception 'Decisão de revisão inválida.';
  end if;
  if v_old.status <> 'awaiting_review' then raise exception 'Este exame foi atualizado por outro profissional. Recarregue os dados para continuar.'; end if;

  select * into v_version from public.clinical_exam_report_versions version
  where version.exam_id = p_exam_id and version.decision = 'pending'
  order by version.version_number desc limit 1 for update;
  if v_version.id is null then
    insert into public.clinical_exam_report_versions (exam_id, version_number, snapshot, submitted_by, submitted_at)
    values (p_exam_id, coalesce((select max(version.version_number) + 1 from public.clinical_exam_report_versions version where version.exam_id = p_exam_id), 1),
      private.build_clinical_exam_report_snapshot(p_exam_id), v_old.responsible_professional_id, coalesce(v_old.submitted_for_review_at, v_old.updated_at))
    returning * into v_version;
  end if;
  select jsonb_build_object('id', reviewer.user_id, 'name', reviewer.display_name, 'position', position.name) into v_reviewer
  from public.profiles reviewer left join public.staff_positions position on position.id = reviewer.position_id where reviewer.user_id = v_actor;

  if p_decision = 'approve' then
    v_final_snapshot := v_version.snapshot || jsonb_build_object('reviewed_by', v_reviewer,
      'dates', coalesce(v_version.snapshot->'dates', '{}'::jsonb) || jsonb_build_object('completed_at', v_reviewed_at));
    update public.clinical_exam_report_versions set decision = 'approved', reviewed_by = v_actor, reviewed_at = v_reviewed_at where id = v_version.id;
    update public.clinical_exams set status = 'completed', reviewed_by = v_actor, completed_at = v_reviewed_at,
      correction_reason = null, final_report_snapshot = v_final_snapshot where id = p_exam_id returning * into v_new;
    insert into public.clinical_exam_status_history (exam_id, from_status, to_status, changed_by, note)
    values (p_exam_id, 'awaiting_review', 'completed', v_actor, 'Laudo revisado, aprovado e concluído.');
    perform private.audit_exam_action(v_actor, 'clinical_exam.completed', 'clinical_exams', p_exam_id::text, to_jsonb(v_old), to_jsonb(v_new));
  else
    if nullif(btrim(p_reason), '') is null or char_length(btrim(p_reason)) < 2 then raise exception 'Informe o motivo da correção.'; end if;
    update public.clinical_exam_report_versions set decision = 'returned', reviewed_by = v_actor, reviewed_at = v_reviewed_at, review_reason = btrim(p_reason) where id = v_version.id;
    update public.clinical_exams set status = 'in_progress', submitted_for_review_at = null, reviewed_by = null,
      completed_at = null, correction_reason = btrim(p_reason), final_report_snapshot = null where id = p_exam_id returning * into v_new;
    insert into public.clinical_exam_status_history (exam_id, from_status, to_status, changed_by, note)
    values (p_exam_id, 'awaiting_review', 'in_progress', v_actor, btrim(p_reason));
    perform private.audit_exam_action(v_actor, 'clinical_exam.returned_for_correction', 'clinical_exams', p_exam_id::text, to_jsonb(v_old), to_jsonb(v_new));
  end if;
end;
$$;

drop policy if exists clinical_exam_images_storage_insert on storage.objects;
revoke execute on function public.clinical_exam_image_upload_context(bigint) from authenticated;
revoke execute on function public.register_clinical_exam_image(bigint, uuid, text, text, text, bigint, text) from authenticated;

revoke all on function public.hpsm_session_bootstrap() from public, anon, authenticated, service_role;
revoke all on function public.clinical_exam_ai_context(bigint, text) from public, anon, authenticated, service_role;
revoke all on function public.begin_clinical_exam_ai_generation(bigint, text, uuid, uuid, uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function private.clinical_exam_ai_report_values(jsonb) from public, anon, authenticated, service_role;
revoke all on function private.validate_exam_ai_suggestion_legacy_v3(bigint, text, jsonb) from public, anon, authenticated, service_role;
revoke all on function private.validate_exam_ai_suggestion(bigint, text, jsonb) from public, anon, authenticated, service_role;
revoke all on function private.submit_clinical_exam_review_as(bigint, uuid) from public, anon, authenticated, service_role;
revoke all on function public.apply_and_submit_clinical_exam_ai_generation(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public.apply_clinical_exam_ai_bundle(uuid, uuid, uuid, uuid, text, bigint) from public, anon, authenticated, service_role;
revoke all on function public.review_clinical_exam(bigint, text, text) from public, anon, authenticated, service_role;

grant execute on function public.hpsm_session_bootstrap() to authenticated;
grant execute on function public.clinical_exam_ai_context(bigint, text) to authenticated;
grant execute on function public.begin_clinical_exam_ai_generation(bigint, text, uuid, uuid, uuid, uuid) to service_role;
grant execute on function public.apply_and_submit_clinical_exam_ai_generation(uuid, uuid) to service_role;
grant execute on function public.apply_clinical_exam_ai_bundle(uuid, uuid, uuid, uuid, text, bigint) to service_role;
grant execute on function public.review_clinical_exam(bigint, text, text) to authenticated;

comment on function public.apply_and_submit_clinical_exam_ai_generation(uuid, uuid) is
  'Aplica resultados e laudo Luna v4 e envia o exame não visual à revisão humana na mesma transação.';
comment on function public.apply_clinical_exam_ai_bundle(uuid, uuid, uuid, uuid, text, bigint) is
  'Registra a imagem IA, aplica o laudo correspondente e envia o exame de imagem à revisão humana atomicamente.';
comment on function public.review_clinical_exam(bigint, text, text) is
  'Aprovação permitida ao solicitante/responsável ou cargos oficiais 11–14; devolução restrita aos cargos 11–14.';

notify pgrst, 'reload schema';
