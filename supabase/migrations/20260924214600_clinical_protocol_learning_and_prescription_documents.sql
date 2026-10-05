-- HPSM Rollup 4: aprendizagem local, integração com a síntese e documentos de Receita RP.

create table public.prescription_documents (
  id uuid primary key default gen_random_uuid(),
  prescription_id uuid not null unique references public.consultation_prescriptions(id) on delete cascade,
  consultation_id bigint not null unique references public.clinical_consultations(id) on delete cascade,
  status text not null default 'pending',
  source_snapshot jsonb not null,
  storage_path text,
  mime_type text,
  file_size integer,
  pixel_width integer,
  pixel_height integer,
  render_version text,
  created_by uuid not null references public.profiles(user_id) on delete restrict,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint prescription_documents_status_check check (status in ('pending', 'completed')),
  constraint prescription_documents_snapshot_check check (jsonb_typeof(source_snapshot) = 'object'),
  constraint prescription_documents_state_check check (
    (status = 'pending' and storage_path is null and completed_at is null)
    or (status = 'completed' and storage_path is not null and mime_type = 'image/png'
      and file_size between 32 and 12582912 and pixel_width between 900 and 1400
      and pixel_height between 400 and 14000 and completed_at is not null)
  ),
  constraint prescription_documents_storage_path_check check (
    storage_path is null or storage_path ~ '^prescriptions/[0-9]+/documents/[0-9a-f-]{36}[.]png$'
  )
);

create table public.prescription_document_shares (
  id uuid primary key default gen_random_uuid(),
  consultation_id bigint not null references public.clinical_consultations(id) on delete cascade,
  document_id uuid not null references public.prescription_documents(id) on delete cascade,
  created_by uuid not null references public.profiles(user_id) on delete restrict,
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  revoked_by uuid references public.profiles(user_id) on delete set null,
  constraint prescription_document_shares_revocation_check check (
    (revoked_at is null and revoked_by is null) or (revoked_at is not null and revoked_by is not null)
  )
);

create unique index prescription_document_shares_one_active_uidx
  on public.prescription_document_shares (consultation_id) where revoked_at is null;
create index prescription_document_shares_document_idx
  on public.prescription_document_shares (document_id);

alter table public.prescription_documents enable row level security;
alter table public.prescription_documents force row level security;
alter table public.prescription_document_shares enable row level security;
alter table public.prescription_document_shares force row level security;
revoke all on public.prescription_documents, public.prescription_document_shares
from public, anon, authenticated;
grant select, insert, update, delete on public.prescription_documents, public.prescription_document_shares
to service_role;

create or replace function private.clinical_protocol_similarity(
  p_signature jsonb,
  p_body_system text,
  p_case_tags text[],
  p_vital_flags text[]
)
returns numeric
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_body text := lower(coalesce(p_signature->>'body_system', 'geral'));
  v_tags text[];
  v_vitals text[];
  v_tag_intersection integer;
  v_tag_union integer;
  v_vital_intersection integer;
  v_vital_union integer;
begin
  select coalesce(array_agg(distinct lower(value)), '{}'::text[]) into v_tags
  from jsonb_array_elements_text(coalesce(p_signature->'case_tags', '[]'::jsonb)) value;
  select coalesce(array_agg(distinct lower(value)), '{}'::text[]) into v_vitals
  from jsonb_array_elements_text(coalesce(p_signature->'vital_flags', '[]'::jsonb)) value;
  select count(*) into v_tag_intersection from unnest(v_tags) tag where tag = any(p_case_tags);
  select count(*) into v_tag_union from (
    select unnest(v_tags) union select unnest(p_case_tags)
  ) tags;
  select count(*) into v_vital_intersection from unnest(v_vitals) flag where flag = any(p_vital_flags);
  select count(*) into v_vital_union from (
    select unnest(v_vitals) union select unnest(p_vital_flags)
  ) flags;
  return round(
    (case when v_body = p_body_system then 0.35 else 0 end)
    + (case when v_tag_union = 0 then 0 else 0.50 * v_tag_intersection::numeric / v_tag_union end)
    + (case when v_vital_union = 0 then 0 else 0.15 * v_vital_intersection::numeric / v_vital_union end),
    3
  );
end;
$$;

create or replace function private.protocol_deidentify(
  p_text text,
  p_patient_name text,
  p_patient_passport text
)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_text text := btrim(coalesce(p_text, ''));
begin
  if v_text = '' then return ''; end if;
  if char_length(btrim(coalesce(p_patient_name, ''))) >= 2 then
    v_text := replace(v_text, p_patient_name, '[Paciente]');
  end if;
  if char_length(btrim(coalesce(p_patient_passport, ''))) >= 1 then
    v_text := replace(v_text, p_patient_passport, '[identificador removido]');
  end if;
  v_text := regexp_replace(v_text, '[[:alnum:]._%+-]+@[[:alnum:].-]+[.][A-Za-z]{2,}', '[contato removido]', 'gi');
  v_text := regexp_replace(v_text, '[+]?[0-9][0-9 ()-]{7,}[0-9]', '[contato removido]', 'g');
  v_text := regexp_replace(v_text, '\m[0-9]{4,}\M', '[identificador removido]', 'g');
  return left(regexp_replace(v_text, '\s+', ' ', 'g'), 2000);
end;
$$;

create or replace function private.refresh_clinical_protocol(
  p_protocol_id uuid,
  p_changed_by uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_protocol public.clinical_protocols;
  v_settings public.clinical_protocol_settings;
  v_count integer;
  v_body text;
  v_tags text[];
  v_vitals text[];
  v_diagnosis text;
  v_state text;
  v_version integer;
  v_passport text;
  v_action text;
begin
  select * into v_protocol from public.clinical_protocols where id = p_protocol_id for update;
  if v_protocol.id is null then return; end if;
  select * into v_settings from public.clinical_protocol_settings where singleton;
  select count(*) into v_count from public.clinical_protocol_observations where protocol_id = p_protocol_id;
  if v_count > 0 then
    select observation.case_signature->>'body_system', count(*)
      into v_body, v_version
    from public.clinical_protocol_observations observation
    where observation.protocol_id = p_protocol_id
    group by observation.case_signature->>'body_system'
    order by count(*) desc, observation.case_signature->>'body_system'
    limit 1;
    select coalesce(array_agg(distinct lower(tag) order by lower(tag)), '{}'::text[]) into v_tags
    from public.clinical_protocol_observations observation
    cross join lateral jsonb_array_elements_text(coalesce(observation.case_signature->'case_tags', '[]'::jsonb)) tag
    where observation.protocol_id = p_protocol_id;
    select coalesce(array_agg(distinct lower(flag) order by lower(flag)), '{}'::text[]) into v_vitals
    from public.clinical_protocol_observations observation
    cross join lateral jsonb_array_elements_text(coalesce(observation.case_signature->'vital_flags', '[]'::jsonb)) flag
    where observation.protocol_id = p_protocol_id;
    select nullif(observation.decision_snapshot->>'diagnosis', ''), count(*)
      into v_diagnosis, v_version
    from public.clinical_protocol_observations observation
    where observation.protocol_id = p_protocol_id
    group by nullif(observation.decision_snapshot->>'diagnosis', '')
    order by count(*) desc, nullif(observation.decision_snapshot->>'diagnosis', '') nulls last
    limit 1;
  else
    v_body := v_protocol.body_system;
    v_tags := '{}'::text[];
    v_vitals := '{}'::text[];
    v_diagnosis := v_protocol.primary_diagnosis;
  end if;
  v_state := case
    when v_count >= v_settings.learned_to_consolidated_count then 'CONSOLIDATED'
    when v_count >= v_settings.candidate_to_learned_count then 'LEARNED'
    else 'CANDIDATE'
  end;
  v_action := case when v_state <> v_protocol.state then 'CLINICAL_PROTOCOL_PROMOTED' else 'CLINICAL_PROTOCOL_UPDATED' end;
  update public.clinical_protocols set
    display_name = left('Padrão observado — ' || coalesce(nullif(v_diagnosis, ''), replace(initcap(v_body), '_', ' ')), 160),
    state = v_state,
    version = version + 1,
    observed_count = v_count,
    body_system = coalesce(nullif(lower(v_body), ''), 'geral'),
    case_tags = v_tags,
    vital_flags = v_vitals,
    primary_diagnosis = v_diagnosis,
    first_observed_at = (select min(observed_at) from public.clinical_protocol_observations where protocol_id = p_protocol_id),
    last_observed_at = (select max(observed_at) from public.clinical_protocol_observations where protocol_id = p_protocol_id),
    updated_at = now()
  where id = p_protocol_id
  returning version into v_version;
  insert into public.clinical_protocol_versions (protocol_id, version, snapshot, change_type, changed_by)
  select protocol.id, protocol.version,
    jsonb_build_object(
      'display_name', protocol.display_name, 'state', protocol.state,
      'moderation_status', protocol.moderation_status, 'observed_count', protocol.observed_count,
      'body_system', protocol.body_system, 'case_tags', to_jsonb(protocol.case_tags),
      'vital_flags', to_jsonb(protocol.vital_flags), 'primary_diagnosis', protocol.primary_diagnosis
    ), v_action, p_changed_by
  from public.clinical_protocols protocol where protocol.id = p_protocol_id;
  select passport into v_passport from public.profiles where user_id = p_changed_by;
  insert into public.audit_logs (actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values)
  select p_changed_by, v_passport, v_action, 'clinical_protocols', protocol.id::text,
    jsonb_build_object('state', v_protocol.state, 'observed_count', v_protocol.observed_count),
    jsonb_build_object('state', protocol.state, 'observed_count', protocol.observed_count, 'version', protocol.version)
  from public.clinical_protocols protocol where protocol.id = p_protocol_id;
end;
$$;

create or replace function private.refresh_clinical_protocol_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.refresh_clinical_protocol(coalesce(new.protocol_id, old.protocol_id), auth.uid());
  return coalesce(new, old);
end;
$$;

create trigger clinical_protocol_observations_refresh
after insert or delete on public.clinical_protocol_observations
for each row execute function private.refresh_clinical_protocol_trigger();

create or replace function private.related_clinical_protocols(
  p_signature jsonb,
  p_limit integer default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_settings public.clinical_protocol_settings;
  v_limit integer;
  v_result jsonb;
begin
  select * into v_settings from public.clinical_protocol_settings where singleton;
  v_limit := least(5, greatest(1, coalesce(p_limit, v_settings.max_related_protocols)));
  if coalesce(p_signature->>'body_system', 'geral') = 'geral'
     and jsonb_array_length(coalesce(p_signature->'case_tags', '[]'::jsonb)) = 0 then
    return '[]'::jsonb;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', ranked.id,
    'display_name', ranked.display_name,
    'state', ranked.state,
    'observed_count', ranked.observed_count,
    'similarity', ranked.similarity,
    'body_system', ranked.body_system,
    'case_tags', to_jsonb(ranked.case_tags),
    'vital_flags', to_jsonb(ranked.vital_flags),
    'diagnoses', coalesce((
      select jsonb_agg(jsonb_build_object('name', diagnosis.name, 'count', diagnosis.uses) order by diagnosis.uses desc, diagnosis.name)
      from (
        select observation.decision_snapshot->>'diagnosis' as name, count(*) as uses
        from public.clinical_protocol_observations observation
        where observation.protocol_id = ranked.id and nullif(observation.decision_snapshot->>'diagnosis', '') is not null
        group by observation.decision_snapshot->>'diagnosis'
        order by count(*) desc, observation.decision_snapshot->>'diagnosis'
        limit 3
      ) diagnosis
    ), '[]'::jsonb),
    'exams', coalesce((
      select jsonb_agg(jsonb_build_object('name', exam.name, 'count', exam.uses) order by exam.uses desc, exam.name)
      from (
        select item->>'name' as name, count(*) as uses
        from public.clinical_protocol_observations observation
        cross join lateral jsonb_array_elements(coalesce(observation.decision_snapshot->'exams', '[]'::jsonb)) item
        where observation.protocol_id = ranked.id
        group by item->>'name'
        order by count(*) desc, item->>'name'
        limit 5
      ) exam
    ), '[]'::jsonb),
    'medications', coalesce((
      select jsonb_agg(jsonb_build_object('id', medication.id, 'name', medication.name, 'count', medication.uses) order by medication.uses desc, medication.name)
      from (
        select item->>'medication_id' as id, item->>'rp_name_snapshot' as name, count(*) as uses
        from public.clinical_protocol_observations observation
        cross join lateral jsonb_array_elements(coalesce(observation.decision_snapshot->'medications', '[]'::jsonb)) item
        where observation.protocol_id = ranked.id
        group by item->>'medication_id', item->>'rp_name_snapshot'
        order by count(*) desc, item->>'rp_name_snapshot'
        limit 5
      ) medication
    ), '[]'::jsonb)
  ) order by ranked.similarity desc, ranked.observed_count desc, ranked.display_name), '[]'::jsonb)
  into v_result
  from (
    select protocol.*,
      private.clinical_protocol_similarity(p_signature, protocol.body_system, protocol.case_tags, protocol.vital_flags) as similarity
    from public.clinical_protocols protocol
    where protocol.moderation_status = 'active'
      and protocol.observed_count > 0
    order by similarity desc, protocol.observed_count desc, protocol.display_name
    limit v_limit
  ) ranked
  where ranked.similarity >= v_settings.related_similarity_threshold;
  return coalesce(v_result, '[]'::jsonb);
end;
$$;

create or replace function private.learn_completed_consultation(p_consultation_id bigint)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_consultation public.clinical_consultations;
  v_patient public.patients;
  v_signature jsonb;
  v_body text;
  v_tags text[];
  v_vitals text[];
  v_diagnosis text;
  v_protocol public.clinical_protocols;
  v_settings public.clinical_protocol_settings;
  v_fingerprint text;
  v_decisions jsonb;
  v_passport text;
begin
  select * into v_consultation from public.clinical_consultations where id = p_consultation_id for update;
  if v_consultation.id is null or v_consultation.status <> 'completed' then
    raise exception 'Somente consultas concluídas alimentam protocolos.';
  end if;
  select protocol.* into v_protocol
  from public.clinical_protocol_observations observation
  join public.clinical_protocols protocol on protocol.id = observation.protocol_id
  where observation.consultation_id = p_consultation_id;
  if v_protocol.id is not null then return v_protocol.id; end if;
  select * into v_patient from public.patients where id = v_consultation.patient_id;
  select * into v_settings from public.clinical_protocol_settings where singleton;
  v_signature := private.rp_case_signature(p_consultation_id);
  v_body := lower(coalesce(nullif(v_signature->>'body_system', ''), 'geral'));
  select coalesce(array_agg(distinct lower(value) order by lower(value)), '{}'::text[]) into v_tags
  from jsonb_array_elements_text(coalesce(v_signature->'case_tags', '[]'::jsonb)) value
  where value ~ '^[a-z0-9_]{2,60}$';
  select coalesce(array_agg(distinct lower(value) order by lower(value)), '{}'::text[]) into v_vitals
  from jsonb_array_elements_text(coalesce(v_signature->'vital_flags', '[]'::jsonb)) value
  where value ~ '^[a-z0-9_]{2,60}$';
  v_signature := jsonb_build_object('body_system', v_body, 'case_tags', to_jsonb(v_tags), 'vital_flags', to_jsonb(v_vitals));
  v_diagnosis := private.protocol_deidentify(
    coalesce(v_consultation.selected_diagnosis->>'diagnosis', v_consultation.selected_diagnosis->>'title', ''),
    v_patient.name, v_patient.passport
  );
  select protocol.* into v_protocol
  from public.clinical_protocols protocol
  where protocol.moderation_status = 'active'
    and private.clinical_protocol_similarity(v_signature, protocol.body_system, protocol.case_tags, protocol.vital_flags)
      >= v_settings.merge_similarity_threshold
  order by private.clinical_protocol_similarity(v_signature, protocol.body_system, protocol.case_tags, protocol.vital_flags) desc,
    protocol.observed_count desc, protocol.id
  limit 1
  for update;
  if v_protocol.id is null then
    select md5(v_body || '|' || array_to_string(v_tags, ',') || '|' || lower(v_diagnosis)) into v_fingerprint;
    if exists (select 1 from public.clinical_protocols where fingerprint = v_fingerprint) then
      v_fingerprint := md5(v_fingerprint || '|' || p_consultation_id::text);
    end if;
    insert into public.clinical_protocols (
      fingerprint, display_name, body_system, case_tags, vital_flags, primary_diagnosis
    ) values (
      v_fingerprint,
      left('Padrão observado — ' || coalesce(nullif(v_diagnosis, ''), replace(initcap(v_body), '_', ' ')), 160),
      v_body, v_tags, v_vitals, nullif(v_diagnosis, '')
    ) returning * into v_protocol;
    select passport into v_passport from public.profiles where user_id = v_consultation.professional_id;
    insert into public.audit_logs (actor_user_id, actor_passport, action, entity_name, entity_id, new_values)
    values (v_consultation.professional_id, v_passport, 'CLINICAL_PROTOCOL_CREATED', 'clinical_protocols', v_protocol.id::text,
      jsonb_build_object('body_system', v_body, 'case_tags', to_jsonb(v_tags), 'state', 'CANDIDATE'));
  end if;
  select jsonb_build_object(
    'diagnosis', v_diagnosis,
    'exams', coalesce((
      select jsonb_agg(jsonb_build_object('exam_type_id', exam.exam_type_id, 'name', exam_type.name) order by exam.requested_at, exam.id)
      from public.clinical_exams exam
      join public.exam_types exam_type on exam_type.id = exam.exam_type_id
      where exam.consultation_id = p_consultation_id
    ), '[]'::jsonb),
    'casts', coalesce((
      select jsonb_agg(jsonb_build_object('body_region', cast_record.body_region, 'status', cast_record.status) order by cast_record.id)
      from public.clinical_casts cast_record
      where cast_record.consultation_id = p_consultation_id and cast_record.status <> 'cancelled'
    ), '[]'::jsonb),
    'hospitalizations', coalesce((
      select jsonb_agg(jsonb_build_object('status', hospitalization.status) order by hospitalization.id)
      from public.hospitalizations hospitalization
      where hospitalization.consultation_id = p_consultation_id and hospitalization.status <> 'cancelled'
    ), '[]'::jsonb),
    'medications', coalesce((
      select jsonb_agg(jsonb_build_object(
        'medication_id', item.medication_id,
        'rp_name_snapshot', item.rp_name_snapshot,
        'dose_snapshot', item.dose_snapshot,
        'frequency_snapshot', item.frequency_snapshot,
        'duration_snapshot', item.duration_snapshot,
        'final_quantity_snapshot', item.final_quantity_snapshot
      ) order by item.created_at, item.id)
      from public.consultation_prescription_items item
      where item.consultation_id = p_consultation_id
    ), '[]'::jsonb),
    'orientation', private.protocol_deidentify(v_consultation.orientation_text, v_patient.name, v_patient.passport),
    'plan', private.protocol_deidentify(v_consultation.final_diagnosis_plan, v_patient.name, v_patient.passport),
    'complementary_action', v_consultation.complementary_action
  ) into v_decisions;
  insert into public.clinical_protocol_observations (
    protocol_id, consultation_id, case_signature, decision_snapshot, observed_at
  ) values (v_protocol.id, p_consultation_id, v_signature, v_decisions, v_consultation.completed_at)
  on conflict (consultation_id) do nothing;
  return v_protocol.id;
end;
$$;

create or replace function public.consultation_rollup_reference_data()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
begin
  if not private.has_permission(v_actor, 'consultations.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'medications', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', medication.id,
        'rp_name', medication.rp_name,
        'reference_name', medication.reference_name,
        'category', medication.category,
        'active', medication.active,
        'controlled', medication.controlled,
        'antibiotic', medication.antibiotic,
        'requires_justification', medication.requires_justification,
        'default_dose', medication.default_dose,
        'default_frequency', medication.default_frequency,
        'default_duration', medication.default_duration,
        'default_duration_days', medication.default_duration_days,
        'default_route', medication.default_route,
        'default_instructions', medication.default_instructions,
        'default_doses_per_day', medication.default_doses_per_day,
        'default_as_needed', medication.default_as_needed,
        'version', medication.version
      ) order by lower(medication.rp_name))
      from public.rp_medications medication
      where medication.active
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.consultation_rollup_detail(p_consultation_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_consultation public.clinical_consultations;
  v_prescription public.consultation_prescriptions;
  v_signature jsonb;
begin
  if not private.has_permission(v_actor, 'consultations.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  select * into v_consultation from public.clinical_consultations where id = p_consultation_id;
  if v_consultation.id is null then raise exception 'Consulta não localizada.'; end if;
  select * into v_prescription from public.consultation_prescriptions where consultation_id = p_consultation_id;
  v_signature := private.rp_case_signature(p_consultation_id);
  return jsonb_build_object(
    'case_signature', v_signature,
    'related_protocols', private.related_clinical_protocols(v_signature),
    'prescription', case when v_prescription.id is null then null else jsonb_build_object(
      'id', v_prescription.id,
      'status', v_prescription.status,
      'final_snapshot', v_prescription.final_snapshot,
      'created_at', v_prescription.created_at,
      'finalized_at', v_prescription.finalized_at,
      'items', coalesce((
        select jsonb_agg(to_jsonb(item) - 'professional_id' order by item.created_at, item.id)
        from public.consultation_prescription_items item
        where item.prescription_id = v_prescription.id
      ), '[]'::jsonb)
    ) end,
    'medication_decisions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'medication_id', decision.medication_id,
        'source', decision.source,
        'decision', decision.decision,
        'reason', decision.reason,
        'created_at', decision.created_at
      ) order by decision.created_at, decision.id)
      from public.consultation_medication_decisions decision
      where decision.consultation_id = p_consultation_id
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.consultation_rollup_ai_context(p_consultation_id bigint)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'case_signature', private.rp_case_signature(p_consultation_id),
    'related_protocols', private.related_clinical_protocols(private.rp_case_signature(p_consultation_id))
  )
  where exists (select 1 from public.clinical_consultations where id = p_consultation_id);
$$;

create or replace function public.clinical_protocol_library()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_level integer;
begin
  if not private.has_permission(v_actor, 'consultations.view') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  select position.level into v_level
  from public.profiles profile join public.staff_positions position on position.id = profile.position_id
  where profile.user_id = v_actor and profile.status = 'active' and position.active and position.official;
  return jsonb_build_object(
    'can_moderate', coalesce(v_level between 11 and 14, false) and private.has_permission(v_actor, 'consultations.manage'),
    'settings', (select to_jsonb(setting) - 'singleton' - 'updated_at' from public.clinical_protocol_settings setting where setting.singleton),
    'protocols', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', protocol.id, 'display_name', protocol.display_name, 'state', protocol.state,
        'moderation_status', protocol.moderation_status, 'version', protocol.version,
        'observed_count', protocol.observed_count, 'body_system', protocol.body_system,
        'case_tags', to_jsonb(protocol.case_tags), 'vital_flags', to_jsonb(protocol.vital_flags),
        'primary_diagnosis', protocol.primary_diagnosis,
        'first_observed_at', protocol.first_observed_at, 'last_observed_at', protocol.last_observed_at
      ) order by protocol.observed_count desc, protocol.display_name)
      from public.clinical_protocols protocol
    ), '[]'::jsonb),
    'medications', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', medication.id, 'rp_name', medication.rp_name, 'reference_name', medication.reference_name,
        'category', medication.category, 'active', medication.active, 'controlled', medication.controlled,
        'antibiotic', medication.antibiotic, 'requires_justification', medication.requires_justification,
        'default_dose', medication.default_dose, 'default_frequency', medication.default_frequency,
        'default_duration', medication.default_duration, 'default_duration_days', medication.default_duration_days,
        'default_route', medication.default_route, 'default_instructions', medication.default_instructions,
        'default_doses_per_day', medication.default_doses_per_day, 'default_as_needed', medication.default_as_needed,
        'version', medication.version
      ) order by lower(medication.rp_name)) from public.rp_medications medication
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.set_clinical_protocol_settings(
  p_candidate_to_learned_count integer,
  p_learned_to_consolidated_count integer,
  p_merge_similarity_threshold numeric,
  p_related_similarity_threshold numeric,
  p_max_related_protocols integer,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_old public.clinical_protocol_settings;
  v_next public.clinical_protocol_settings;
  v_passport text;
begin
  perform private.assert_protocol_moderator(v_actor);
  if char_length(btrim(coalesce(p_reason, ''))) not between 3 and 500 then raise exception 'Informe o motivo da alteração dos limiares.'; end if;
  if p_candidate_to_learned_count < 2 or p_learned_to_consolidated_count <= p_candidate_to_learned_count
     or p_merge_similarity_threshold not between 0 and 1 or p_related_similarity_threshold not between 0 and 1
     or p_max_related_protocols not between 1 and 5 then raise exception 'Revise os limiares de aprendizado.'; end if;
  select * into v_old from public.clinical_protocol_settings where singleton for update;
  update public.clinical_protocol_settings set
    candidate_to_learned_count = p_candidate_to_learned_count,
    learned_to_consolidated_count = p_learned_to_consolidated_count,
    merge_similarity_threshold = p_merge_similarity_threshold,
    related_similarity_threshold = p_related_similarity_threshold,
    max_related_protocols = p_max_related_protocols,
    updated_at = now()
  where singleton returning * into v_next;
  perform private.refresh_clinical_protocol(protocol.id, v_actor)
  from public.clinical_protocols protocol;
  select passport into v_passport from public.profiles where user_id = v_actor;
  insert into public.audit_logs (actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values)
  values (v_actor, v_passport, 'CLINICAL_PROTOCOL_SETTINGS_UPDATED', 'clinical_protocol_settings', 'singleton',
    to_jsonb(v_old) - 'singleton', (to_jsonb(v_next) - 'singleton') || jsonb_build_object('reason', btrim(p_reason)));
end;
$$;

create or replace function private.assert_protocol_moderator(p_actor uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_level integer;
begin
  select position.level into v_level
  from public.profiles profile
  join public.staff_positions position on position.id = profile.position_id
  where profile.user_id = p_actor and profile.status = 'active' and position.active and position.official;
  if not private.has_permission(p_actor, 'consultations.manage') or v_level not between 11 and 14 then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.moderate_clinical_protocol(
  p_protocol_id uuid,
  p_status text,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_protocol public.clinical_protocols;
  v_next public.clinical_protocols;
  v_passport text;
  v_action text;
begin
  perform private.assert_protocol_moderator(v_actor);
  if p_status not in ('active', 'inactive', 'quarantined') then raise exception 'Estado de moderação inválido.'; end if;
  if char_length(btrim(coalesce(p_reason, ''))) not between 3 and 500 then raise exception 'Informe o motivo da moderação.'; end if;
  select * into v_protocol from public.clinical_protocols where id = p_protocol_id for update;
  if v_protocol.id is null then raise exception 'Protocolo não localizado.'; end if;
  if v_protocol.moderation_status = p_status then return; end if;
  update public.clinical_protocols set
    moderation_status = p_status, version = version + 1,
    moderated_at = now(), moderated_by = v_actor, moderation_reason = btrim(p_reason), updated_at = now()
  where id = p_protocol_id returning * into v_next;
  v_action := case p_status when 'active' then 'CLINICAL_PROTOCOL_REACTIVATED'
    when 'inactive' then 'CLINICAL_PROTOCOL_DEACTIVATED' else 'CLINICAL_PROTOCOL_QUARANTINED' end;
  insert into public.clinical_protocol_versions (protocol_id, version, snapshot, change_type, changed_by)
  values (v_next.id, v_next.version,
    jsonb_build_object('display_name', v_next.display_name, 'state', v_next.state,
      'moderation_status', v_next.moderation_status, 'observed_count', v_next.observed_count,
      'body_system', v_next.body_system, 'case_tags', to_jsonb(v_next.case_tags),
      'vital_flags', to_jsonb(v_next.vital_flags), 'reason', btrim(p_reason)),
    v_action, v_actor);
  select passport into v_passport from public.profiles where user_id = v_actor;
  insert into public.audit_logs (actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values)
  values (v_actor, v_passport, v_action, 'clinical_protocols', v_next.id::text,
    jsonb_build_object('moderation_status', v_protocol.moderation_status),
    jsonb_build_object('moderation_status', v_next.moderation_status, 'reason', btrim(p_reason), 'version', v_next.version));
end;
$$;

create or replace function public.set_rp_medication_active(
  p_medication_id text,
  p_active boolean,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_medication public.rp_medications;
  v_next public.rp_medications;
  v_passport text;
begin
  perform private.assert_protocol_moderator(v_actor);
  if char_length(btrim(coalesce(p_reason, ''))) not between 3 and 500 then raise exception 'Informe o motivo da alteração.'; end if;
  select * into v_medication from public.rp_medications where id = upper(btrim(coalesce(p_medication_id, ''))) for update;
  if v_medication.id is null then raise exception 'Medicamento não localizado.'; end if;
  if v_medication.active = p_active then return; end if;
  update public.rp_medications set active = p_active, version = version + 1, updated_at = now()
  where id = v_medication.id returning * into v_next;
  insert into public.rp_medication_versions (medication_id, version, snapshot, changed_by, change_reason)
  values (v_next.id, v_next.version, to_jsonb(v_next) - 'created_at' - 'updated_at', v_actor, btrim(p_reason));
  select passport into v_passport from public.profiles where user_id = v_actor;
  insert into public.audit_logs (actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values)
  values (v_actor, v_passport, case when p_active then 'RP_MEDICATION_REACTIVATED' else 'RP_MEDICATION_DEACTIVATED' end,
    'rp_medications', v_next.id, jsonb_build_object('active', v_medication.active),
    jsonb_build_object('active', v_next.active, 'reason', btrim(p_reason), 'version', v_next.version));
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
  if p_model <> 'gpt-5.6-luna' or p_prompt_version <> 'consultation-assistant-v5' then
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
         or not private.rp_medication_context_compatible(p_consultation_id, suggestion->>'medication_id')
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
      jsonb_build_object('severity', option->>'severity', 'medication_id', suggestion->>'medication_id', 'reason', suggestion->>'reason')
    from jsonb_array_elements(p_response_payload->'options') option
    cross join lateral jsonb_array_elements(option->'medication_suggestions') suggestion;
  end if;
  return p_response_payload;
end;
$$;

create or replace function private.build_consultation_snapshot_v3(
  p_consultation_id bigint,
  p_completed_at timestamptz,
  p_prescription_snapshot jsonb default null
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select private.build_consultation_snapshot_v2(p_consultation_id, p_completed_at)
    || jsonb_build_object(
      'schema', 'hpsm.clinical_consultation.v3',
      'case_signature', private.rp_case_signature(p_consultation_id),
      'prescription', p_prescription_snapshot
    );
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
  v_prescription jsonb;
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
  v_prescription := private.finalize_consultation_prescription(p_consultation_id, v_completed_at);
  v_snapshot := private.build_consultation_snapshot_v3(p_consultation_id, v_completed_at, v_prescription);
  update public.clinical_consultations
  set status = 'completed', completed_at = v_completed_at, final_snapshot = v_snapshot
  where id = p_consultation_id;
  if v_consultation.appointment_id is not null then
    update public.patient_appointments set status = 'completed', completed_at = v_completed_at
    where id = v_consultation.appointment_id and status = 'in_progress';
  end if;
  perform private.learn_completed_consultation(p_consultation_id);
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
  select * into v_consultation from public.clinical_consultations where id = p_consultation_id;
  if v_consultation.id is null then raise exception 'Consulta não localizada.'; end if;
  if v_consultation.status <> 'completed' or v_consultation.final_snapshot is null then raise exception 'O prontuário está disponível somente para consultas concluídas.'; end if;
  select * into v_document from public.consultation_documents where consultation_id = p_consultation_id for update;
  if v_document.id is null then
    v_snapshot := case
      when v_consultation.final_snapshot->>'schema' in ('hpsm.clinical_consultation.v2', 'hpsm.clinical_consultation.v3') then v_consultation.final_snapshot
      else private.build_consultation_snapshot_v3(p_consultation_id, v_consultation.completed_at, null)
    end;
    insert into public.consultation_documents (consultation_id, source_snapshot, created_by)
    values (p_consultation_id, v_snapshot, v_actor) returning * into v_document;
  end if;
  return jsonb_build_object('document_id', v_document.id, 'status', v_document.status, 'source_snapshot', v_document.source_snapshot);
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
     or p_pixel_height not between 400 and 14000 or p_render_version <> 'consultation-document-png-v2' then
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

create or replace function public.begin_prescription_document(p_consultation_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_prescription public.consultation_prescriptions;
  v_document public.prescription_documents;
begin
  if not private.has_permission(v_actor, 'consultations.view') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  select * into v_prescription from public.consultation_prescriptions
  where consultation_id = p_consultation_id and status = 'finalized';
  if v_prescription.id is null or v_prescription.final_snapshot is null then raise exception 'A Receita está disponível somente após a conclusão de uma prescrição com itens.'; end if;
  select * into v_document from public.prescription_documents where prescription_id = v_prescription.id for update;
  if v_document.id is null then
    insert into public.prescription_documents (prescription_id, consultation_id, source_snapshot, created_by)
    values (v_prescription.id, p_consultation_id, v_prescription.final_snapshot, v_actor)
    returning * into v_document;
  end if;
  return jsonb_build_object('document_id', v_document.id, 'status', v_document.status, 'source_snapshot', v_document.source_snapshot);
end;
$$;

create or replace function public.prescription_document_state(p_consultation_id bigint)
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
  select jsonb_build_object(
    'document', case when document.status = 'completed' then jsonb_build_object(
      'id', document.id, 'created_at', document.created_at, 'completed_at', document.completed_at,
      'file_size', document.file_size, 'pixel_width', document.pixel_width,
      'pixel_height', document.pixel_height, 'render_version', document.render_version
    ) else null end,
    'share', case when share.id is null then null else jsonb_build_object('id', share.id, 'created_at', share.created_at) end
  ) into v_result
  from public.consultation_prescriptions prescription
  left join public.prescription_documents document on document.prescription_id = prescription.id
  left join public.prescription_document_shares share on share.consultation_id = prescription.consultation_id and share.revoked_at is null
  where prescription.consultation_id = p_consultation_id and prescription.status = 'finalized';
  if v_result is null then raise exception 'A Receita está disponível somente após a conclusão de uma prescrição com itens.'; end if;
  return v_result;
end;
$$;

create or replace function public.complete_prescription_document(
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
  v_document public.prescription_documents;
  v_passport text;
begin
  if not private.has_permission(v_actor, 'consultations.view') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  select * into v_document from public.prescription_documents
  where id = p_document_id and consultation_id = p_consultation_id for update;
  if v_document.id is null then raise exception 'Preparação de Receita inválida.'; end if;
  if v_document.status = 'completed' then return public.prescription_document_state(p_consultation_id); end if;
  if p_storage_path !~ ('^prescriptions/' || p_consultation_id::text || '/documents/' || p_document_id::text || '[.]png$')
     or p_file_size not between 32 and 12582912 or p_pixel_width not between 900 and 1400
     or p_pixel_height not between 400 and 14000 or p_render_version <> 'prescription-document-png-v1' then
    raise exception 'Metadados da Receita inválidos.';
  end if;
  if not exists (
    select 1 from storage.objects object
    where object.bucket_id = 'clinical-exam-documents' and object.name = p_storage_path
  ) then raise exception 'A imagem da Receita ainda não foi confirmada no Storage.'; end if;
  update public.prescription_documents set
    status = 'completed', storage_path = p_storage_path, mime_type = 'image/png', file_size = p_file_size,
    pixel_width = p_pixel_width, pixel_height = p_pixel_height, render_version = p_render_version,
    completed_at = now()
  where id = p_document_id;
  select passport into v_passport from public.profiles where user_id = v_actor;
  insert into public.audit_logs (actor_user_id, actor_passport, action, entity_name, entity_id, new_values)
  values (v_actor, v_passport, 'PRESCRIPTION_DOCUMENT_GENERATED', 'consultation_prescriptions', v_document.prescription_id::text,
    jsonb_build_object('document_id', p_document_id, 'render_version', p_render_version, 'file_size', p_file_size));
  return public.prescription_document_state(p_consultation_id);
end;
$$;

create or replace function public.create_prescription_document_share(p_consultation_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_document public.prescription_documents;
  v_share public.prescription_document_shares;
  v_passport text;
begin
  if not private.has_permission(v_actor, 'consultations.view') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  select * into v_document from public.prescription_documents
  where consultation_id = p_consultation_id and status = 'completed' for update;
  if v_document.id is null then raise exception 'Gere a Receita antes de compartilhar.'; end if;
  select * into v_share from public.prescription_document_shares
  where consultation_id = p_consultation_id and revoked_at is null for update;
  if v_share.id is null then
    insert into public.prescription_document_shares (consultation_id, document_id, created_by)
    values (p_consultation_id, v_document.id, v_actor) returning * into v_share;
    select passport into v_passport from public.profiles where user_id = v_actor;
    insert into public.audit_logs (actor_user_id, actor_passport, action, entity_name, entity_id, new_values)
    values (v_actor, v_passport, 'PRESCRIPTION_DOCUMENT_SHARED', 'consultation_prescriptions', v_document.prescription_id::text,
      jsonb_build_object('share_id', v_share.id, 'document_id', v_document.id));
  end if;
  return public.prescription_document_state(p_consultation_id);
end;
$$;

create or replace function public.revoke_prescription_document_share(p_consultation_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_share public.prescription_document_shares;
  v_passport text;
begin
  if not private.has_permission(v_actor, 'consultations.view') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  select * into v_share from public.prescription_document_shares
  where consultation_id = p_consultation_id and revoked_at is null for update;
  if v_share.id is not null then
    update public.prescription_document_shares set revoked_at = now(), revoked_by = v_actor where id = v_share.id;
    select passport into v_passport from public.profiles where user_id = v_actor;
    insert into public.audit_logs (actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values)
    values (v_actor, v_passport, 'PRESCRIPTION_DOCUMENT_SHARE_REVOKED', 'clinical_consultations', p_consultation_id::text,
      jsonb_build_object('share_id', v_share.id), jsonb_build_object('revoked', true));
  end if;
  return public.prescription_document_state(p_consultation_id);
end;
$$;

create or replace function public.record_prescription_document_access(
  p_consultation_id bigint,
  p_action text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_passport text;
begin
  if not private.has_permission(v_actor, 'consultations.view') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if p_action not in ('PRESCRIPTION_DOCUMENT_VIEWED', 'PRESCRIPTION_DOCUMENT_DOWNLOADED') then raise exception 'Ação de documento inválida.'; end if;
  if not exists (select 1 from public.prescription_documents where consultation_id = p_consultation_id and status = 'completed') then
    raise exception 'Receita não localizada.';
  end if;
  select passport into v_passport from public.profiles where user_id = v_actor;
  insert into public.audit_logs (actor_user_id, actor_passport, action, entity_name, entity_id, new_values)
  values (v_actor, v_passport, p_action, 'clinical_consultations', p_consultation_id::text, jsonb_build_object('channel', 'professional'));
end;
$$;

create or replace function public.resolve_prescription_document_share(p_share_id uuid)
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
    'render_version', document.render_version
  )
  from public.prescription_document_shares share
  join public.prescription_documents document on document.id = share.document_id
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
  v_level integer;
  v_paths jsonb;
begin
  select position.level into v_level
  from public.profiles profile
  join public.staff_positions position on position.id = profile.position_id
  where profile.user_id = v_actor and profile.status = 'active' and position.active and position.official;
  if v_level not in (13, 14) or not private.has_permission(v_actor, 'consultations.delete') then
    raise exception 'A exclusão de consulta é exclusiva dos cargos de Diretoria.' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(path order by path), '[]'::jsonb) into v_paths
  from (
    select document.storage_path as path
    from public.consultation_documents document
    where document.consultation_id = p_consultation_id and document.storage_path is not null
    union all
    select document.storage_path
    from public.prescription_documents document
    where document.consultation_id = p_consultation_id and document.storage_path is not null
  ) files;
  return v_paths;
end;
$$;

revoke all on function public.consultation_rollup_reference_data() from public, anon, authenticated, service_role;
revoke all on function public.consultation_rollup_detail(bigint) from public, anon, authenticated, service_role;
revoke all on function public.consultation_rollup_ai_context(bigint) from public, anon, authenticated, service_role;
revoke all on function public.clinical_protocol_library() from public, anon, authenticated, service_role;
revoke all on function public.moderate_clinical_protocol(uuid, text, text) from public, anon, authenticated, service_role;
revoke all on function public.set_rp_medication_active(text, boolean, text) from public, anon, authenticated, service_role;
revoke all on function public.set_clinical_protocol_settings(integer, integer, numeric, numeric, integer, text) from public, anon, authenticated, service_role;
revoke all on function public.upsert_consultation_prescription_item(bigint, uuid, text, text, text, text, text, integer, text, text, text, integer, text) from public, anon, authenticated, service_role;
revoke all on function public.reject_consultation_medication_suggestion(bigint, text, text) from public, anon, authenticated, service_role;
revoke all on function public.remove_consultation_prescription_item(bigint, uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.complete_consultation_ai_generation_v3(bigint, text, uuid, jsonb, text, text, integer, integer, integer) from public, anon, authenticated, service_role;
revoke all on function public.begin_prescription_document(bigint) from public, anon, authenticated, service_role;
revoke all on function public.prescription_document_state(bigint) from public, anon, authenticated, service_role;
revoke all on function public.complete_prescription_document(bigint, uuid, text, integer, integer, integer, text) from public, anon, authenticated, service_role;
revoke all on function public.create_prescription_document_share(bigint) from public, anon, authenticated, service_role;
revoke all on function public.revoke_prescription_document_share(bigint) from public, anon, authenticated, service_role;
revoke all on function public.record_prescription_document_access(bigint, text) from public, anon, authenticated, service_role;
revoke all on function public.resolve_prescription_document_share(uuid) from public, anon, authenticated, service_role;

grant execute on function public.consultation_rollup_reference_data() to authenticated;
grant execute on function public.consultation_rollup_detail(bigint) to authenticated;
grant execute on function public.consultation_rollup_ai_context(bigint) to service_role;
grant execute on function public.clinical_protocol_library() to authenticated;
grant execute on function public.moderate_clinical_protocol(uuid, text, text) to authenticated;
grant execute on function public.set_rp_medication_active(text, boolean, text) to authenticated;
grant execute on function public.set_clinical_protocol_settings(integer, integer, numeric, numeric, integer, text) to authenticated;
grant execute on function public.upsert_consultation_prescription_item(bigint, uuid, text, text, text, text, text, integer, text, text, text, integer, text) to authenticated;
grant execute on function public.reject_consultation_medication_suggestion(bigint, text, text) to authenticated;
grant execute on function public.remove_consultation_prescription_item(bigint, uuid, text) to authenticated;
grant execute on function public.complete_consultation_ai_generation_v3(bigint, text, uuid, jsonb, text, text, integer, integer, integer) to service_role;
grant execute on function public.begin_prescription_document(bigint) to authenticated;
grant execute on function public.prescription_document_state(bigint) to authenticated;
grant execute on function public.complete_prescription_document(bigint, uuid, text, integer, integer, integer, text) to authenticated;
grant execute on function public.create_prescription_document_share(bigint) to authenticated;
grant execute on function public.revoke_prescription_document_share(bigint) to authenticated;
grant execute on function public.record_prescription_document_access(bigint, text) to authenticated;
grant execute on function public.resolve_prescription_document_share(uuid) to service_role;

comment on table public.prescription_documents is
  'Receita RP em PNG criada deterministicamente do snapshot final, sem chamada de IA.';
comment on table public.prescription_document_shares is
  'Um link público revogável por Receita, resolvido somente pelo backend service_role.';
