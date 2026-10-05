-- Chaves sb_secret executam como service_role sem request.jwt.claim.role.
-- A autorização é o GRANT EXECUTE exclusivo ao papel de serviço, com validação dos vínculos da análise.

create or replace function public.complete_clinical_exam_result_options(
  p_exam_id bigint, p_analysis_key uuid, p_actor uuid, p_options jsonb, p_response_id text,
  p_input_tokens integer, p_output_tokens integer, p_latency_ms integer
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_state public.exam_result_choices;
begin
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
  update public.exam_result_choices set status='failed', failed_at=now(), error_code=left(coalesce(p_error_code,'failed'),80)
  where exam_id=p_exam_id and status='analyzing' and analysis_key=p_analysis_key and requested_by=p_actor;
  if found then perform private.audit_exam_action(p_actor,'EXAM_RESULT_OPTIONS_FAILED','clinical_exams',p_exam_id::text,null,
    jsonb_build_object('error_code',left(coalesce(p_error_code,'failed'),80))); end if;
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

revoke all on function public.complete_clinical_exam_result_options(bigint,uuid,uuid,jsonb,text,integer,integer,integer) from public,anon,authenticated;
revoke all on function public.fail_clinical_exam_result_options(bigint,uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.save_clinical_exam_visual_study(bigint,uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.complete_clinical_exam_result_options(bigint,uuid,uuid,jsonb,text,integer,integer,integer),
  public.fail_clinical_exam_result_options(bigint,uuid,uuid,text),
  public.save_clinical_exam_visual_study(bigint,uuid,uuid,jsonb) to service_role;
notify pgrst,'reload schema';
