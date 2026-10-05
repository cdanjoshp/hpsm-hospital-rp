-- HPSM: decisão humana antes da geração clínica final de novos exames.
-- As execuções em andamento no momento da migração seguem o contrato anterior.

create table public.exam_result_choices (
  exam_id bigint primary key references public.clinical_exams(id) on delete cascade,
  status text not null check (status in ('legacy', 'analyzing', 'ready', 'selected', 'failed')),
  analysis_key uuid,
  analysis_count smallint not null default 0 check (analysis_count between 0 and 2),
  requested_by uuid references public.profiles(user_id) on delete restrict,
  options jsonb check (options is null or jsonb_typeof(options) = 'array'),
  selected_option_id text,
  selected_snapshot jsonb check (selected_snapshot is null or jsonb_typeof(selected_snapshot) = 'object'),
  selected_by uuid references public.profiles(user_id) on delete restrict,
  selected_at timestamptz,
  visual_study jsonb check (visual_study is null or jsonb_typeof(visual_study) = 'object'),
  report_generation_id uuid references public.exam_ai_generations(id) on delete set null,
  model text,
  openai_response_id text,
  input_tokens integer,
  output_tokens integer,
  latency_ms integer,
  requested_at timestamptz,
  completed_at timestamptz,
  failed_at timestamptz,
  error_code text,
  constraint exam_result_choices_state_check check (
    (status = 'legacy' and analysis_count = 0 and selected_snapshot is null)
    or (status = 'analyzing' and analysis_key is not null and requested_by is not null)
    or (status = 'ready' and coalesce(jsonb_array_length(options) between 1 and 3, false))
    or (status = 'selected' and selected_snapshot is not null and selected_by is not null and selected_at is not null)
    or (status = 'failed' and requested_by is not null)
  )
);
alter table public.exam_result_choices enable row level security;
alter table public.exam_result_choices force row level security;
revoke all on public.exam_result_choices from public, anon, authenticated, service_role;

insert into public.exam_result_choices(exam_id, status)
select id, 'legacy' from public.clinical_exams where status = 'in_progress'
on conflict (exam_id) do nothing;

create table public.exam_visual_type_config (
  exam_type_id bigint primary key references public.exam_types(id) on delete restrict,
  min_visual_panels smallint not null check (min_visual_panels between 1 and 9),
  max_visual_panels smallint not null check (max_visual_panels between min_visual_panels and 9),
  preferred_planes text[] not null,
  preferred_sequences text[] not null default '{}',
  updated_at timestamptz not null default now()
);
alter table public.exam_visual_type_config enable row level security;
alter table public.exam_visual_type_config force row level security;
revoke all on public.exam_visual_type_config from public, anon, authenticated, service_role;
insert into public.exam_visual_type_config(exam_type_id, min_visual_panels, max_visual_panels, preferred_planes, preferred_sequences)
select id,
  case when code in ('tomografia', 'ressonancia_magnetica') then 6 else 1 end,
  case when code in ('tomografia', 'ressonancia_magnetica') then 9 else 2 end,
  case when code in ('tomografia', 'ressonancia_magnetica') then array['axial','coronal','sagital'] else array['frontal'] end,
  case when code = 'ressonancia_magnetica' then array['T1','T2','FLAIR'] else '{}'::text[] end
from public.exam_types where result_config->>'kind' = 'imaging'
on conflict (exam_type_id) do nothing;

create or replace function private.exam_visual_configuration(p_exam_type_id bigint)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'min_visual_panels', coalesce(config.min_visual_panels, 1),
    'max_visual_panels', coalesce(config.max_visual_panels, 2),
    'preferred_planes', coalesce(to_jsonb(config.preferred_planes), '["frontal"]'::jsonb),
    'preferred_sequences', coalesce(to_jsonb(config.preferred_sequences), '[]'::jsonb)
  ) from public.exam_types exam_type
  left join public.exam_visual_type_config config on config.exam_type_id = exam_type.id
  where exam_type.id = p_exam_type_id;
$$;

create or replace function public.clinical_exam_result_state(p_exam_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_actor uuid := private.hpsm_current_actor(); v_state public.exam_result_choices; v_exam public.clinical_exams;
  v_report public.exam_ai_generations;
begin
  if not private.has_permission(v_actor, 'exams.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  select * into v_exam from public.clinical_exams where id = p_exam_id;
  if v_exam.id is null then raise exception 'Exame não localizado.'; end if;
  select * into v_state from public.exam_result_choices where exam_id = p_exam_id;
  select * into v_report from public.exam_ai_generations where id=v_state.report_generation_id;
  return jsonb_build_object(
    'status', coalesce(v_state.status, 'not_started'), 'options', coalesce(v_state.options, '[]'::jsonb),
    'selected_option_id', v_state.selected_option_id, 'selected_snapshot', v_state.selected_snapshot,
    'analysis_count', coalesce(v_state.analysis_count, 0), 'selected_at', v_state.selected_at,
    'visual_study', v_state.visual_study,
    'report_generation_id', case when v_report.source_exam_updated_at is not distinct from v_exam.updated_at then v_state.report_generation_id else null end,
    'error_code', v_state.error_code
  );
end;
$$;

create or replace function public.begin_clinical_exam_result_options(p_exam_id bigint, p_analysis_key uuid, p_reanalyze boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_actor uuid := private.hpsm_current_actor(); v_exam public.clinical_exams; v_state public.exam_result_choices;
begin
  if p_analysis_key is null then raise exception 'Solicitação inválida.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_exam_id::text || ':result_options', 0));
  select * into v_exam from public.clinical_exams where id = p_exam_id for update;
  if v_exam.id is null or v_exam.status <> 'in_progress' then raise exception 'Exame indisponível para análise.'; end if;
  if not private.can_access_clinical_exam_ai(v_actor, p_exam_id) then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  select * into v_state from public.exam_result_choices where exam_id = p_exam_id for update;
  if v_state.status = 'legacy' then raise exception 'Este exame em andamento utiliza o fluxo anterior.'; end if;
  if v_state.status = 'selected' then return jsonb_build_object('status', 'selected', 'options', v_state.options, 'replayed', true); end if;
  if v_state.status = 'ready' and not p_reanalyze then return jsonb_build_object('status', 'ready', 'options', v_state.options, 'replayed', true); end if;
  if v_state.status = 'analyzing' then
    if v_state.analysis_key = p_analysis_key then return jsonb_build_object('status', 'analyzing', 'replayed', true); end if;
    if v_state.requested_at > now() - interval '2 minutes' then return jsonb_build_object('status', 'analyzing', 'replayed', true); end if;
  end if;
  if p_reanalyze and v_state.status is distinct from 'ready' then raise exception 'A reanálise só pode ocorrer antes da seleção.'; end if;
  if p_reanalyze and v_state.analysis_count >= 2 then raise exception 'O limite de reanálise foi atingido.'; end if;
  if v_state.status = 'ready' and not p_reanalyze then raise exception 'As possibilidades já estão disponíveis.'; end if;
  if v_state.exam_id is null then
    insert into public.exam_result_choices(exam_id,status,analysis_key,analysis_count,requested_by,requested_at,model)
    values(p_exam_id,'analyzing',p_analysis_key,1,v_actor,now(),'gpt-6-sol');
  else
    update public.exam_result_choices set status='analyzing', analysis_key=p_analysis_key,
      analysis_count=case when status='ready' then analysis_count+1 else analysis_count end,
      requested_by=v_actor, requested_at=now(), completed_at=null,
      failed_at=null, error_code=null, options=null, model='gpt-6-sol', openai_response_id=null,
      input_tokens=null, output_tokens=null, latency_ms=null
    where exam_id=p_exam_id;
  end if;
  perform private.audit_exam_action(v_actor, case when p_reanalyze then 'EXAM_RESULT_OPTIONS_REGENERATED' else 'EXAM_RESULT_OPTIONS_REQUESTED' end,
    'clinical_exams', p_exam_id::text, null, jsonb_build_object('analysis_key',p_analysis_key));
  return jsonb_build_object('status','analyzing','replayed',false,'analysis_key',p_analysis_key);
end;
$$;

create or replace function public.complete_clinical_exam_result_options(
  p_exam_id bigint, p_analysis_key uuid, p_actor uuid, p_options jsonb, p_response_id text,
  p_input_tokens integer, p_output_tokens integer, p_latency_ms integer
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_state public.exam_result_choices;
begin
  if current_setting('request.jwt.claim.role', true) is distinct from 'service_role' then raise exception 'Acesso não autorizado.' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_exam_id::text || ':result_options', 0));
  select * into v_state from public.exam_result_choices where exam_id=p_exam_id for update;
  if v_state.status is distinct from 'analyzing' or v_state.analysis_key is distinct from p_analysis_key or v_state.requested_by is distinct from p_actor then
    raise exception 'Análise desatualizada.';
  end if;
  if jsonb_typeof(p_options) <> 'array' or jsonb_array_length(p_options) not between 1 and 3
     or exists (select 1 from jsonb_array_elements(p_options) option_value where
       jsonb_typeof(option_value) <> 'object' or option_value->>'id' !~ '^option_[1-3]$'
       or char_length(btrim(coalesce(option_value->>'title',''))) not between 3 and 100
       or char_length(btrim(coalesce(option_value->>'summary',''))) not between 8 and 500
       or char_length(btrim(coalesce(option_value->>'result_pattern',''))) not between 8 and 600
       or char_length(btrim(coalesce(option_value->>'confidence_context',''))) not between 3 and 400
       or option_value->>'severity' not in ('normal','mild','moderate','severe','critical')
       or private.exam_ai_payload_contains_meta_language(option_value))
     or (select count(*) <> count(distinct option_value->>'id') from jsonb_array_elements(p_options) option_value)
  then raise exception 'Possibilidades de exame inválidas.'; end if;
  update public.exam_result_choices set status='ready', options=p_options,
    completed_at=now(), openai_response_id=left(p_response_id,200),
    input_tokens=greatest(coalesce(p_input_tokens,0),0), output_tokens=greatest(coalesce(p_output_tokens,0),0),
    latency_ms=greatest(coalesce(p_latency_ms,0),0) where exam_id=p_exam_id;
  perform private.audit_exam_action(p_actor,'EXAM_RESULT_OPTIONS_GENERATED','clinical_exams',p_exam_id::text,null,
    jsonb_build_object('count',jsonb_array_length(p_options),'model','gpt-6-sol'));
  return jsonb_build_object('status','ready','options',p_options);
end;
$$;

create or replace function public.fail_clinical_exam_result_options(p_exam_id bigint,p_analysis_key uuid,p_actor uuid,p_error_code text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if current_setting('request.jwt.claim.role', true) is distinct from 'service_role' then raise exception 'Acesso não autorizado.' using errcode='42501'; end if;
  update public.exam_result_choices set status='failed', failed_at=now(), error_code=left(coalesce(p_error_code,'failed'),80)
  where exam_id=p_exam_id and status='analyzing' and analysis_key=p_analysis_key and requested_by=p_actor;
  if found then perform private.audit_exam_action(p_actor,'EXAM_RESULT_OPTIONS_FAILED','clinical_exams',p_exam_id::text,null,
    jsonb_build_object('error_code',left(coalesce(p_error_code,'failed'),80))); end if;
end;
$$;

create or replace function public.select_clinical_exam_result(
  p_exam_id bigint,p_option_id text,p_manual_title text default null,p_manual_context text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_actor uuid := private.hpsm_current_actor(); v_exam public.clinical_exams; v_state public.exam_result_choices;
  v_option jsonb; v_manual boolean := p_option_id = 'manual';
begin
  perform pg_advisory_xact_lock(hashtextextended(p_exam_id::text || ':result_options', 0));
  select * into v_exam from public.clinical_exams where id=p_exam_id for update;
  if v_exam.id is null or v_exam.status <> 'in_progress' or not private.can_access_clinical_exam_ai(v_actor,p_exam_id) then
    raise exception 'Acesso não autorizado.' using errcode='42501';
  end if;
  select * into v_state from public.exam_result_choices where exam_id=p_exam_id for update;
  if v_state.status='selected' then
    if v_state.selected_option_id=p_option_id and v_state.selected_by=v_actor then return v_state.selected_snapshot; end if;
    raise exception 'O resultado já foi confirmado. A decisão não pode ser trocada.';
  end if;
  if v_state.status is distinct from 'ready' then raise exception 'Analise as possibilidades antes de selecionar.'; end if;
  if v_manual then
    if char_length(btrim(coalesce(p_manual_title,''))) not between 3 and 120
       or char_length(btrim(coalesce(p_manual_context,''))) not between 8 and 1000 then
      raise exception 'Informe um resultado e o contexto clínico complementar.';
    end if;
    v_option := jsonb_build_object('id','manual','title',btrim(p_manual_title),'summary',btrim(p_manual_context),
      'result_pattern',btrim(p_manual_context),'severity','manual','confidence_context','Direção definida pelo profissional');
  else
    select option_value into v_option from jsonb_array_elements(v_state.options) option_value
    where option_value->>'id'=p_option_id limit 1;
    if v_option is null then raise exception 'Selecione uma possibilidade válida.'; end if;
  end if;
  if private.exam_ai_payload_contains_meta_language(v_option) then raise exception 'Direção clínica inválida.'; end if;
  v_option := v_option || jsonb_build_object('professional_id',v_actor,'selected_at',now(),'source',case when v_manual then 'manual' else 'options' end);
  update public.exam_result_choices set status='selected', selected_option_id=p_option_id,
    selected_snapshot=v_option, selected_by=v_actor, selected_at=now() where exam_id=p_exam_id;
  perform private.audit_exam_action(v_actor,case when v_manual then 'EXAM_RESULT_MANUAL_DIRECTION' else 'EXAM_RESULT_OPTION_SELECTED' end,
    'clinical_exams',p_exam_id::text,null,jsonb_build_object('selected_option_id',p_option_id));
  return v_option;
end;
$$;

-- A função antiga continua disponível apenas como implementação interna da leitura do contexto.
alter function public.clinical_exam_ai_context(bigint,text) rename to clinical_exam_ai_context_legacy;
revoke all on function public.clinical_exam_ai_context_legacy(bigint,text) from public,anon,authenticated,service_role;

create or replace function public.clinical_exam_result_context(p_exam_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_exam public.clinical_exams; v_state public.exam_result_choices; v_context jsonb;
begin
  select * into v_exam from public.clinical_exams where id=p_exam_id;
  select * into v_state from public.exam_result_choices where exam_id=p_exam_id;
  if v_state.status is distinct from 'analyzing' then raise exception 'Análise de possibilidades não iniciada.'; end if;
  v_context := public.clinical_exam_ai_context_legacy(p_exam_id,
    case when v_exam.result_data->>'schema'='hpsm.image_result.v1' then 'generate_report' else 'generate_exam' end);
  return v_context || jsonb_build_object('generation_type','result_options',
    'visual_config',case when v_exam.result_data->>'schema'='hpsm.image_result.v1'
      then private.exam_visual_configuration(v_exam.exam_type_id) else null end);
end;
$$;

create or replace function public.clinical_exam_ai_context(p_exam_id bigint,p_generation_type text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_exam public.clinical_exams; v_state public.exam_result_choices; v_context jsonb;
begin
  select * into v_exam from public.clinical_exams where id=p_exam_id;
  select * into v_state from public.exam_result_choices where exam_id=p_exam_id;
  if p_generation_type in ('generate_exam','generate_report') and coalesce(v_state.status,'not_started') not in ('legacy','selected')
    then raise exception 'Selecione um resultado antes de gerar o exame.'; end if;
  v_context := public.clinical_exam_ai_context_legacy(p_exam_id,p_generation_type);
  return v_context || jsonb_build_object('selected_result',v_state.selected_snapshot,
    'visual_config',case when v_exam.result_data->>'schema'='hpsm.image_result.v1'
      then private.exam_visual_configuration(v_exam.exam_type_id) else null end,
    'legacy_result_flow',v_state.status='legacy');
end;
$$;

alter table public.exam_ai_generations drop constraint exam_ai_generations_model_check;
alter table public.exam_ai_generations add constraint exam_ai_generations_model_check check (
  (generation_type='generate_image' and model='gpt-image-2') or
  (generation_type<>'generate_image' and model in ('gpt-5.6-luna','gpt-6-sol'))
);
alter table public.exam_ai_generations drop constraint exam_ai_generations_reasoning_check;
alter table public.exam_ai_generations add constraint exam_ai_generations_reasoning_check check (reasoning_effort in ('low','medium'));
alter table public.exam_ai_generations drop constraint exam_ai_generations_prompt_check;
alter table public.exam_ai_generations add constraint exam_ai_generations_prompt_check check (
  (generation_type='generate_image' and prompt_version in ('exam-image-rp-v1','exam-image-rp-v2','exam-image-clinical-v3')) or
  (generation_type='generate_exam' and prompt_version in ('exam-rp-luna-v4','exam-clinical-exam-v5','exam-clinical-exam-v6','exam-clinical-exam-v7','exam-clinical-exam-v8','exam-sol-final-v1')) or
  (generation_type='generate_report' and prompt_version in ('exam-rp-luna-v1','exam-rp-luna-v2','exam-rp-luna-v3','exam-clinical-report-v4','exam-sol-report-v1')) or
  (generation_type='generate_lab_results' and prompt_version in ('exam-rp-luna-v1','exam-rp-luna-v2','exam-rp-luna-v3','exam-clinical-lab-v3','exam-clinical-lab-v4','exam-clinical-lab-v5'))
);

create or replace function private.assign_current_exam_ai_prompt_version()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_selected boolean;
begin
  select state.status='selected' into v_selected from public.exam_result_choices state where state.exam_id=new.exam_id;
  if new.generation_type in ('generate_exam','generate_report') and coalesce(v_selected,false) then
    new.model := 'gpt-6-sol'; new.reasoning_effort := 'medium';
    new.prompt_version := case when new.generation_type='generate_exam' then 'exam-sol-final-v1' else 'exam-sol-report-v1' end;
  else
    new.prompt_version := case new.generation_type
      when 'generate_image' then 'exam-image-clinical-v3'
      when 'generate_lab_results' then 'exam-clinical-lab-v5'
      when 'generate_report' then 'exam-clinical-report-v4'
      when 'generate_exam' then 'exam-clinical-exam-v8'
      else new.prompt_version end;
  end if;
  return new;
end;
$$;

create or replace function public.save_clinical_exam_visual_study(p_exam_id bigint,p_generation_id uuid,p_actor uuid,p_study jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_state public.exam_result_choices;
  v_generation public.exam_ai_generations;
  v_exam public.clinical_exams;
  v_type public.exam_types;
  v_config jsonb;
  v_region text;
begin
  if current_setting('request.jwt.claim.role', true) is distinct from 'service_role' then
    raise exception 'Acesso não autorizado.' using errcode='42501';
  end if;
  select * into v_state from public.exam_result_choices where exam_id=p_exam_id for update;
  select * into v_generation from public.exam_ai_generations where id=p_generation_id;
  select * into v_exam from public.clinical_exams where id=p_exam_id;
  select * into v_type from public.exam_types where id=v_exam.exam_type_id;
  v_config := private.exam_visual_configuration(v_exam.exam_type_id);
  v_region := case when v_exam.result_data->>'region'='Outra região'
    then v_exam.result_data->>'other_region' else v_exam.result_data->>'region' end;
  if v_state.status is distinct from 'selected' or v_generation.id is null
    or v_generation.exam_id is distinct from p_exam_id
    or v_generation.generation_type is distinct from 'generate_report'
    or v_generation.requested_by is distinct from p_actor
    or v_generation.status is distinct from 'requested'
    or v_generation.source_exam_updated_at is distinct from v_exam.updated_at then
    raise exception 'Geração clínica indisponível para estudo visual.';
  end if;
  if jsonb_typeof(p_study) is distinct from 'object'
    or jsonb_typeof(p_study->'panels') is distinct from 'array' then
    raise exception 'Estudo visual inválido.';
  end if;
  if coalesce(p_study->>'panel_count','') !~ '^[1-9]$' then
    raise exception 'Número de painéis inválido.';
  end if;
  if (p_study->>'panel_count')::integer is distinct from jsonb_array_length(p_study->'panels')
    or jsonb_array_length(p_study->'panels') not between (v_config->>'min_visual_panels')::integer and (v_config->>'max_visual_panels')::integer
    or p_study->>'modality' is distinct from v_type.code
    or p_study->>'region' is distinct from v_region
    or p_study->>'laterality' is distinct from coalesce(v_exam.result_data->>'laterality','') then
    raise exception 'Estudo visual incompatível com o exame.';
  end if;
  if exists (select 1 from jsonb_array_elements(p_study->'panels') as panel
    where jsonb_typeof(panel) is distinct from 'object'
      or char_length(btrim(coalesce(panel->>'plane',''))) not between 1 and 300
      or char_length(btrim(coalesce(panel->>'level',''))) not between 1 and 300
      or char_length(btrim(coalesce(panel->>'finding_focus',''))) not between 1 and 300
      or char_length(btrim(coalesce(panel->>'description',''))) not between 1 and 300) then
    raise exception 'Painel visual inválido.';
  end if;
  update public.exam_result_choices set visual_study=p_study,report_generation_id=p_generation_id where exam_id=p_exam_id;
end;
$$;

create or replace function public.clinical_exam_visual_direction(p_exam_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_actor uuid := private.hpsm_current_actor(); v_state public.exam_result_choices; v_generation public.exam_ai_generations;
begin
  if not private.can_access_clinical_exam_ai(v_actor,p_exam_id) then raise exception 'Acesso não autorizado.' using errcode='42501'; end if;
  select * into v_state from public.exam_result_choices where exam_id=p_exam_id;
  if v_state.status='legacy' then return jsonb_build_object('legacy',true); end if;
  select * into v_generation from public.exam_ai_generations where id=v_state.report_generation_id;
  if v_state.status is distinct from 'selected' or coalesce(v_generation.status,'missing') not in ('completed','applied')
     or v_generation.source_exam_updated_at is distinct from (select updated_at from public.clinical_exams where id=p_exam_id)
     or v_generation.model <> 'gpt-6-sol' or v_state.visual_study is null then
    raise exception 'Gere o resultado clínico final antes do estudo visual.';
  end if;
  return jsonb_build_object('selected_result',v_state.selected_snapshot,'report',v_generation.suggestion_payload,
    'visual_study',v_state.visual_study,'report_generation_id',v_generation.id);
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
  v_result_choice public.exam_result_choices;
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
  select * into v_result_choice from public.exam_result_choices where exam_id=p_exam_id;
  if coalesce(v_result_choice.status,'not_started') not in ('legacy','selected') then raise exception 'Selecione um resultado antes de gerar o exame.'; end if;
  if v_result_choice.status='selected' and (p_generation_type not in ('generate_exam','generate_report') or p_source_image_generation_id is not null or p_source_image_id is not null) then raise exception 'Operação incompatível com o resultado selecionado.'; end if;
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
  v_result_choice public.exam_result_choices;
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
  select * into v_result_choice from public.exam_result_choices where exam_id=v_exam.id for update;
  if v_result_choice.status='selected' then
    if v_report_generation.model <> 'gpt-6-sol' or v_report_generation.source_image_generation_id is not null
      or v_result_choice.report_generation_id is distinct from p_report_generation_id or v_result_choice.visual_study is null
      then raise exception 'O estudo visual não corresponde ao resultado clínico aprovado.'; end if;
  elsif coalesce(v_result_choice.status,'not_started')='legacy' then
    if v_report_generation.source_image_generation_id is distinct from p_image_generation_id then raise exception 'O laudo não corresponde à imagem gerada.'; end if;
  else raise exception 'Selecione um resultado antes de gerar a imagem.'; end if;
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


revoke all on function public.clinical_exam_result_state(bigint) from public,anon,authenticated,service_role;
revoke all on function public.begin_clinical_exam_result_options(bigint,uuid,boolean) from public,anon,authenticated,service_role;
revoke all on function public.complete_clinical_exam_result_options(bigint,uuid,uuid,jsonb,text,integer,integer,integer) from public,anon,authenticated,service_role;
revoke all on function public.fail_clinical_exam_result_options(bigint,uuid,uuid,text) from public,anon,authenticated,service_role;
revoke all on function public.select_clinical_exam_result(bigint,text,text,text) from public,anon,authenticated,service_role;
revoke all on function public.clinical_exam_result_context(bigint) from public,anon,authenticated,service_role;
revoke all on function public.clinical_exam_ai_context(bigint,text) from public,anon,authenticated,service_role;
revoke all on function public.save_clinical_exam_visual_study(bigint,uuid,uuid,jsonb) from public,anon,authenticated,service_role;
revoke all on function public.clinical_exam_visual_direction(bigint) from public,anon,authenticated,service_role;
grant execute on function public.clinical_exam_result_state(bigint),public.begin_clinical_exam_result_options(bigint,uuid,boolean),
  public.select_clinical_exam_result(bigint,text,text,text),public.clinical_exam_result_context(bigint),
  public.clinical_exam_ai_context(bigint,text),public.clinical_exam_visual_direction(bigint) to authenticated;
grant execute on function public.complete_clinical_exam_result_options(bigint,uuid,uuid,jsonb,text,integer,integer,integer),
  public.fail_clinical_exam_result_options(bigint,uuid,uuid,text),public.save_clinical_exam_visual_study(bigint,uuid,uuid,jsonb) to service_role;

notify pgrst,'reload schema';
