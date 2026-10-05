-- HPSM — Fase 4.6: assistência de IA para resultados laboratoriais e laudos.
-- A IA apenas sugere rascunhos. Aplicação, revisão e conclusão permanecem humanas.

create table public.exam_ai_generations (
  id uuid primary key default gen_random_uuid(),
  exam_id bigint not null references public.clinical_exams(id) on delete restrict,
  generation_type text not null,
  status text not null default 'requested',
  requested_by uuid not null references public.profiles(user_id) on delete restrict,
  model text not null,
  reasoning_effort text not null,
  prompt_version text not null,
  source_exam_updated_at timestamptz not null,
  openai_response_id text,
  input_tokens integer,
  output_tokens integer,
  total_tokens integer,
  suggestion_payload jsonb,
  error_code text,
  idempotency_key uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  failed_at timestamptz,
  applied_at timestamptz,
  discarded_at timestamptz,
  constraint exam_ai_generations_type_check check (generation_type in ('generate_lab_results', 'generate_report')),
  constraint exam_ai_generations_status_check check (status in ('requested', 'completed', 'failed', 'applied', 'discarded')),
  constraint exam_ai_generations_model_check check (model = 'gpt-5.6-luna'),
  constraint exam_ai_generations_reasoning_check check (reasoning_effort = 'low'),
  constraint exam_ai_generations_prompt_check check (prompt_version = 'exam-rp-luna-v1'),
  constraint exam_ai_generations_response_id_check check (openai_response_id is null or char_length(openai_response_id) between 3 and 200),
  constraint exam_ai_generations_token_check check (
    (input_tokens is null or input_tokens >= 0)
    and (output_tokens is null or output_tokens >= 0)
    and (total_tokens is null or total_tokens >= 0)
  ),
  constraint exam_ai_generations_payload_check check (suggestion_payload is null or jsonb_typeof(suggestion_payload) = 'object'),
  constraint exam_ai_generations_error_check check (error_code is null or char_length(error_code) between 2 and 80),
  constraint exam_ai_generations_state_check check (
    (status = 'requested' and suggestion_payload is null and openai_response_id is null and input_tokens is null and output_tokens is null and total_tokens is null and completed_at is null and failed_at is null and applied_at is null and discarded_at is null)
    or (status = 'completed' and suggestion_payload is not null and openai_response_id is not null and input_tokens is not null and output_tokens is not null and total_tokens is not null and completed_at is not null and failed_at is null and applied_at is null and discarded_at is null)
    or (status = 'failed' and suggestion_payload is null and error_code is not null and failed_at is not null and applied_at is null and discarded_at is null)
    or (status = 'applied' and suggestion_payload is not null and openai_response_id is not null and input_tokens is not null and output_tokens is not null and total_tokens is not null and completed_at is not null and applied_at is not null and failed_at is null and discarded_at is null)
    or (status = 'discarded' and suggestion_payload is not null and openai_response_id is not null and input_tokens is not null and output_tokens is not null and total_tokens is not null and completed_at is not null and discarded_at is not null and failed_at is null and applied_at is null)
  ),
  unique (idempotency_key)
);

create index exam_ai_generations_exam_latest_idx
  on public.exam_ai_generations (exam_id, generation_type, created_at desc, id desc);
create index exam_ai_generations_requested_by_idx
  on public.exam_ai_generations (requested_by, created_at desc);
create unique index exam_ai_generations_one_active_idx
  on public.exam_ai_generations (exam_id, generation_type)
  where status = 'requested';

alter table public.exam_ai_generations enable row level security;
alter table public.exam_ai_generations force row level security;

create policy exam_ai_generations_read_participant
on public.exam_ai_generations for select to authenticated
using (
  (select auth.uid()) is not null
  and exists (
    select 1
    from public.clinical_exams exam
    where exam.id = exam_ai_generations.exam_id
      and (
        (exam.responsible_professional_id = (select auth.uid()) and private.has_permission((select auth.uid()), 'exams.perform'))
        or private.has_permission((select auth.uid()), 'exams.review')
      )
  )
);

revoke all on public.exam_ai_generations from public, anon, authenticated, service_role;
grant select on public.exam_ai_generations to authenticated;
grant select, insert, update on public.exam_ai_generations to service_role;

create or replace function private.protect_exam_ai_generation_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
     or new.exam_id is distinct from old.exam_id
     or new.generation_type is distinct from old.generation_type
     or new.requested_by is distinct from old.requested_by
     or new.model is distinct from old.model
     or new.reasoning_effort is distinct from old.reasoning_effort
     or new.prompt_version is distinct from old.prompt_version
     or new.source_exam_updated_at is distinct from old.source_exam_updated_at
     or new.idempotency_key is distinct from old.idempotency_key
     or new.created_at is distinct from old.created_at then
    raise exception 'Os metadados da geração de IA são imutáveis.';
  end if;

  if not (
    (old.status = 'requested' and new.status in ('completed', 'failed'))
    or (old.status = 'completed' and new.status in ('applied', 'discarded'))
  ) then
    raise exception 'Transição inválida da geração de IA.';
  end if;

  new.updated_at := now();
  return new;
end;
$$;

revoke all on function private.protect_exam_ai_generation_update() from public, anon, authenticated, service_role;

create trigger exam_ai_generations_protect_update
before update on public.exam_ai_generations
for each row execute function private.protect_exam_ai_generation_update();

create or replace function private.can_access_clinical_exam_ai(p_actor uuid, p_exam_id bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_actor is not null and exists (
    select 1
    from public.clinical_exams exam
    where exam.id = p_exam_id
      and (
        (exam.responsible_professional_id = p_actor and private.has_permission(p_actor, 'exams.perform'))
        or private.has_permission(p_actor, 'exams.review')
      )
  );
$$;

revoke all on function private.can_access_clinical_exam_ai(uuid, bigint) from public, anon, authenticated, service_role;

create or replace function public.clinical_exam_ai_context(
  p_exam_id bigint,
  p_generation_type text
)
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
  if p_generation_type not in ('generate_lab_results', 'generate_report') then
    raise exception 'Operação de IA inválida.';
  end if;

  select * into v_exam
  from public.clinical_exams exam
  where exam.id = p_exam_id;

  if v_exam.id is null then raise exception 'Exame não localizado.'; end if;
  if v_exam.status <> 'in_progress' then raise exception 'A IA só pode auxiliar exames em execução.'; end if;
  if not private.can_access_clinical_exam_ai(v_actor, p_exam_id) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  select category.code, category.name, exam_type.code, exam_type.name
  into v_category_code, v_category_name, v_type_code, v_type_name
  from public.exam_types exam_type
  join public.exam_categories category on category.id = exam_type.category_id
  where exam_type.id = v_exam.exam_type_id;

  v_report_config := coalesce(v_exam.result_data->'report_config_snapshot', private.clinical_exam_report_config(v_exam.exam_type_id));

  if p_generation_type = 'generate_lab_results' then
    if v_exam.result_data->>'schema' <> 'hpsm.lab_result.v1' then
      raise exception 'A geração de resultados está disponível apenas para exames laboratoriais.';
    end if;
    v_lab_template := jsonb_build_object(
      'schema', v_exam.result_data#>>'{template_snapshot,schema}',
      'version', v_exam.result_data->'template_version',
      'parameters', coalesce(v_exam.result_data#>'{template_snapshot,parameters}', '[]'::jsonb)
    );
  else
    if v_exam.result_data->>'schema' = 'hpsm.lab_result.v1' then
      select jsonb_build_object(
        'kind', 'laboratory',
        'parameters', coalesce(jsonb_agg(jsonb_build_object(
          'key', parameter->>'key',
          'label', parameter->>'label',
          'value', parameter->>'value',
          'unit', parameter->>'unit',
          'reference', parameter->>'reference',
          'flag', parameter->'flag'
        ) order by (parameter->>'sort_order')::integer, parameter->>'label'), '[]'::jsonb)
      ) into v_result_context
      from jsonb_array_elements(v_exam.result_data->'parameters') parameter;
    elsif v_exam.result_data->>'schema' = 'hpsm.image_result.v1' then
      v_result_context := jsonb_build_object(
        'kind', 'imaging_without_image_input',
        'region', v_exam.result_data->>'region',
        'laterality', v_exam.result_data->>'laterality',
        'contrast', v_exam.result_data->>'contrast'
      );
    else
      v_result_context := jsonb_build_object('kind', 'generic');
    end if;
  end if;

  return jsonb_build_object(
    'actor_id', v_actor,
    'exam_id', v_exam.id,
    'generation_type', p_generation_type,
    'patient_context', 'Paciente fictício do RP',
    'exam', jsonb_build_object(
      'category_code', v_category_code,
      'category_name', v_category_name,
      'type_code', v_type_code,
      'type_name', v_type_name
    ),
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
  p_idempotency_key uuid
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

  perform pg_advisory_xact_lock(hashtextextended(p_exam_id::text || ':' || p_generation_type, 0));

  select * into v_generation
  from public.exam_ai_generations generation
  where generation.idempotency_key = p_idempotency_key
  for update;

  if v_generation.id is not null then
    if v_generation.exam_id <> p_exam_id
       or v_generation.generation_type <> p_generation_type
       or v_generation.requested_by <> p_requested_by then
      raise exception 'Chave de idempotência inválida.';
    end if;
    return jsonb_build_object(
      'generation_id', v_generation.id,
      'status', v_generation.status,
      'suggestion', v_generation.suggestion_payload,
      'replayed', true
    );
  end if;

  select * into v_exam from public.clinical_exams where id = p_exam_id for update;
  if v_exam.id is null then raise exception 'Exame não localizado.'; end if;
  if v_exam.status <> 'in_progress' then raise exception 'A IA só pode auxiliar exames em execução.'; end if;
  if not private.can_access_clinical_exam_ai(p_requested_by, p_exam_id) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if p_generation_type = 'generate_lab_results' and v_exam.result_data->>'schema' <> 'hpsm.lab_result.v1' then
    raise exception 'A geração de resultados está disponível apenas para exames laboratoriais.';
  end if;

  select * into v_generation
  from public.exam_ai_generations generation
  where generation.exam_id = p_exam_id
    and generation.generation_type = p_generation_type
    and generation.status = 'requested'
  order by generation.created_at desc
  limit 1
  for update;

  if v_generation.id is not null and v_generation.created_at >= now() - interval '2 minutes' then
    return jsonb_build_object('generation_id', v_generation.id, 'status', 'requested', 'suggestion', null, 'replayed', true);
  elsif v_generation.id is not null then
    update public.exam_ai_generations
    set status = 'failed', failed_at = now(), error_code = 'stale_request'
    where id = v_generation.id;
  end if;

  select count(*)::integer into v_recent_count
  from public.exam_ai_generations generation
  where generation.requested_by = p_requested_by
    and generation.created_at >= now() - interval '10 minutes';
  if v_recent_count >= 6 then raise exception 'Limite temporário de gerações atingido. Aguarde alguns minutos.'; end if;

  insert into public.exam_ai_generations (
    exam_id, generation_type, requested_by, model, reasoning_effort, prompt_version, source_exam_updated_at, idempotency_key
  ) values (
    p_exam_id, p_generation_type, p_requested_by, 'gpt-5.6-luna', 'low', 'exam-rp-luna-v1', v_exam.updated_at, p_idempotency_key
  ) returning * into v_generation;

  perform private.audit_exam_action(
    p_requested_by,
    'clinical_exam.ai_requested',
    'exam_ai_generations',
    v_generation.id::text,
    null,
    jsonb_build_object('exam_id', p_exam_id, 'generation_type', p_generation_type, 'model', v_generation.model, 'prompt_version', v_generation.prompt_version)
  );

  return jsonb_build_object('generation_id', v_generation.id, 'status', v_generation.status, 'suggestion', null, 'replayed', false);
end;
$$;

create or replace function private.validate_exam_ai_suggestion(
  p_exam_id bigint,
  p_generation_type text,
  p_payload jsonb
)
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
         select 1
         from jsonb_array_elements(v_exam.result_data#>'{template_snapshot,parameters}') snapshot
         where coalesce((snapshot->>'active')::boolean, false)
           and not exists (
             select 1 from jsonb_array_elements(p_payload->'parameters') suggestion
             where suggestion->>'key' = snapshot->>'key'
           )
       ) then
      raise exception 'Sugestão laboratorial incompatível com o template.';
    end if;

    v_candidate := v_exam.result_data || jsonb_build_object(
      'parameters', p_payload->'parameters',
      'notes', left(p_payload->>'notes', 12000)
    );
    perform private.normalize_lab_result(v_exam.result_data, v_candidate);
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
         where coalesce((v_config#>>array['fields', key, 'visible'])::boolean, false)
           and not (p_payload->'fields' ? key)
       ) then
      raise exception 'Sugestão de laudo incompatível com a configuração do exame.';
    end if;
  else
    raise exception 'Operação de IA inválida.';
  end if;
end;
$$;

revoke all on function private.validate_exam_ai_suggestion(bigint, text, jsonb) from public, anon, authenticated, service_role;

create or replace function public.complete_clinical_exam_ai_generation(
  p_generation_id uuid,
  p_openai_response_id text,
  p_input_tokens integer,
  p_output_tokens integer,
  p_total_tokens integer,
  p_suggestion_payload jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_generation public.exam_ai_generations;
  v_exam public.clinical_exams;
begin
  select * into v_generation from public.exam_ai_generations where id = p_generation_id;
  if v_generation.id is null then raise exception 'Geração de IA não localizada.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_generation.exam_id::text || ':' || v_generation.generation_type, 0));
  select * into v_exam from public.clinical_exams where id = v_generation.exam_id for update;
  select * into v_generation from public.exam_ai_generations where id = p_generation_id for update;
  if v_generation.status <> 'requested' then raise exception 'A geração de IA já foi finalizada.'; end if;

  perform private.validate_exam_ai_suggestion(v_generation.exam_id, v_generation.generation_type, p_suggestion_payload);

  update public.exam_ai_generations
  set status = 'completed',
      openai_response_id = left(nullif(btrim(p_openai_response_id), ''), 200),
      input_tokens = greatest(coalesce(p_input_tokens, 0), 0),
      output_tokens = greatest(coalesce(p_output_tokens, 0), 0),
      total_tokens = greatest(coalesce(p_total_tokens, 0), 0),
      suggestion_payload = p_suggestion_payload,
      completed_at = now()
  where id = p_generation_id;

  perform private.audit_exam_action(
    v_generation.requested_by,
    'clinical_exam.ai_completed',
    'exam_ai_generations',
    p_generation_id::text,
    jsonb_build_object('status', 'requested'),
    jsonb_build_object('status', 'completed', 'exam_id', v_generation.exam_id, 'generation_type', v_generation.generation_type, 'model', v_generation.model, 'prompt_version', v_generation.prompt_version)
  );
end;
$$;

create or replace function public.fail_clinical_exam_ai_generation(
  p_generation_id uuid,
  p_error_code text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_generation public.exam_ai_generations;
begin
  select * into v_generation from public.exam_ai_generations where id = p_generation_id;
  if v_generation.id is null then return; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_generation.exam_id::text || ':' || v_generation.generation_type, 0));
  select * into v_generation from public.exam_ai_generations where id = p_generation_id for update;
  if v_generation.status <> 'requested' then return; end if;

  update public.exam_ai_generations
  set status = 'failed', failed_at = now(), error_code = left(coalesce(nullif(btrim(p_error_code), ''), 'unknown_error'), 80)
  where id = p_generation_id;

  perform private.audit_exam_action(
    v_generation.requested_by,
    'clinical_exam.ai_failed',
    'exam_ai_generations',
    p_generation_id::text,
    jsonb_build_object('status', 'requested'),
    jsonb_build_object('status', 'failed', 'exam_id', v_generation.exam_id, 'generation_type', v_generation.generation_type, 'error_code', left(coalesce(p_error_code, 'unknown_error'), 80))
  );
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
  v_fields jsonb;
  v_technique text;
  v_findings text;
  v_conclusion text;
begin
  select * into v_generation from public.exam_ai_generations where id = p_generation_id;
  if v_generation.id is null then raise exception 'Sugestão de IA não localizada.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_generation.exam_id::text || ':' || v_generation.generation_type, 0));
  select * into v_exam from public.clinical_exams where id = v_generation.exam_id for update;
  select * into v_generation from public.exam_ai_generations where id = p_generation_id for update;

  if v_exam.status <> 'in_progress' then raise exception 'O exame não aceita mais alterações.'; end if;
  if not private.can_access_clinical_exam_ai(v_actor, v_exam.id) then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if v_generation.status <> 'completed' then raise exception 'A sugestão de IA não está disponível para aplicação.'; end if;
  if v_exam.updated_at is distinct from v_generation.source_exam_updated_at then
    raise exception 'O exame foi atualizado após a geração. Gere uma nova sugestão para comparar com o rascunho atual.';
  end if;

  perform private.validate_exam_ai_suggestion(v_exam.id, v_generation.generation_type, v_generation.suggestion_payload);

  if v_generation.generation_type = 'generate_lab_results' then
    select jsonb_agg(
      parameter || jsonb_build_object(
        'value', suggestion.item->>'value',
        'flag', suggestion.item->'flag'
      ) order by (parameter->>'sort_order')::integer, parameter->>'label'
    ) into v_parameters
    from jsonb_array_elements(v_exam.result_data->'parameters') parameter
    join lateral (
      select item
      from jsonb_array_elements(v_generation.suggestion_payload->'parameters') item
      where item->>'key' = parameter->>'key'
      limit 1
    ) suggestion on true;

    v_candidate := v_exam.result_data || jsonb_build_object(
      'parameters', v_parameters,
      'notes', v_generation.suggestion_payload->>'notes'
    );
    v_result_data := private.normalize_lab_result(v_exam.result_data, v_candidate)
      || jsonb_build_object(
        'report_config_snapshot', v_exam.result_data->'report_config_snapshot',
        'exam_type_snapshot', v_exam.result_data->'exam_type_snapshot'
      );

    update public.clinical_exams set result_data = v_result_data where id = v_exam.id;
  else
    v_config := coalesce(v_exam.result_data->'report_config_snapshot', private.clinical_exam_report_config(v_exam.exam_type_id));
    v_fields := v_generation.suggestion_payload->'fields';
    v_technique := case when coalesce((v_config#>>'{fields,technique,visible}')::boolean, false) then nullif(btrim(v_fields->>'technique'), '') else v_exam.technique end;
    v_findings := case when coalesce((v_config#>>'{fields,findings,visible}')::boolean, false) then nullif(btrim(v_fields->>'findings'), '') else v_exam.findings end;
    v_conclusion := case when coalesce((v_config#>>'{fields,conclusion,visible}')::boolean, false) then nullif(btrim(v_fields->>'conclusion'), '') else v_exam.conclusion end;
    v_result_data := case
      when coalesce((v_config#>>'{fields,observations,visible}')::boolean, false)
        then jsonb_set(v_exam.result_data, '{notes}', to_jsonb(coalesce(v_fields->>'observations', '')), true)
      else v_exam.result_data
    end;

    update public.clinical_exams
    set technique = v_technique, findings = v_findings, conclusion = v_conclusion, result_data = v_result_data
    where id = v_exam.id;
  end if;

  update public.exam_ai_generations set status = 'applied', applied_at = now() where id = p_generation_id;

  perform private.audit_exam_action(
    v_actor,
    'clinical_exam.ai_applied',
    'exam_ai_generations',
    p_generation_id::text,
    jsonb_build_object('status', 'completed'),
    jsonb_build_object('status', 'applied', 'exam_id', v_exam.id, 'generation_type', v_generation.generation_type, 'model', v_generation.model, 'prompt_version', v_generation.prompt_version)
  );
end;
$$;

create or replace function public.discard_clinical_exam_ai_generation(p_generation_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_generation public.exam_ai_generations;
  v_exam public.clinical_exams;
begin
  select * into v_generation from public.exam_ai_generations where id = p_generation_id;
  if v_generation.id is null then raise exception 'Sugestão de IA não localizada.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_generation.exam_id::text || ':' || v_generation.generation_type, 0));
  select * into v_exam from public.clinical_exams where id = v_generation.exam_id for update;
  select * into v_generation from public.exam_ai_generations where id = p_generation_id for update;

  if v_exam.status <> 'in_progress' then raise exception 'O exame não aceita mais alterações.'; end if;
  if not private.can_access_clinical_exam_ai(v_actor, v_exam.id) then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if v_generation.status <> 'completed' then raise exception 'A sugestão de IA não está disponível para descarte.'; end if;

  update public.exam_ai_generations set status = 'discarded', discarded_at = now() where id = p_generation_id;
  perform private.audit_exam_action(
    v_actor,
    'clinical_exam.ai_discarded',
    'exam_ai_generations',
    p_generation_id::text,
    jsonb_build_object('status', 'completed'),
    jsonb_build_object('status', 'discarded', 'exam_id', v_exam.id, 'generation_type', v_generation.generation_type)
  );
end;
$$;

create or replace function public.clinical_exam_ai_generations(p_exam_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_result jsonb;
begin
  if not private.has_permission(v_actor, 'exams.view') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if not exists (select 1 from public.clinical_exams exam where exam.id = p_exam_id) then raise exception 'Exame não localizado.'; end if;
  if not private.can_access_clinical_exam_ai(v_actor, p_exam_id) then return '[]'::jsonb; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', generation.id,
    'generation_type', generation.generation_type,
    'status', generation.status,
    'model', generation.model,
    'reasoning_effort', generation.reasoning_effort,
    'prompt_version', generation.prompt_version,
    'suggestion_payload', generation.suggestion_payload,
    'created_at', generation.created_at,
    'completed_at', generation.completed_at,
    'applied_at', generation.applied_at
  ) order by generation.generation_type, generation.state_rank), '[]'::jsonb)
  into v_result
  from (
    select distinct on (item.generation_type, case when item.status = 'applied' then 1 else 0 end)
      item.*,
      case when item.status = 'applied' then 1 else 0 end as state_rank
    from public.exam_ai_generations item
    where item.exam_id = p_exam_id
      and item.status in ('requested', 'completed', 'applied')
    order by item.generation_type, case when item.status = 'applied' then 1 else 0 end, item.created_at desc, item.id desc
  ) generation;

  return v_result;
end;
$$;

revoke all on function public.clinical_exam_ai_context(bigint, text) from public, anon, authenticated, service_role;
revoke all on function public.begin_clinical_exam_ai_generation(bigint, text, uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public.complete_clinical_exam_ai_generation(uuid, text, integer, integer, integer, jsonb) from public, anon, authenticated, service_role;
revoke all on function public.fail_clinical_exam_ai_generation(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.apply_clinical_exam_ai_generation(uuid) from public, anon, authenticated, service_role;
revoke all on function public.discard_clinical_exam_ai_generation(uuid) from public, anon, authenticated, service_role;
revoke all on function public.clinical_exam_ai_generations(bigint) from public, anon, authenticated, service_role;

grant execute on function public.clinical_exam_ai_context(bigint, text) to authenticated;
grant execute on function public.apply_clinical_exam_ai_generation(uuid) to authenticated;
grant execute on function public.discard_clinical_exam_ai_generation(uuid) to authenticated;
grant execute on function public.clinical_exam_ai_generations(bigint) to authenticated;
grant execute on function public.begin_clinical_exam_ai_generation(bigint, text, uuid, uuid) to service_role;
grant execute on function public.complete_clinical_exam_ai_generation(uuid, text, integer, integer, integer, jsonb) to service_role;
grant execute on function public.fail_clinical_exam_ai_generation(uuid, text) to service_role;

comment on table public.exam_ai_generations is 'Gerações assistivas de IA da Fase 4.6; sugestões exigem decisão humana explícita.';
comment on function public.clinical_exam_ai_context(bigint, text) is 'Entrega à Edge Function somente contexto clínico sem identificação do paciente.';

notify pgrst, 'reload schema';
