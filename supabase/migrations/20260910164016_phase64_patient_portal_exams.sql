-- HPSM — Fase 6.4: exames, laudo final e segunda via PNG no Portal do Paciente.
-- O paciente é sempre derivado da sessão opaca; nenhuma RPC recebe patient_id.

alter table public.clinical_exam_documents
  alter column created_by drop not null,
  add column created_by_patient_id bigint references public.patients(id) on delete restrict;

alter table public.clinical_exam_documents
  add constraint clinical_exam_documents_creator_check check (
    (created_by is not null and created_by_patient_id is null)
    or (created_by is null and created_by_patient_id is not null)
  );

alter table public.clinical_exam_document_shares
  alter column created_by drop not null,
  add column created_by_patient_id bigint references public.patients(id) on delete restrict;

alter table public.clinical_exam_document_shares
  add constraint clinical_exam_document_shares_creator_check check (
    (created_by is not null and created_by_patient_id is null)
    or (created_by is null and created_by_patient_id is not null)
  );

create index clinical_exam_documents_created_by_patient_idx
  on public.clinical_exam_documents (created_by_patient_id)
  where created_by_patient_id is not null;

create index clinical_exam_document_shares_created_by_patient_idx
  on public.clinical_exam_document_shares (created_by_patient_id)
  where created_by_patient_id is not null;

create index clinical_exams_patient_status_requested_idx
  on public.clinical_exams (patient_id, status, requested_at desc, id desc);

create or replace function public.patient_portal_exam_page(
  p_token_hash text,
  p_cursor_at timestamptz default null,
  p_cursor_id bigint default null,
  p_status_group text default 'all',
  p_limit integer default 15
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_has_more boolean;
  v_items jsonb;
  v_limit integer := least(greatest(coalesce(p_limit, 15), 1), 30);
  v_next_at timestamptz;
  v_next_id bigint;
  v_session record;
  v_status_group text := coalesce(nullif(trim(p_status_group), ''), 'all');
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('authenticated', false);
  end if;
  if (p_cursor_at is null) <> (p_cursor_id is null)
     or (p_cursor_id is not null and p_cursor_id < 1)
     or v_status_group not in ('all', 'in_progress', 'completed') then
    raise exception 'Parâmetros inválidos.' using errcode = '22023';
  end if;

  select * into v_session
  from private.patient_portal_session_record(p_token_hash);

  if not found then
    return jsonb_build_object('authenticated', false);
  end if;

  with page_rows as materialized (
    select exam.id, exam.requested_at, exam.completed_at, exam.status,
      exam_type.name as type_name, category.name as category_name
    from public.clinical_exams exam
    join public.exam_types exam_type on exam_type.id = exam.exam_type_id
    join public.exam_categories category on category.id = exam_type.category_id
    where exam.patient_id = v_session.patient_id
      and (
        v_status_group = 'all'
        or (v_status_group = 'completed' and exam.status = 'completed')
        or (v_status_group = 'in_progress' and exam.status in ('requested', 'in_progress', 'awaiting_review'))
      )
      and (p_cursor_at is null or (exam.requested_at, exam.id) < (p_cursor_at, p_cursor_id))
    order by exam.requested_at desc, exam.id desc
    limit v_limit + 1
  ), visible_rows as materialized (
    select * from page_rows order by requested_at desc, id desc limit v_limit
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'id', visible.id,
      'type', visible.type_name,
      'category', visible.category_name,
      'occurred_at', visible.requested_at,
      'completed_at', visible.completed_at,
      'status', visible.status
    ) order by visible.requested_at desc, visible.id desc), '[]'::jsonb),
    (select count(*) > v_limit from page_rows),
    (select requested_at from visible_rows order by requested_at, id limit 1),
    (select id from visible_rows order by requested_at, id limit 1)
  into v_items, v_has_more, v_next_at, v_next_id
  from visible_rows visible;

  return jsonb_build_object(
    'authenticated', true,
    'patient', jsonb_build_object('name', v_session.patient_name, 'passport', v_session.patient_passport),
    'items', v_items,
    'next_cursor', case when v_has_more then jsonb_build_object('occurred_at', v_next_at, 'id', v_next_id) else null end
  );
end;
$$;

create or replace function public.patient_portal_exam_detail(p_token_hash text, p_exam_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_images jsonb := '[]'::jsonb;
  v_session record;
  v_target record;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('authenticated', false);
  end if;

  select * into v_session
  from private.patient_portal_session_record(p_token_hash);

  if not found then
    return jsonb_build_object('authenticated', false);
  end if;

  select exam.id, exam.requested_at, exam.completed_at, exam.status,
    exam.final_report_snapshot, exam_type.name as type_name, category.name as category_name
  into v_target
  from public.clinical_exams exam
  join public.exam_types exam_type on exam_type.id = exam.exam_type_id
  join public.exam_categories category on category.id = exam_type.category_id
  where exam.id = p_exam_id and exam.patient_id = v_session.patient_id;

  if not found then
    return jsonb_build_object('authenticated', true, 'found', false);
  end if;

  if v_target.status = 'completed' and v_target.final_report_snapshot is not null then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', image.id,
      'storage_path', image.storage_path,
      'original_filename', image.original_filename,
      'mime_type', image.mime_type,
      'sort_order', image.sort_order,
      'caption', image.caption,
      'source', image.source,
      'created_at', image.created_at
    ) order by image.sort_order, image.created_at, image.id), '[]'::jsonb)
    into v_images
    from public.clinical_exam_images image
    where image.exam_id = v_target.id
      and image.removed_at is null
      and exists (
        select 1
        from jsonb_array_elements(coalesce(v_target.final_report_snapshot -> 'images', '[]'::jsonb)) snapshot_image
        where snapshot_image ->> 'id' = image.id::text
      );
  end if;

  return jsonb_build_object(
    'authenticated', true,
    'found', true,
    'patient', jsonb_build_object('name', v_session.patient_name, 'passport', v_session.patient_passport),
    'exam', jsonb_build_object(
      'id', v_target.id,
      'type', v_target.type_name,
      'category', v_target.category_name,
      'occurred_at', v_target.requested_at,
      'completed_at', v_target.completed_at,
      'status', v_target.status
    ),
    'final_report_snapshot', case when v_target.status = 'completed' then v_target.final_report_snapshot else null end,
    'images', case when v_target.status = 'completed' then v_images else '[]'::jsonb end
  );
end;
$$;

create or replace function public.patient_portal_exam_image(
  p_token_hash text,
  p_exam_id bigint,
  p_image_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
  v_session record;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('authenticated', false);
  end if;

  select * into v_session
  from private.patient_portal_session_record(p_token_hash);

  if not found then
    return jsonb_build_object('authenticated', false);
  end if;

  select jsonb_build_object(
    'storage_path', image.storage_path,
    'mime_type', image.mime_type,
    'file_size', image.file_size
  ) into v_result
  from public.clinical_exams exam
  join public.clinical_exam_images image on image.exam_id = exam.id
  where exam.id = p_exam_id
    and exam.patient_id = v_session.patient_id
    and exam.status = 'completed'
    and exam.final_report_snapshot is not null
    and image.id = p_image_id
    and image.removed_at is null
    and exists (
      select 1
      from jsonb_array_elements(coalesce(exam.final_report_snapshot -> 'images', '[]'::jsonb)) snapshot_image
      where snapshot_image ->> 'id' = image.id::text
    );

  if v_result is null then
    return jsonb_build_object('authenticated', true, 'found', false);
  end if;

  return jsonb_build_object('authenticated', true, 'found', true, 'image', v_result);
end;
$$;

create or replace function public.patient_portal_exam_document_state(p_token_hash text, p_exam_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_session record;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('authenticated', false);
  end if;

  select * into v_session
  from private.patient_portal_session_record(p_token_hash);

  if not found then
    return jsonb_build_object('authenticated', false);
  end if;

  if not exists (
    select 1 from public.clinical_exams exam
    where exam.id = p_exam_id
      and exam.patient_id = v_session.patient_id
      and exam.status = 'completed'
      and exam.final_report_snapshot is not null
  ) then
    return jsonb_build_object('authenticated', true, 'found', false);
  end if;

  return jsonb_build_object(
    'authenticated', true,
    'found', true,
    'state', private.clinical_exam_document_state_json(p_exam_id)
  );
end;
$$;

create or replace function public.patient_portal_register_clinical_exam_document(
  p_token_hash text,
  p_exam_id bigint,
  p_document_id uuid,
  p_storage_path text,
  p_file_size bigint,
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
  v_document public.clinical_exam_documents;
  v_session record;
  v_target public.clinical_exams;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('authenticated', false);
  end if;

  select * into v_session
  from private.patient_portal_session_record(p_token_hash);

  if not found then
    return jsonb_build_object('authenticated', false);
  end if;

  select exam.* into v_target
  from public.clinical_exams exam
  where exam.id = p_exam_id and exam.patient_id = v_session.patient_id
  for update;

  if not found or v_target.status <> 'completed' or v_target.final_report_snapshot is null then
    return jsonb_build_object('authenticated', true, 'found', false);
  end if;

  if p_document_id is null
     or p_render_version <> 'exam-document-png-v1'
     or p_storage_path <> format('clinical-exams/%s/documents/%s.png', p_exam_id, p_document_id)
     or p_file_size not between 1 and 12582912
     or p_pixel_width not between 900 and 1400
     or p_pixel_height not between 400 and 14000 then
    raise exception 'Metadados inválidos para a imagem do documento.' using errcode = '22023';
  end if;

  if not exists (
    select 1 from storage.objects object
    where object.bucket_id = 'clinical-exam-documents'
      and object.name = p_storage_path
      and lower(coalesce(object.metadata ->> 'mimetype', '')) = 'image/png'
      and coalesce((object.metadata ->> 'size')::bigint, 0) = p_file_size
  ) then
    raise exception 'A imagem do documento ainda não foi confirmada no Storage.';
  end if;

  insert into public.clinical_exam_documents (
    id, exam_id, storage_path, mime_type, file_size, pixel_width, pixel_height,
    render_version, created_by, created_by_patient_id
  ) values (
    p_document_id, p_exam_id, p_storage_path, 'image/png', p_file_size, p_pixel_width, p_pixel_height,
    p_render_version, null, v_session.patient_id
  ) on conflict (exam_id, render_version) do nothing;

  select document.* into v_document
  from public.clinical_exam_documents document
  where document.exam_id = p_exam_id and document.render_version = p_render_version
  limit 1;

  if v_document.id is null then
    raise exception 'Não foi possível registrar a imagem do documento.';
  end if;

  return jsonb_build_object(
    'authenticated', true,
    'found', true,
    'state', private.clinical_exam_document_state_json(p_exam_id)
  );
end;
$$;

create or replace function public.patient_portal_create_clinical_exam_document_share(
  p_token_hash text,
  p_exam_id bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_document public.clinical_exam_documents;
  v_session record;
  v_share public.clinical_exam_document_shares;
  v_target public.clinical_exams;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('authenticated', false);
  end if;

  select * into v_session
  from private.patient_portal_session_record(p_token_hash);

  if not found then
    return jsonb_build_object('authenticated', false);
  end if;

  select exam.* into v_target
  from public.clinical_exams exam
  where exam.id = p_exam_id and exam.patient_id = v_session.patient_id
  for update;

  if not found or v_target.status <> 'completed' or v_target.final_report_snapshot is null then
    return jsonb_build_object('authenticated', true, 'found', false);
  end if;

  select document.* into v_document
  from public.clinical_exam_documents document
  where document.exam_id = p_exam_id and document.render_version = 'exam-document-png-v1'
  limit 1;

  if v_document.id is null then
    raise exception 'Prepare a imagem do resultado antes de criar o link.';
  end if;

  insert into public.clinical_exam_document_shares (
    exam_id, document_id, created_by, created_by_patient_id
  ) values (
    p_exam_id, v_document.id, null, v_session.patient_id
  ) on conflict (exam_id) where revoked_at is null do nothing;

  select share.* into v_share
  from public.clinical_exam_document_shares share
  where share.exam_id = p_exam_id and share.revoked_at is null
  limit 1;

  if v_share.id is null then
    raise exception 'Não foi possível criar o link do resultado.';
  end if;

  return jsonb_build_object(
    'authenticated', true,
    'found', true,
    'state', private.clinical_exam_document_state_json(p_exam_id)
  );
end;
$$;

-- O Resumo passa a expor o identificador público do registro clínico apenas para
-- permitir o deep link do exame concluído; nenhum resultado é carregado aqui.
create or replace function public.patient_portal_summary(p_token_hash text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_metrics record;
  v_result jsonb;
  v_session record;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('authenticated', false);
  end if;

  select * into v_session from private.patient_portal_session_record(p_token_hash);
  if not found then return jsonb_build_object('authenticated', false); end if;
  select * into v_metrics from private.patient_portal_attendance_metrics(v_session.patient_id);

  with last_attendance as (
    select attendance.id, attendance.created_at, attendance.total, professional.display_name as professional_name
    from public.attendances attendance
    left join public.profiles professional on professional.user_id = attendance.performed_by
    where attendance.patient_id = v_session.patient_id and attendance.status = 'completed'
    order by attendance.created_at desc, attendance.id desc limit 1
  ), latest_approved_plan as (
    select request.id, request.coverage_end
    from public.patient_health_plan_requests request
    where request.patient_id = v_session.patient_id and request.status = 'approved'
    order by request.coverage_end desc, request.id desc limit 1
  ), latest_pending_plan as (
    select request.id
    from public.patient_health_plan_requests request
    where request.patient_id = v_session.patient_id and request.status = 'pending'
    order by request.requested_at, request.id limit 1
  ), health_plan_payload as (
    select jsonb_build_object(
      'status', case
        when approved.id is not null and approved.coverage_end > clock_timestamp() then 'active'
        when approved.id is not null then 'expired'
        when pending.id is not null then 'awaiting_confirmation'
        else 'none'
      end,
      'valid_until', approved.coverage_end
    ) as value
    from (select true) singleton
    left join latest_approved_plan approved on true
    left join latest_pending_plan pending on true
  ), recent_exams as materialized (
    select exam.id, exam.requested_at, exam.status, exam_type.name as type_name
    from public.clinical_exams exam
    join public.exam_types exam_type on exam_type.id = exam.exam_type_id
    where exam.patient_id = v_session.patient_id
    order by exam.requested_at desc, exam.id desc limit 3
  ), recent_exams_payload as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', exam.id,
      'type', exam.type_name,
      'occurred_at', exam.requested_at,
      'status', exam.status
    ) order by exam.requested_at desc, exam.id desc), '[]'::jsonb) as value
    from recent_exams exam
  ), active_casts as materialized (
    select cast_record.id, cast_record.body_region, cast_record.laterality,
      cast_record.applied_at, cast_record.expected_removal_at
    from public.clinical_casts cast_record
    where cast_record.patient_id = v_session.patient_id and cast_record.status = 'in_use'
    order by cast_record.expected_removal_at, cast_record.id
  ), active_casts_payload as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'body_region', cast_record.body_region,
      'laterality', cast_record.laterality,
      'applied_at', cast_record.applied_at,
      'expected_removal_at', cast_record.expected_removal_at
    ) order by cast_record.expected_removal_at, cast_record.id), '[]'::jsonb) as value
    from active_casts cast_record
  )
  select jsonb_build_object(
    'authenticated', true,
    'patient', jsonb_build_object('name', v_session.patient_name, 'passport', v_session.patient_passport),
    'summary', jsonb_build_object(
      'total_attendances', v_metrics.total_attendances,
      'lifetime_spent', v_metrics.lifetime_spent,
      'last_attendance', case when latest.id is null then null else jsonb_build_object(
        'occurred_at', latest.created_at, 'total', latest.total, 'professional_name', latest.professional_name
      ) end
    ),
    'health_plan', plan.value,
    'recent_exams', exams.value,
    'active_casts', casts.value
  ) into v_result
  from (select true) singleton
  left join last_attendance latest on true
  cross join health_plan_payload plan
  cross join recent_exams_payload exams
  cross join active_casts_payload casts;

  return v_result;
end;
$$;

revoke all on function public.patient_portal_exam_page(text, timestamptz, bigint, text, integer)
from public, anon, authenticated, service_role;
revoke all on function public.patient_portal_exam_detail(text, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.patient_portal_exam_image(text, bigint, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.patient_portal_exam_document_state(text, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.patient_portal_register_clinical_exam_document(text, bigint, uuid, text, bigint, integer, integer, text)
from public, anon, authenticated, service_role;
revoke all on function public.patient_portal_create_clinical_exam_document_share(text, bigint)
from public, anon, authenticated, service_role;

grant execute on function public.patient_portal_exam_page(text, timestamptz, bigint, text, integer) to service_role;
grant execute on function public.patient_portal_exam_detail(text, bigint) to service_role;
grant execute on function public.patient_portal_exam_image(text, bigint, uuid) to service_role;
grant execute on function public.patient_portal_exam_document_state(text, bigint) to service_role;
grant execute on function public.patient_portal_register_clinical_exam_document(text, bigint, uuid, text, bigint, integer, integer, text) to service_role;
grant execute on function public.patient_portal_create_clinical_exam_document_share(text, bigint) to service_role;

comment on function public.patient_portal_exam_page(text, timestamptz, bigint, text, integer) is
  'Lista metadados leves de exames do paciente derivado da sessão opaca. Somente service_role.';
comment on function public.patient_portal_exam_detail(text, bigint) is
  'Entrega metadados básicos e, somente após conclusão, o snapshot final aprovado do exame pertencente ao paciente.';
comment on function public.patient_portal_exam_image(text, bigint, uuid) is
  'Resolve para o backend apenas uma imagem aprovada do exame concluído pertencente ao paciente da sessão.';
comment on function public.patient_portal_register_clinical_exam_document(text, bigint, uuid, text, bigint, integer, integer, text) is
  'Registra no documento canônico a segunda via preparada pelo próprio paciente, sem conceder permissão profissional.';
comment on function public.patient_portal_create_clinical_exam_document_share(text, bigint) is
  'Cria ou reutiliza o link público canônico do exame concluído pertencente ao paciente da sessão.';

notify pgrst, 'reload schema';
