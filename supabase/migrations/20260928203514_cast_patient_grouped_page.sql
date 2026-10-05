-- Paginate complete patient groups in Cast Control without changing the legacy record page RPC.
create or replace function public.clinical_cast_patient_page(
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
  ), patient_groups as (
    select patient_id,
      bool_or(status = 'in_use') as has_active,
      min(expected_removal_at) filter (where status = 'in_use') as next_due,
      max(updated_at) as last_update
    from filtered
    group by patient_id
  ), ranked_patients as (
    select patient_id,
      row_number() over (order by has_active desc, next_due asc nulls last, last_update desc, patient_id desc) as sort_order
    from patient_groups
  ), page_patients as (
    select patient_id, sort_order from ranked_patients
    where sort_order > v_offset and sort_order <= v_offset + v_limit
  ), page_rows as (
    select filtered.*, page_patients.sort_order
    from page_patients join filtered using (patient_id)
  )
  select jsonb_build_object(
    'items', coalesce((select jsonb_agg(to_jsonb(page_rows) - 'sort_order' order by
      sort_order,
      case when status = 'in_use' then 0 else 1 end,
      case when status = 'in_use' then expected_removal_at end asc,
      case when status <> 'in_use' then updated_at end desc,
      id desc
    ) from page_rows), '[]'::jsonb),
    'total', (select count(*) from patient_groups),
    'cast_total', (select count(*) from filtered)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.clinical_cast_patient_page(text, text, integer, integer) from public, anon, authenticated, service_role;
grant execute on function public.clinical_cast_patient_page(text, text, integer, integer) to authenticated;

comment on function public.clinical_cast_patient_page(text, text, integer, integer) is
  'Cast Control read with canonical session: paginates patients and returns all matching casts for each selected patient.';
