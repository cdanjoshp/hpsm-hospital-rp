-- HPSM: até três sínteses clínicas, prescrição automática ao selecionar a
-- hipótese e preservação da revisão humana por Editar/Remover.

alter table public.consultation_ai_generations
  add column if not exists attempt_number integer not null default 1;

alter table public.consultation_ai_generations
  drop constraint if exists consultation_ai_generations_consultation_id_action_type_key;

alter table public.consultation_ai_generations
  drop constraint if exists consultation_ai_generations_attempt_number_check;

alter table public.consultation_ai_generations
  add constraint consultation_ai_generations_attempt_number_check check (
    (action_type = 'CLINICAL_SYNTHESIS' and attempt_number between 1 and 3)
    or (action_type <> 'CLINICAL_SYNTHESIS' and attempt_number = 1)
  );

alter table public.consultation_ai_generations
  drop constraint if exists consultation_ai_generations_consultation_action_attempt_key;

alter table public.consultation_ai_generations
  add constraint consultation_ai_generations_consultation_action_attempt_key
  unique (consultation_id, action_type, attempt_number);

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
  v_completed_count integer := 0;
begin
  select * into v_consultation
  from public.clinical_consultations
  where id = p_consultation_id
  for update;

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

  if p_action_type = 'CLINICAL_SYNTHESIS' then
    select * into v_generation
    from public.consultation_ai_generations generation
    where generation.consultation_id = p_consultation_id
      and generation.action_type = p_action_type
      and generation.status = 'pending'
    order by generation.attempt_number desc
    limit 1
    for update;

    if v_generation.id is null then
      select * into v_generation
      from public.consultation_ai_generations generation
      where generation.consultation_id = p_consultation_id
        and generation.action_type = p_action_type
        and generation.status = 'failed'
      order by generation.attempt_number desc
      limit 1
      for update;

      if v_generation.id is not null then
        update public.consultation_ai_generations set
          status = 'pending', request_key = p_request_key, response_payload = null,
          error_message = null, model = null, prompt_version = null,
          requested_by = v_actor, requested_at = now(), completed_at = null,
          failed_at = null, input_tokens = null, output_tokens = null,
          cached_input_tokens = null
        where id = v_generation.id
        returning * into v_generation;
      else
        select count(*)::integer into v_completed_count
        from public.consultation_ai_generations generation
        where generation.consultation_id = p_consultation_id
          and generation.action_type = p_action_type
          and generation.status = 'completed';
        if v_completed_count >= 3 then
          raise exception 'As hipóteses diagnósticas já foram geradas três vezes nesta consulta.';
        end if;
        insert into public.consultation_ai_generations (
          consultation_id, action_type, attempt_number, request_key, requested_by
        ) values (
          p_consultation_id, p_action_type, v_completed_count + 1, p_request_key, v_actor
        ) returning * into v_generation;
      end if;
    end if;
  else
    select * into v_generation
    from public.consultation_ai_generations generation
    where generation.consultation_id = p_consultation_id
      and generation.action_type = p_action_type
      and generation.attempt_number = 1
    for update;
    if v_generation.id is null then
      insert into public.consultation_ai_generations (
        consultation_id, action_type, attempt_number, request_key, requested_by
      ) values (p_consultation_id, p_action_type, 1, p_request_key, v_actor)
      returning * into v_generation;
    elsif v_generation.status = 'failed' then
      update public.consultation_ai_generations set
        status = 'pending', request_key = p_request_key, response_payload = null,
        error_message = null, model = null, prompt_version = null,
        requested_by = v_actor, requested_at = now(), completed_at = null,
        failed_at = null, input_tokens = null, output_tokens = null,
        cached_input_tokens = null
      where id = v_generation.id
      returning * into v_generation;
    end if;
  end if;

  return jsonb_build_object(
    'id', v_generation.id,
    'status', v_generation.status,
    'request_key', v_generation.request_key,
    'response', v_generation.response_payload,
    'attempt_number', v_generation.attempt_number,
    'attempts_remaining', case when p_action_type = 'CLINICAL_SYNTHESIS' then 3 - v_generation.attempt_number else 0 end
  );
end;
$$;

create or replace function private.rp_medication_context_compatible(
  p_consultation_id bigint,
  p_medication_id text,
  p_signature jsonb
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_medication public.rp_medications;
  v_consultation public.clinical_consultations;
  v_allergies text;
  v_body_system text;
  v_tags text[];
begin
  select * into v_medication from public.rp_medications where id = p_medication_id and active;
  if v_medication.id is null then return false; end if;
  select * into v_consultation from public.clinical_consultations where id = p_consultation_id;
  if v_consultation.id is null then return false; end if;
  select lower(coalesce(patient.allergies, '')) into v_allergies
  from public.patients patient where patient.id = v_consultation.patient_id;
  if exists (
    select 1 from unnest(v_medication.allergy_keywords) keyword
    where char_length(keyword) >= 3 and v_allergies like '%' || lower(keyword) || '%'
  ) then return false; end if;
  v_body_system := lower(coalesce(p_signature->>'body_system', 'geral'));
  select coalesce(array_agg(lower(value)), '{}'::text[]) into v_tags
  from jsonb_array_elements_text(coalesce(p_signature->'case_tags', '[]'::jsonb)) value;
  if cardinality(v_medication.disallowed_case_tags) > 0
     and v_tags && v_medication.disallowed_case_tags then return false; end if;
  if v_medication.id = 'DORMAX'
     and coalesce(v_consultation.pain_score, 0) < 7
     and not (v_tags && v_medication.allowed_case_tags) then return false; end if;
  if cardinality(v_medication.allowed_body_systems) = 0
     and cardinality(v_medication.allowed_case_tags) = 0 then return true; end if;
  return v_body_system = any(v_medication.allowed_body_systems)
    or v_tags && v_medication.allowed_case_tags;
end;
$$;

create or replace function public.complete_consultation_ai_generation_v3(
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
  v_signature jsonb;
  v_passport text;
begin
  select generation.* into v_generation
  from public.consultation_ai_generations generation
  join public.clinical_consultations consultation on consultation.id = generation.consultation_id
  where generation.consultation_id = p_consultation_id
    and generation.action_type = p_action_type
    and generation.request_key = p_request_key
    and consultation.status = 'in_progress'
    and private.is_hpsm_workforce(consultation.professional_id)
    and private.has_permission(consultation.professional_id, 'consultations.complete')
  for update of generation;
  if v_generation.id is null then
    raise exception 'Solicitação de IA inválida.' using errcode = '42501';
  end if;
  if v_generation.status = 'completed' then return v_generation.response_payload; end if;
  if v_generation.status <> 'pending' or p_response_payload is null or jsonb_typeof(p_response_payload) <> 'object' then
    raise exception 'Resposta de IA inválida.';
  end if;
  if p_model <> 'gpt-5.6-luna' or p_prompt_version <> 'consultation-assistant-v6' then
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
  if p_action_type in ('EXAM_SUGGESTIONS', 'CLINICAL_SYNTHESIS') then
    v_signature := p_response_payload->'case_signature';
    if jsonb_typeof(v_signature) is distinct from 'object'
       or coalesce(v_signature->>'body_system', '') !~ '^[a-z0-9_]{2,60}$'
       or jsonb_typeof(v_signature->'case_tags') is distinct from 'array'
       or jsonb_array_length(v_signature->'case_tags') > 12
       or jsonb_typeof(v_signature->'vital_flags') is distinct from 'array'
       or jsonb_array_length(v_signature->'vital_flags') > 8
       or exists (select 1 from jsonb_array_elements_text(v_signature->'case_tags') value where value !~ '^[a-z0-9_]{2,60}$')
       or exists (select 1 from jsonb_array_elements_text(v_signature->'vital_flags') value where value !~ '^[a-z0-9_]{2,60}$') then
      raise exception 'A assinatura clínica retornou um formato inválido.';
    end if;
  end if;
  if p_action_type = 'EXAM_SUGGESTIONS' then
    if jsonb_typeof(p_response_payload->'no_exam_needed') is distinct from 'boolean'
       or jsonb_typeof(p_response_payload->'exam_suggestions') is distinct from 'array'
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
    if jsonb_typeof(p_response_payload->'options') is distinct from 'array'
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
            or jsonb_typeof(option->'medication_suggestions') is distinct from 'array'
            or jsonb_array_length(option->'medication_suggestions') > 5
       ) then raise exception 'A síntese deve retornar exatamente Normal, Grave e Gravíssimo com diagnóstico, plano, conduta, orientação e medicações válidas.';
    end if;
    if exists (
      select 1
      from jsonb_array_elements(p_response_payload->'options') option
      cross join lateral jsonb_array_elements(option->'medication_suggestions') suggestion
      where char_length(btrim(coalesce(suggestion->>'reason', ''))) < 3
         or not exists (
           select 1 from public.rp_medications medication
           where medication.id = suggestion->>'medication_id' and medication.active
         )
         or not private.rp_medication_context_compatible(p_consultation_id, suggestion->>'medication_id', v_signature)
    ) then raise exception 'A síntese sugeriu um medicamento inexistente, inativo, incompatível ou contraindicado por alergia.'; end if;
    if exists (
      select 1 from jsonb_array_elements(p_response_payload->'options') option
      where (select count(*) from jsonb_array_elements(option->'medication_suggestions'))
        <> (select count(distinct suggestion->>'medication_id') from jsonb_array_elements(option->'medication_suggestions') suggestion)
    ) then raise exception 'A síntese repetiu um medicamento na mesma opção.'; end if;
  end if;
  update public.consultation_ai_generations set
    status = 'completed', response_payload = p_response_payload, error_message = null,
    model = btrim(p_model), prompt_version = btrim(p_prompt_version), completed_at = now(), failed_at = null,
    input_tokens = p_input_tokens, output_tokens = p_output_tokens,
    cached_input_tokens = p_cached_input_tokens
  where id = v_generation.id;
  if p_action_type = 'CLINICAL_SYNTHESIS' then
    select passport into v_passport from public.profiles where user_id = v_generation.requested_by;
    insert into public.audit_logs (actor_user_id, actor_passport, action, entity_name, entity_id, new_values)
    select v_generation.requested_by, v_passport, 'MEDICATION_SUGGESTED', 'clinical_consultations', p_consultation_id::text,
      jsonb_build_object('attempt_number', v_generation.attempt_number, 'severity', option->>'severity', 'medication_id', suggestion->>'medication_id', 'reason', suggestion->>'reason')
    from jsonb_array_elements(p_response_payload->'options') option
    cross join lateral jsonb_array_elements(option->'medication_suggestions') suggestion;
  end if;
  return p_response_payload;
end;
$$;

create or replace function private.rp_medication_context_compatible(
  p_consultation_id bigint,
  p_medication_id text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.rp_medication_context_compatible(
    p_consultation_id,
    p_medication_id,
    private.rp_case_signature(p_consultation_id)
  );
$$;

create or replace function private.rp_case_signature(p_consultation_id bigint)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select generation.response_payload->'case_signature'
      from public.consultation_ai_generations generation
      where generation.consultation_id = p_consultation_id
        and generation.action_type = 'CLINICAL_SYNTHESIS'
        and generation.status = 'completed'
      order by generation.attempt_number desc, generation.id desc
      limit 1
    ),
    (
      select generation.response_payload->'case_signature'
      from public.consultation_ai_generations generation
      where generation.consultation_id = p_consultation_id
        and generation.action_type = 'EXAM_SUGGESTIONS'
        and generation.status = 'completed'
      limit 1
    ),
    jsonb_build_object('body_system', 'geral', 'case_tags', '[]'::jsonb, 'vital_flags', '[]'::jsonb)
  );
$$;

create or replace function public.select_consultation_diagnosis(
  p_consultation_id bigint,
  p_selected_diagnosis jsonb,
  p_final_diagnosis_plan text,
  p_complementary_action text,
  p_orientation_text text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_consultation public.clinical_consultations;
  v_prescription public.consultation_prescriptions;
  v_medication public.rp_medications;
  v_suggestion jsonb;
  v_medication_id text;
  v_reason text;
  v_calculated integer;
  v_inserted integer := 0;
  v_skipped integer := 0;
  v_latest_decision text;
  v_passport text;
begin
  select * into v_consultation
  from public.clinical_consultations
  where id = p_consultation_id
  for update;
  if v_consultation.id is null then raise exception 'Consulta não localizada.'; end if;
  if v_consultation.status <> 'in_progress'
     or not private.can_edit_consultation(v_actor, v_consultation.professional_id) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if jsonb_typeof(p_selected_diagnosis) is distinct from 'object'
     or p_selected_diagnosis->>'severity' not in ('normal', 'grave', 'gravissimo')
     or char_length(btrim(coalesce(p_selected_diagnosis->>'diagnosis', p_selected_diagnosis->>'title', ''))) not between 3 and 500
     or jsonb_typeof(coalesce(p_selected_diagnosis->'medication_suggestions', '[]'::jsonb)) is distinct from 'array'
     or jsonb_array_length(coalesce(p_selected_diagnosis->'medication_suggestions', '[]'::jsonb)) > 5 then
    raise exception 'Diagnóstico selecionado inválido.';
  end if;
  if not exists (
    select 1
    from (
      select generation.response_payload
      from public.consultation_ai_generations generation
      where generation.consultation_id = p_consultation_id
        and generation.action_type = 'CLINICAL_SYNTHESIS'
        and generation.status = 'completed'
      order by generation.attempt_number desc, generation.id desc
      limit 1
    ) generation
    cross join lateral jsonb_array_elements(generation.response_payload->'options') as option(value)
    where option.value = p_selected_diagnosis
  ) then
    raise exception 'Selecione uma hipótese da síntese clínica mais recente.';
  end if;
  if char_length(btrim(coalesce(p_final_diagnosis_plan, ''))) not between 3 and 12000 then
    raise exception 'Informe o diagnóstico final e o plano.';
  end if;
  if p_complementary_action not in ('NONE', 'CAST', 'HOSPITALIZATION') then
    raise exception 'Conduta complementar inválida.';
  end if;
  if char_length(btrim(coalesce(p_orientation_text, ''))) not between 3 and 12000 then
    raise exception 'Informe as orientações ao paciente.';
  end if;

  update public.clinical_consultations set
    selected_diagnosis = p_selected_diagnosis,
    final_diagnosis_plan = btrim(p_final_diagnosis_plan),
    complementary_action = p_complementary_action,
    orientation_text = btrim(p_orientation_text)
  where id = p_consultation_id;

  if jsonb_array_length(coalesce(p_selected_diagnosis->'medication_suggestions', '[]'::jsonb)) > 0 then
    v_prescription := private.ensure_consultation_prescription(p_consultation_id, v_actor);
  end if;

  for v_suggestion in
    select value from jsonb_array_elements(coalesce(p_selected_diagnosis->'medication_suggestions', '[]'::jsonb)) value
  loop
    v_latest_decision := null;
    v_medication_id := upper(btrim(coalesce(v_suggestion->>'medication_id', '')));
    v_reason := btrim(coalesce(v_suggestion->>'reason', ''));
    if v_medication_id !~ '^[A-Z0-9_]{3,40}$' or char_length(v_reason) not between 3 and 1000 then
      raise exception 'Sugestão de medicamento inválida.';
    end if;
    select * into v_medication
    from public.rp_medications
    where id = v_medication_id and active;
    if v_medication.id is null or not private.rp_medication_context_compatible(p_consultation_id, v_medication_id) then
      raise exception 'O medicamento é incompatível com o contexto clínico ou com as alergias informadas.';
    end if;
    if exists (
      select 1 from public.consultation_prescription_items item
      where item.consultation_id = p_consultation_id and item.medication_id = v_medication_id
    ) then
      v_skipped := v_skipped + 1;
      continue;
    end if;
    select decision.decision into v_latest_decision
    from public.consultation_medication_decisions decision
    where decision.consultation_id = p_consultation_id
      and decision.medication_id = v_medication_id
    order by decision.created_at desc, decision.id desc
    limit 1;
    if v_latest_decision in ('removed', 'rejected') then
      v_skipped := v_skipped + 1;
      continue;
    end if;
    v_calculated := private.rp_quantity(v_medication.default_frequency, v_medication.default_duration_days);
    insert into public.consultation_prescription_items (
      prescription_id, consultation_id, medication_id, source, catalog_version,
      rp_name_snapshot, reference_name_snapshot, dose_snapshot, frequency_snapshot,
      duration_snapshot, duration_days, route_snapshot, reason_snapshot,
      instructions_snapshot, justification_snapshot, calculated_quantity_snapshot,
      final_quantity_snapshot, quantity_override_snapshot, override_reason, professional_id
    ) values (
      v_prescription.id, p_consultation_id, v_medication.id, 'ai', v_medication.version,
      v_medication.rp_name, v_medication.reference_name, v_medication.default_dose,
      v_medication.default_frequency,
      v_medication.default_duration_days::text || case when v_medication.default_duration_days = 1 then ' dia' else ' dias' end,
      v_medication.default_duration_days, v_medication.default_route, v_reason,
      v_medication.default_instructions,
      case when v_medication.requires_justification then v_reason else null end,
      v_calculated, v_calculated, false, null, v_consultation.professional_id
    );
    insert into public.consultation_medication_decisions (
      consultation_id, medication_id, source, decision, reason, actor_user_id
    ) values (p_consultation_id, v_medication.id, 'ai', 'accepted', v_reason, v_actor);
    v_inserted := v_inserted + 1;
  end loop;

  select passport into v_passport from public.profiles where user_id = v_actor;
  insert into public.audit_logs (
    actor_user_id, actor_passport, action, entity_name, entity_id, new_values
  ) values (
    v_actor, v_passport, 'CONSULTATION_DIAGNOSIS_SELECTED', 'clinical_consultations', p_consultation_id::text,
    jsonb_build_object(
      'severity', p_selected_diagnosis->>'severity',
      'diagnosis', coalesce(p_selected_diagnosis->>'diagnosis', p_selected_diagnosis->>'title'),
      'automatic_medications_inserted', v_inserted,
      'automatic_medications_preserved_or_skipped', v_skipped
    )
  );
  return jsonb_build_object('automatic_medications_inserted', v_inserted, 'automatic_medications_skipped', v_skipped);
end;
$$;

revoke all on function public.begin_consultation_ai_generation(bigint, text, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.begin_consultation_ai_generation(bigint, text, uuid)
to service_role;

revoke all on function public.complete_consultation_ai_generation_v3(bigint, text, uuid, jsonb, text, text, integer, integer, integer)
from public, anon, authenticated, service_role;
grant execute on function public.complete_consultation_ai_generation_v3(bigint, text, uuid, jsonb, text, text, integer, integer, integer)
to service_role;

revoke all on function public.select_consultation_diagnosis(bigint, jsonb, text, text, text)
from public, anon, authenticated, service_role;
grant execute on function public.select_consultation_diagnosis(bigint, jsonb, text, text, text)
to authenticated;

revoke all on function private.rp_case_signature(bigint)
from public, anon, authenticated, service_role;
revoke all on function private.rp_medication_context_compatible(bigint, text, jsonb)
from public, anon, authenticated, service_role;
revoke all on function private.rp_medication_context_compatible(bigint, text)
from public, anon, authenticated, service_role;

comment on function public.begin_consultation_ai_generation(bigint, text, uuid) is
'Mantém uma geração para anamnese/exames e permite até três sínteses clínicas concluídas por consulta; falhas podem ser repetidas sem consumir o limite.';
comment on function public.select_consultation_diagnosis(bigint, jsonb, text, text, text) is
'Seleciona a hipótese e materializa automaticamente as medicações válidas na prescrição, preservando itens editados e remoções explícitas.';

notify pgrst, 'reload schema';
