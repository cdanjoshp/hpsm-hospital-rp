-- Vincula a sugestão ao tipo real e impede solicitações duplicadas na mesma consulta.

create or replace function public.clinical_consultation_detail(p_consultation_id bigint)
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
  if not private.has_permission(v_actor, 'consultations.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  select jsonb_build_object(
    'id', consultation.id,
    'status', consultation.status,
    'patient', jsonb_build_object(
      'id', patient.id,
      'name', patient.name,
      'passport', patient.passport,
      'allergies', patient.allergies,
      'plan_active', exists (
        select 1 from public.patient_health_plan_requests plan
        where plan.patient_id = patient.id and plan.status = 'approved'
          and (plan.coverage_end is null or plan.coverage_end >= current_date)
      ),
      'cast_active', exists (
        select 1 from public.clinical_casts cast_record
        where cast_record.patient_id = patient.id and cast_record.status = 'in_use'
      ),
      'hospitalization_active', exists (
        select 1 from public.hospitalizations hospitalization
        where hospitalization.patient_id = patient.id and hospitalization.status = 'active'
      )
    ),
    'professional', jsonb_build_object('id', professional.user_id, 'name', professional.display_name, 'position', position.name),
    'appointment', case when appointment.id is null then null else jsonb_build_object(
      'id', appointment.id,
      'scheduled_start', appointment.scheduled_start,
      'scheduled_end', appointment.scheduled_end,
      'reason', appointment.reason,
      'notes', appointment.notes
    ) end,
    'started_at', consultation.started_at,
    'completed_at', consultation.completed_at,
    'vitals', jsonb_build_object(
      'blood_pressure_systolic', consultation.blood_pressure_systolic,
      'blood_pressure_diastolic', consultation.blood_pressure_diastolic,
      'blood_pressure_class', consultation.blood_pressure_class,
      'temperature_c', consultation.temperature_c,
      'temperature_class', consultation.temperature_class,
      'heart_rate_bpm', consultation.heart_rate_bpm,
      'heart_rate_class', consultation.heart_rate_class,
      'oxygen_saturation_percent', consultation.oxygen_saturation_percent,
      'oxygen_saturation_class', consultation.oxygen_saturation_class,
      'pain_score', consultation.pain_score
    ),
    'anamnesis', consultation.anamnesis,
    'selected_diagnosis', consultation.selected_diagnosis,
    'final_diagnosis_plan', consultation.final_diagnosis_plan,
    'complementary_action', consultation.complementary_action,
    'orientation_text', consultation.orientation_text,
    'final_snapshot', consultation.final_snapshot,
    'ai_generations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'action_type', generation.action_type,
        'status', generation.status,
        'response', generation.response_payload,
        'error', generation.error_message,
        'requested_at', generation.requested_at,
        'completed_at', generation.completed_at
      ) order by generation.id)
      from public.consultation_ai_generations generation
      where generation.consultation_id = consultation.id
    ), '[]'::jsonb),
    'exams', case when private.has_permission(v_actor, 'exams.view') then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', exam.id,
        'exam_type_id', exam.exam_type_id,
        'type', exam_type.name,
        'status', exam.status,
        'conclusion', exam.conclusion,
        'completed_at', exam.completed_at
      ) order by exam.requested_at desc, exam.id desc)
      from public.clinical_exams exam
      join public.exam_types exam_type on exam_type.id = exam.exam_type_id
      where exam.consultation_id = consultation.id
    ), '[]'::jsonb) else '[]'::jsonb end,
    'casts', case when private.has_permission(v_actor, 'casts.view') then coalesce((
      select jsonb_agg(jsonb_build_object('id', cast_record.id, 'body_region', cast_record.body_region, 'status', cast_record.status, 'applied_at', cast_record.applied_at) order by cast_record.id desc)
      from public.clinical_casts cast_record where cast_record.consultation_id = consultation.id
    ), '[]'::jsonb) else '[]'::jsonb end,
    'hospitalizations', case when private.has_permission(v_actor, 'hospitalizations.view') then coalesce((
      select jsonb_agg(jsonb_build_object('id', hospitalization.id, 'status', hospitalization.status, 'admitted_at', hospitalization.admitted_at) order by hospitalization.id desc)
      from public.hospitalizations hospitalization where hospitalization.consultation_id = consultation.id
    ), '[]'::jsonb) else '[]'::jsonb end,
    'certificates', case when private.has_permission(v_actor, 'atestados.view') then coalesce((
      select jsonb_agg(jsonb_build_object('id', certificate.id, 'status', certificate.status, 'leave_days', certificate.leave_days, 'created_at', certificate.created_at) order by certificate.id desc)
      from public.medical_certificates certificate where certificate.consultation_id = consultation.id
    ), '[]'::jsonb) else '[]'::jsonb end,
    'can_edit', private.can_edit_consultation(v_actor, consultation.professional_id) and consultation.status = 'in_progress'
  ) into v_result
  from public.clinical_consultations consultation
  join public.patients patient on patient.id = consultation.patient_id
  join public.profiles professional on professional.user_id = consultation.professional_id
  left join public.staff_positions position on position.id = professional.position_id
  left join public.patient_appointments appointment on appointment.id = consultation.appointment_id
  where consultation.id = p_consultation_id;
  if v_result is null then raise exception 'Consulta não localizada.'; end if;
  return v_result;
end;
$$;


create or replace function public.create_consultation_clinical_exam(
  p_consultation_id bigint,
  p_exam_type_id bigint,
  p_indication text,
  p_clinical_context text default null,
  p_attendance_id bigint default null,
  p_initial_result_data jsonb default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_consultation public.clinical_consultations;
  v_exam_id bigint;
begin
  select * into v_consultation from public.clinical_consultations where id = p_consultation_id for update;
  if v_consultation.id is null then raise exception 'Consulta não localizada.'; end if;
  if not private.can_edit_consultation(v_actor, v_consultation.professional_id) or v_consultation.status <> 'in_progress' then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if exists (
    select 1 from public.clinical_exams exam
    where exam.consultation_id = p_consultation_id and exam.exam_type_id = p_exam_type_id
  ) then
    raise exception 'Este tipo de exame já foi solicitado nesta consulta.' using errcode = '23505';
  end if;
  v_exam_id := public.create_clinical_exam(
    v_consultation.patient_id,
    p_exam_type_id,
    v_actor,
    p_indication,
    p_clinical_context,
    p_attendance_id,
    p_initial_result_data
  );
  update public.clinical_exams set consultation_id = p_consultation_id where id = v_exam_id;
  return v_exam_id;
end;
$$;

