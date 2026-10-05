-- Exibe retry quando uma invocação de Edge não finaliza nem grava falha.
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
    'status', case when v_state.status='analyzing' and v_state.requested_at < now()-interval '2 minutes' then 'failed' else coalesce(v_state.status, 'not_started') end, 'options', coalesce(v_state.options, '[]'::jsonb),
    'selected_option_id', v_state.selected_option_id, 'selected_snapshot', v_state.selected_snapshot,
    'analysis_count', coalesce(v_state.analysis_count, 0), 'selected_at', v_state.selected_at,
    'visual_study', v_state.visual_study,
    'report_generation_id', case when v_report.source_exam_updated_at is not distinct from v_exam.updated_at then v_state.report_generation_id else null end,
    'error_code', case when v_state.status='analyzing' and v_state.requested_at < now()-interval '2 minutes' then 'analysis_timeout' else v_state.error_code end
  );
end;
$$;


revoke all on function public.clinical_exam_result_state(bigint) from public,anon,service_role;
grant execute on function public.clinical_exam_result_state(bigint) to authenticated;
notify pgrst,'reload schema';
