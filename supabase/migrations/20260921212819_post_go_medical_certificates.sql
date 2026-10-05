-- HPSM · Pós-GO · Atestados Médicos em PNG
-- Módulo clínico independente do financeiro, com atendimento obrigatório e documento final imutável.

insert into public.system_permissions (code, module, label, description, sort_order) values
  ('atestados.view', 'Atestados Médicos', 'Visualizar atestados', 'Consulta atestados médicos autorizados e seus documentos finais.', 34),
  ('atestados.create', 'Atestados Médicos', 'Criar atestados', 'Cria e edita rascunhos próprios de atestados médicos.', 35),
  ('atestados.finalize', 'Atestados Médicos', 'Finalizar atestados', 'Finaliza atestados próprios após revisão humana.', 36),
  ('atestados.cancel', 'Atestados Médicos', 'Cancelar atestados', 'Cancela atestados finalizados sem apagar o histórico.', 37)
on conflict (code) do update set
  module = excluded.module,
  label = excluded.label,
  description = excluded.description,
  sort_order = excluded.sort_order;

with grants(permission_code, min_level) as (
  values
    ('atestados.view', 1),
    ('atestados.create', 1),
    ('atestados.finalize', 1),
    ('atestados.cancel', 11)
)
insert into public.staff_position_permissions (position_id, permission_code, granted_by)
select
  position.id,
  grant_row.permission_code,
  coalesce(
    (select profile.user_id from public.profiles profile where profile.role_code = 'diretor_geral' limit 1),
    position.updated_by,
    position.created_by
  )
from public.staff_positions position
join grants grant_row on position.level >= grant_row.min_level
where position.official and position.active
on conflict (position_id, permission_code) do nothing;

create table public.medical_certificates (
  id bigint generated always as identity primary key,
  patient_id bigint not null references public.patients(id) on delete restrict,
  attendance_id bigint not null references public.attendances(id) on delete restrict,
  created_by uuid not null references public.profiles(user_id) on delete restrict,
  medical_context text not null,
  leave_days integer not null,
  generated_text text,
  final_text text,
  status text not null default 'draft',
  ai_model text,
  ai_prompt_version text,
  ai_generated_at timestamptz,
  finalized_at timestamptz,
  finalized_by uuid references public.profiles(user_id) on delete restrict,
  professional_snapshot jsonb,
  final_png_path text,
  final_png_file_size integer,
  final_png_width integer,
  final_png_height integer,
  final_png_render_version text,
  cancelled_at timestamptz,
  cancelled_by uuid references public.profiles(user_id) on delete restrict,
  cancellation_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint medical_certificates_context_check check (char_length(btrim(medical_context)) between 3 and 4000),
  constraint medical_certificates_leave_days_check check (leave_days between 1 and 365),
  constraint medical_certificates_generated_text_check check (generated_text is null or char_length(btrim(generated_text)) between 20 and 4000),
  constraint medical_certificates_final_text_check check (final_text is null or char_length(btrim(final_text)) between 20 and 4000),
  constraint medical_certificates_status_check check (status in ('draft', 'finalized', 'cancelled')),
  constraint medical_certificates_ai_fields_check check (
    (ai_generated_at is null and ai_model is null and ai_prompt_version is null)
    or (ai_generated_at is not null and ai_model is not null and ai_prompt_version is not null and generated_text is not null)
  ),
  constraint medical_certificates_document_fields_check check (
    (final_png_path is null and final_png_file_size is null and final_png_width is null and final_png_height is null and final_png_render_version is null)
    or (
      final_png_path is not null
      and final_png_file_size between 32 and 12582912
      and final_png_width between 900 and 1400
      and final_png_height between 400 and 14000
      and final_png_render_version is not null
    )
  ),
  constraint medical_certificates_state_check check (
    (
      status = 'draft'
      and finalized_at is null and finalized_by is null and professional_snapshot is null
      and cancelled_at is null and cancelled_by is null and cancellation_reason is null
      and final_png_path is null
    )
    or (
      status = 'finalized'
      and final_text is not null and finalized_at is not null and finalized_by is not null and professional_snapshot is not null
      and cancelled_at is null and cancelled_by is null and cancellation_reason is null
    )
    or (
      status = 'cancelled'
      and final_text is not null and finalized_at is not null and finalized_by is not null and professional_snapshot is not null
      and cancelled_at is not null and cancelled_by is not null and cancellation_reason is not null
    )
  )
);

create table public.medical_certificate_exams (
  certificate_id bigint not null references public.medical_certificates(id) on delete cascade,
  exam_id bigint not null references public.clinical_exams(id) on delete restrict,
  linked_by uuid not null references public.profiles(user_id) on delete restrict,
  linked_at timestamptz not null default now(),
  primary key (certificate_id, exam_id)
);

create table public.medical_certificate_casts (
  certificate_id bigint not null references public.medical_certificates(id) on delete cascade,
  cast_id bigint not null references public.clinical_casts(id) on delete restrict,
  linked_by uuid not null references public.profiles(user_id) on delete restrict,
  linked_at timestamptz not null default now(),
  primary key (certificate_id, cast_id)
);

create index medical_certificates_patient_created_idx on public.medical_certificates (patient_id, created_at desc, id desc);
create index medical_certificates_attendance_idx on public.medical_certificates (attendance_id);
create index medical_certificates_created_by_idx on public.medical_certificates (created_by, created_at desc, id desc);
create index medical_certificates_status_created_idx on public.medical_certificates (status, created_at desc, id desc);
create index medical_certificate_exams_exam_idx on public.medical_certificate_exams (exam_id, certificate_id);
create index medical_certificate_casts_cast_idx on public.medical_certificate_casts (cast_id, certificate_id);

create trigger medical_certificates_touch_updated_at
before update on public.medical_certificates
for each row execute function private.touch_updated_at();

create or replace function private.validate_medical_certificate_link()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.attendances attendance
    where attendance.id = new.attendance_id
      and attendance.patient_id = new.patient_id
      and attendance.status = 'completed'
  ) then
    raise exception 'O atendimento informado não pertence ao paciente ou não está concluído.';
  end if;
  return new;
end;
$$;

create trigger medical_certificates_validate_link
before insert or update of patient_id, attendance_id on public.medical_certificates
for each row execute function private.validate_medical_certificate_link();

create or replace function private.validate_medical_certificate_exam_link()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.medical_certificates certificate
    join public.clinical_exams exam on exam.id = new.exam_id
    where certificate.id = new.certificate_id
      and certificate.patient_id = exam.patient_id
      and certificate.status = 'draft'
  ) then
    raise exception 'O exame não pertence ao paciente do atestado ou o atestado não aceita alterações.';
  end if;
  return new;
end;
$$;

create trigger medical_certificate_exams_validate_link
before insert or update on public.medical_certificate_exams
for each row execute function private.validate_medical_certificate_exam_link();

create or replace function private.validate_medical_certificate_cast_link()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.medical_certificates certificate
    join public.clinical_casts cast_record on cast_record.id = new.cast_id
    where certificate.id = new.certificate_id
      and certificate.patient_id = cast_record.patient_id
      and certificate.status = 'draft'
  ) then
    raise exception 'O registro de gesso não pertence ao paciente do atestado ou o atestado não aceita alterações.';
  end if;
  return new;
end;
$$;

create trigger medical_certificate_casts_validate_link
before insert or update on public.medical_certificate_casts
for each row execute function private.validate_medical_certificate_cast_link();

alter table public.medical_certificates enable row level security;
alter table public.medical_certificates force row level security;
alter table public.medical_certificate_exams enable row level security;
alter table public.medical_certificate_exams force row level security;
alter table public.medical_certificate_casts enable row level security;
alter table public.medical_certificate_casts force row level security;

create policy medical_certificates_read_authorized
on public.medical_certificates for select to authenticated
using ((select private.has_permission((select auth.uid()), 'atestados.view')));

create policy medical_certificate_exams_read_authorized
on public.medical_certificate_exams for select to authenticated
using ((select private.has_permission((select auth.uid()), 'atestados.view')));

create policy medical_certificate_casts_read_authorized
on public.medical_certificate_casts for select to authenticated
using ((select private.has_permission((select auth.uid()), 'atestados.view')));

create policy phase_post_go_medical_certificates_valid_session
on public.medical_certificates as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase_post_go_medical_certificate_exams_valid_session
on public.medical_certificate_exams as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase_post_go_medical_certificate_casts_valid_session
on public.medical_certificate_casts as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

revoke all on public.medical_certificates, public.medical_certificate_exams, public.medical_certificate_casts
from public, anon, authenticated, service_role;
grant select on public.medical_certificates, public.medical_certificate_exams, public.medical_certificate_casts to authenticated;
grant select, insert, update on public.medical_certificates, public.medical_certificate_exams, public.medical_certificate_casts to service_role;
grant delete on public.medical_certificate_exams, public.medical_certificate_casts to service_role;
grant usage, select on sequence public.medical_certificates_id_seq to service_role;

revoke all on function private.validate_medical_certificate_link() from public, anon, authenticated, service_role;
revoke all on function private.validate_medical_certificate_exam_link() from public, anon, authenticated, service_role;
revoke all on function private.validate_medical_certificate_cast_link() from public, anon, authenticated, service_role;

create or replace function private.medical_certificate_text_matches_days(p_text text, p_leave_days integer)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_match text[];
  v_count integer := 0;
begin
  if p_text is null or char_length(btrim(p_text)) not between 20 and 4000 or p_leave_days not between 1 and 365 then
    return false;
  end if;
  if lower(p_text) ~ '(inteligência artificial|inteligencia artificial|gerado por ia|gta[[:space:]-]*rp|role[[:space:]-]*play|fictíci|fictici|simulaç|simulac|personagem|videogame|video game)' then
    return false;
  end if;
  for v_match in select regexp_matches(p_text, '([0-9]{1,3})[[:space:]]+dias?', 'gi') loop
    v_count := v_count + 1;
    if v_match[1]::integer <> p_leave_days then return false; end if;
  end loop;
  return v_count > 0;
end;
$$;

revoke all on function private.medical_certificate_text_matches_days(text, integer)
from public, anon, authenticated, service_role;

create or replace function private.audit_medical_certificate_action(
  p_actor_id uuid,
  p_action text,
  p_certificate_id bigint,
  p_old_values jsonb,
  p_new_values jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_passport text;
begin
  if p_actor_id is null then raise exception 'Ação sem profissional autenticado.'; end if;
  select profile.passport into v_passport
  from public.profiles profile
  where profile.user_id = p_actor_id and profile.status = 'active';
  if v_passport is null then raise exception 'Profissional não autorizado.'; end if;
  insert into public.audit_logs (actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values)
  values (p_actor_id, v_passport, p_action, 'medical_certificates', p_certificate_id::text, p_old_values, p_new_values);
end;
$$;

revoke all on function private.audit_medical_certificate_action(uuid, text, bigint, jsonb, jsonb)
from public, anon, authenticated, service_role;

create or replace function private.set_medical_certificate_links(
  p_certificate_id bigint,
  p_patient_id bigint,
  p_actor uuid,
  p_exam_ids bigint[],
  p_cast_ids bigint[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_exam_ids bigint[] := coalesce(p_exam_ids, '{}'::bigint[]);
  v_cast_ids bigint[] := coalesce(p_cast_ids, '{}'::bigint[]);
begin
  if cardinality(v_exam_ids) > 50 or cardinality(v_cast_ids) > 50 then
    raise exception 'A quantidade de vínculos excede o limite permitido.';
  end if;
  if cardinality(v_exam_ids) > 0 then
    if not private.has_permission(p_actor, 'exams.view') then raise exception 'Acesso aos exames não autorizado.' using errcode = '42501'; end if;
    if exists (
      select 1 from unnest(v_exam_ids) selected(id)
      left join public.clinical_exams exam on exam.id = selected.id and exam.patient_id = p_patient_id
      where exam.id is null
    ) then raise exception 'Um dos exames selecionados não pertence ao paciente.'; end if;
  end if;
  if cardinality(v_cast_ids) > 0 then
    if not private.has_permission(p_actor, 'casts.view') then raise exception 'Acesso aos gessos não autorizado.' using errcode = '42501'; end if;
    if exists (
      select 1 from unnest(v_cast_ids) selected(id)
      left join public.clinical_casts cast_record on cast_record.id = selected.id and cast_record.patient_id = p_patient_id
      where cast_record.id is null
    ) then raise exception 'Um dos registros de gesso selecionados não pertence ao paciente.'; end if;
  end if;

  delete from public.medical_certificate_exams where certificate_id = p_certificate_id;
  insert into public.medical_certificate_exams (certificate_id, exam_id, linked_by)
  select p_certificate_id, selected.id, p_actor from (select distinct unnest(v_exam_ids) id) selected;

  delete from public.medical_certificate_casts where certificate_id = p_certificate_id;
  insert into public.medical_certificate_casts (certificate_id, cast_id, linked_by)
  select p_certificate_id, selected.id, p_actor from (select distinct unnest(v_cast_ids) id) selected;
end;
$$;

revoke all on function private.set_medical_certificate_links(bigint, bigint, uuid, bigint[], bigint[])
from public, anon, authenticated, service_role;

create or replace function public.medical_certificate_page(
  p_search text default null,
  p_status text default null,
  p_date_from date default null,
  p_date_to date default null,
  p_created_by uuid default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
begin
  if not private.has_permission(v_actor, 'atestados.view') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if p_status is not null and p_status not in ('draft', 'finalized', 'cancelled') then raise exception 'Status de atestado inválido.'; end if;
  if p_date_from is not null and p_date_to is not null and p_date_from > p_date_to then raise exception 'Período inválido.'; end if;

  return (
    with filtered as (
      select certificate.id, certificate.patient_id, patient.name patient_name, patient.passport patient_passport,
        certificate.attendance_id, certificate.leave_days, certificate.status, certificate.created_by,
        creator.display_name professional_name, position.name professional_position,
        certificate.created_at, certificate.finalized_at, certificate.cancelled_at,
        (certificate.final_png_path is not null) document_ready
      from public.medical_certificates certificate
      join public.patients patient on patient.id = certificate.patient_id
      join public.profiles creator on creator.user_id = certificate.created_by
      left join public.staff_positions position on position.id = creator.position_id
      where (p_status is null or certificate.status = p_status)
        and (p_created_by is null or certificate.created_by = p_created_by)
        and (p_date_from is null or certificate.created_at >= p_date_from::timestamptz)
        and (p_date_to is null or certificate.created_at < (p_date_to + 1)::timestamptz)
        and (
          nullif(btrim(p_search), '') is null
          or patient.name ilike '%' || btrim(p_search) || '%'
          or patient.passport ilike btrim(p_search) || '%'
          or certificate.id::text = btrim(p_search)
        )
    ), page_rows as (
      select * from filtered order by created_at desc, id desc limit v_limit offset v_offset
    )
    select jsonb_build_object(
      'items', coalesce((select jsonb_agg(to_jsonb(page_rows) order by created_at desc, id desc) from page_rows), '[]'::jsonb),
      'total', (select count(*)::integer from filtered)
    )
  );
end;
$$;

create or replace function public.medical_certificate_detail(p_certificate_id bigint)
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
  if not private.has_permission(v_actor, 'atestados.view') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  select jsonb_build_object(
    'id', certificate.id,
    'patient_id', certificate.patient_id,
    'patient_name', patient.name,
    'patient_passport', patient.passport,
    'attendance_id', certificate.attendance_id,
    'attendance_created_at', attendance.created_at,
    'attendance_summary', coalesce((select string_agg(item.service_name || case when item.quantity > 1 then ' ×' || item.quantity::text else '' end, ', ' order by item.id) from public.attendance_items item where item.attendance_id = attendance.id), 'Atendimento sem itens'),
    'created_by', certificate.created_by,
    'professional_name', creator.display_name,
    'professional_position', position.name,
    'medical_context', certificate.medical_context,
    'leave_days', certificate.leave_days,
    'generated_text', certificate.generated_text,
    'final_text', certificate.final_text,
    'status', certificate.status,
    'ai_model', certificate.ai_model,
    'ai_prompt_version', certificate.ai_prompt_version,
    'ai_generated_at', certificate.ai_generated_at,
    'finalized_at', certificate.finalized_at,
    'professional_snapshot', certificate.professional_snapshot,
    'document_ready', certificate.final_png_path is not null,
    'cancelled_at', certificate.cancelled_at,
    'cancellation_reason', certificate.cancellation_reason,
    'created_at', certificate.created_at,
    'updated_at', certificate.updated_at,
    'exams', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', exam.id, 'type', exam_type.name, 'status', exam.status,
        'requested_at', exam.requested_at, 'completed_at', exam.completed_at
      ) order by exam.requested_at desc, exam.id desc)
      from public.medical_certificate_exams link
      join public.clinical_exams exam on exam.id = link.exam_id
      join public.exam_types exam_type on exam_type.id = exam.exam_type_id
      where link.certificate_id = certificate.id
    ), '[]'::jsonb),
    'casts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', cast_record.id, 'body_region', cast_record.body_region, 'laterality', cast_record.laterality,
        'status', cast_record.status, 'applied_at', cast_record.applied_at
      ) order by cast_record.applied_at desc, cast_record.id desc)
      from public.medical_certificate_casts link
      join public.clinical_casts cast_record on cast_record.id = link.cast_id
      where link.certificate_id = certificate.id
    ), '[]'::jsonb)
  ) into v_result
  from public.medical_certificates certificate
  join public.patients patient on patient.id = certificate.patient_id
  join public.attendances attendance on attendance.id = certificate.attendance_id
  join public.profiles creator on creator.user_id = certificate.created_by
  left join public.staff_positions position on position.id = creator.position_id
  where certificate.id = p_certificate_id;
  if v_result is null then raise exception 'Atestado não localizado.'; end if;
  return v_result;
end;
$$;

create or replace function public.medical_certificate_reference_options(p_patient_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
begin
  if not private.has_permission(v_actor, 'atestados.create') or not private.has_permission(v_actor, 'patients.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.patients patient where patient.id = p_patient_id) then raise exception 'Paciente não localizado.'; end if;
  return jsonb_build_object(
    'attendances', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', attendance.id, 'created_at', attendance.created_at, 'professional_name', profile.display_name,
        'summary', coalesce((select string_agg(item.service_name || case when item.quantity > 1 then ' ×' || item.quantity::text else '' end, ', ' order by item.id) from public.attendance_items item where item.attendance_id = attendance.id), 'Atendimento sem itens')
      ) order by attendance.created_at desc, attendance.id desc)
      from (select * from public.attendances where patient_id = p_patient_id and status = 'completed' order by created_at desc, id desc limit 50) attendance
      join public.profiles profile on profile.user_id = attendance.performed_by
    ), '[]'::jsonb),
    'exams', case when private.has_permission(v_actor, 'exams.view') then coalesce((
      select jsonb_agg(jsonb_build_object('id', exam.id, 'type', exam_type.name, 'status', exam.status, 'requested_at', exam.requested_at, 'attendance_id', exam.attendance_id) order by exam.requested_at desc, exam.id desc)
      from (select * from public.clinical_exams where patient_id = p_patient_id order by requested_at desc, id desc limit 50) exam
      join public.exam_types exam_type on exam_type.id = exam.exam_type_id
    ), '[]'::jsonb) else '[]'::jsonb end,
    'casts', case when private.has_permission(v_actor, 'casts.view') then coalesce((
      select jsonb_agg(jsonb_build_object('id', cast_record.id, 'body_region', cast_record.body_region, 'laterality', cast_record.laterality, 'status', cast_record.status, 'applied_at', cast_record.applied_at, 'attendance_id', cast_record.attendance_id) order by cast_record.applied_at desc, cast_record.id desc)
      from (select * from public.clinical_casts where patient_id = p_patient_id order by applied_at desc, id desc limit 50) cast_record
    ), '[]'::jsonb) else '[]'::jsonb end
  );
end;
$$;

create or replace function public.create_medical_certificate(
  p_patient_id bigint,
  p_attendance_id bigint,
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
  v_context text := btrim(coalesce(p_medical_context, ''));
  v_certificate public.medical_certificates;
begin
  if not private.has_permission(v_actor, 'atestados.create') or not private.has_permission(v_actor, 'patients.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if char_length(v_context) not between 3 and 4000 then raise exception 'Informe o motivo e o contexto médico.'; end if;
  if p_leave_days is null or p_leave_days not between 1 and 365 then raise exception 'Informe uma quantidade inteira e positiva de dias.'; end if;
  if not exists (select 1 from public.patients patient where patient.id = p_patient_id) then raise exception 'Paciente não localizado.'; end if;
  if not exists (select 1 from public.attendances attendance where attendance.id = p_attendance_id and attendance.patient_id = p_patient_id and attendance.status = 'completed') then
    raise exception 'O atendimento informado não pertence ao paciente ou não está concluído.';
  end if;
  insert into public.medical_certificates (patient_id, attendance_id, created_by, medical_context, leave_days)
  values (p_patient_id, p_attendance_id, v_actor, v_context, p_leave_days)
  returning * into v_certificate;
  perform private.set_medical_certificate_links(v_certificate.id, p_patient_id, v_actor, p_exam_ids, p_cast_ids);
  perform private.audit_medical_certificate_action(v_actor, 'MEDICAL_CERTIFICATE_CREATED', v_certificate.id, null, jsonb_build_object(
    'patient_id', p_patient_id, 'attendance_id', p_attendance_id, 'leave_days', p_leave_days,
    'exam_ids', coalesce(p_exam_ids, '{}'::bigint[]), 'cast_ids', coalesce(p_cast_ids, '{}'::bigint[]), 'status', 'draft'
  ));
  return v_certificate.id;
end;
$$;

create or replace function public.update_medical_certificate(
  p_certificate_id bigint,
  p_medical_context text,
  p_leave_days integer,
  p_final_text text,
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
begin
  if not private.has_permission(v_actor, 'atestados.create') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  select * into v_old from public.medical_certificates where id = p_certificate_id for update;
  if v_old.id is null then raise exception 'Atestado não localizado.'; end if;
  if v_old.status <> 'draft' then raise exception 'Somente rascunhos podem ser editados.'; end if;
  if v_old.created_by <> v_actor then raise exception 'Somente o responsável pode editar este atestado.' using errcode = '42501'; end if;
  if char_length(v_context) not between 3 and 4000 then raise exception 'Informe o motivo e o contexto médico.'; end if;
  if p_leave_days is null or p_leave_days not between 1 and 365 then raise exception 'Informe uma quantidade inteira e positiva de dias.'; end if;
  if v_text is not null and not private.medical_certificate_text_matches_days(v_text, p_leave_days) then
    raise exception 'O texto precisa mencionar exatamente % dias e não pode conter outro período divergente.', p_leave_days;
  end if;
  update public.medical_certificates set medical_context = v_context, leave_days = p_leave_days, final_text = v_text where id = p_certificate_id;
  perform private.set_medical_certificate_links(p_certificate_id, v_old.patient_id, v_actor, p_exam_ids, p_cast_ids);
  perform private.audit_medical_certificate_action(v_actor, 'MEDICAL_CERTIFICATE_UPDATED', p_certificate_id,
    jsonb_build_object('leave_days', v_old.leave_days, 'medical_context', v_old.medical_context),
    jsonb_build_object('leave_days', p_leave_days, 'medical_context', v_context, 'has_final_text', v_text is not null, 'exam_ids', coalesce(p_exam_ids, '{}'::bigint[]), 'cast_ids', coalesce(p_cast_ids, '{}'::bigint[]))
  );
end;
$$;

create or replace function public.medical_certificate_ai_context(p_certificate_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_certificate public.medical_certificates;
begin
  if not private.has_permission(v_actor, 'atestados.create') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  select * into v_certificate from public.medical_certificates where id = p_certificate_id;
  if v_certificate.id is null then raise exception 'Atestado não localizado.'; end if;
  if v_certificate.status <> 'draft' or v_certificate.created_by <> v_actor then raise exception 'Este atestado não aceita geração de texto.' using errcode = '42501'; end if;
  return jsonb_build_object(
    'certificate_id', v_certificate.id,
    'actor_id', v_actor,
    'medical_context', v_certificate.medical_context,
    'leave_days', v_certificate.leave_days,
    'exams', coalesce((
      select jsonb_agg(jsonb_build_object('type', exam_type.name, 'status', exam.status, 'conclusion', case when exam.status = 'completed' then exam.conclusion else null end) order by exam.requested_at desc)
      from public.medical_certificate_exams link join public.clinical_exams exam on exam.id = link.exam_id join public.exam_types exam_type on exam_type.id = exam.exam_type_id
      where link.certificate_id = v_certificate.id
    ), '[]'::jsonb),
    'casts', coalesce((
      select jsonb_agg(jsonb_build_object('body_region', cast_record.body_region, 'laterality', cast_record.laterality, 'status', cast_record.status, 'applied_at', cast_record.applied_at) order by cast_record.applied_at desc)
      from public.medical_certificate_casts link join public.clinical_casts cast_record on cast_record.id = link.cast_id
      where link.certificate_id = v_certificate.id
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.apply_medical_certificate_ai_text(
  p_certificate_id bigint,
  p_text text,
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
begin
  if not private.has_permission(v_actor, 'atestados.create') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  select * into v_certificate from public.medical_certificates where id = p_certificate_id for update;
  if v_certificate.id is null then raise exception 'Atestado não localizado.'; end if;
  if v_certificate.status <> 'draft' or v_certificate.created_by <> v_actor then raise exception 'Este atestado não aceita geração de texto.' using errcode = '42501'; end if;
  if p_model <> 'gpt-5.6-luna' or p_prompt_version <> 'medical-certificate-v1' then raise exception 'Modelo de assistência incompatível.'; end if;
  if not private.medical_certificate_text_matches_days(v_text, v_certificate.leave_days) then
    raise exception 'A sugestão não preservou exatamente os dias informados. Nada foi alterado.';
  end if;
  update public.medical_certificates set generated_text = v_text, final_text = v_text, ai_model = p_model, ai_prompt_version = p_prompt_version, ai_generated_at = now() where id = p_certificate_id;
  perform private.audit_medical_certificate_action(v_actor, 'MEDICAL_CERTIFICATE_AI_GENERATED', p_certificate_id, null,
    jsonb_build_object('model', p_model, 'prompt_version', p_prompt_version, 'leave_days', v_certificate.leave_days));
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
begin
  if not private.has_permission(v_actor, 'atestados.finalize') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  select * into v_certificate from public.medical_certificates where id = p_certificate_id for update;
  if v_certificate.id is null then raise exception 'Atestado não localizado.'; end if;
  if v_certificate.status <> 'draft' then raise exception 'Este atestado já foi finalizado ou cancelado.'; end if;
  if v_certificate.created_by <> v_actor then raise exception 'Somente o responsável pode finalizar este atestado.' using errcode = '42501'; end if;
  if not private.medical_certificate_text_matches_days(v_text, v_certificate.leave_days) then
    raise exception 'O texto final precisa mencionar exatamente % dias e não pode conter outro período divergente.', v_certificate.leave_days;
  end if;
  select jsonb_build_object(
    'schema', 'hpsm.medical_certificate_snapshot.v1',
    'certificate_id', v_certificate.id,
    'patient', jsonb_build_object('id', patient.id, 'name', patient.name, 'passport', patient.passport),
    'attendance', jsonb_build_object('id', attendance.id, 'created_at', attendance.created_at),
    'leave_days', v_certificate.leave_days,
    'text', v_text,
    'issued_at', now(),
    'professional', jsonb_build_object(
      'id', profile.user_id,
      'name', profile.display_name,
      'position', position.name,
      'crm_code', identity.crm_code,
      'registration_date', identity.registration_date,
      'signature_image_path', identity.signature_image_path
    )
  ) into v_snapshot
  from public.patients patient
  join public.attendances attendance on attendance.id = v_certificate.attendance_id and attendance.patient_id = patient.id
  join public.profiles profile on profile.user_id = v_actor and profile.status = 'active'
  left join public.staff_positions position on position.id = profile.position_id
  join public.professional_identities identity on identity.user_id = profile.user_id
    and identity.status = 'active' and identity.signature_image_path is not null and identity.crm_code ~ '^[0-9]{8}$'
  where patient.id = v_certificate.patient_id;
  if v_snapshot is null then raise exception 'A identidade profissional precisa estar ativa antes da finalização.'; end if;
  update public.medical_certificates set status = 'finalized', final_text = v_text, finalized_at = now(), finalized_by = v_actor, professional_snapshot = v_snapshot where id = p_certificate_id;
  perform private.audit_medical_certificate_action(v_actor, 'MEDICAL_CERTIFICATE_FINALIZED', p_certificate_id,
    jsonb_build_object('status', 'draft'), jsonb_build_object('status', 'finalized', 'leave_days', v_certificate.leave_days, 'snapshot_schema', v_snapshot->>'schema'));
  return v_snapshot;
end;
$$;

create or replace function public.cancel_medical_certificate(p_certificate_id bigint, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_certificate public.medical_certificates;
  v_reason text := btrim(coalesce(p_reason, ''));
begin
  if not private.has_permission(v_actor, 'atestados.cancel') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if char_length(v_reason) not between 5 and 500 then raise exception 'Informe o motivo do cancelamento.'; end if;
  select * into v_certificate from public.medical_certificates where id = p_certificate_id for update;
  if v_certificate.id is null then raise exception 'Atestado não localizado.'; end if;
  if v_certificate.status <> 'finalized' then raise exception 'Somente um atestado finalizado pode ser cancelado.'; end if;
  update public.medical_certificates set status = 'cancelled', cancelled_at = now(), cancelled_by = v_actor, cancellation_reason = v_reason where id = p_certificate_id;
  perform private.audit_medical_certificate_action(v_actor, 'MEDICAL_CERTIFICATE_CANCELLED', p_certificate_id,
    jsonb_build_object('status', 'finalized'), jsonb_build_object('status', 'cancelled', 'reason', v_reason));
end;
$$;

create or replace function public.medical_certificate_document_state(p_certificate_id bigint)
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
  if not private.has_permission(v_actor, 'atestados.view') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  select jsonb_build_object(
    'id', certificate.id, 'status', certificate.status, 'snapshot', certificate.professional_snapshot,
    'document', case when certificate.final_png_path is null then null else jsonb_build_object(
      'path', certificate.final_png_path, 'file_size', certificate.final_png_file_size,
      'width', certificate.final_png_width, 'height', certificate.final_png_height,
      'render_version', certificate.final_png_render_version
    ) end
  ) into v_result from public.medical_certificates certificate where certificate.id = p_certificate_id;
  if v_result is null then raise exception 'Atestado não localizado.'; end if;
  return v_result;
end;
$$;

create or replace function public.register_medical_certificate_document(
  p_certificate_id bigint,
  p_storage_path text,
  p_file_size integer,
  p_width integer,
  p_height integer,
  p_render_version text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_certificate public.medical_certificates;
begin
  if not private.has_permission(v_actor, 'atestados.view') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  select * into v_certificate from public.medical_certificates where id = p_certificate_id for update;
  if v_certificate.id is null then raise exception 'Atestado não localizado.'; end if;
  if v_certificate.status <> 'finalized' then raise exception 'O documento está disponível somente para atestados finalizados.'; end if;
  if p_storage_path !~ ('^medical-certificates/' || p_certificate_id::text || '/documents/[0-9a-f-]{36}\\.png$') then raise exception 'Caminho de documento inválido.'; end if;
  if p_file_size not between 32 and 12582912 or p_width not between 900 and 1400 or p_height not between 400 and 14000 or nullif(btrim(p_render_version), '') is null then
    raise exception 'Metadados do documento inválidos.';
  end if;
  if v_certificate.final_png_path is null then
    update public.medical_certificates set final_png_path = p_storage_path, final_png_file_size = p_file_size, final_png_width = p_width, final_png_height = p_height, final_png_render_version = p_render_version where id = p_certificate_id;
    perform private.audit_medical_certificate_action(v_actor, 'MEDICAL_CERTIFICATE_DOCUMENT_GENERATED', p_certificate_id, null, jsonb_build_object('render_version', p_render_version, 'file_size', p_file_size));
  end if;
  return public.medical_certificate_document_state(p_certificate_id);
end;
$$;

create or replace function public.audit_medical_certificate_download(p_certificate_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_actor uuid := private.hpsm_current_actor();
begin
  if not private.has_permission(v_actor, 'atestados.view') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if not exists (select 1 from public.medical_certificates where id = p_certificate_id and status = 'finalized' and final_png_path is not null) then raise exception 'Documento não localizado.'; end if;
  perform private.audit_medical_certificate_action(v_actor, 'MEDICAL_CERTIFICATE_DOWNLOADED', p_certificate_id, null, jsonb_build_object('channel', 'professional'));
end;
$$;

create or replace function public.patient_medical_certificate_page(
  p_patient_id bigint,
  p_limit integer default 10,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_actor uuid := private.hpsm_current_actor(); v_limit integer := least(greatest(coalesce(p_limit, 10), 1), 25); v_offset integer := greatest(coalesce(p_offset, 0), 0);
begin
  if not private.has_permission(v_actor, 'patients.view') or not private.has_permission(v_actor, 'atestados.view') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if not exists (select 1 from public.patients where id = p_patient_id) then raise exception 'Paciente não localizado.'; end if;
  return (
    with filtered as (
      select certificate.id, certificate.attendance_id, certificate.leave_days, certificate.status,
        certificate.created_at, certificate.finalized_at, certificate.cancelled_at,
        creator.display_name professional_name, position.name professional_position,
        certificate.final_png_path is not null document_ready
      from public.medical_certificates certificate
      join public.profiles creator on creator.user_id = certificate.created_by
      left join public.staff_positions position on position.id = creator.position_id
      where certificate.patient_id = p_patient_id
    ), page_rows as (select * from filtered order by created_at desc, id desc limit v_limit offset v_offset)
    select jsonb_build_object('items', coalesce((select jsonb_agg(to_jsonb(page_rows) order by created_at desc, id desc) from page_rows), '[]'::jsonb), 'total', (select count(*)::integer from filtered))
  );
end;
$$;

create or replace function public.patient_portal_medical_certificate_page(
  p_token_hash text,
  p_limit integer default 15,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_session record;
  v_limit integer := least(greatest(coalesce(p_limit, 15), 1), 30);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then return jsonb_build_object('authenticated', false); end if;
  select * into v_session from private.patient_portal_session_record(p_token_hash);
  if v_session.patient_id is null then return jsonb_build_object('authenticated', false); end if;
  return jsonb_build_object(
    'authenticated', true,
    'patient', jsonb_build_object('name', v_session.patient_name, 'passport', v_session.patient_passport),
    'items', coalesce((
      select jsonb_agg(to_jsonb(item) order by item.finalized_at desc, item.id desc)
      from (
        select certificate.id, certificate.attendance_id, certificate.leave_days, certificate.finalized_at,
          certificate.created_at, creator.display_name professional_name, position.name professional_position,
          certificate.final_png_path is not null document_ready
        from public.medical_certificates certificate
        join public.profiles creator on creator.user_id = certificate.created_by
        left join public.staff_positions position on position.id = creator.position_id
        where certificate.patient_id = v_session.patient_id and certificate.status = 'finalized'
        order by certificate.finalized_at desc, certificate.id desc
        limit v_limit offset v_offset
      ) item
    ), '[]'::jsonb),
    'total', (select count(*)::integer from public.medical_certificates certificate where certificate.patient_id = v_session.patient_id and certificate.status = 'finalized')
  );
end;
$$;

create or replace function public.patient_portal_medical_certificate_detail(p_token_hash text, p_certificate_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_session record; v_result jsonb;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then return jsonb_build_object('authenticated', false, 'found', false); end if;
  select * into v_session from private.patient_portal_session_record(p_token_hash);
  if v_session.patient_id is null then return jsonb_build_object('authenticated', false, 'found', false); end if;
  select jsonb_build_object(
    'authenticated', true, 'found', true,
    'patient', jsonb_build_object('name', v_session.patient_name, 'passport', v_session.patient_passport),
    'certificate', jsonb_build_object('id', certificate.id, 'snapshot', certificate.professional_snapshot),
    'document', case when certificate.final_png_path is null then null else jsonb_build_object('path', certificate.final_png_path, 'file_size', certificate.final_png_file_size, 'width', certificate.final_png_width, 'height', certificate.final_png_height, 'render_version', certificate.final_png_render_version) end
  ) into v_result
  from public.medical_certificates certificate
  where certificate.id = p_certificate_id and certificate.patient_id = v_session.patient_id and certificate.status = 'finalized';
  return coalesce(v_result, jsonb_build_object('authenticated', true, 'found', false, 'patient', jsonb_build_object('name', v_session.patient_name, 'passport', v_session.patient_passport)));
end;
$$;

create or replace function public.patient_portal_register_medical_certificate_document(
  p_token_hash text,
  p_certificate_id bigint,
  p_storage_path text,
  p_file_size integer,
  p_width integer,
  p_height integer,
  p_render_version text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_session record; v_certificate public.medical_certificates;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then return jsonb_build_object('authenticated', false, 'found', false); end if;
  select * into v_session from private.patient_portal_session_record(p_token_hash);
  if v_session.patient_id is null then return jsonb_build_object('authenticated', false, 'found', false); end if;
  select * into v_certificate from public.medical_certificates where id = p_certificate_id and patient_id = v_session.patient_id and status = 'finalized' for update;
  if v_certificate.id is null then return jsonb_build_object('authenticated', true, 'found', false); end if;
  if p_storage_path !~ ('^medical-certificates/' || p_certificate_id::text || '/documents/[0-9a-f-]{36}\\.png$')
    or p_file_size not between 32 and 12582912 or p_width not between 900 and 1400 or p_height not between 400 and 14000 or nullif(btrim(p_render_version), '') is null then
    raise exception 'Metadados do documento inválidos.';
  end if;
  if v_certificate.final_png_path is null then
    update public.medical_certificates set final_png_path = p_storage_path, final_png_file_size = p_file_size, final_png_width = p_width, final_png_height = p_height, final_png_render_version = p_render_version where id = p_certificate_id;
    insert into public.audit_logs (actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values)
    values (null, v_session.patient_passport, 'MEDICAL_CERTIFICATE_DOCUMENT_GENERATED', 'medical_certificates', p_certificate_id::text, null, jsonb_build_object('channel', 'patient_portal', 'render_version', p_render_version));
  end if;
  return public.patient_portal_medical_certificate_detail(p_token_hash, p_certificate_id);
end;
$$;

create or replace function public.patient_portal_audit_medical_certificate_download(p_token_hash text, p_certificate_id bigint)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare v_session record;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then return false; end if;
  select * into v_session from private.patient_portal_session_record(p_token_hash);
  if v_session.patient_id is null or not exists (select 1 from public.medical_certificates where id = p_certificate_id and patient_id = v_session.patient_id and status = 'finalized' and final_png_path is not null) then return false; end if;
  insert into public.audit_logs (actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values)
  values (null, v_session.patient_passport, 'MEDICAL_CERTIFICATE_DOWNLOADED', 'medical_certificates', p_certificate_id::text, null, jsonb_build_object('channel', 'patient_portal'));
  return true;
end;
$$;

revoke all on function public.medical_certificate_page(text, text, date, date, uuid, integer, integer) from public, anon, authenticated, service_role;
revoke all on function public.medical_certificate_detail(bigint) from public, anon, authenticated, service_role;
revoke all on function public.medical_certificate_reference_options(bigint) from public, anon, authenticated, service_role;
revoke all on function public.create_medical_certificate(bigint, bigint, text, integer, bigint[], bigint[]) from public, anon, authenticated, service_role;
revoke all on function public.update_medical_certificate(bigint, text, integer, text, bigint[], bigint[]) from public, anon, authenticated, service_role;
revoke all on function public.medical_certificate_ai_context(bigint) from public, anon, authenticated, service_role;
revoke all on function public.apply_medical_certificate_ai_text(bigint, text, text, text) from public, anon, authenticated, service_role;
revoke all on function public.finalize_medical_certificate(bigint, text) from public, anon, authenticated, service_role;
revoke all on function public.cancel_medical_certificate(bigint, text) from public, anon, authenticated, service_role;
revoke all on function public.medical_certificate_document_state(bigint) from public, anon, authenticated, service_role;
revoke all on function public.register_medical_certificate_document(bigint, text, integer, integer, integer, text) from public, anon, authenticated, service_role;
revoke all on function public.audit_medical_certificate_download(bigint) from public, anon, authenticated, service_role;
revoke all on function public.patient_medical_certificate_page(bigint, integer, integer) from public, anon, authenticated, service_role;
revoke all on function public.patient_portal_medical_certificate_page(text, integer, integer) from public, anon, authenticated, service_role;
revoke all on function public.patient_portal_medical_certificate_detail(text, bigint) from public, anon, authenticated, service_role;
revoke all on function public.patient_portal_register_medical_certificate_document(text, bigint, text, integer, integer, integer, text) from public, anon, authenticated, service_role;
revoke all on function public.patient_portal_audit_medical_certificate_download(text, bigint) from public, anon, authenticated, service_role;

grant execute on function public.medical_certificate_page(text, text, date, date, uuid, integer, integer) to authenticated;
grant execute on function public.medical_certificate_detail(bigint) to authenticated;
grant execute on function public.medical_certificate_reference_options(bigint) to authenticated;
grant execute on function public.create_medical_certificate(bigint, bigint, text, integer, bigint[], bigint[]) to authenticated;
grant execute on function public.update_medical_certificate(bigint, text, integer, text, bigint[], bigint[]) to authenticated;
grant execute on function public.medical_certificate_ai_context(bigint) to authenticated;
grant execute on function public.apply_medical_certificate_ai_text(bigint, text, text, text) to authenticated;
grant execute on function public.finalize_medical_certificate(bigint, text) to authenticated;
grant execute on function public.cancel_medical_certificate(bigint, text) to authenticated;
grant execute on function public.medical_certificate_document_state(bigint) to authenticated;
grant execute on function public.register_medical_certificate_document(bigint, text, integer, integer, integer, text) to authenticated;
grant execute on function public.audit_medical_certificate_download(bigint) to authenticated;
grant execute on function public.patient_medical_certificate_page(bigint, integer, integer) to authenticated;
grant execute on function public.patient_portal_medical_certificate_page(text, integer, integer) to service_role;
grant execute on function public.patient_portal_medical_certificate_detail(text, bigint) to service_role;
grant execute on function public.patient_portal_register_medical_certificate_document(text, bigint, text, integer, integer, integer, text) to service_role;
grant execute on function public.patient_portal_audit_medical_certificate_download(text, bigint) to service_role;

comment on table public.medical_certificates is 'Atestados médicos clínicos com atendimento obrigatório, dias definidos pelo profissional e snapshot final imutável.';
comment on function public.medical_certificate_ai_context(bigint) is 'Entrega à Edge Function somente o contexto clínico autorizado do rascunho, sem identidade do paciente.';
comment on function public.patient_portal_medical_certificate_page(text, integer, integer) is 'Lista somente atestados finalizados pertencentes à sessão opaca do paciente.';
