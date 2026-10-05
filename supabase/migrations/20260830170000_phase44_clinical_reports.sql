-- HPSM — Fase 4.4: laudos e revisão clínica avançada.
-- Reutiliza technique/findings/conclusion/result_data e o histórico de status existente.

create or replace function private.clinical_exam_report_config(p_exam_type_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_category_code text;
  v_type_code text;
  v_uses_technique boolean := true;
  v_requires_technique boolean := true;
  v_uses_findings boolean := true;
  v_requires_findings boolean := true;
  v_uses_conclusion boolean := true;
  v_requires_conclusion boolean := true;
  v_findings_label text := 'Achados';
begin
  select category.code, exam_type.code
  into v_category_code, v_type_code
  from public.exam_types exam_type
  join public.exam_categories category on category.id = exam_type.category_id
  where exam_type.id = p_exam_type_id;

  if v_category_code is null then
    raise exception 'Tipo de exame não localizado.';
  end if;

  if v_category_code = 'laboratorial' then
    v_uses_technique := false;
    v_requires_technique := false;
    v_findings_label := 'Interpretação';

    if v_type_code = 'tipagem_sanguinea' then
      v_uses_findings := false;
      v_requires_findings := false;
      v_uses_conclusion := false;
      v_requires_conclusion := false;
    end if;
  end if;

  return jsonb_build_object(
    'schema', 'hpsm.report_config.v1',
    'fields', jsonb_build_object(
      'technique', jsonb_build_object('visible', v_uses_technique, 'required', v_requires_technique, 'label', 'Técnica'),
      'findings', jsonb_build_object('visible', v_uses_findings, 'required', v_requires_findings, 'label', v_findings_label),
      'conclusion', jsonb_build_object('visible', v_uses_conclusion, 'required', v_requires_conclusion, 'label', 'Conclusão'),
      'observations', jsonb_build_object('visible', true, 'required', false, 'label', 'Observações')
    )
  );
end;
$$;

revoke all on function private.clinical_exam_report_config(bigint) from public, anon, authenticated, service_role;

create or replace function private.attach_clinical_exam_report_context(p_exam_type_id bigint, p_result_data jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_type_snapshot jsonb;
begin
  select jsonb_build_object(
    'id', exam_type.id,
    'code', exam_type.code,
    'name', exam_type.name,
    'category_id', category.id,
    'category_code', category.code,
    'category_name', category.name,
    'result_config', exam_type.result_config
  )
  into v_type_snapshot
  from public.exam_types exam_type
  join public.exam_categories category on category.id = exam_type.category_id
  where exam_type.id = p_exam_type_id;

  if v_type_snapshot is null then
    raise exception 'Tipo de exame não localizado.';
  end if;

  return coalesce(p_result_data, '{}'::jsonb) || jsonb_build_object(
    'report_config_snapshot', private.clinical_exam_report_config(p_exam_type_id),
    'exam_type_snapshot', v_type_snapshot
  );
end;
$$;

revoke all on function private.attach_clinical_exam_report_context(bigint, jsonb) from public, anon, authenticated, service_role;

alter table public.clinical_exams
  add column final_report_snapshot jsonb;

update public.clinical_exams exam
set result_data = private.attach_clinical_exam_report_context(exam.exam_type_id, exam.result_data)
where exam.result_data->>'report_config_snapshot' is null
   or exam.result_data->>'exam_type_snapshot' is null;

create table public.clinical_exam_report_versions (
  id bigint generated always as identity primary key,
  exam_id bigint not null references public.clinical_exams(id) on delete restrict,
  version_number integer not null,
  snapshot jsonb not null,
  submitted_by uuid not null references public.profiles(user_id) on delete restrict,
  submitted_at timestamptz not null default now(),
  decision text not null default 'pending',
  reviewed_by uuid references public.profiles(user_id) on delete restrict,
  reviewed_at timestamptz,
  review_reason text,
  constraint clinical_exam_report_versions_number_check check (version_number > 0),
  constraint clinical_exam_report_versions_snapshot_check check (jsonb_typeof(snapshot) = 'object'),
  constraint clinical_exam_report_versions_decision_check check (decision in ('pending', 'returned', 'approved')),
  constraint clinical_exam_report_versions_review_check check (
    (decision = 'pending' and reviewed_by is null and reviewed_at is null and review_reason is null)
    or (decision = 'returned' and reviewed_by is not null and reviewed_at is not null and review_reason is not null)
    or (decision = 'approved' and reviewed_by is not null and reviewed_at is not null and review_reason is null)
  ),
  constraint clinical_exam_report_versions_reason_check check (review_reason is null or char_length(btrim(review_reason)) between 2 and 2000),
  unique (exam_id, version_number)
);

create index clinical_exam_report_versions_exam_date_idx
  on public.clinical_exam_report_versions (exam_id, submitted_at desc, id desc);
create index clinical_exam_report_versions_pending_idx
  on public.clinical_exam_report_versions (exam_id, version_number desc)
  where decision = 'pending';
create index clinical_exam_report_versions_submitted_by_idx
  on public.clinical_exam_report_versions (submitted_by, submitted_at desc);
create index clinical_exam_report_versions_reviewed_by_idx
  on public.clinical_exam_report_versions (reviewed_by, reviewed_at desc)
  where reviewed_by is not null;

alter table public.clinical_exam_report_versions enable row level security;
alter table public.clinical_exam_report_versions force row level security;

create policy clinical_exam_report_versions_read_authorized
on public.clinical_exam_report_versions for select to authenticated
using (
  (select auth.uid()) is not null
  and private.has_permission((select auth.uid()), 'exams.view')
);

revoke all on public.clinical_exam_report_versions from public, anon, authenticated, service_role;
grant select on public.clinical_exam_report_versions to authenticated;
grant select, insert, update on public.clinical_exam_report_versions to service_role;
grant usage, select on sequence public.clinical_exam_report_versions_id_seq to service_role;

create or replace function private.build_clinical_exam_report_snapshot(p_exam_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  select jsonb_build_object(
    'schema', 'hpsm.exam_report_snapshot.v1',
    'exam', coalesce(exam.result_data->'exam_type_snapshot', jsonb_build_object(
      'id', exam_type.id,
      'code', exam_type.code,
      'name', exam_type.name,
      'category_id', category.id,
      'category_code', category.code,
      'category_name', category.name,
      'result_config', exam_type.result_config
    )),
    'patient', jsonb_build_object('id', patient.id, 'name', patient.name, 'passport', patient.passport),
    'indication', exam.indication,
    'clinical_context', exam.clinical_context,
    'report_config', coalesce(exam.result_data->'report_config_snapshot', private.clinical_exam_report_config(exam.exam_type_id)),
    'content', jsonb_build_object(
      'technique', exam.technique,
      'findings', exam.findings,
      'conclusion', exam.conclusion,
      'observations', nullif(exam.result_data->>'notes', ''),
      'result_data', exam.result_data - 'report_config_snapshot' - 'exam_type_snapshot'
    ),
    'images', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', image.id,
        'caption', image.caption,
        'mime_type', image.mime_type,
        'original_filename', image.original_filename,
        'sort_order', image.sort_order,
        'source', image.source,
        'uploaded_by', image.uploaded_by,
        'created_at', image.created_at
      ) order by image.sort_order, image.created_at, image.id)
      from public.clinical_exam_images image
      where image.exam_id = exam.id and image.removed_at is null
    ), '[]'::jsonb),
    'requested_by', jsonb_build_object('id', requester.user_id, 'name', requester.display_name, 'position', requester_position.name),
    'executed_by', jsonb_build_object('id', responsible.user_id, 'name', responsible.display_name, 'position', responsible_position.name),
    'reviewed_by', case when reviewer.user_id is null then null else jsonb_build_object('id', reviewer.user_id, 'name', reviewer.display_name, 'position', reviewer_position.name) end,
    'dates', jsonb_build_object(
      'requested_at', exam.requested_at,
      'started_at', exam.started_at,
      'submitted_for_review_at', exam.submitted_for_review_at,
      'completed_at', exam.completed_at
    )
  )
  into v_result
  from public.clinical_exams exam
  join public.patients patient on patient.id = exam.patient_id
  join public.exam_types exam_type on exam_type.id = exam.exam_type_id
  join public.exam_categories category on category.id = exam_type.category_id
  join public.profiles requester on requester.user_id = exam.requested_by
  left join public.staff_positions requester_position on requester_position.id = requester.position_id
  join public.profiles responsible on responsible.user_id = exam.responsible_professional_id
  left join public.staff_positions responsible_position on responsible_position.id = responsible.position_id
  left join public.profiles reviewer on reviewer.user_id = exam.reviewed_by
  left join public.staff_positions reviewer_position on reviewer_position.id = reviewer.position_id
  where exam.id = p_exam_id;

  if v_result is null then raise exception 'Exame não localizado.'; end if;
  return v_result;
end;
$$;

revoke all on function private.build_clinical_exam_report_snapshot(bigint) from public, anon, authenticated, service_role;

update public.clinical_exams exam
set final_report_snapshot = private.build_clinical_exam_report_snapshot(exam.id)
where exam.status = 'completed' and exam.final_report_snapshot is null;

insert into public.clinical_exam_report_versions (
  exam_id, version_number, snapshot, submitted_by, submitted_at,
  decision, reviewed_by, reviewed_at, review_reason
)
select
  exam.id,
  1,
  coalesce(exam.final_report_snapshot, private.build_clinical_exam_report_snapshot(exam.id)),
  exam.responsible_professional_id,
  coalesce(exam.submitted_for_review_at, exam.updated_at),
  case when exam.status = 'completed' then 'approved' else 'pending' end,
  case when exam.status = 'completed' then exam.reviewed_by else null end,
  case when exam.status = 'completed' then exam.completed_at else null end,
  null
from public.clinical_exams exam
where exam.status in ('awaiting_review', 'completed')
  and not exists (
    select 1 from public.clinical_exam_report_versions version where version.exam_id = exam.id
  );

alter table public.clinical_exams
  add constraint clinical_exams_final_report_snapshot_check
  check (final_report_snapshot is null or jsonb_typeof(final_report_snapshot) = 'object'),
  add constraint clinical_exams_final_report_status_check
  check (
    (status = 'completed' and final_report_snapshot is not null)
    or (status <> 'completed' and final_report_snapshot is null)
  );

create or replace function private.protect_completed_clinical_exam()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status = 'completed' then
    raise exception 'Exames concluídos são imutáveis no fluxo normal.';
  end if;
  if new.status = 'completed' and old.status <> 'awaiting_review' then
    raise exception 'A conclusão exige revisão prévia.';
  end if;
  return new;
end;
$$;

revoke all on function private.protect_completed_clinical_exam() from public, anon, authenticated, service_role;

drop trigger if exists clinical_exams_protect_completed on public.clinical_exams;
create trigger clinical_exams_protect_completed
before update of patient_id, exam_type_id, attendance_id, status, requested_by,
  responsible_professional_id, indication, clinical_context, technique, findings,
  conclusion, result_data, correction_reason, requested_at, started_at,
  submitted_for_review_at, completed_at, reviewed_by, final_report_snapshot
on public.clinical_exams
for each row execute function private.protect_completed_clinical_exam();

create or replace function public.clinical_exam_detail(p_exam_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_result jsonb;
begin
  if v_actor is null or not private.has_permission(v_actor, 'exams.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'id', exam.id,
    'patient', jsonb_build_object('id', patient.id, 'name', patient.name, 'passport', patient.passport),
    'exam_type', jsonb_build_object('id', exam_type.id, 'name', exam_type.name, 'category_id', category.id, 'category_name', category.name),
    'attendance_id', exam.attendance_id,
    'status', exam.status,
    'requested_by', jsonb_build_object('id', requester.user_id, 'name', requester.display_name, 'position', requester_position.name),
    'responsible_professional', jsonb_build_object('id', responsible.user_id, 'name', responsible.display_name, 'position', responsible_position.name),
    'reviewed_by', case when reviewer.user_id is null then null else jsonb_build_object('id', reviewer.user_id, 'name', reviewer.display_name, 'position', reviewer_position.name) end,
    'indication', exam.indication,
    'clinical_context', exam.clinical_context,
    'technique', exam.technique,
    'findings', exam.findings,
    'conclusion', exam.conclusion,
    'result_data', exam.result_data,
    'report_config', coalesce(exam.result_data->'report_config_snapshot', private.clinical_exam_report_config(exam.exam_type_id)),
    'final_report_snapshot', exam.final_report_snapshot,
    'correction_reason', exam.correction_reason,
    'requested_at', exam.requested_at,
    'started_at', exam.started_at,
    'submitted_for_review_at', exam.submitted_for_review_at,
    'completed_at', exam.completed_at,
    'created_at', exam.created_at,
    'updated_at', exam.updated_at,
    'history', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', history.id,
        'from_status', history.from_status,
        'to_status', history.to_status,
        'note', history.note,
        'changed_at', history.changed_at,
        'changed_by', jsonb_build_object('id', changer.user_id, 'name', changer.display_name, 'position', changer_position.name)
      ) order by history.changed_at, history.id)
      from public.clinical_exam_status_history history
      join public.profiles changer on changer.user_id = history.changed_by
      left join public.staff_positions changer_position on changer_position.id = changer.position_id
      where history.exam_id = exam.id
    ), '[]'::jsonb),
    'report_versions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', version.id,
        'version_number', version.version_number,
        'decision', version.decision,
        'submitted_at', version.submitted_at,
        'submitted_by', jsonb_build_object('id', submitter.user_id, 'name', submitter.display_name, 'position', submitter_position.name),
        'reviewed_at', version.reviewed_at,
        'review_reason', version.review_reason,
        'reviewed_by', case when version_reviewer.user_id is null then null else jsonb_build_object('id', version_reviewer.user_id, 'name', version_reviewer.display_name, 'position', version_reviewer_position.name) end
      ) order by version.version_number)
      from public.clinical_exam_report_versions version
      join public.profiles submitter on submitter.user_id = version.submitted_by
      left join public.staff_positions submitter_position on submitter_position.id = submitter.position_id
      left join public.profiles version_reviewer on version_reviewer.user_id = version.reviewed_by
      left join public.staff_positions version_reviewer_position on version_reviewer_position.id = version_reviewer.position_id
      where version.exam_id = exam.id
    ), '[]'::jsonb)
  ) into v_result
  from public.clinical_exams exam
  join public.patients patient on patient.id = exam.patient_id
  join public.exam_types exam_type on exam_type.id = exam.exam_type_id
  join public.exam_categories category on category.id = exam_type.category_id
  join public.profiles requester on requester.user_id = exam.requested_by
  left join public.staff_positions requester_position on requester_position.id = requester.position_id
  join public.profiles responsible on responsible.user_id = exam.responsible_professional_id
  left join public.staff_positions responsible_position on responsible_position.id = responsible.position_id
  left join public.profiles reviewer on reviewer.user_id = exam.reviewed_by
  left join public.staff_positions reviewer_position on reviewer_position.id = reviewer.position_id
  where exam.id = p_exam_id;

  if v_result is null then raise exception 'Exame não localizado.'; end if;
  return v_result;
end;
$$;

create or replace function public.create_clinical_exam(
  p_patient_id bigint,
  p_exam_type_id bigint,
  p_responsible_professional_id uuid,
  p_indication text,
  p_clinical_context text default null,
  p_attendance_id bigint default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_responsible uuid := coalesce(p_responsible_professional_id, v_actor);
  v_exam public.clinical_exams;
  v_result_data jsonb;
begin
  if v_actor is null or not private.has_permission(v_actor, 'exams.create') or not private.has_permission(v_actor, 'patients.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.patients patient where patient.id = p_patient_id) then raise exception 'Paciente não localizado.'; end if;
  if not exists (
    select 1 from public.exam_types exam_type join public.exam_categories category on category.id = exam_type.category_id
    where exam_type.id = p_exam_type_id and exam_type.active and category.active
  ) then raise exception 'Tipo de exame indisponível.'; end if;
  if not exists (select 1 from public.profiles profile where profile.user_id = v_responsible and profile.status = 'active')
     or not (private.has_permission(v_responsible, 'exams.perform') or private.has_permission(v_responsible, 'exams.review')) then
    raise exception 'Profissional responsável inválido.';
  end if;

  v_result_data := private.attach_clinical_exam_report_context(
    p_exam_type_id,
    private.build_clinical_exam_result(p_exam_type_id)
  );

  insert into public.clinical_exams (
    patient_id, exam_type_id, attendance_id, requested_by, responsible_professional_id,
    indication, clinical_context, result_data
  ) values (
    p_patient_id, p_exam_type_id, p_attendance_id, v_actor, v_responsible,
    btrim(p_indication), nullif(btrim(p_clinical_context), ''), v_result_data
  ) returning * into v_exam;

  insert into public.clinical_exam_status_history (exam_id, from_status, to_status, changed_by, note)
  values (v_exam.id, null, 'requested', v_actor, 'Exame solicitado.');
  perform private.audit_exam_action(v_actor, 'clinical_exam.created', 'clinical_exams', v_exam.id::text, null, to_jsonb(v_exam));
  return v_exam.id;
end;
$$;

create or replace function public.start_clinical_exam(p_exam_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_old public.clinical_exams;
  v_new public.clinical_exams;
  v_result_data jsonb;
begin
  select * into v_old from public.clinical_exams where id = p_exam_id for update;
  if v_old.id is null then raise exception 'Exame não localizado.'; end if;
  if not private.can_perform_clinical_exam(v_actor, v_old.responsible_professional_id) then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if v_old.status <> 'requested' then raise exception 'Este exame foi atualizado por outro profissional. Recarregue os dados para continuar.'; end if;

  v_result_data := case
    when v_old.result_data->>'schema' in ('hpsm.lab_result.v1', 'hpsm.image_result.v1') then v_old.result_data
    else private.build_clinical_exam_result(v_old.exam_type_id)
  end;
  v_result_data := private.attach_clinical_exam_report_context(v_old.exam_type_id, v_result_data);

  update public.clinical_exams
  set status = 'in_progress', started_at = now(), result_data = v_result_data
  where id = p_exam_id
  returning * into v_new;

  insert into public.clinical_exam_status_history (exam_id, from_status, to_status, changed_by, note)
  values (p_exam_id, 'requested', 'in_progress', v_actor, 'Execução iniciada.');
  perform private.audit_exam_action(v_actor, 'clinical_exam.started', 'clinical_exams', p_exam_id::text, to_jsonb(v_old), to_jsonb(v_new));
end;
$$;

create or replace function public.save_clinical_exam_draft(
  p_exam_id bigint,
  p_technique text,
  p_findings text,
  p_conclusion text,
  p_result_data jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_old public.clinical_exams;
  v_new public.clinical_exams;
  v_result_data jsonb;
begin
  select * into v_old from public.clinical_exams where id = p_exam_id for update;
  if v_old.id is null then raise exception 'Exame não localizado.'; end if;
  if not private.can_perform_clinical_exam(v_actor, v_old.responsible_professional_id) then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if v_old.status <> 'in_progress' then raise exception 'Este exame foi atualizado por outro profissional. Recarregue os dados para continuar.'; end if;
  if p_result_data is null or jsonb_typeof(p_result_data) <> 'object' then raise exception 'Dados adicionais inválidos.'; end if;

  v_result_data := case
    when v_old.result_data->>'schema' = 'hpsm.lab_result.v1' then private.normalize_lab_result(v_old.result_data, p_result_data)
    when v_old.result_data->>'schema' = 'hpsm.image_result.v1' then private.normalize_image_result(v_old.result_data, p_result_data)
    else p_result_data
  end;
  v_result_data := v_result_data || jsonb_build_object(
    'report_config_snapshot', v_old.result_data->'report_config_snapshot',
    'exam_type_snapshot', v_old.result_data->'exam_type_snapshot'
  );

  update public.clinical_exams
  set technique = nullif(btrim(p_technique), ''),
      findings = nullif(btrim(p_findings), ''),
      conclusion = nullif(btrim(p_conclusion), ''),
      result_data = v_result_data
  where id = p_exam_id
  returning * into v_new;

  if (to_jsonb(v_old) - 'updated_at') is distinct from (to_jsonb(v_new) - 'updated_at') then
    perform private.audit_exam_action(
      v_actor, 'clinical_exam.result_saved', 'clinical_exams', p_exam_id::text,
      jsonb_build_object('technique', v_old.technique, 'findings', v_old.findings, 'conclusion', v_old.conclusion, 'result_data', v_old.result_data),
      jsonb_build_object('technique', v_new.technique, 'findings', v_new.findings, 'conclusion', v_new.conclusion, 'result_data', v_new.result_data)
    );
  end if;
end;
$$;

create or replace function public.submit_clinical_exam_review(p_exam_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_old public.clinical_exams;
  v_new public.clinical_exams;
  v_missing text;
  v_missing_report text[] := array[]::text[];
  v_report_config jsonb;
  v_version integer;
  v_note text;
begin
  select * into v_old from public.clinical_exams where id = p_exam_id for update;
  if v_old.id is null then raise exception 'Exame não localizado.'; end if;
  if not private.can_perform_clinical_exam(v_actor, v_old.responsible_professional_id) then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if v_old.status <> 'in_progress' then raise exception 'Este exame foi atualizado por outro profissional. Recarregue os dados para continuar.'; end if;

  v_report_config := coalesce(v_old.result_data->'report_config_snapshot', private.clinical_exam_report_config(v_old.exam_type_id));
  if coalesce((v_report_config#>>'{fields,technique,required}')::boolean, false) and v_old.technique is null then
    v_missing_report := array_append(v_missing_report, v_report_config#>>'{fields,technique,label}');
  end if;
  if coalesce((v_report_config#>>'{fields,findings,required}')::boolean, false) and v_old.findings is null then
    v_missing_report := array_append(v_missing_report, v_report_config#>>'{fields,findings,label}');
  end if;
  if coalesce((v_report_config#>>'{fields,conclusion,required}')::boolean, false) and v_old.conclusion is null then
    v_missing_report := array_append(v_missing_report, v_report_config#>>'{fields,conclusion,label}');
  end if;
  if coalesce((v_report_config#>>'{fields,observations,required}')::boolean, false)
     and nullif(btrim(v_old.result_data->>'notes'), '') is null then
    v_missing_report := array_append(v_missing_report, v_report_config#>>'{fields,observations,label}');
  end if;
  if cardinality(v_missing_report) > 0 then
    raise exception 'Preencha os campos obrigatórios do laudo: %.', array_to_string(v_missing_report, ', ');
  end if;

  if v_old.result_data->>'schema' = 'hpsm.lab_result.v1' then
    select string_agg(snapshot->>'label', ', ' order by (snapshot->>'sort_order')::integer) into v_missing
    from jsonb_array_elements(v_old.result_data#>'{template_snapshot,parameters}') snapshot
    where (snapshot->>'active')::boolean and (snapshot->>'required')::boolean
      and not exists (
        select 1 from jsonb_array_elements(v_old.result_data->'parameters') result_parameter
        where result_parameter->>'key' = snapshot->>'key' and nullif(btrim(result_parameter->>'value'), '') is not null
      );
    if v_missing is not null then raise exception 'Preencha os parâmetros obrigatórios: %.', v_missing; end if;
  elsif v_old.result_data->>'schema' = 'hpsm.image_result.v1' then
    if (v_old.result_data#>>'{template_snapshot,region,required}')::boolean and nullif(btrim(v_old.result_data->>'region'), '') is null then
      raise exception 'Selecione a região examinada.';
    end if;
    if v_old.result_data->>'region' = 'Outra região' and nullif(btrim(v_old.result_data->>'other_region'), '') is null then
      raise exception 'Informe a outra região examinada.';
    end if;
    if (v_old.result_data#>>'{template_snapshot,supports_laterality}')::boolean and nullif(v_old.result_data->>'laterality', '') is null then
      raise exception 'Selecione a lateralidade.';
    end if;
    if (v_old.result_data#>>'{template_snapshot,supports_contrast}')::boolean and nullif(v_old.result_data->>'contrast', '') is null then
      raise exception 'Informe o uso de contraste.';
    end if;
    if (v_old.result_data#>>'{template_snapshot,requires_image}')::boolean and not exists (
      select 1 from public.clinical_exam_images image where image.exam_id = p_exam_id and image.removed_at is null
    ) then raise exception 'Adicione ao menos uma imagem antes do envio.'; end if;
  end if;

  v_note := case when exists (
    select 1 from public.clinical_exam_status_history history
    where history.exam_id = p_exam_id and history.to_status = 'awaiting_review'
  ) then 'Exame corrigido e reenviado para revisão.' else 'Exame enviado para revisão.' end;

  update public.clinical_exams
  set status = 'awaiting_review', submitted_for_review_at = now(), correction_reason = null
  where id = p_exam_id
  returning * into v_new;

  insert into public.clinical_exam_status_history (exam_id, from_status, to_status, changed_by, note)
  values (p_exam_id, 'in_progress', 'awaiting_review', v_actor, v_note);

  select coalesce(max(version.version_number), 0) + 1
  into v_version
  from public.clinical_exam_report_versions version
  where version.exam_id = p_exam_id;

  insert into public.clinical_exam_report_versions (
    exam_id, version_number, snapshot, submitted_by, submitted_at
  ) values (
    p_exam_id, v_version, private.build_clinical_exam_report_snapshot(p_exam_id), v_actor, v_new.submitted_for_review_at
  );

  perform private.audit_exam_action(v_actor, 'clinical_exam.submitted_for_review', 'clinical_exams', p_exam_id::text, to_jsonb(v_old), to_jsonb(v_new));
end;
$$;

create or replace function public.review_clinical_exam(p_exam_id bigint, p_decision text, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_old public.clinical_exams;
  v_new public.clinical_exams;
  v_version public.clinical_exam_report_versions;
  v_reviewed_at timestamptz := now();
  v_reviewer jsonb;
  v_final_snapshot jsonb;
begin
  if v_actor is null or not private.has_permission(v_actor, 'exams.review') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  select * into v_old from public.clinical_exams where id = p_exam_id for update;
  if v_old.id is null then raise exception 'Exame não localizado.'; end if;
  if v_old.status <> 'awaiting_review' then
    raise exception 'Este exame foi atualizado por outro profissional. Recarregue os dados para continuar.';
  end if;

  select * into v_version
  from public.clinical_exam_report_versions version
  where version.exam_id = p_exam_id and version.decision = 'pending'
  order by version.version_number desc
  limit 1
  for update;

  if v_version.id is null then
    insert into public.clinical_exam_report_versions (
      exam_id, version_number, snapshot, submitted_by, submitted_at
    ) values (
      p_exam_id,
      coalesce((select max(version.version_number) + 1 from public.clinical_exam_report_versions version where version.exam_id = p_exam_id), 1),
      private.build_clinical_exam_report_snapshot(p_exam_id),
      v_old.responsible_professional_id,
      coalesce(v_old.submitted_for_review_at, v_old.updated_at)
    ) returning * into v_version;
  end if;

  select jsonb_build_object('id', reviewer.user_id, 'name', reviewer.display_name, 'position', position.name)
  into v_reviewer
  from public.profiles reviewer
  left join public.staff_positions position on position.id = reviewer.position_id
  where reviewer.user_id = v_actor;

  if p_decision = 'approve' then
    v_final_snapshot := v_version.snapshot || jsonb_build_object(
      'reviewed_by', v_reviewer,
      'dates', coalesce(v_version.snapshot->'dates', '{}'::jsonb) || jsonb_build_object('completed_at', v_reviewed_at)
    );

    update public.clinical_exam_report_versions
    set decision = 'approved', reviewed_by = v_actor, reviewed_at = v_reviewed_at
    where id = v_version.id;

    update public.clinical_exams
    set status = 'completed', reviewed_by = v_actor, completed_at = v_reviewed_at,
        correction_reason = null, final_report_snapshot = v_final_snapshot
    where id = p_exam_id
    returning * into v_new;

    insert into public.clinical_exam_status_history (exam_id, from_status, to_status, changed_by, note)
    values (p_exam_id, 'awaiting_review', 'completed', v_actor, 'Laudo revisado, aprovado e concluído.');
    perform private.audit_exam_action(v_actor, 'clinical_exam.completed', 'clinical_exams', p_exam_id::text, to_jsonb(v_old), to_jsonb(v_new));
  elsif p_decision = 'return' then
    if nullif(btrim(p_reason), '') is null or char_length(btrim(p_reason)) < 2 then
      raise exception 'Informe o motivo da correção.';
    end if;

    update public.clinical_exam_report_versions
    set decision = 'returned', reviewed_by = v_actor, reviewed_at = v_reviewed_at, review_reason = btrim(p_reason)
    where id = v_version.id;

    update public.clinical_exams
    set status = 'in_progress', submitted_for_review_at = null, reviewed_by = null,
        completed_at = null, correction_reason = btrim(p_reason), final_report_snapshot = null
    where id = p_exam_id
    returning * into v_new;

    insert into public.clinical_exam_status_history (exam_id, from_status, to_status, changed_by, note)
    values (p_exam_id, 'awaiting_review', 'in_progress', v_actor, btrim(p_reason));
    perform private.audit_exam_action(v_actor, 'clinical_exam.returned_for_correction', 'clinical_exams', p_exam_id::text, to_jsonb(v_old), to_jsonb(v_new));
  else
    raise exception 'Decisão de revisão inválida.';
  end if;
end;
$$;

revoke all on function public.clinical_exam_detail(bigint) from public, anon, authenticated;
revoke all on function public.create_clinical_exam(bigint, bigint, uuid, text, text, bigint) from public, anon, authenticated;
revoke all on function public.start_clinical_exam(bigint) from public, anon, authenticated;
revoke all on function public.save_clinical_exam_draft(bigint, text, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.submit_clinical_exam_review(bigint) from public, anon, authenticated;
revoke all on function public.review_clinical_exam(bigint, text, text) from public, anon, authenticated;

grant execute on function public.clinical_exam_detail(bigint) to authenticated;
grant execute on function public.create_clinical_exam(bigint, bigint, uuid, text, text, bigint) to authenticated;
grant execute on function public.start_clinical_exam(bigint) to authenticated;
grant execute on function public.save_clinical_exam_draft(bigint, text, text, text, jsonb) to authenticated;
grant execute on function public.submit_clinical_exam_review(bigint) to authenticated;
grant execute on function public.review_clinical_exam(bigint, text, text) to authenticated;

comment on table public.clinical_exam_report_versions is 'Snapshots imutáveis de cada envio do laudo para revisão e sua decisão.';
comment on column public.clinical_exams.final_report_snapshot is 'Snapshot final do laudo efetivamente aprovado, preservando conteúdo, autoria e contexto clínico.';
comment on function private.clinical_exam_report_config(bigint) is 'Configuração condicional e versionável dos campos de laudo por tipo/categoria.';
