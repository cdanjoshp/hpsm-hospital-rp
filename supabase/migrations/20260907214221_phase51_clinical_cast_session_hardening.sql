-- HPSM · Fase 5.1 · validação canônica de sessão e vínculo financeiro
-- Todas as RPCs exigem sessão ativa; GESSO é identificado pelo código estável do catálogo.

drop policy if exists clinical_casts_read_authorized on public.clinical_casts;
create policy clinical_casts_read_authorized
on public.clinical_casts for select to authenticated
using ((select private.has_permission(private.hpsm_current_actor(), 'casts.view')));

create or replace function public.clinical_cast_page(
  p_search text default null,
  p_status text default 'in_use',
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
  v_actor uuid;
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_result jsonb;
begin
  v_actor := private.hpsm_current_actor();
  if v_actor is null or not private.has_permission(v_actor, 'casts.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if p_status is not null and p_status not in ('in_use', 'removed', 'cancelled') then
    raise exception 'Status de gesso inválido.';
  end if;

  with filtered as (
    select
      cast_record.id,
      cast_record.patient_id,
      patient.name as patient_name,
      patient.passport as patient_passport,
      cast_record.attendance_id,
      cast_record.body_region,
      cast_record.laterality,
      cast_record.status,
      cast_record.applied_at,
      cast_record.expected_removal_at,
      cast_record.removed_at,
      cast_record.applied_by,
      applied.display_name as applied_by_name,
      applied_position.name as applied_by_position,
      cast_record.updated_at
    from public.clinical_casts cast_record
    join public.patients patient on patient.id = cast_record.patient_id
    join public.profiles applied on applied.user_id = cast_record.applied_by
    left join public.staff_positions applied_position on applied_position.id = applied.position_id
    where (p_status is null or cast_record.status = p_status)
      and (
        nullif(btrim(p_search), '') is null
        or patient.name ilike '%' || btrim(p_search) || '%'
        or patient.passport ilike btrim(p_search) || '%'
      )
  ), counted as (
    select count(*)::integer as total from filtered
  ), page_rows as (
    select *
    from filtered
    order by
      case when status = 'in_use' then 0 else 1 end,
      case when status = 'in_use' then expected_removal_at end asc,
      case when status <> 'in_use' then updated_at end desc,
      id desc
    limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'items', coalesce((select jsonb_agg(to_jsonb(page_rows) order by
      case when status = 'in_use' then 0 else 1 end,
      case when status = 'in_use' then expected_removal_at end asc,
      case when status <> 'in_use' then updated_at end desc,
      id desc
    ) from page_rows), '[]'::jsonb),
    'total', (select total from counted)
  ) into v_result;

  return v_result;
end;
$$;

create or replace function public.clinical_cast_detail(p_cast_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
  v_result jsonb;
begin
  v_actor := private.hpsm_current_actor();
  if v_actor is null or not private.has_permission(v_actor, 'casts.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'id', cast_record.id,
    'patient_id', cast_record.patient_id,
    'patient_name', patient.name,
    'patient_passport', patient.passport,
    'attendance_id', cast_record.attendance_id,
    'attendance_created_at', attendance.created_at,
    'attendance_total', attendance.total,
    'attendance_summary', case when attendance.id is null then null else coalesce((
      select string_agg(item.service_name || case when item.quantity > 1 then ' ×' || item.quantity::text else '' end, ', ' order by item.id)
      from public.attendance_items item where item.attendance_id = attendance.id
    ), 'Atendimento sem itens') end,
    'body_region', cast_record.body_region,
    'laterality', cast_record.laterality,
    'status', cast_record.status,
    'applied_at', cast_record.applied_at,
    'applied_by', cast_record.applied_by,
    'applied_by_name', applied.display_name,
    'applied_by_position', applied_position.name,
    'expected_removal_at', cast_record.expected_removal_at,
    'application_notes', cast_record.application_notes,
    'removed_at', cast_record.removed_at,
    'removed_by', cast_record.removed_by,
    'removed_by_name', removed.display_name,
    'removed_by_position', removed_position.name,
    'removal_notes', cast_record.removal_notes,
    'cancelled_at', cast_record.cancelled_at,
    'cancelled_by', cast_record.cancelled_by,
    'cancelled_by_name', cancelled.display_name,
    'cancelled_by_position', cancelled_position.name,
    'cancellation_reason', cast_record.cancellation_reason,
    'created_at', cast_record.created_at,
    'updated_at', cast_record.updated_at
  ) into v_result
  from public.clinical_casts cast_record
  join public.patients patient on patient.id = cast_record.patient_id
  left join public.attendances attendance on attendance.id = cast_record.attendance_id
  join public.profiles applied on applied.user_id = cast_record.applied_by
  left join public.staff_positions applied_position on applied_position.id = applied.position_id
  left join public.profiles removed on removed.user_id = cast_record.removed_by
  left join public.staff_positions removed_position on removed_position.id = removed.position_id
  left join public.profiles cancelled on cancelled.user_id = cast_record.cancelled_by
  left join public.staff_positions cancelled_position on cancelled_position.id = cancelled.position_id
  where cast_record.id = p_cast_id;

  if v_result is null then raise exception 'Registro de gesso não localizado.'; end if;
  return v_result;
end;
$$;

create or replace function public.clinical_cast_attendance_options(p_patient_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
begin
  v_actor := private.hpsm_current_actor();
  if v_actor is null
     or not private.has_permission(v_actor, 'casts.create')
     or not private.has_permission(v_actor, 'patients.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.patients patient where patient.id = p_patient_id) then
    raise exception 'Paciente não localizado.';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', option.id,
      'created_at', option.created_at,
      'total', option.total,
      'has_cast_item', option.has_cast_item,
      'summary', coalesce((
        select string_agg(item.service_name || case when item.quantity > 1 then ' ×' || item.quantity::text else '' end, ', ' order by item.id)
        from public.attendance_items item where item.attendance_id = option.id
      ), 'Atendimento sem itens')
    ) order by option.has_cast_item desc, option.created_at desc)
    from (
      select
        attendance.id,
        attendance.created_at,
        attendance.total,
        exists (
          select 1
          from public.attendance_items item
          join public.service_catalog catalog on catalog.id = item.service_id
          where item.attendance_id = attendance.id
            and catalog.code = 'gesso'
        ) as has_cast_item
      from public.attendances attendance
      where attendance.patient_id = p_patient_id and attendance.status = 'completed'
      order by has_cast_item desc, attendance.created_at desc
      limit 30
    ) option
  ), '[]'::jsonb);
end;
$$;

create or replace function public.create_clinical_cast(
  p_patient_id bigint,
  p_attendance_id bigint,
  p_body_region text,
  p_laterality text,
  p_applied_at timestamptz,
  p_expected_removal_at timestamptz,
  p_application_notes text default null,
  p_confirm_duplicate boolean default false
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
  v_cast public.clinical_casts;
  v_notes text := nullif(btrim(coalesce(p_application_notes, '')), '');
begin
  v_actor := private.hpsm_current_actor();
  if v_actor is null
     or not private.has_permission(v_actor, 'casts.create')
     or not private.has_permission(v_actor, 'patients.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles profile where profile.user_id = v_actor and profile.status = 'active') then
    raise exception 'Profissional responsável não localizado.';
  end if;
  if not exists (select 1 from public.patients patient where patient.id = p_patient_id) then
    raise exception 'Paciente não localizado.';
  end if;
  if p_body_region not in ('hand', 'wrist', 'forearm', 'elbow', 'arm', 'foot', 'ankle', 'leg', 'knee', 'other') then
    raise exception 'Região inválida.';
  end if;
  if p_laterality not in ('right', 'left', 'bilateral', 'not_applicable') then
    raise exception 'Lateralidade inválida.';
  end if;
  if p_applied_at is null then raise exception 'Informe a data e hora da aplicação.'; end if;
  if p_expected_removal_at is null or p_expected_removal_at <= p_applied_at then
    raise exception 'A previsão de retirada deve ser posterior à aplicação.';
  end if;
  if v_notes is not null and char_length(v_notes) > 1000 then
    raise exception 'A observação deve ter no máximo 1000 caracteres.';
  end if;
  if p_attendance_id is not null and not exists (
    select 1 from public.attendances attendance
    where attendance.id = p_attendance_id
      and attendance.patient_id = p_patient_id
      and attendance.status = 'completed'
  ) then
    raise exception 'O atendimento informado não pertence ao paciente ou não está concluído.';
  end if;
  if not coalesce(p_confirm_duplicate, false) and exists (
    select 1 from public.clinical_casts active_cast
    where active_cast.patient_id = p_patient_id
      and active_cast.body_region = p_body_region
      and active_cast.laterality = p_laterality
      and active_cast.status = 'in_use'
  ) then
    raise exception 'O paciente já possui um gesso em uso na mesma região e lateralidade.'
      using errcode = '23505', detail = 'HPSM_ACTIVE_CAST_DUPLICATE';
  end if;

  insert into public.clinical_casts (
    patient_id, attendance_id, body_region, laterality, status,
    applied_at, applied_by, expected_removal_at, application_notes, created_by
  ) values (
    p_patient_id, p_attendance_id, p_body_region, p_laterality, 'in_use',
    p_applied_at, v_actor, p_expected_removal_at, v_notes, v_actor
  ) returning * into v_cast;

  perform private.audit_cast_action(
    v_actor, 'CAST_APPLIED', v_cast.id, null,
    jsonb_build_object(
      'patient_id', v_cast.patient_id,
      'attendance_id', v_cast.attendance_id,
      'body_region', v_cast.body_region,
      'laterality', v_cast.laterality,
      'applied_at', v_cast.applied_at,
      'expected_removal_at', v_cast.expected_removal_at,
      'status', v_cast.status
    )
  );
  return v_cast.id;
end;
$$;

create or replace function public.update_clinical_cast_expected_removal(
  p_cast_id bigint,
  p_expected_removal_at timestamptz,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
  v_old public.clinical_casts;
  v_new public.clinical_casts;
  v_reason text := btrim(coalesce(p_reason, ''));
begin
  v_actor := private.hpsm_current_actor();
  select * into v_old from public.clinical_casts where id = p_cast_id for update;
  if v_old.id is null then raise exception 'Registro de gesso não localizado.'; end if;
  if v_actor is null or not (
    private.has_permission(v_actor, 'casts.manage')
    or (v_old.applied_by = v_actor and private.has_permission(v_actor, 'casts.create'))
  ) then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if v_old.status <> 'in_use' then raise exception 'Somente gessos em uso permitem alterar a previsão.'; end if;
  if p_expected_removal_at is null or p_expected_removal_at <= v_old.applied_at then
    raise exception 'A previsão de retirada deve ser posterior à aplicação.';
  end if;
  if p_expected_removal_at = v_old.expected_removal_at then raise exception 'Informe uma nova previsão de retirada.'; end if;
  if char_length(v_reason) not between 2 and 500 then raise exception 'Informe o motivo da alteração.'; end if;

  update public.clinical_casts
  set expected_removal_at = p_expected_removal_at
  where id = p_cast_id
  returning * into v_new;

  perform private.audit_cast_action(
    v_actor, 'CAST_EXPECTED_REMOVAL_CHANGED', v_new.id,
    jsonb_build_object('expected_removal_at', v_old.expected_removal_at),
    jsonb_build_object('expected_removal_at', v_new.expected_removal_at, 'reason', v_reason)
  );
end;
$$;

create or replace function public.remove_clinical_cast(
  p_cast_id bigint,
  p_removed_at timestamptz,
  p_removal_notes text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
  v_old public.clinical_casts;
  v_new public.clinical_casts;
  v_notes text := nullif(btrim(coalesce(p_removal_notes, '')), '');
begin
  v_actor := private.hpsm_current_actor();
  if v_actor is null or not private.has_permission(v_actor, 'casts.remove') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  select * into v_old from public.clinical_casts where id = p_cast_id for update;
  if v_old.id is null then raise exception 'Registro de gesso não localizado.'; end if;
  if v_old.status <> 'in_use' then raise exception 'Este gesso já foi retirado ou cancelado.'; end if;
  if p_removed_at is null then raise exception 'Informe a data e hora da retirada.'; end if;
  if p_removed_at < v_old.applied_at then raise exception 'A retirada não pode ocorrer antes da aplicação.'; end if;
  if v_notes is not null and char_length(v_notes) > 1000 then
    raise exception 'A observação da retirada deve ter no máximo 1000 caracteres.';
  end if;

  update public.clinical_casts
  set status = 'removed', removed_at = p_removed_at, removed_by = v_actor, removal_notes = v_notes
  where id = p_cast_id
  returning * into v_new;

  perform private.audit_cast_action(
    v_actor, 'CAST_REMOVED', v_new.id,
    jsonb_build_object('status', v_old.status, 'expected_removal_at', v_old.expected_removal_at),
    jsonb_build_object(
      'status', v_new.status,
      'removed_at', v_new.removed_at,
      'removed_by', v_new.removed_by,
      'early_removal', v_new.removed_at < v_new.expected_removal_at,
      'removal_notes', v_new.removal_notes
    )
  );
end;
$$;

create or replace function public.cancel_clinical_cast(p_cast_id bigint, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
  v_old public.clinical_casts;
  v_new public.clinical_casts;
  v_reason text := btrim(coalesce(p_reason, ''));
begin
  v_actor := private.hpsm_current_actor();
  if v_actor is null or not private.has_permission(v_actor, 'casts.manage') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if char_length(v_reason) not between 2 and 500 then raise exception 'Informe o motivo do cancelamento.'; end if;
  select * into v_old from public.clinical_casts where id = p_cast_id for update;
  if v_old.id is null then raise exception 'Registro de gesso não localizado.'; end if;
  if v_old.status <> 'in_use' then raise exception 'Somente um gesso em uso pode ser cancelado.'; end if;

  update public.clinical_casts
  set status = 'cancelled', cancelled_at = now(), cancelled_by = v_actor, cancellation_reason = v_reason
  where id = p_cast_id
  returning * into v_new;

  perform private.audit_cast_action(
    v_actor, 'CAST_CANCELLED', v_new.id,
    jsonb_build_object('status', v_old.status),
    jsonb_build_object(
      'status', v_new.status,
      'cancelled_at', v_new.cancelled_at,
      'cancelled_by', v_new.cancelled_by,
      'reason', v_new.cancellation_reason
    )
  );
end;
$$;
