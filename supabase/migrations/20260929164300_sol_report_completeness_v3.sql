-- V3 exige achados completos e linguagem mais clara, preservando v1/v2.
alter table public.exam_ai_generations drop constraint exam_ai_generations_prompt_check;
alter table public.exam_ai_generations add constraint exam_ai_generations_prompt_check check (
  (generation_type='generate_image' and prompt_version in ('exam-image-rp-v1','exam-image-rp-v2','exam-image-clinical-v3')) or
  (generation_type='generate_exam' and prompt_version in ('exam-rp-luna-v4','exam-clinical-exam-v5','exam-clinical-exam-v6','exam-clinical-exam-v7','exam-clinical-exam-v8','exam-sol-final-v1','exam-sol-legacy-final-v1')) or
  (generation_type='generate_report' and prompt_version in ('exam-rp-luna-v1','exam-rp-luna-v2','exam-rp-luna-v3','exam-clinical-report-v4','exam-sol-report-v1','exam-sol-report-v2','exam-sol-report-v3','exam-sol-legacy-report-v1')) or
  (generation_type='generate_lab_results' and prompt_version in ('exam-rp-luna-v1','exam-rp-luna-v2','exam-rp-luna-v3','exam-clinical-lab-v3','exam-clinical-lab-v4','exam-clinical-lab-v5','exam-sol-lab-v1'))
);

create or replace function private.assign_current_exam_ai_prompt_version()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_selected boolean;
begin
  if new.generation_type = 'generate_image' then
    new.prompt_version := 'exam-image-clinical-v3';
    return new;
  end if;

  select state.status='selected' into v_selected
  from public.exam_result_choices state where state.exam_id=new.exam_id;
  new.model := 'gpt-6-sol';
  new.reasoning_effort := 'medium';
  new.prompt_version := case new.generation_type
    when 'generate_lab_results' then 'exam-sol-lab-v1'
    when 'generate_exam' then case when coalesce(v_selected,false) then 'exam-sol-final-v1' else 'exam-sol-legacy-final-v1' end
    when 'generate_report' then case when coalesce(v_selected,false) then 'exam-sol-report-v3' else 'exam-sol-legacy-report-v1' end
    else new.prompt_version end;
  return new;
end;
$$;

notify pgrst, 'reload schema';
