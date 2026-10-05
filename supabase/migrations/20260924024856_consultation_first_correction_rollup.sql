-- Correction rollup: consultation-first UX, centralized vital generation, CID-10 and certificate integrity.

update public.consultation_vital_ranges set configuration = case code
  when 'blood_pressure' then '{"lowSystolicMax":89,"lowDiastolicMax":59,"normalSystolicMax":129,"normalDiastolicMax":84,"highSystolicMin":130,"highDiastolicMin":85,"criticalSystolicMin":180,"criticalDiastolicMin":120,"generation":{"Baixo":{"systolicMin":75,"systolicMax":89,"diastolicMin":45,"diastolicMax":59},"Normal":{"systolicMin":100,"systolicMax":129,"diastolicMin":65,"diastolicMax":84},"Elevado":{"systolicMin":130,"systolicMax":159,"diastolicMin":85,"diastolicMax":99},"Crítico":{"systolicMin":180,"systolicMax":210,"diastolicMin":120,"diastolicMax":135}}}'::jsonb
  when 'temperature' then '{"lowMax":35.4,"normalMax":37.4,"highMin":37.5,"criticalMin":39.5,"generation":{"Baixo":{"min":34.8,"max":35.4},"Normal":{"min":36.0,"max":37.4},"Elevado":{"min":37.5,"max":39.4},"Crítico":{"min":39.5,"max":41.0}}}'::jsonb
  when 'heart_rate' then '{"criticalLowMax":39,"lowMax":59,"normalMax":100,"highMin":101,"criticalHighMin":150,"generation":{"Baixo":{"min":45,"max":59},"Normal":{"min":60,"max":100},"Elevado":{"min":101,"max":149},"Crítico":{"min":150,"max":180}}}'::jsonb
  when 'oxygen_saturation' then '{"criticalMax":89,"lowMax":94,"normalMin":95,"normalMax":97,"elevatedMin":98,"generation":{"Baixo":{"min":90,"max":94},"Normal":{"min":95,"max":97},"Elevado":{"min":98,"max":100},"Crítico":{"min":80,"max":89}}}'::jsonb
  else configuration end,
  updated_at = now();

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

revoke all on function public.create_consultation_clinical_exam(bigint, bigint, text, text, bigint, jsonb) from public, anon;
grant execute on function public.create_consultation_clinical_exam(bigint, bigint, text, text, bigint, jsonb) to authenticated, service_role;

create table if not exists public.medical_cid10_catalog (
  code text primary key,
  description text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint medical_cid10_catalog_code_check check (code ~ '^[A-Z][0-9]{2}(\.[0-9A-Z]{1,2})?$'),
  constraint medical_cid10_catalog_description_check check (char_length(btrim(description)) between 3 and 240)
);

insert into public.medical_cid10_catalog (code, description) values
  ('A09', 'Diarreia e gastroenterite de origem infecciosa presumível'),
  ('B34.9', 'Infecção viral não especificada'),
  ('F41.1', 'Ansiedade generalizada'),
  ('F43.0', 'Reação aguda ao estresse'),
  ('G43.9', 'Enxaqueca não especificada'),
  ('H10.9', 'Conjuntivite não especificada'),
  ('J00', 'Nasofaringite aguda'),
  ('J02.9', 'Faringite aguda não especificada'),
  ('J06.9', 'Infecção aguda das vias aéreas superiores não especificada'),
  ('J11.1', 'Influenza com outras manifestações respiratórias, vírus não identificado'),
  ('J18.9', 'Pneumonia não especificada'),
  ('J45.9', 'Asma não especificada'),
  ('K29.7', 'Gastrite não especificada'),
  ('K52.9', 'Gastroenterite e colite não infecciosas não especificadas'),
  ('M25.5', 'Dor articular'),
  ('M54.5', 'Dor lombar baixa'),
  ('M79.1', 'Mialgia'),
  ('R05', 'Tosse'),
  ('R10.4', 'Outras dores abdominais e as não especificadas'),
  ('R11', 'Náusea e vômitos'),
  ('R42', 'Tontura e instabilidade'),
  ('R50.9', 'Febre não especificada'),
  ('R51', 'Cefaleia'),
  ('R53', 'Mal-estar e fadiga'),
  ('S52.9', 'Fratura do antebraço, parte não especificada'),
  ('S62.9', 'Fratura ao nível do punho e da mão, parte não especificada'),
  ('S82.9', 'Fratura da perna, parte não especificada'),
  ('S93.4', 'Entorse e distensão do tornozelo')
on conflict (code) do update set description = excluded.description, active = true, updated_at = now();

alter table public.medical_cid10_catalog enable row level security;
alter table public.medical_cid10_catalog force row level security;
drop policy if exists medical_cid10_catalog_read_authorized on public.medical_cid10_catalog;
create policy medical_cid10_catalog_read_authorized on public.medical_cid10_catalog for select to authenticated
  using (private.has_permission(auth.uid(), 'atestados.view'));
revoke all on public.medical_cid10_catalog from public, anon, authenticated;
grant select on public.medical_cid10_catalog to authenticated;
grant select, insert, update, delete on public.medical_cid10_catalog to service_role;

alter table public.medical_certificates add column if not exists diagnosis_text text;
alter table public.medical_certificates add column if not exists cid_code text references public.medical_cid10_catalog(code) on update cascade on delete restrict;

create unique index if not exists medical_certificates_one_per_consultation_uidx
  on public.medical_certificates (consultation_id)
  where consultation_id is not null;

create or replace function public.medical_certificate_cid_catalog(p_search text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_actor uuid := private.hpsm_current_actor();
begin
  if not private.has_permission(v_actor, 'atestados.view') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('code', item.code, 'description', item.description) order by item.code)
    from public.medical_cid10_catalog item
    where item.active and (nullif(btrim(coalesce(p_search, '')), '') is null or item.code ilike btrim(p_search) || '%' or item.description ilike '%' || btrim(p_search) || '%')
  ), '[]'::jsonb);
end;
$$;

create or replace function public.create_consultation_medical_certificate(
  p_consultation_id bigint,
  p_medical_context text,
  p_leave_days integer,
  p_exam_ids bigint[] default '{}'::bigint[],
  p_cast_ids bigint[] default '{}'::bigint[]
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_consultation public.clinical_consultations;
  v_context text := btrim(coalesce(p_medical_context, ''));
  v_diagnosis text;
  v_certificate public.medical_certificates;
begin
  if not private.has_permission(v_actor, 'atestados.create') or not private.has_permission(v_actor, 'patients.view') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  select * into v_consultation from public.clinical_consultations where id = p_consultation_id for update;
  if v_consultation.id is null or not private.can_edit_consultation(v_actor, v_consultation.professional_id) or v_consultation.status <> 'in_progress' then raise exception 'A consulta não está disponível para emissão.' using errcode = '42501'; end if;
  if exists (select 1 from public.medical_certificates where consultation_id = p_consultation_id) then raise exception 'Esta consulta já possui um atestado, inclusive no histórico de cancelamentos.'; end if;
  if char_length(v_context) not between 3 and 4000 then raise exception 'Informe o motivo e o contexto médico.'; end if;
  if p_leave_days is null or p_leave_days not between 1 and 365 then raise exception 'Informe manualmente uma quantidade inteira e positiva de dias.'; end if;
  v_diagnosis := nullif(btrim(coalesce(v_consultation.selected_diagnosis->>'title', '')), '');
  insert into public.medical_certificates (patient_id, consultation_id, created_by, medical_context, leave_days, diagnosis_text)
  values (v_consultation.patient_id, p_consultation_id, v_actor, v_context, p_leave_days, v_diagnosis)
  returning * into v_certificate;
  perform private.set_medical_certificate_links(v_certificate.id, v_consultation.patient_id, v_actor, p_exam_ids, p_cast_ids);
  perform private.audit_medical_certificate_action(v_actor, 'MEDICAL_CERTIFICATE_CREATED', v_certificate.id, null, jsonb_build_object('patient_id', v_consultation.patient_id, 'consultation_id', p_consultation_id, 'leave_days', p_leave_days, 'diagnosis_text', v_diagnosis, 'status', 'draft'));
  return v_certificate.id;
end;
$$;

create or replace function public.update_medical_certificate_v2(
  p_certificate_id bigint,
  p_medical_context text,
  p_leave_days integer,
  p_final_text text,
  p_diagnosis_text text,
  p_cid_code text,
  p_exam_ids bigint[] default '{}'::bigint[],
  p_cast_ids bigint[] default '{}'::bigint[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_old public.medical_certificates;
  v_context text := btrim(coalesce(p_medical_context, ''));
  v_text text := nullif(btrim(coalesce(p_final_text, '')), '');
  v_diagnosis text := nullif(btrim(coalesce(p_diagnosis_text, '')), '');
  v_cid text := upper(nullif(btrim(coalesce(p_cid_code, '')), ''));
begin
  if not private.has_permission(v_actor, 'atestados.create') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  select * into v_old from public.medical_certificates where id = p_certificate_id for update;
  if v_old.id is null then raise exception 'Atestado não localizado.'; end if;
  if v_old.status <> 'draft' then raise exception 'Somente rascunhos podem ser editados.'; end if;
  if v_old.created_by <> v_actor then raise exception 'Somente o responsável pode editar este atestado.' using errcode = '42501'; end if;
  if char_length(v_context) not between 3 and 4000 then raise exception 'Informe o motivo e o contexto médico.'; end if;
  if p_leave_days is null or p_leave_days not between 1 and 365 then raise exception 'Informe uma quantidade inteira e positiva de dias.'; end if;
  if v_diagnosis is null or char_length(v_diagnosis) > 500 then raise exception 'Informe o diagnóstico do atestado.'; end if;
  if v_cid is null or not exists (select 1 from public.medical_cid10_catalog where code = v_cid and active) then raise exception 'Selecione um CID-10 válido no catálogo.'; end if;
  if v_text is not null and (not private.medical_certificate_text_matches_days(v_text, p_leave_days) or strpos(lower(v_text), lower(v_diagnosis)) = 0 or strpos(upper(v_text), v_cid) = 0) then raise exception 'O texto precisa preservar os dias, o diagnóstico e o CID-10 selecionado.'; end if;
  update public.medical_certificates set medical_context = v_context, leave_days = p_leave_days, final_text = v_text, diagnosis_text = v_diagnosis, cid_code = v_cid where id = p_certificate_id;
  perform private.set_medical_certificate_links(p_certificate_id, v_old.patient_id, v_actor, p_exam_ids, p_cast_ids);
  perform private.audit_medical_certificate_action(v_actor, 'MEDICAL_CERTIFICATE_UPDATED', p_certificate_id, jsonb_build_object('leave_days', v_old.leave_days, 'diagnosis_text', v_old.diagnosis_text, 'cid_code', v_old.cid_code), jsonb_build_object('leave_days', p_leave_days, 'diagnosis_text', v_diagnosis, 'cid_code', v_cid, 'has_final_text', v_text is not null));
end;
$$;

create or replace function public.medical_certificate_ai_context(p_certificate_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_actor uuid := private.hpsm_current_actor(); v_certificate public.medical_certificates;
begin
  if not private.has_permission(v_actor, 'atestados.create') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  select * into v_certificate from public.medical_certificates where id = p_certificate_id;
  if v_certificate.id is null then raise exception 'Atestado não localizado.'; end if;
  if v_certificate.status <> 'draft' or v_certificate.created_by <> v_actor then raise exception 'Este atestado não aceita geração de texto.' using errcode = '42501'; end if;
  return jsonb_build_object(
    'certificate_id', v_certificate.id, 'actor_id', v_actor, 'medical_context', v_certificate.medical_context,
    'leave_days', v_certificate.leave_days, 'diagnosis_text', v_certificate.diagnosis_text, 'cid_code', v_certificate.cid_code,
    'cid_catalog', coalesce((select jsonb_agg(jsonb_build_object('code', code, 'description', description) order by code) from public.medical_cid10_catalog where active), '[]'::jsonb),
    'exams', coalesce((select jsonb_agg(jsonb_build_object('type', exam_type.name, 'status', exam.status, 'conclusion', case when exam.status = 'completed' then exam.conclusion else null end) order by exam.requested_at desc) from public.medical_certificate_exams link join public.clinical_exams exam on exam.id = link.exam_id join public.exam_types exam_type on exam_type.id = exam.exam_type_id where link.certificate_id = v_certificate.id), '[]'::jsonb),
    'casts', coalesce((select jsonb_agg(jsonb_build_object('body_region', cast_record.body_region, 'laterality', cast_record.laterality, 'status', cast_record.status, 'applied_at', cast_record.applied_at) order by cast_record.applied_at desc) from public.medical_certificate_casts link join public.clinical_casts cast_record on cast_record.id = link.cast_id where link.certificate_id = v_certificate.id), '[]'::jsonb)
  );
end;
$$;

create or replace function public.apply_medical_certificate_ai_result(
  p_certificate_id bigint,
  p_text text,
  p_diagnosis_text text,
  p_cid_code text,
  p_model text,
  p_prompt_version text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_certificate public.medical_certificates;
  v_text text := btrim(coalesce(p_text, ''));
  v_diagnosis text := nullif(btrim(coalesce(p_diagnosis_text, '')), '');
  v_cid text := upper(nullif(btrim(coalesce(p_cid_code, '')), ''));
begin
  if not private.has_permission(v_actor, 'atestados.create') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  select * into v_certificate from public.medical_certificates where id = p_certificate_id for update;
  if v_certificate.id is null then raise exception 'Atestado não localizado.'; end if;
  if v_certificate.status <> 'draft' or v_certificate.created_by <> v_actor then raise exception 'Este atestado não aceita geração de texto.' using errcode = '42501'; end if;
  if p_model <> 'gpt-5.6-luna' or p_prompt_version <> 'medical-certificate-v2' then raise exception 'Modelo de assistência incompatível.'; end if;
  if v_diagnosis is null or char_length(v_diagnosis) > 500 then raise exception 'A sugestão não retornou um diagnóstico válido.'; end if;
  if v_cid is null or not exists (select 1 from public.medical_cid10_catalog where code = v_cid and active) then raise exception 'A sugestão não retornou um CID-10 do catálogo. Nada foi alterado.'; end if;
  if not private.medical_certificate_text_matches_days(v_text, v_certificate.leave_days) or strpos(lower(v_text), lower(v_diagnosis)) = 0 or strpos(upper(v_text), v_cid) = 0 then raise exception 'A sugestão não preservou dias, diagnóstico e CID-10. Nada foi alterado.'; end if;
  update public.medical_certificates set generated_text = v_text, final_text = v_text, diagnosis_text = v_diagnosis, cid_code = v_cid, ai_model = p_model, ai_prompt_version = p_prompt_version, ai_generated_at = now() where id = p_certificate_id;
  perform private.audit_medical_certificate_action(v_actor, 'MEDICAL_CERTIFICATE_AI_GENERATED', p_certificate_id, null, jsonb_build_object('model', p_model, 'prompt_version', p_prompt_version, 'leave_days', v_certificate.leave_days, 'diagnosis_text', v_diagnosis, 'cid_code', v_cid));
end;
$$;

create or replace function public.medical_certificate_detail(p_certificate_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_actor uuid := private.hpsm_current_actor(); v_result jsonb;
begin
  if not private.has_permission(v_actor, 'atestados.view') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  select jsonb_build_object(
    'id', certificate.id, 'patient_id', certificate.patient_id, 'patient_name', patient.name, 'patient_passport', patient.passport,
    'attendance_id', certificate.attendance_id, 'consultation_id', certificate.consultation_id,
    'origin_type', case when certificate.consultation_id is not null then 'consultation' else 'attendance' end,
    'attendance_created_at', coalesce(attendance.created_at, consultation.started_at),
    'attendance_summary', case when certificate.consultation_id is not null then 'Consulta clínica #' || certificate.consultation_id::text else coalesce((select string_agg(item.service_name || case when item.quantity > 1 then ' ×' || item.quantity::text else '' end, ', ' order by item.id) from public.attendance_items item where item.attendance_id = attendance.id), 'Atendimento sem itens') end,
    'created_by', certificate.created_by, 'professional_name', creator.display_name, 'professional_position', position.name,
    'medical_context', certificate.medical_context, 'leave_days', certificate.leave_days,
    'diagnosis_text', certificate.diagnosis_text, 'cid_code', certificate.cid_code, 'cid_description', cid.description,
    'generated_text', certificate.generated_text, 'final_text', certificate.final_text, 'status', certificate.status,
    'ai_model', certificate.ai_model, 'ai_prompt_version', certificate.ai_prompt_version, 'ai_generated_at', certificate.ai_generated_at,
    'finalized_at', certificate.finalized_at, 'professional_snapshot', certificate.professional_snapshot,
    'document_ready', certificate.final_png_path is not null, 'cancelled_at', certificate.cancelled_at, 'cancellation_reason', certificate.cancellation_reason,
    'created_at', certificate.created_at, 'updated_at', certificate.updated_at,
    'exams', coalesce((select jsonb_agg(jsonb_build_object('id', exam.id, 'type', exam_type.name, 'status', exam.status, 'requested_at', exam.requested_at, 'completed_at', exam.completed_at) order by exam.requested_at desc, exam.id desc) from public.medical_certificate_exams link join public.clinical_exams exam on exam.id = link.exam_id join public.exam_types exam_type on exam_type.id = exam.exam_type_id where link.certificate_id = certificate.id), '[]'::jsonb),
    'casts', coalesce((select jsonb_agg(jsonb_build_object('id', cast_record.id, 'body_region', cast_record.body_region, 'laterality', cast_record.laterality, 'status', cast_record.status, 'applied_at', cast_record.applied_at) order by cast_record.applied_at desc, cast_record.id desc) from public.medical_certificate_casts link join public.clinical_casts cast_record on cast_record.id = link.cast_id where link.certificate_id = certificate.id), '[]'::jsonb)
  ) into v_result
  from public.medical_certificates certificate
  join public.patients patient on patient.id = certificate.patient_id
  left join public.attendances attendance on attendance.id = certificate.attendance_id
  left join public.clinical_consultations consultation on consultation.id = certificate.consultation_id
  join public.profiles creator on creator.user_id = certificate.created_by
  left join public.staff_positions position on position.id = creator.position_id
  left join public.medical_cid10_catalog cid on cid.code = certificate.cid_code
  where certificate.id = p_certificate_id;
  if v_result is null then raise exception 'Atestado não localizado.'; end if;
  return v_result;
end;
$$;

create or replace function public.finalize_medical_certificate(p_certificate_id bigint, p_final_text text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_certificate public.medical_certificates;
  v_text text := btrim(coalesce(p_final_text, ''));
  v_snapshot jsonb;
  v_cid_description text;
begin
  if not private.has_permission(v_actor, 'atestados.finalize') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  select * into v_certificate from public.medical_certificates where id = p_certificate_id for update;
  if v_certificate.id is null then raise exception 'Atestado não localizado.'; end if;
  if v_certificate.status <> 'draft' then raise exception 'Este atestado já foi finalizado ou cancelado.'; end if;
  if v_certificate.created_by <> v_actor then raise exception 'Somente o responsável pode finalizar este atestado.' using errcode = '42501'; end if;
  select description into v_cid_description from public.medical_cid10_catalog where code = v_certificate.cid_code and active;
  if nullif(btrim(coalesce(v_certificate.diagnosis_text, '')), '') is null or v_cid_description is null then raise exception 'Informe diagnóstico e selecione um CID-10 válido antes de finalizar.'; end if;
  if not private.medical_certificate_text_matches_days(v_text, v_certificate.leave_days) or strpos(lower(v_text), lower(v_certificate.diagnosis_text)) = 0 or strpos(upper(v_text), v_certificate.cid_code) = 0 then raise exception 'O texto final precisa preservar exatamente os dias, o diagnóstico e o CID-10 selecionado.'; end if;
  select jsonb_build_object(
    'schema', 'hpsm.medical_certificate_snapshot.v2', 'certificate_id', v_certificate.id,
    'origin_type', case when v_certificate.consultation_id is not null then 'consultation' else 'attendance' end,
    'patient', jsonb_build_object('id', patient.id, 'name', patient.name, 'passport', patient.passport),
    'attendance', jsonb_build_object('id', coalesce(attendance.id, consultation.id), 'created_at', coalesce(attendance.created_at, consultation.started_at)),
    'consultation_id', v_certificate.consultation_id, 'leave_days', v_certificate.leave_days,
    'diagnosis', jsonb_build_object('text', v_certificate.diagnosis_text, 'cid_code', v_certificate.cid_code, 'cid_description', v_cid_description),
    'text', v_text, 'issued_at', now(),
    'professional', jsonb_build_object('id', profile.user_id, 'name', profile.display_name, 'position', position.name, 'crm_code', identity.crm_code, 'registration_date', identity.registration_date, 'signature_image_path', identity.signature_image_path)
  ) into v_snapshot
  from public.patients patient
  left join public.attendances attendance on attendance.id = v_certificate.attendance_id and attendance.patient_id = patient.id
  left join public.clinical_consultations consultation on consultation.id = v_certificate.consultation_id and consultation.patient_id = patient.id
  join public.profiles profile on profile.user_id = v_actor and profile.status = 'active'
  left join public.staff_positions position on position.id = profile.position_id
  join public.professional_identities identity on identity.user_id = profile.user_id and identity.status = 'active' and identity.signature_image_path is not null and identity.crm_code ~ '^[0-9]{8}$'
  where patient.id = v_certificate.patient_id and (attendance.id is not null or consultation.id is not null);
  if v_snapshot is null then raise exception 'A identidade profissional precisa estar ativa antes da finalização.'; end if;
  update public.medical_certificates set status = 'finalized', final_text = v_text, finalized_at = now(), finalized_by = v_actor, professional_snapshot = v_snapshot where id = p_certificate_id;
  perform private.audit_medical_certificate_action(v_actor, 'MEDICAL_CERTIFICATE_FINALIZED', p_certificate_id, jsonb_build_object('status', 'draft'), jsonb_build_object('status', 'finalized', 'leave_days', v_certificate.leave_days, 'diagnosis_text', v_certificate.diagnosis_text, 'cid_code', v_certificate.cid_code, 'snapshot_schema', v_snapshot->>'schema'));
  return v_snapshot;
end;
$$;

create or replace function public.register_medical_certificate_document(p_certificate_id bigint, p_storage_path text, p_file_size integer, p_width integer, p_height integer, p_render_version text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_actor uuid := private.hpsm_current_actor(); v_certificate public.medical_certificates;
begin
  if not private.has_permission(v_actor, 'atestados.view') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  select * into v_certificate from public.medical_certificates where id = p_certificate_id for update;
  if v_certificate.id is null then raise exception 'Atestado não localizado.'; end if;
  if v_certificate.status <> 'finalized' then raise exception 'O documento está disponível somente para atestados finalizados.'; end if;
  if p_storage_path !~ ('^medical-certificates/' || p_certificate_id::text || '/documents/[0-9a-f-]{36}[.]png$') then raise exception 'Caminho de documento inválido.'; end if;
  if p_file_size not between 32 and 12582912 or p_width not between 900 and 1400 or p_height not between 400 and 14000 or nullif(btrim(p_render_version), '') is null then raise exception 'Metadados do documento inválidos.'; end if;
  if v_certificate.final_png_path is null then
    update public.medical_certificates set final_png_path = p_storage_path, final_png_file_size = p_file_size, final_png_width = p_width, final_png_height = p_height, final_png_render_version = p_render_version where id = p_certificate_id;
    perform private.audit_medical_certificate_action(v_actor, 'MEDICAL_CERTIFICATE_DOCUMENT_GENERATED', p_certificate_id, null, jsonb_build_object('render_version', p_render_version, 'file_size', p_file_size));
  end if;
  return public.medical_certificate_document_state(p_certificate_id);
end;
$$;

create or replace function public.patient_portal_register_medical_certificate_document(p_token_hash text, p_certificate_id bigint, p_storage_path text, p_file_size integer, p_width integer, p_height integer, p_render_version text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_session record; v_certificate public.medical_certificates;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then return jsonb_build_object('authenticated', false, 'found', false); end if;
  select * into v_session from private.patient_portal_session_record(p_token_hash);
  if v_session.patient_id is null then return jsonb_build_object('authenticated', false, 'found', false); end if;
  select * into v_certificate from public.medical_certificates where id = p_certificate_id and patient_id = v_session.patient_id and status = 'finalized' for update;
  if v_certificate.id is null then return jsonb_build_object('authenticated', true, 'found', false); end if;
  if p_storage_path !~ ('^medical-certificates/' || p_certificate_id::text || '/documents/[0-9a-f-]{36}[.]png$') or p_file_size not between 32 and 12582912 or p_width not between 900 and 1400 or p_height not between 400 and 14000 or nullif(btrim(p_render_version), '') is null then raise exception 'Metadados do documento inválidos.'; end if;
  if v_certificate.final_png_path is null then
    update public.medical_certificates set final_png_path = p_storage_path, final_png_file_size = p_file_size, final_png_width = p_width, final_png_height = p_height, final_png_render_version = p_render_version where id = p_certificate_id;
    insert into public.audit_logs (actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values) values (null, v_session.patient_passport, 'MEDICAL_CERTIFICATE_DOCUMENT_GENERATED', 'medical_certificates', p_certificate_id::text, null, jsonb_build_object('channel', 'patient_portal', 'render_version', p_render_version));
  end if;
  return public.patient_portal_medical_certificate_detail(p_token_hash, p_certificate_id);
end;
$$;

revoke all on function public.medical_certificate_cid_catalog(text) from public, anon;
revoke all on function public.update_medical_certificate_v2(bigint, text, integer, text, text, text, bigint[], bigint[]) from public, anon;
revoke all on function public.apply_medical_certificate_ai_result(bigint, text, text, text, text, text) from public, anon;
grant execute on function public.medical_certificate_cid_catalog(text) to authenticated, service_role;
grant execute on function public.update_medical_certificate_v2(bigint, text, integer, text, text, text, bigint[], bigint[]) to authenticated, service_role;
grant execute on function public.apply_medical_certificate_ai_result(bigint, text, text, text, text, text) to authenticated, service_role;

create or replace function public.complete_consultation_ai_generation(
  p_consultation_id bigint,
  p_action_type text,
  p_request_key uuid,
  p_response_payload jsonb,
  p_model text,
  p_prompt_version text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_generation public.consultation_ai_generations;
begin
  select generation.* into v_generation
  from public.consultation_ai_generations generation
  join public.clinical_consultations consultation on consultation.id = generation.consultation_id
  where generation.consultation_id = p_consultation_id and generation.action_type = p_action_type
    and private.can_edit_consultation(v_actor, consultation.professional_id)
  for update of generation;
  if v_generation.id is null or v_generation.request_key <> p_request_key then raise exception 'Solicitação de IA inválida.' using errcode = '42501'; end if;
  if v_generation.status = 'completed' then return v_generation.response_payload; end if;
  if v_generation.status <> 'pending' or p_response_payload is null or jsonb_typeof(p_response_payload) <> 'object' then raise exception 'Resposta de IA inválida.'; end if;
  if p_model <> 'gpt-5.6-luna' or p_prompt_version <> 'consultation-assistant-v2' then raise exception 'Modelo de assistência incompatível.'; end if;
  if p_action_type = 'DIAGNOSIS_OPTIONS' and (
    jsonb_typeof(p_response_payload->'options') <> 'array'
    or jsonb_array_length(p_response_payload->'options') <> 3
    or (select array_agg(option->>'severity' order by option->>'severity') from jsonb_array_elements(p_response_payload->'options') option) <> array['grave', 'gravissimo', 'normal']::text[]
  ) then raise exception 'A IA deve retornar exatamente as opções Normal, Grave e Gravíssimo.'; end if;
  if p_action_type = 'EXAM_SUGGESTIONS' and exists (
    select 1 from jsonb_array_elements(coalesce(p_response_payload->'suggestions', '[]'::jsonb)) suggestion
    where not exists (select 1 from public.exam_types exam_type join public.exam_categories category on category.id = exam_type.category_id where exam_type.id = nullif(suggestion->>'exam_type_id', '')::bigint and exam_type.active and category.active)
  ) then raise exception 'A IA sugeriu um tipo de exame indisponível.'; end if;
  update public.consultation_ai_generations set status = 'completed', response_payload = p_response_payload, error_message = null, model = btrim(p_model), prompt_version = btrim(p_prompt_version), completed_at = now(), failed_at = null where id = v_generation.id;
  return p_response_payload;
end;
$$;

comment on table public.medical_cid10_catalog is 'Catálogo controlado de códigos CID-10 permitidos em atestados; a IA e a interface só podem selecionar códigos ativos.';
comment on index public.medical_certificates_one_per_consultation_uidx is 'Garante no máximo um atestado por consulta, inclusive quando o registro foi cancelado.';
