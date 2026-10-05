-- Padroniza a solicitação clínica e impede resultados toxicológicos inconclusivos gerados pela Luna.
-- Snapshots e laudos históricos permanecem inalterados.

update public.exam_types as exam_type
set result_config = jsonb_set(
  jsonb_set(
    exam_type.result_config,
    '{version}',
    to_jsonb(greatest(coalesce((exam_type.result_config->>'version')::integer, 1) + 1, 2)),
    true
  ),
  '{parameters}',
  (
    select jsonb_agg(
      case
        when parameter.value->'options' ? 'Inconclusivo'
          then jsonb_set(parameter.value, '{options}', '["Negativo", "Positivo"]'::jsonb, true)
        else parameter.value
      end
      order by parameter.ordinality
    )
    from jsonb_array_elements(exam_type.result_config->'parameters') with ordinality as parameter(value, ordinality)
  ),
  true
)
where exam_type.code = 'toxicologia'
  and exam_type.result_config->>'schema' = 'hpsm.lab_template.v1'
  and jsonb_typeof(exam_type.result_config->'parameters') = 'array'
  and exists (
    select 1
    from jsonb_array_elements(exam_type.result_config->'parameters') as parameter(value)
    where parameter.value->'options' ? 'Inconclusivo'
  );

do $$
begin
  if not exists (
    select 1
    from public.exam_types as exam_type
    where exam_type.code = 'toxicologia'
      and exam_type.result_config->>'schema' = 'hpsm.lab_template.v1'
      and coalesce((exam_type.result_config->>'version')::integer, 0) >= 2
      and not exists (
        select 1
        from jsonb_array_elements(exam_type.result_config->'parameters') as parameter(value)
        where parameter.value->'options' ? 'Inconclusivo'
      )
  ) then
    raise exception 'O template de Toxicologia não pôde ser padronizado.';
  end if;
end;
$$;

alter table public.exam_ai_generations drop constraint exam_ai_generations_prompt_check;
alter table public.exam_ai_generations add constraint exam_ai_generations_prompt_check check (
  (generation_type = 'generate_image' and prompt_version in ('exam-image-rp-v1', 'exam-image-rp-v2', 'exam-image-clinical-v3'))
  or (generation_type = 'generate_exam' and prompt_version in ('exam-rp-luna-v4', 'exam-clinical-exam-v5', 'exam-clinical-exam-v6'))
  or (generation_type = 'generate_report' and prompt_version in ('exam-rp-luna-v1', 'exam-rp-luna-v2', 'exam-rp-luna-v3', 'exam-clinical-report-v4'))
  or (generation_type = 'generate_lab_results' and prompt_version in ('exam-rp-luna-v1', 'exam-rp-luna-v2', 'exam-rp-luna-v3', 'exam-clinical-lab-v3'))
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
    when 'generate_lab_results' then 'exam-clinical-lab-v3'
    when 'generate_report' then 'exam-clinical-report-v4'
    when 'generate_exam' then 'exam-clinical-exam-v6'
    else new.prompt_version
  end;
  return new;
end;
$$;

alter function private.validate_exam_ai_suggestion(bigint, text, jsonb)
  rename to validate_exam_ai_suggestion_clinical_v5;

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
  v_exam_type_code text;
begin
  perform private.validate_exam_ai_suggestion_clinical_v5(p_exam_id, p_generation_type, p_payload);

  if p_generation_type not in ('generate_exam', 'generate_lab_results') then
    return;
  end if;

  select exam_type.code
  into v_exam_type_code
  from public.clinical_exams as exam
  join public.exam_types as exam_type on exam_type.id = exam.exam_type_id
  where exam.id = p_exam_id;

  if v_exam_type_code <> 'toxicologia' then
    return;
  end if;

  if jsonb_typeof(p_payload->'parameters') <> 'array'
     or exists (
       select 1
       from jsonb_array_elements(p_payload->'parameters') as parameter(value)
       where not (
         (parameter.value->>'value' = 'Positivo' and parameter.value->>'flag' = 'positive')
         or (parameter.value->>'value' = 'Negativo' and parameter.value->>'flag' = 'negative')
       )
     )
     or lower(p_payload::text) ~ '(inconclus|indeterminad|sem[[:space:]]+conclus)' then
    raise exception 'A Toxicologia gerada pela IA deve ter somente resultados Positivo ou Negativo.';
  end if;
end;
$$;

revoke all on function private.assign_current_exam_ai_prompt_version() from public, anon, authenticated, service_role;
revoke all on function private.validate_exam_ai_suggestion_clinical_v5(bigint, text, jsonb) from public, anon, authenticated, service_role;
revoke all on function private.validate_exam_ai_suggestion(bigint, text, jsonb) from public, anon, authenticated, service_role;

comment on function private.validate_exam_ai_suggestion(bigint, text, jsonb) is
  'Valida o pacote clínico Luna e restringe Toxicologia gerada por IA a resultados binários coerentes.';

notify pgrst, 'reload schema';
