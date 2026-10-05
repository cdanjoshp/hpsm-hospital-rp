-- Alertas clínicos derivados somente para os cartões da página atual.
-- Cada domínio mantém sua permissão específica; nenhum estado de alerta é persistido.
set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function public.hpsm_patient_card_page(
  p_search text default '',
  p_filter text default 'all',
  p_page integer default 1,
  p_page_size integer default 20
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_search text := left(btrim(coalesce(p_search, '')), 100);
  v_filter text := coalesce(p_filter, 'all');
  v_page integer := least(greatest(coalesce(p_page, 1), 1), 100000);
  v_page_size integer := least(greatest(coalesce(p_page_size, 20), 1), 50);
  v_passport text;
  v_name_pattern text;
  v_result jsonb;
  v_casts boolean;
  v_hospitalizations boolean;
  v_consultations boolean;
begin
  if v_actor is null or not private.has_permission(v_actor, 'patients.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if v_filter not in ('all', 'active', 'expired', 'partner', 'police', 'none') then
    raise exception 'Filtro inválido.' using errcode = '22023';
  end if;

  v_casts := private.has_permission(v_actor, 'casts.view');
  v_hospitalizations := private.has_permission(v_actor, 'hospitalizations.view');
  v_consultations := private.has_permission(v_actor, 'consultations.view');

  v_passport := case when v_search ~ '^[0-9]{1,4}$' then lpad(v_search, 4, '0') else null end;
  v_name_pattern := '%' || replace(replace(replace(v_search, E'\\', E'\\\\'), '%', E'\\%'), '_', E'\\_') || '%';

  with candidates as materialized (
    select directory.id, directory.passport, directory.name, directory.allergies,
      case
        when directory.plan_status = 'active' then 'active'
        when partner.has_active then 'partner'
        when latest.plan_code = 'policiais_arcanjos' then 'police'
        when directory.plan_status = 'expired' then 'expired'
        else 'none'
      end as benefit
    from public.patient_directory directory
    left join lateral (
      select true as has_active
      from public.patient_partnerships membership
      join public.partnerships partnership on partnership.id = membership.partnership_id
      where membership.patient_id = directory.id
        and membership.status = 'active' and partnership.status = 'active'
      limit 1
    ) partner on true
    left join lateral (
      select attendance.plan_code
      from public.attendances attendance
      where attendance.patient_id = directory.id and attendance.status = 'completed'
      order by attendance.created_at desc, attendance.id desc
      limit 1
    ) latest on true
    where v_search = ''
      or (v_passport is not null and directory.passport = v_passport)
      or (v_passport is null and directory.name ilike v_name_pattern)
  ), matching as materialized (
    select id, passport, name, allergies, benefit
    from candidates
    where v_filter = 'all' or benefit = v_filter
  ), page_rows as (
    select id, passport, name, allergies, benefit
    from matching
    order by passport, name
    limit v_page_size offset (v_page - 1) * v_page_size
  )
  select jsonb_build_object(
    'page', v_page,
    'pageSize', v_page_size,
    'total', (select count(*) from matching),
    'patients', coalesce((
      select jsonb_agg(
        to_jsonb(row_data) || jsonb_build_object('alerts', jsonb_strip_nulls(jsonb_build_object(
          'casts', case when v_casts and casts.total > 0 then jsonb_build_object('count', casts.total, 'latest', casts.latest) end,
          'hospitalization', case when v_hospitalizations then hospitalization.detail end,
          'appointments', case when v_consultations and appointments.total > 0 then jsonb_build_object('count', appointments.total, 'next', appointments.next) end
        ))) order by row_data.passport, row_data.name
      )
      from page_rows row_data
      left join lateral (
        select count(*)::integer as total,
          (array_agg(jsonb_build_object(
            'id', cast_record.id,
            'location', private.clinical_cast_location_label(cast_record.body_region, cast_record.laterality),
            'appliedAt', cast_record.applied_at,
            'expectedRemovalAt', cast_record.expected_removal_at
          ) order by cast_record.expected_removal_at, cast_record.id))[1] as latest
        from public.clinical_casts cast_record
        where v_casts and cast_record.patient_id = row_data.id and cast_record.status = 'in_use'
      ) casts on true
      left join lateral (
        select jsonb_build_object(
          'id', h.id, 'bed', bed.label, 'reason', h.reason, 'admittedAt', h.admitted_at
        ) as detail
        from public.hospitalizations h
        join public.hospital_beds bed on bed.id = h.bed_id
        where v_hospitalizations and h.patient_id = row_data.id and h.status = 'active'
        limit 1
      ) hospitalization on true
      left join lateral (
        select count(*)::integer as total,
          (array_agg(jsonb_build_object(
            'id', a.id, 'reason', a.reason, 'scheduledStart', a.scheduled_start,
            'status', a.status
          ) order by
            case when a.scheduled_start >= now() then 0 else 1 end,
            case when a.scheduled_start >= now() then a.scheduled_start end asc,
            a.scheduled_start desc, a.id))[1] as next
        from public.patient_appointments a
        where v_consultations and a.patient_id = row_data.id and a.status in ('scheduled', 'confirmed')
      ) appointments on true
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.hpsm_patient_card_page(text, text, integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.hpsm_patient_card_page(text, text, integer, integer) to authenticated;
