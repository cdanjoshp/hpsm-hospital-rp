-- HPSM · Consultas pós-implementação 3
-- Consolida o consumo de IA e cria o prontuário completo em PNG sobre a
-- infraestrutura clínica, de identidade profissional, Storage e auditoria já existentes.

alter table public.consultation_ai_generations
  add column if not exists input_tokens integer,
  add column if not exists output_tokens integer,
  add column if not exists cached_input_tokens integer;

alter table public.consultation_ai_generations
  drop constraint if exists consultation_ai_action_check;

alter table public.consultation_ai_generations
  drop constraint if exists consultation_ai_generations_action_type_check;

alter table public.consultation_ai_generations
  add constraint consultation_ai_action_check check (action_type in (
    'ANAMNESIS_REWRITE',
    'EXAM_SUGGESTIONS',
    'DIAGNOSIS_OPTIONS',
    'FINAL_DIAGNOSIS_PLAN',
    'ORIENTATION_MEDICATION',
    'CLINICAL_SYNTHESIS'
  ));

alter table public.consultation_ai_generations
  drop constraint if exists consultation_ai_token_usage_check;

alter table public.consultation_ai_generations
  add constraint consultation_ai_token_usage_check check (
    (input_tokens is null or input_tokens >= 0)
    and (output_tokens is null or output_tokens >= 0)
    and (cached_input_tokens is null or cached_input_tokens >= 0)
    and (input_tokens is null or cached_input_tokens is null or cached_input_tokens <= input_tokens)
  );

create table public.consultation_documents (
  id uuid primary key default gen_random_uuid(),
  consultation_id bigint not null unique references public.clinical_consultations(id) on delete cascade,
  status text not null default 'pending',
  source_snapshot jsonb not null,
  storage_path text,
  mime_type text,
  file_size bigint,
  pixel_width integer,
  pixel_height integer,
  render_version text,
  created_by uuid not null references public.profiles(user_id) on delete restrict,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint consultation_documents_status_check check (status in ('pending', 'completed')),
  constraint consultation_documents_snapshot_check check (jsonb_typeof(source_snapshot) = 'object'),
  constraint consultation_documents_state_check check (
    (status = 'pending' and storage_path is null and mime_type is null and file_size is null
      and pixel_width is null and pixel_height is null and render_version is null and completed_at is null)
    or
    (status = 'completed' and storage_path is not null and mime_type = 'image/png'
      and file_size between 32 and 12582912 and pixel_width between 900 and 1400
      and pixel_height between 400 and 14000 and render_version = 'consultation-document-png-v1'
      and completed_at is not null)
  ),
  constraint consultation_documents_storage_path_check check (
    storage_path is null
    or storage_path ~ ('^consultations/' || consultation_id::text || '/documents/[0-9a-f-]{36}[.]png$')
  )
);

create table public.consultation_document_shares (
  id uuid primary key default gen_random_uuid(),
  consultation_id bigint not null references public.clinical_consultations(id) on delete cascade,
  document_id uuid not null references public.consultation_documents(id) on delete cascade,
  created_by uuid not null references public.profiles(user_id) on delete restrict,
  created_at timestamptz not null default now(),
  revoked_by uuid references public.profiles(user_id) on delete restrict,
  revoked_at timestamptz,
  constraint consultation_document_shares_revocation_check check (
    (revoked_at is null and revoked_by is null) or (revoked_at is not null and revoked_by is not null)
  )
);

create unique index consultation_document_shares_one_active_uidx
  on public.consultation_document_shares (consultation_id)
  where revoked_at is null;
create index consultation_document_shares_document_idx
  on public.consultation_document_shares (document_id);

alter table public.consultation_documents enable row level security;
alter table public.consultation_documents force row level security;
alter table public.consultation_document_shares enable row level security;
alter table public.consultation_document_shares force row level security;

revoke all on public.consultation_documents, public.consultation_document_shares
from public, anon, authenticated, service_role;
grant select, insert, update, delete on public.consultation_documents, public.consultation_document_shares
to service_role;

create or replace function private.build_consultation_snapshot_v2(
  p_consultation_id bigint,
  p_completed_at timestamptz
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_consultation public.clinical_consultations;
  v_snapshot jsonb;
begin
  select * into v_consultation
  from public.clinical_consultations consultation
  where consultation.id = p_consultation_id;
  if v_consultation.id is null then raise exception 'Consulta não localizada.'; end if;

  select jsonb_build_object(
    'schema', 'hpsm.clinical_consultation.v2',
    'consultation_id', consultation.id,
    'patient', jsonb_build_object(
      'id', patient.id,
      'name', patient.name,
      'passport', patient.passport,
      'birth_date', patient.birth_date,
      'phone', patient.phone,
      'emergency_contact_name', patient.emergency_contact_name,
      'emergency_contact_phone', patient.emergency_contact_phone,
      'allergies', patient.allergies,
      'plan_code', patient.plan_code,
      'health_plan', (
        select jsonb_build_object(
          'status', plan.status,
          'coverage_start', plan.coverage_start,
          'coverage_end', plan.coverage_end
        )
        from public.patient_health_plan_requests plan
        where plan.patient_id = patient.id and plan.status = 'approved'
        order by plan.coverage_end desc nulls first, plan.id desc
        limit 1
      ),
      'partnerships', coalesce((
        select jsonb_agg(jsonb_build_object('id', partnership.id, 'name', partnership.name) order by lower(partnership.name))
        from public.patient_partnerships membership
        join public.partnerships partnership on partnership.id = membership.partnership_id
        where membership.patient_id = patient.id and membership.status = 'active' and partnership.status = 'active'
      ), '[]'::jsonb)
    ),
    'professional', jsonb_build_object(
      'id', professional.user_id,
      'name', professional.display_name,
      'position', position.name,
      'crm_code', identity.crm_code,
      'signature_image_path', identity.signature_image_path
    ),
    'appointment', case when appointment.id is null then null else jsonb_build_object(
      'id', appointment.id,
      'scheduled_start', appointment.scheduled_start,
      'scheduled_end', appointment.scheduled_end,
      'reason', appointment.reason,
      'notes', appointment.notes
    ) end,
    'started_at', consultation.started_at,
    'completed_at', p_completed_at,
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
    'exam_analysis', (
      select generation.response_payload
      from public.consultation_ai_generations generation
      where generation.consultation_id = consultation.id
        and generation.action_type = 'EXAM_SUGGESTIONS'
        and generation.status = 'completed'
    ),
    'exams', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', exam.id,
        'type', exam_type.name,
        'category', category.name,
        'indication', exam.indication,
        'clinical_context', exam.clinical_context,
        'status', exam.status,
        'result', case when exam.status = 'completed' then coalesce(
          exam.final_report_snapshot->'content',
          jsonb_build_object('technique', exam.technique, 'findings', exam.findings, 'conclusion', exam.conclusion, 'result_data', exam.result_data)
        ) else null end,
        'requested_by', requester.display_name,
        'responsible_professional', responsible.display_name,
        'requested_at', exam.requested_at,
        'completed_at', exam.completed_at
      ) order by exam.requested_at, exam.id)
      from public.clinical_exams exam
      join public.exam_types exam_type on exam_type.id = exam.exam_type_id
      join public.exam_categories category on category.id = exam_type.category_id
      join public.profiles requester on requester.user_id = exam.requested_by
      join public.profiles responsible on responsible.user_id = exam.responsible_professional_id
      where exam.consultation_id = consultation.id
    ), '[]'::jsonb),
    'casts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', cast_record.id,
        'body_region', cast_record.body_region,
        'laterality', cast_record.laterality,
        'body_model', cast_record.body_model_snapshot,
        'game_reference', cast_record.game_reference_snapshot,
        'status', cast_record.status,
        'applied_at', cast_record.applied_at,
        'expected_removal_at', cast_record.expected_removal_at,
        'responsible', cast_professional.display_name
      ) order by cast_record.applied_at, cast_record.id)
      from public.clinical_casts cast_record
      join public.profiles cast_professional on cast_professional.user_id = cast_record.applied_by
      where cast_record.consultation_id = consultation.id
    ), '[]'::jsonb),
    'hospitalizations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', hospitalization.id,
        'bed', coalesce(bed.label, bed.code, bed.number::text),
        'reason', hospitalization.reason,
        'status', hospitalization.status,
        'admitted_at', hospitalization.admitted_at,
        'responsible', admitting_professional.display_name
      ) order by hospitalization.admitted_at, hospitalization.id)
      from public.hospitalizations hospitalization
      join public.hospital_beds bed on bed.id = hospitalization.bed_id
      join public.profiles admitting_professional on admitting_professional.user_id = hospitalization.admitted_by
      where hospitalization.consultation_id = consultation.id
    ), '[]'::jsonb),
    'certificates', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', certificate.id,
        'status', certificate.status,
        'diagnosis', certificate.diagnosis_text,
        'cid_code', certificate.cid_code,
        'leave_days', certificate.leave_days,
        'created_at', certificate.created_at,
        'finalized_at', certificate.finalized_at
      ) order by certificate.created_at, certificate.id)
      from public.medical_certificates certificate
      where certificate.consultation_id = consultation.id
    ), '[]'::jsonb),
    'follow_ups', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', follow_up.id,
        'scheduled_start', follow_up.scheduled_start,
        'professional', follow_up_professional.display_name,
        'status', follow_up.status,
        'reason', follow_up.reason
      ) order by follow_up.scheduled_start, follow_up.id)
      from public.patient_appointments follow_up
      join public.profiles follow_up_professional on follow_up_professional.user_id = follow_up.professional_id
      where follow_up.follow_up_of_consultation_id = consultation.id
    ), '[]'::jsonb)
  ) into v_snapshot
  from public.clinical_consultations consultation
  join public.patients patient on patient.id = consultation.patient_id
  join public.profiles professional on professional.user_id = consultation.professional_id
  join public.staff_positions position on position.id = professional.position_id
  join public.professional_identities identity on identity.user_id = professional.user_id
  left join public.patient_appointments appointment on appointment.id = consultation.appointment_id
  where consultation.id = p_consultation_id
    and identity.status = 'active'
    and identity.signature_image_path is not null
    and identity.crm_code ~ '^[0-9]{8}$';

  if v_snapshot is null then
    raise exception 'A identidade profissional ainda está sendo preparada. Gere a assinatura e o CRM antes de concluir.';
  end if;
  return v_snapshot;
end;
$$;

revoke all on function private.build_consultation_snapshot_v2(bigint, timestamptz)
from public, anon, authenticated, service_role;

create or replace function public.begin_consultation_ai_generation(
  p_consultation_id bigint,
  p_action_type text,
  p_request_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
  v_consultation public.clinical_consultations;
  v_generation public.consultation_ai_generations;
begin
  select * into v_consultation from public.clinical_consultations where id = p_consultation_id for update;
  if v_consultation.id is null then raise exception 'Consulta não localizada.'; end if;
  v_actor := v_consultation.professional_id;
  if v_consultation.status <> 'in_progress'
     or not private.is_hpsm_workforce(v_actor)
     or not private.has_permission(v_actor, 'consultations.complete') then
    raise exception 'A consulta não aceita assistência.' using errcode = '42501';
  end if;
  if p_action_type not in ('ANAMNESIS_REWRITE', 'EXAM_SUGGESTIONS', 'CLINICAL_SYNTHESIS') then
    raise exception 'Ação de IA inválida.';
  end if;
  if p_request_key is null then raise exception 'Identificador da solicitação ausente.'; end if;
  if p_action_type in ('EXAM_SUGGESTIONS', 'CLINICAL_SYNTHESIS') and (
    v_consultation.blood_pressure_systolic is null or v_consultation.blood_pressure_diastolic is null
    or v_consultation.temperature_c is null or v_consultation.heart_rate_bpm is null
    or v_consultation.oxygen_saturation_percent is null or v_consultation.pain_score is null
    or char_length(btrim(coalesce(v_consultation.anamnesis, ''))) < 3
  ) then raise exception 'Preencha os sinais vitais, a dor e a anamnese antes desta análise.'; end if;
  if p_action_type = 'CLINICAL_SYNTHESIS' and not exists (
    select 1 from public.consultation_ai_generations generation
    where generation.consultation_id = p_consultation_id
      and generation.action_type = 'EXAM_SUGGESTIONS'
      and generation.status = 'completed'
  ) then raise exception 'Analise a necessidade de exames antes da síntese clínica.'; end if;

  select * into v_generation
  from public.consultation_ai_generations generation
  where generation.consultation_id = p_consultation_id and generation.action_type = p_action_type
  for update;
  if v_generation.id is null then
    insert into public.consultation_ai_generations (consultation_id, action_type, request_key, requested_by)
    values (p_consultation_id, p_action_type, p_request_key, v_actor)
    returning * into v_generation;
  elsif v_generation.status = 'failed' then
    update public.consultation_ai_generations set
      status = 'pending', request_key = p_request_key, response_payload = null, error_message = null,
      model = null, prompt_version = null, requested_by = v_actor, requested_at = now(),
      completed_at = null, failed_at = null, input_tokens = null, output_tokens = null,
      cached_input_tokens = null
    where id = v_generation.id returning * into v_generation;
  end if;
  return jsonb_build_object(
    'id', v_generation.id,
    'status', v_generation.status,
    'request_key', v_generation.request_key,
    'response', v_generation.response_payload
  );
end;
$$;

create or replace function public.complete_consultation_ai_generation_v2(
  p_consultation_id bigint,
  p_action_type text,
  p_request_key uuid,
  p_response_payload jsonb,
  p_model text,
  p_prompt_version text,
  p_input_tokens integer,
  p_output_tokens integer,
  p_cached_input_tokens integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_generation public.consultation_ai_generations;
begin
  select generation.* into v_generation
  from public.consultation_ai_generations generation
  join public.clinical_consultations consultation on consultation.id = generation.consultation_id
  where generation.consultation_id = p_consultation_id
    and generation.action_type = p_action_type
    and consultation.status = 'in_progress'
    and private.is_hpsm_workforce(consultation.professional_id)
    and private.has_permission(consultation.professional_id, 'consultations.complete')
  for update of generation;
  if v_generation.id is null or v_generation.request_key <> p_request_key then
    raise exception 'Solicitação de IA inválida.' using errcode = '42501';
  end if;
  if v_generation.status = 'completed' then return v_generation.response_payload; end if;
  if v_generation.status <> 'pending' or p_response_payload is null or jsonb_typeof(p_response_payload) <> 'object' then
    raise exception 'Resposta de IA inválida.';
  end if;
  if p_model <> 'gpt-5.6-luna' or p_prompt_version <> 'consultation-assistant-v4' then
    raise exception 'Origem da assistência inválida.' using errcode = '42501';
  end if;
  if p_action_type not in ('ANAMNESIS_REWRITE', 'EXAM_SUGGESTIONS', 'CLINICAL_SYNTHESIS') then
    raise exception 'Ação de IA inválida.';
  end if;
  if coalesce(p_input_tokens, -1) < 0 or coalesce(p_output_tokens, -1) < 0
     or coalesce(p_cached_input_tokens, -1) < 0 or p_cached_input_tokens > p_input_tokens then
    raise exception 'Telemetria de IA inválida.';
  end if;
  if p_action_type = 'ANAMNESIS_REWRITE' and char_length(btrim(coalesce(p_response_payload->>'text', ''))) < 3 then
    raise exception 'A reescrita da anamnese está vazia.';
  end if;
  if p_action_type = 'EXAM_SUGGESTIONS' then
    if jsonb_typeof(p_response_payload->'no_exam_needed') <> 'boolean'
       or jsonb_typeof(p_response_payload->'exam_suggestions') <> 'array'
       or jsonb_array_length(p_response_payload->'exam_suggestions') > 5
       or ((p_response_payload->>'no_exam_needed')::boolean and jsonb_array_length(p_response_payload->'exam_suggestions') <> 0)
       or (not (p_response_payload->>'no_exam_needed')::boolean and jsonb_array_length(p_response_payload->'exam_suggestions') = 0) then
      raise exception 'A análise de exames retornou um formato inválido.';
    end if;
    if exists (
      select 1 from jsonb_array_elements(p_response_payload->'exam_suggestions') suggestion
      where not exists (
        select 1 from public.exam_types exam_type
        join public.exam_categories category on category.id = exam_type.category_id
        where exam_type.id = nullif(suggestion->>'exam_type_id', '')::bigint
          and exam_type.active and category.active
      )
    ) then raise exception 'A IA sugeriu um tipo de exame indisponível.'; end if;
  end if;
  if p_action_type = 'CLINICAL_SYNTHESIS' then
    if jsonb_typeof(p_response_payload->'options') <> 'array'
       or jsonb_array_length(p_response_payload->'options') <> 3
       or (select array_agg(option->>'severity' order by option->>'severity')
           from jsonb_array_elements(p_response_payload->'options') option)
          <> array['grave', 'gravissimo', 'normal']::text[]
       or exists (
         select 1 from jsonb_array_elements(p_response_payload->'options') option
         where char_length(btrim(coalesce(option->>'diagnosis', ''))) < 3
            or char_length(btrim(coalesce(option->>'reasoning_summary', ''))) < 3
            or char_length(btrim(coalesce(option->>'final_plan', ''))) < 3
            or option->>'complementary_action' not in ('NONE', 'CAST', 'HOSPITALIZATION')
            or char_length(btrim(coalesce(option->>'orientation', ''))) < 3
       ) then raise exception 'A síntese deve retornar exatamente Normal, Grave e Gravíssimo com diagnóstico, justificativa, plano, conduta e orientação.';
    end if;
  end if;

  update public.consultation_ai_generations set
    status = 'completed', response_payload = p_response_payload, error_message = null,
    model = btrim(p_model), prompt_version = btrim(p_prompt_version), completed_at = now(), failed_at = null,
    input_tokens = p_input_tokens, output_tokens = p_output_tokens,
    cached_input_tokens = p_cached_input_tokens
  where id = v_generation.id;
  return p_response_payload;
end;
$$;

create or replace function public.consultation_ai_context(p_consultation_id bigint)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'status', consultation.status,
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
    'allergies', patient.allergies,
    'anamnesis', consultation.anamnesis,
    'exam_analysis', (
      select generation.response_payload
      from public.consultation_ai_generations generation
      where generation.consultation_id = consultation.id
        and generation.action_type = 'EXAM_SUGGESTIONS'
        and generation.status = 'completed'
    ),
    'linked_exams', coalesce((
      select jsonb_agg(jsonb_build_object(
        'type', exam_type.name,
        'category', category.name,
        'indication', exam.indication,
        'status', exam.status,
        'conclusion', exam.conclusion,
        'result_data', case when exam.status = 'completed' then exam.result_data else null end
      ) order by exam.requested_at, exam.id)
      from public.clinical_exams exam
      join public.exam_types exam_type on exam_type.id = exam.exam_type_id
      join public.exam_categories category on category.id = exam_type.category_id
      where exam.consultation_id = consultation.id
    ), '[]'::jsonb)
  )
  from public.clinical_consultations consultation
  join public.patients patient on patient.id = consultation.patient_id
  where consultation.id = p_consultation_id;
$$;

create or replace function public.save_clinical_consultation_draft(
  p_consultation_id bigint,
  p_blood_pressure_systolic integer,
  p_blood_pressure_diastolic integer,
  p_blood_pressure_class text,
  p_temperature_c numeric,
  p_temperature_class text,
  p_heart_rate_bpm integer,
  p_heart_rate_class text,
  p_oxygen_saturation_percent integer,
  p_oxygen_saturation_class text,
  p_pain_score integer,
  p_anamnesis text,
  p_selected_diagnosis jsonb,
  p_final_diagnosis_plan text,
  p_complementary_action text,
  p_orientation_text text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_consultation public.clinical_consultations;
begin
  select * into v_consultation from public.clinical_consultations where id = p_consultation_id for update;
  if v_consultation.id is null then raise exception 'Consulta não localizada.'; end if;
  if not private.can_edit_consultation(v_actor, v_consultation.professional_id) then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if v_consultation.status <> 'in_progress' then raise exception 'A consulta já foi concluída.'; end if;
  if p_complementary_action not in ('NONE', 'CAST', 'HOSPITALIZATION') then raise exception 'Conduta complementar inválida.'; end if;
  if p_selected_diagnosis is not null and (
    jsonb_typeof(p_selected_diagnosis) <> 'object'
    or p_selected_diagnosis->>'severity' not in ('normal', 'grave', 'gravissimo')
    or char_length(btrim(coalesce(p_selected_diagnosis->>'diagnosis', p_selected_diagnosis->>'title', ''))) < 3
  ) then raise exception 'Diagnóstico selecionado inválido.'; end if;

  update public.clinical_consultations set
    blood_pressure_systolic = p_blood_pressure_systolic,
    blood_pressure_diastolic = p_blood_pressure_diastolic,
    blood_pressure_class = nullif(btrim(coalesce(p_blood_pressure_class, '')), ''),
    temperature_c = p_temperature_c,
    temperature_class = nullif(btrim(coalesce(p_temperature_class, '')), ''),
    heart_rate_bpm = p_heart_rate_bpm,
    heart_rate_class = nullif(btrim(coalesce(p_heart_rate_class, '')), ''),
    oxygen_saturation_percent = p_oxygen_saturation_percent,
    oxygen_saturation_class = nullif(btrim(coalesce(p_oxygen_saturation_class, '')), ''),
    pain_score = p_pain_score,
    anamnesis = nullif(btrim(coalesce(p_anamnesis, '')), ''),
    selected_diagnosis = p_selected_diagnosis,
    final_diagnosis_plan = nullif(btrim(coalesce(p_final_diagnosis_plan, '')), ''),
    complementary_action = p_complementary_action,
    orientation_text = nullif(btrim(coalesce(p_orientation_text, '')), '')
  where id = p_consultation_id;
end;
$$;

create or replace function public.complete_clinical_consultation(p_consultation_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_consultation public.clinical_consultations;
  v_completed_at timestamptz := clock_timestamp();
  v_snapshot jsonb;
begin
  select * into v_consultation from public.clinical_consultations where id = p_consultation_id for update;
  if v_consultation.id is null then raise exception 'Consulta não localizada.'; end if;
  if not private.can_edit_consultation(v_actor, v_consultation.professional_id) then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if v_consultation.status <> 'in_progress' then raise exception 'A consulta já foi concluída.'; end if;
  if v_consultation.blood_pressure_systolic is null or v_consultation.blood_pressure_diastolic is null or v_consultation.blood_pressure_class is null
     or v_consultation.temperature_c is null or v_consultation.temperature_class is null
     or v_consultation.heart_rate_bpm is null or v_consultation.heart_rate_class is null
     or v_consultation.oxygen_saturation_percent is null or v_consultation.oxygen_saturation_class is null
     or v_consultation.pain_score is null then
    raise exception 'Preencha e classifique todos os sinais vitais e a escala de dor.';
  end if;
  if char_length(btrim(coalesce(v_consultation.anamnesis, ''))) < 3 then raise exception 'Preencha a anamnese e evolução.'; end if;
  if not exists (select 1 from public.consultation_ai_generations where consultation_id = p_consultation_id and action_type = 'EXAM_SUGGESTIONS' and status = 'completed') then
    raise exception 'Analise a necessidade de exames antes de concluir.';
  end if;
  if not exists (select 1 from public.consultation_ai_generations where consultation_id = p_consultation_id and action_type = 'CLINICAL_SYNTHESIS' and status = 'completed') then
    raise exception 'Execute a síntese clínica antes de concluir.';
  end if;
  if v_consultation.selected_diagnosis is null then raise exception 'Selecione uma hipótese diagnóstica.'; end if;
  if char_length(btrim(coalesce(v_consultation.final_diagnosis_plan, ''))) < 3 then raise exception 'Preencha o diagnóstico final e o plano.'; end if;
  if char_length(btrim(coalesce(v_consultation.orientation_text, ''))) < 3 then raise exception 'Preencha as orientações ao paciente.'; end if;

  v_snapshot := private.build_consultation_snapshot_v2(p_consultation_id, v_completed_at);
  update public.clinical_consultations
  set status = 'completed', completed_at = v_completed_at, final_snapshot = v_snapshot
  where id = p_consultation_id;
  if v_consultation.appointment_id is not null then
    update public.patient_appointments set status = 'completed', completed_at = v_completed_at
    where id = v_consultation.appointment_id and status = 'in_progress';
  end if;
  return v_snapshot;
end;
$$;

create or replace function public.begin_consultation_document(p_consultation_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_consultation public.clinical_consultations;
  v_document public.consultation_documents;
  v_snapshot jsonb;
begin
  if not private.has_permission(v_actor, 'consultations.view') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  select * into v_consultation from public.clinical_consultations where id = p_consultation_id for update;
  if v_consultation.id is null then raise exception 'Consulta não localizada.'; end if;
  if v_consultation.status <> 'completed' or v_consultation.final_snapshot is null then raise exception 'O prontuário está disponível somente para consultas concluídas.'; end if;

  select * into v_document from public.consultation_documents where consultation_id = p_consultation_id for update;
  if v_document.id is null then
    v_snapshot := case
      when v_consultation.final_snapshot->>'schema' = 'hpsm.clinical_consultation.v2' then v_consultation.final_snapshot
      else private.build_consultation_snapshot_v2(p_consultation_id, v_consultation.completed_at)
    end;
    insert into public.consultation_documents (consultation_id, source_snapshot, created_by)
    values (p_consultation_id, v_snapshot, v_actor)
    returning * into v_document;
  end if;
  return jsonb_build_object(
    'document_id', v_document.id,
    'status', v_document.status,
    'source_snapshot', v_document.source_snapshot,
    'storage_path', v_document.storage_path,
    'file_size', v_document.file_size,
    'pixel_width', v_document.pixel_width,
    'pixel_height', v_document.pixel_height,
    'render_version', v_document.render_version
  );
end;
$$;

create or replace function public.complete_consultation_document(
  p_consultation_id bigint,
  p_document_id uuid,
  p_storage_path text,
  p_file_size integer,
  p_pixel_width integer,
  p_pixel_height integer,
  p_render_version text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_document public.consultation_documents;
  v_passport text;
begin
  if not private.has_permission(v_actor, 'consultations.view') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  select * into v_document from public.consultation_documents
  where id = p_document_id and consultation_id = p_consultation_id for update;
  if v_document.id is null then raise exception 'Preparação de prontuário inválida.'; end if;
  if v_document.status = 'completed' then return public.consultation_document_state(p_consultation_id); end if;
  if p_storage_path !~ ('^consultations/' || p_consultation_id::text || '/documents/' || p_document_id::text || '[.]png$')
     or p_file_size not between 32 and 12582912 or p_pixel_width not between 900 and 1400
     or p_pixel_height not between 400 and 14000 or p_render_version <> 'consultation-document-png-v1' then
    raise exception 'Metadados do prontuário inválidos.';
  end if;
  if not exists (
    select 1 from storage.objects object
    where object.bucket_id = 'clinical-exam-documents' and object.name = p_storage_path
  ) then raise exception 'A imagem do prontuário ainda não foi confirmada no Storage.'; end if;

  update public.consultation_documents set
    status = 'completed', storage_path = p_storage_path, mime_type = 'image/png', file_size = p_file_size,
    pixel_width = p_pixel_width, pixel_height = p_pixel_height, render_version = p_render_version,
    completed_at = now()
  where id = p_document_id;
  select passport into v_passport from public.profiles where user_id = v_actor;
  insert into public.audit_logs (actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values)
  values (v_actor, v_passport, 'CONSULTATION_DOCUMENT_GENERATED', 'clinical_consultations', p_consultation_id::text,
    null, jsonb_build_object('document_id', p_document_id, 'render_version', p_render_version, 'file_size', p_file_size));
  return public.consultation_document_state(p_consultation_id);
end;
$$;

create or replace function public.consultation_document_state(p_consultation_id bigint)
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
  if not private.has_permission(v_actor, 'consultations.view') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if not exists (select 1 from public.clinical_consultations where id = p_consultation_id and status = 'completed') then
    raise exception 'O prontuário está disponível somente para consultas concluídas.';
  end if;
  select jsonb_build_object(
    'document', case when document.status = 'completed' then jsonb_build_object(
      'id', document.id,
      'created_at', document.created_at,
      'completed_at', document.completed_at,
      'file_size', document.file_size,
      'pixel_width', document.pixel_width,
      'pixel_height', document.pixel_height,
      'render_version', document.render_version
    ) else null end,
    'share', case when share.id is null then null else jsonb_build_object('id', share.id, 'created_at', share.created_at) end
  ) into v_result
  from public.clinical_consultations consultation
  left join public.consultation_documents document on document.consultation_id = consultation.id
  left join public.consultation_document_shares share on share.consultation_id = consultation.id and share.revoked_at is null
  where consultation.id = p_consultation_id;
  return coalesce(v_result, jsonb_build_object('document', null, 'share', null));
end;
$$;

create or replace function public.create_consultation_document_share(p_consultation_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_document public.consultation_documents;
  v_share public.consultation_document_shares;
  v_passport text;
begin
  if not private.has_permission(v_actor, 'consultations.view') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  select * into v_document from public.consultation_documents
  where consultation_id = p_consultation_id and status = 'completed' for update;
  if v_document.id is null then raise exception 'Gere o prontuário antes de compartilhar.'; end if;
  select * into v_share from public.consultation_document_shares
  where consultation_id = p_consultation_id and revoked_at is null for update;
  if v_share.id is null then
    insert into public.consultation_document_shares (consultation_id, document_id, created_by)
    values (p_consultation_id, v_document.id, v_actor)
    returning * into v_share;
    select passport into v_passport from public.profiles where user_id = v_actor;
    insert into public.audit_logs (actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values)
    values (v_actor, v_passport, 'CONSULTATION_DOCUMENT_SHARED', 'clinical_consultations', p_consultation_id::text,
      null, jsonb_build_object('share_id', v_share.id, 'document_id', v_document.id));
  end if;
  return public.consultation_document_state(p_consultation_id);
end;
$$;

create or replace function public.revoke_consultation_document_share(p_consultation_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_share public.consultation_document_shares;
  v_passport text;
begin
  if not private.has_permission(v_actor, 'consultations.view') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  select * into v_share from public.consultation_document_shares
  where consultation_id = p_consultation_id and revoked_at is null for update;
  if v_share.id is not null then
    update public.consultation_document_shares set revoked_by = v_actor, revoked_at = now() where id = v_share.id;
    select passport into v_passport from public.profiles where user_id = v_actor;
    insert into public.audit_logs (actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values)
    values (v_actor, v_passport, 'CONSULTATION_DOCUMENT_SHARE_REVOKED', 'clinical_consultations', p_consultation_id::text,
      jsonb_build_object('share_id', v_share.id), jsonb_build_object('revoked', true));
  end if;
  return public.consultation_document_state(p_consultation_id);
end;
$$;

create or replace function public.resolve_consultation_document_share(p_share_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'document_id', document.id,
    'consultation_id', document.consultation_id,
    'storage_path', document.storage_path,
    'mime_type', document.mime_type,
    'file_size', document.file_size,
    'pixel_width', document.pixel_width,
    'pixel_height', document.pixel_height,
    'render_version', document.render_version
  )
  from public.consultation_document_shares share
  join public.consultation_documents document on document.id = share.document_id
  where share.id = p_share_id and share.revoked_at is null and document.status = 'completed';
$$;

create or replace function public.consultation_document_storage_paths_for_delete(p_consultation_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
begin
  if not private.has_permission(v_actor, 'consultations.delete') or not exists (
    select 1 from public.profiles profile
    join public.staff_positions position on position.id = profile.position_id
    where profile.user_id = v_actor and profile.status = 'active' and position.official and position.active and position.level in (13, 14)
  ) then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(document.storage_path order by document.storage_path)
    from public.consultation_documents document
    where document.consultation_id = p_consultation_id and document.storage_path is not null
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.begin_consultation_ai_generation(bigint, text, uuid) from public, anon, authenticated, service_role;
revoke all on function public.complete_consultation_ai_generation_v2(bigint, text, uuid, jsonb, text, text, integer, integer, integer) from public, anon, authenticated, service_role;
revoke all on function public.consultation_ai_context(bigint) from public, anon, authenticated, service_role;
revoke all on function public.begin_consultation_document(bigint) from public, anon, authenticated, service_role;
revoke all on function public.complete_consultation_document(bigint, uuid, text, integer, integer, integer, text) from public, anon, authenticated, service_role;
revoke all on function public.consultation_document_state(bigint) from public, anon, authenticated, service_role;
revoke all on function public.create_consultation_document_share(bigint) from public, anon, authenticated, service_role;
revoke all on function public.revoke_consultation_document_share(bigint) from public, anon, authenticated, service_role;
revoke all on function public.resolve_consultation_document_share(uuid) from public, anon, authenticated, service_role;
revoke all on function public.consultation_document_storage_paths_for_delete(bigint) from public, anon, authenticated, service_role;

grant execute on function public.begin_consultation_ai_generation(bigint, text, uuid) to service_role;
grant execute on function public.complete_consultation_ai_generation_v2(bigint, text, uuid, jsonb, text, text, integer, integer, integer) to service_role;
grant execute on function public.consultation_ai_context(bigint) to service_role;
grant execute on function public.begin_consultation_document(bigint) to authenticated;
grant execute on function public.complete_consultation_document(bigint, uuid, text, integer, integer, integer, text) to authenticated;
grant execute on function public.consultation_document_state(bigint) to authenticated;
grant execute on function public.create_consultation_document_share(bigint) to authenticated;
grant execute on function public.revoke_consultation_document_share(bigint) to authenticated;
grant execute on function public.resolve_consultation_document_share(uuid) to service_role;
grant execute on function public.consultation_document_storage_paths_for_delete(bigint) to authenticated;

comment on table public.consultation_documents is
  'Prontuário PNG imutável da consulta, com snapshot clínico congelado antes da renderização determinística.';
comment on table public.consultation_document_shares is
  'Links públicos revogáveis e não previsíveis para um único prontuário de consulta.';
