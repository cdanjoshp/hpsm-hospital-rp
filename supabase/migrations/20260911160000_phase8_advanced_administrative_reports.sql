-- HPSM · Fase 8 — Central de Relatórios Administrativos Avançados.
-- Agrega fontes canônicas de RH, equipe e financeiro sem criar data warehouse.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function private.hpsm_report_validate_period(
  p_start_date date,
  p_end_date date
)
returns void
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception 'Período inválido.' using errcode = '22023';
  end if;
  if (p_end_date - p_start_date) > 366 then
    raise exception 'O período detalhado deve ter no máximo 12 meses.' using errcode = '22023';
  end if;
end;
$$;

create or replace function private.hpsm_report_hours(
  p_start_date date,
  p_end_date date
)
returns table(employee_id uuid, worked_minutes bigint)
language sql
stable
security definer
set search_path = ''
as $$
  with months as (
    select month_value::date as month_start
    from pg_catalog.generate_series(
      pg_catalog.date_trunc('month', p_start_date::timestamp)::date,
      pg_catalog.date_trunc('month', p_end_date::timestamp)::date,
      interval '1 month'
    ) month_value
  ), eligible as (
    select profile.user_id
    from public.profiles profile
    where profile.role_code <> 'diretor_geral'
      and profile.status in ('active', 'suspended')
  ), boundaries as (
    select
      eligible.user_id as employee_id,
      months.month_start,
      greatest(p_start_date, months.month_start) as range_start,
      least(p_end_date, (months.month_start + interval '1 month - 1 day')::date) as range_end
    from eligible cross join months
  ), measured as (
    select
      boundary.employee_id,
      boundary.month_start,
      boundary.range_start,
      ending.total_minutes as ending_minutes,
      baseline.total_minutes as baseline_minutes
    from boundaries boundary
    left join lateral (
      select snapshot.total_minutes
      from public.rh_hour_snapshots snapshot
      where snapshot.employee_id = boundary.employee_id
        and snapshot.reference_month = boundary.month_start
        and snapshot.reading_date <= boundary.range_end
      order by snapshot.reading_date desc, snapshot.updated_at desc, snapshot.id desc
      limit 1
    ) ending on true
    left join lateral (
      select snapshot.total_minutes
      from public.rh_hour_snapshots snapshot
      where snapshot.employee_id = boundary.employee_id
        and snapshot.reference_month = boundary.month_start
        and snapshot.reading_date < boundary.range_start
      order by snapshot.reading_date desc, snapshot.updated_at desc, snapshot.id desc
      limit 1
    ) baseline on true
  )
  select
    measured.employee_id,
    coalesce(sum(greatest(
      measured.ending_minutes - case when measured.range_start = measured.month_start then 0 else measured.baseline_minutes end,
      0
    )), 0)::bigint as worked_minutes
  from measured
  where measured.ending_minutes is not null
    and (measured.range_start = measured.month_start or measured.baseline_minutes is not null)
  group by measured.employee_id;
$$;

revoke all on function private.hpsm_report_validate_period(date, date) from public, anon, authenticated, service_role;
revoke all on function private.hpsm_report_hours(date, date) from public, anon, authenticated, service_role;

create or replace function public.hpsm_report_staff_search(p_query text, p_limit integer default 8)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_query text := btrim(coalesce(p_query, ''));
  v_limit integer := least(12, greatest(1, coalesce(p_limit, 8)));
  v_result jsonb;
begin
  if not private.has_permission(v_actor, 'hr.reports.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if char_length(v_query) < 2 or char_length(v_query) > 80 then
    return jsonb_build_object('items', '[]'::jsonb);
  end if;

  select jsonb_build_object(
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'id', result.user_id,
      'name', result.display_name,
      'passport', result.passport,
      'position_id', result.position_id,
      'position', result.position_name,
      'status', result.status
    ) order by result.priority, result.display_name, result.passport), '[]'::jsonb)
  ) into v_result
  from (
    select
      profile.user_id,
      profile.display_name,
      profile.passport,
      profile.position_id,
      position.name as position_name,
      profile.status,
      case when profile.passport = v_query then 0 when profile.passport like v_query || '%' then 1 else 2 end as priority
    from public.profiles profile
    left join public.staff_positions position on position.id = profile.position_id
    where profile.role_code <> 'diretor_geral'
      and profile.status in ('active', 'suspended')
      and (profile.passport like '%' || v_query || '%' or lower(profile.display_name) like '%' || lower(v_query) || '%')
    order by priority, profile.display_name, profile.passport
    limit v_limit
  ) result;
  return v_result;
end;
$$;

create or replace function public.hpsm_report_overview(p_start_date date, p_end_date date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_financial boolean;
  v_result jsonb;
begin
  if not private.has_permission(v_actor, 'hr.reports.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  perform private.hpsm_report_validate_period(p_start_date, p_end_date);
  v_financial := private.has_permission(v_actor, 'attendances.manage');

  with goal_by_employee as (
    select
      record.employee_id,
      count(*) filter (where record.required_minutes = 0) as excused_weeks,
      count(*) filter (where record.required_minutes > 0 and record.remaining_deficit_minutes = 0) as met_weeks,
      count(*) filter (where record.remaining_deficit_minutes > 0) as below_weeks
    from public.rh_weekly_records record
    join public.profiles profile on profile.user_id = record.employee_id and profile.status = 'active'
    where record.week_start <= p_end_date and record.week_end >= p_start_date
    group by record.employee_id
  ), goal_summary as (
    select
      count(*) filter (where goal.below_weeks = 0 and goal.met_weeks > 0)::integer as met_professionals,
      count(*) filter (where goal.below_weeks > 0)::integer as below_professionals,
      count(*) filter (where goal.excused_weeks > 0 and goal.met_weeks = 0 and goal.below_weeks = 0)::integer as fully_excused_professionals
    from goal_by_employee goal
  ), financial as (
    select
      count(*)::integer as attendance_count,
      coalesce(sum(attendance.total), 0) as total_amount,
      count(distinct attendance.patient_id) filter (where attendance.patient_id is not null)::integer as unique_patients,
      count(distinct attendance.performed_by)::integer as participating_professionals
    from public.attendances attendance
    where v_financial
      and attendance.status = 'completed'
      and attendance.created_at >= (p_start_date::timestamp at time zone 'America/Sao_Paulo')
      and attendance.created_at < ((p_end_date + 1)::timestamp at time zone 'America/Sao_Paulo')
  )
  select jsonb_build_object(
    'period', jsonb_build_object('start', p_start_date, 'end', p_end_date),
    'financial_access', v_financial,
    'active_professionals', (
      select count(*)::integer from public.profiles profile
      where profile.status = 'active' and profile.role_code <> 'diretor_geral'
    ),
    'hours_minutes', coalesce((select sum(hours.worked_minutes) from private.hpsm_report_hours(p_start_date, p_end_date) hours), 0),
    'met_professionals', coalesce(goal_summary.met_professionals, 0),
    'below_professionals', coalesce(goal_summary.below_professionals, 0),
    'fully_excused_professionals', coalesce(goal_summary.fully_excused_professionals, 0)
  ) || case when v_financial then jsonb_build_object(
    'attendance_count', financial.attendance_count,
    'total_amount', financial.total_amount,
    'ticket_average', case when financial.attendance_count = 0 then 0 else round(financial.total_amount / financial.attendance_count, 2) end,
    'unique_patients', financial.unique_patients,
    'participating_professionals', financial.participating_professionals
  ) else '{}'::jsonb end
  into v_result
  from goal_summary cross join financial;

  return v_result;
end;
$$;

create or replace function public.hpsm_report_hr(
  p_start_date date,
  p_end_date date,
  p_position_id bigint,
  p_status text,
  p_search text,
  p_sort text,
  p_direction text,
  p_page integer,
  p_page_size integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_status text := coalesce(nullif(p_status, ''), 'active');
  v_search text := btrim(coalesce(p_search, ''));
  v_sort text := coalesce(nullif(p_sort, ''), 'name');
  v_direction text := coalesce(nullif(p_direction, ''), 'asc');
  v_page integer := greatest(1, coalesce(p_page, 1));
  v_page_size integer := least(100, greatest(1, coalesce(p_page_size, 25)));
  v_result jsonb;
begin
  if not private.has_permission(v_actor, 'hr.reports.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  perform private.hpsm_report_validate_period(p_start_date, p_end_date);
  if v_status not in ('all', 'active', 'suspended')
     or v_sort not in ('name', 'position', 'hours', 'difference', 'status')
     or v_direction not in ('asc', 'desc')
     or char_length(v_search) > 80 then
    raise exception 'Filtros inválidos.' using errcode = '22023';
  end if;

  with hours as (
    select * from private.hpsm_report_hours(p_start_date, p_end_date)
  ), goals as (
    select
      record.employee_id,
      count(*)::integer as recorded_weeks,
      coalesce(sum(record.base_required_minutes), 0)::bigint as base_target_minutes,
      coalesce(sum(record.leave_deduction_minutes), 0)::bigint as leave_minutes,
      coalesce(sum(record.required_minutes), 0)::bigint as effective_target_minutes,
      count(*) filter (where record.required_minutes = 0)::integer as excused_weeks,
      count(*) filter (where record.required_minutes > 0 and record.remaining_deficit_minutes = 0)::integer as met_weeks,
      count(*) filter (where record.remaining_deficit_minutes > 0)::integer as below_weeks
    from public.rh_weekly_records record
    where record.week_start <= p_end_date and record.week_end >= p_start_date
    group by record.employee_id
  ), rows as (
    select
      profile.user_id,
      profile.display_name,
      profile.passport,
      profile.position_id,
      coalesce(position.name, 'Cargo não informado') as position_name,
      profile.status,
      coalesce(hours.worked_minutes, 0)::bigint as worked_minutes,
      coalesce(goals.base_target_minutes, 0)::bigint as base_target_minutes,
      coalesce(goals.leave_minutes, 0)::bigint as leave_minutes,
      coalesce(goals.effective_target_minutes, 0)::bigint as effective_target_minutes,
      (coalesce(hours.worked_minutes, 0) - coalesce(goals.effective_target_minutes, 0))::bigint as difference_minutes,
      coalesce(goals.recorded_weeks, 0)::integer as recorded_weeks,
      coalesce(goals.met_weeks, 0)::integer as met_weeks,
      coalesce(goals.below_weeks, 0)::integer as below_weeks,
      coalesce(goals.excused_weeks, 0)::integer as excused_weeks,
      case
        when coalesce(goals.recorded_weeks, 0) = 0 then 'no_data'
        when goals.below_weeks > 0 then 'below'
        when goals.excused_weeks > 0 and goals.met_weeks = 0 then 'fully_excused'
        else 'met'
      end as goal_status,
      exists (
        select 1 from public.rh_absence_requests absence
        where absence.employee_id = profile.user_id and absence.status = 'approved'
          and absence.start_date <= p_end_date and absence.end_date >= p_start_date
      ) as has_absence,
      exists (
        select 1 from public.rh_hour_justifications justification
        join public.rh_weekly_records weekly on weekly.id = justification.weekly_record_id
        where justification.employee_id = profile.user_id
          and weekly.week_start <= p_end_date and weekly.week_end >= p_start_date
      ) as has_justification,
      (
        select count(*)::integer from public.rh_warnings warning
        where warning.employee_id = profile.user_id and warning.status = 'active'
          and warning.cycle_month between pg_catalog.date_trunc('month', p_start_date::timestamp)::date
            and pg_catalog.date_trunc('month', p_end_date::timestamp)::date
      ) as active_warnings
    from public.profiles profile
    left join public.staff_positions position on position.id = profile.position_id
    left join hours on hours.employee_id = profile.user_id
    left join goals on goals.employee_id = profile.user_id
    where profile.role_code <> 'diretor_geral'
      and profile.status <> 'inactive'
  ), filtered as (
    select * from rows
    where (v_status = 'all' or status = v_status)
      and (p_position_id is null or position_id = p_position_id)
      and (v_search = '' or passport like '%' || v_search || '%' or lower(display_name) like '%' || lower(v_search) || '%')
  ), ordered as (
    select filtered.*,
      row_number() over (order by
        case when v_sort = 'name' and v_direction = 'asc' then display_name end asc,
        case when v_sort = 'name' and v_direction = 'desc' then display_name end desc,
        case when v_sort = 'position' and v_direction = 'asc' then position_name end asc,
        case when v_sort = 'position' and v_direction = 'desc' then position_name end desc,
        case when v_sort = 'hours' and v_direction = 'asc' then worked_minutes end asc,
        case when v_sort = 'hours' and v_direction = 'desc' then worked_minutes end desc,
        case when v_sort = 'difference' and v_direction = 'asc' then difference_minutes end asc,
        case when v_sort = 'difference' and v_direction = 'desc' then difference_minutes end desc,
        case when v_sort = 'status' and v_direction = 'asc' then goal_status end asc,
        case when v_sort = 'status' and v_direction = 'desc' then goal_status end desc,
        display_name asc, user_id asc
      ) as row_number
    from filtered
  ), paged as (
    select * from ordered
    where row_number > (v_page - 1) * v_page_size
      and row_number <= v_page * v_page_size
  )
  select jsonb_build_object(
    'items', coalesce((select jsonb_agg(jsonb_build_object(
      'id', item.user_id,
      'name', item.display_name,
      'passport', item.passport,
      'position_id', item.position_id,
      'position', item.position_name,
      'profile_status', item.status,
      'worked_minutes', item.worked_minutes,
      'base_target_minutes', item.base_target_minutes,
      'leave_minutes', item.leave_minutes,
      'effective_target_minutes', item.effective_target_minutes,
      'difference_minutes', item.difference_minutes,
      'recorded_weeks', item.recorded_weeks,
      'met_weeks', item.met_weeks,
      'below_weeks', item.below_weeks,
      'excused_weeks', item.excused_weeks,
      'goal_status', item.goal_status,
      'has_absence', item.has_absence,
      'has_justification', item.has_justification,
      'active_warnings', item.active_warnings
    ) order by item.row_number) from paged item), '[]'::jsonb),
    'total', (select count(*)::integer from filtered),
    'page', v_page,
    'page_size', v_page_size,
    'positions', coalesce((select jsonb_agg(jsonb_build_object('id', position.id, 'name', position.name) order by position.sort_order, position.name)
      from public.staff_positions position where position.active), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

create or replace function public.hpsm_report_financial(
  p_start_date date,
  p_end_date date,
  p_employee_id uuid,
  p_position_id bigint,
  p_sort text,
  p_direction text,
  p_page integer,
  p_page_size integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_sort text := coalesce(nullif(p_sort, ''), 'value');
  v_direction text := coalesce(nullif(p_direction, ''), 'desc');
  v_page integer := greatest(1, coalesce(p_page, 1));
  v_page_size integer := least(100, greatest(1, coalesce(p_page_size, 25)));
  v_result jsonb;
begin
  if not private.has_permission(v_actor, 'hr.reports.view')
     or not private.has_permission(v_actor, 'attendances.manage') then
    raise exception 'Acesso financeiro não autorizado.' using errcode = '42501';
  end if;
  perform private.hpsm_report_validate_period(p_start_date, p_end_date);
  if v_sort not in ('name', 'attendances', 'items', 'value') or v_direction not in ('asc', 'desc') then
    raise exception 'Ordenação inválida.' using errcode = '22023';
  end if;

  with filtered_attendances as (
    select attendance.*, profile.display_name, profile.passport, profile.position_id,
      coalesce(position.name, 'Cargo não informado') as position_name
    from public.attendances attendance
    join public.profiles profile on profile.user_id = attendance.performed_by
    left join public.staff_positions position on position.id = profile.position_id
    where attendance.status = 'completed'
      and attendance.created_at >= (p_start_date::timestamp at time zone 'America/Sao_Paulo')
      and attendance.created_at < ((p_end_date + 1)::timestamp at time zone 'America/Sao_Paulo')
      and (p_employee_id is null or attendance.performed_by = p_employee_id)
      and (p_position_id is null or profile.position_id = p_position_id)
  ), item_by_attendance as (
    select item.attendance_id, coalesce(sum(item.quantity), 0)::integer as item_count
    from public.attendance_items item
    join filtered_attendances attendance on attendance.id = item.attendance_id
    group by item.attendance_id
  ), production as (
    select
      attendance.performed_by as employee_id,
      attendance.display_name,
      attendance.passport,
      attendance.position_id,
      attendance.position_name,
      count(*)::integer as attendance_count,
      coalesce(sum(item.item_count), 0)::integer as item_count,
      coalesce(sum(attendance.total), 0) as total_amount,
      case when count(*) = 0 then 0 else round(sum(attendance.total) / count(*), 2) end as ticket_average
    from filtered_attendances attendance
    left join item_by_attendance item on item.attendance_id = attendance.id
    group by attendance.performed_by, attendance.display_name, attendance.passport, attendance.position_id, attendance.position_name
  ), ordered as (
    select production.*,
      row_number() over (order by
        case when v_sort = 'name' and v_direction = 'asc' then display_name end asc,
        case when v_sort = 'name' and v_direction = 'desc' then display_name end desc,
        case when v_sort = 'attendances' and v_direction = 'asc' then attendance_count end asc,
        case when v_sort = 'attendances' and v_direction = 'desc' then attendance_count end desc,
        case when v_sort = 'items' and v_direction = 'asc' then item_count end asc,
        case when v_sort = 'items' and v_direction = 'desc' then item_count end desc,
        case when v_sort = 'value' and v_direction = 'asc' then total_amount end asc,
        case when v_sort = 'value' and v_direction = 'desc' then total_amount end desc,
        display_name asc, employee_id asc
      ) as row_number
    from production
  ), paged as (
    select * from ordered
    where row_number > (v_page - 1) * v_page_size and row_number <= v_page * v_page_size
  ), totals as (
    select
      count(*)::integer as attendance_count,
      coalesce(sum(attendance.total), 0) as total_amount,
      coalesce(sum(item.item_count), 0)::integer as item_count,
      count(distinct attendance.performed_by)::integer as professional_count,
      count(distinct attendance.patient_id) filter (where attendance.patient_id is not null)::integer as unique_patients
    from filtered_attendances attendance
    left join item_by_attendance item on item.attendance_id = attendance.id
  ), top_items as (
    select
      item.service_id,
      item.service_name,
      coalesce(catalog.category, 'Sem categoria') as category,
      sum(item.quantity)::integer as quantity,
      coalesce(sum(item.line_total), 0) as total_amount
    from public.attendance_items item
    join filtered_attendances attendance on attendance.id = item.attendance_id
    left join public.service_catalog catalog on catalog.id = item.service_id
    group by item.service_id, item.service_name, catalog.category
    order by sum(item.quantity) desc, sum(item.line_total) desc, item.service_name
    limit 10
  ), benefits as (
    select
      coalesce(attendance.plan_code, 'none') as code,
      coalesce(max(attendance.plan_name), 'Sem benefício') as name,
      count(*)::integer as attendance_count,
      coalesce(sum(attendance.total), 0) as total_amount,
      coalesce(sum(attendance.discount), 0) as discount_amount
    from filtered_attendances attendance
    group by attendance.plan_code
    order by count(*) desc, coalesce(attendance.plan_code, 'none')
  )
  select jsonb_build_object(
    'summary', jsonb_build_object(
      'attendance_count', totals.attendance_count,
      'total_amount', totals.total_amount,
      'ticket_average', case when totals.attendance_count = 0 then 0 else round(totals.total_amount / totals.attendance_count, 2) end,
      'item_count', totals.item_count,
      'professional_count', totals.professional_count,
      'unique_patients', totals.unique_patients
    ),
    'production', coalesce((select jsonb_agg(jsonb_build_object(
      'employee_id', item.employee_id,
      'name', item.display_name,
      'passport', item.passport,
      'position_id', item.position_id,
      'position', item.position_name,
      'attendance_count', item.attendance_count,
      'item_count', item.item_count,
      'total_amount', item.total_amount,
      'ticket_average', item.ticket_average
    ) order by item.row_number) from paged item), '[]'::jsonb),
    'production_total', (select count(*)::integer from production),
    'page', v_page,
    'page_size', v_page_size,
    'top_items', coalesce((select jsonb_agg(jsonb_build_object(
      'service_id', item.service_id,
      'name', item.service_name,
      'category', item.category,
      'quantity', item.quantity,
      'total_amount', item.total_amount
    ) order by item.quantity desc, item.total_amount desc, item.service_name) from top_items item), '[]'::jsonb),
    'benefits', coalesce((select jsonb_agg(jsonb_build_object(
      'code', benefit.code,
      'name', benefit.name,
      'attendance_count', benefit.attendance_count,
      'total_amount', benefit.total_amount,
      'discount_amount', benefit.discount_amount
    ) order by benefit.attendance_count desc, benefit.code) from benefits benefit), '[]'::jsonb),
    'positions', coalesce((select jsonb_agg(jsonb_build_object('id', position.id, 'name', position.name) order by position.sort_order, position.name)
      from public.staff_positions position where position.active), '[]'::jsonb)
  ) into v_result
  from totals;
  return v_result;
end;
$$;

create or replace function public.hpsm_report_team(p_start_date date, p_end_date date)
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
  if not private.has_permission(v_actor, 'hr.reports.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  perform private.hpsm_report_validate_period(p_start_date, p_end_date);

  select jsonb_build_object(
    'summary', jsonb_build_object(
      'active_professionals', (select count(*)::integer from public.profiles profile where profile.status = 'active' and profile.role_code <> 'diretor_geral'),
      'admissions', (select count(*)::integer from public.profiles profile where profile.role_code <> 'diretor_geral'
        and profile.created_at >= (p_start_date::timestamp at time zone 'America/Sao_Paulo')
        and profile.created_at < ((p_end_date + 1)::timestamp at time zone 'America/Sao_Paulo')),
      'promotions', (select count(*)::integer from public.staff_position_history history where history.event_type = 'promotion'
        and history.effective_at >= (p_start_date::timestamp at time zone 'America/Sao_Paulo')
        and history.effective_at < ((p_end_date + 1)::timestamp at time zone 'America/Sao_Paulo')),
      'approved_absences', (select count(*)::integer from public.rh_absence_requests absence where absence.status = 'approved'
        and absence.start_date <= p_end_date and absence.end_date >= p_start_date),
      'suspensions', (select count(*)::integer from public.profiles profile where profile.status = 'suspended' and profile.role_code <> 'diretor_geral')
    ),
    'admissions', coalesce((select jsonb_agg(jsonb_build_object(
      'employee_id', admission.user_id,
      'name', admission.display_name,
      'passport', admission.passport,
      'position', admission.position_name,
      'date', admission.admission_date
    ) order by admission.admission_date desc, admission.display_name) from (
      select profile.user_id, profile.display_name, profile.passport, coalesce(position.name, 'Cargo não informado') as position_name,
        (profile.created_at at time zone 'America/Sao_Paulo')::date as admission_date
      from public.profiles profile left join public.staff_positions position on position.id = profile.position_id
      where profile.role_code <> 'diretor_geral'
        and profile.created_at >= (p_start_date::timestamp at time zone 'America/Sao_Paulo')
        and profile.created_at < ((p_end_date + 1)::timestamp at time zone 'America/Sao_Paulo')
      order by profile.created_at desc limit 20
    ) admission), '[]'::jsonb),
    'promotions', coalesce((select jsonb_agg(jsonb_build_object(
      'employee_id', promotion.employee_id,
      'name', promotion.display_name,
      'passport', promotion.passport,
      'from_position', promotion.from_position,
      'to_position', promotion.to_position,
      'date', promotion.promotion_date
    ) order by promotion.promotion_date desc, promotion.display_name) from (
      select history.employee_id, profile.display_name, profile.passport,
        coalesce(previous.name, 'Sem cargo anterior') as from_position,
        current.name as to_position,
        (history.effective_at at time zone 'America/Sao_Paulo')::date as promotion_date
      from public.staff_position_history history
      join public.profiles profile on profile.user_id = history.employee_id
      left join public.staff_positions previous on previous.id = history.from_position_id
      join public.staff_positions current on current.id = history.to_position_id
      where history.event_type = 'promotion'
        and history.effective_at >= (p_start_date::timestamp at time zone 'America/Sao_Paulo')
        and history.effective_at < ((p_end_date + 1)::timestamp at time zone 'America/Sao_Paulo')
      order by history.effective_at desc limit 20
    ) promotion), '[]'::jsonb),
    'absences', coalesce((select jsonb_agg(jsonb_build_object(
      'employee_id', absence.employee_id,
      'name', absence.display_name,
      'passport', absence.passport,
      'position', absence.position_name,
      'start_date', absence.start_date,
      'end_date', absence.end_date,
      'deducted_minutes', absence.deducted_minutes
    ) order by absence.start_date desc, absence.display_name) from (
      select request.employee_id, profile.display_name, profile.passport,
        coalesce(position.name, 'Cargo não informado') as position_name,
        request.start_date, request.end_date,
        coalesce(sum(adjustment.deducted_minutes), 0)::integer as deducted_minutes
      from public.rh_absence_requests request
      join public.profiles profile on profile.user_id = request.employee_id
      left join public.staff_positions position on position.id = profile.position_id
      left join public.rh_leave_week_adjustments adjustment on adjustment.leave_request_id = request.id
      where request.status = 'approved' and request.start_date <= p_end_date and request.end_date >= p_start_date
      group by request.id, request.employee_id, profile.display_name, profile.passport, position.name, request.start_date, request.end_date
      order by request.start_date desc limit 20
    ) absence), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

create or replace function public.hpsm_report_individual(
  p_start_date date,
  p_end_date date,
  p_employee_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_financial boolean;
  v_courses boolean;
  v_result jsonb;
begin
  if not private.has_permission(v_actor, 'hr.reports.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  perform private.hpsm_report_validate_period(p_start_date, p_end_date);
  if p_employee_id is null then raise exception 'Selecione um profissional.' using errcode = '22023'; end if;
  v_financial := private.has_permission(v_actor, 'attendances.manage');
  v_courses := private.has_permission(v_actor, 'courses.view');

  with employee as (
    select profile.user_id, profile.display_name, profile.passport, profile.status, profile.position_id,
      coalesce(position.name, 'Cargo não informado') as position_name
    from public.profiles profile
    left join public.staff_positions position on position.id = profile.position_id
    where profile.user_id = p_employee_id and profile.role_code <> 'diretor_geral'
  ), hours as (
    select coalesce(sum(value.worked_minutes), 0)::bigint as worked_minutes
    from private.hpsm_report_hours(p_start_date, p_end_date) value where value.employee_id = p_employee_id
  ), goals as (
    select
      count(*)::integer as recorded_weeks,
      coalesce(sum(record.base_required_minutes), 0)::bigint as base_target_minutes,
      coalesce(sum(record.leave_deduction_minutes), 0)::bigint as leave_minutes,
      coalesce(sum(record.required_minutes), 0)::bigint as effective_target_minutes,
      count(*) filter (where record.required_minutes = 0)::integer as excused_weeks,
      count(*) filter (where record.required_minutes > 0 and record.remaining_deficit_minutes = 0)::integer as met_weeks,
      count(*) filter (where record.remaining_deficit_minutes > 0)::integer as below_weeks
    from public.rh_weekly_records record
    where record.employee_id = p_employee_id and record.week_start <= p_end_date and record.week_end >= p_start_date
  ), production as (
    select count(*)::integer as attendance_count, coalesce(sum(attendance.total), 0) as total_amount
    from public.attendances attendance
    where v_financial and attendance.performed_by = p_employee_id and attendance.status = 'completed'
      and attendance.created_at >= (p_start_date::timestamp at time zone 'America/Sao_Paulo')
      and attendance.created_at < ((p_end_date + 1)::timestamp at time zone 'America/Sao_Paulo')
  ), production_items as (
    select coalesce(sum(item.quantity), 0)::integer as item_count
    from public.attendance_items item
    join public.attendances attendance on attendance.id = item.attendance_id
    where v_financial and attendance.performed_by = p_employee_id and attendance.status = 'completed'
      and attendance.created_at >= (p_start_date::timestamp at time zone 'America/Sao_Paulo')
      and attendance.created_at < ((p_end_date + 1)::timestamp at time zone 'America/Sao_Paulo')
  ), rh as (
    select
      (select count(*)::integer from public.rh_warnings warning where warning.employee_id = p_employee_id and warning.status = 'active'
        and warning.cycle_month between pg_catalog.date_trunc('month', p_start_date::timestamp)::date and pg_catalog.date_trunc('month', p_end_date::timestamp)::date) as active_warnings,
      (select count(*)::integer from public.rh_absence_requests absence where absence.employee_id = p_employee_id and absence.status = 'approved'
        and absence.start_date <= p_end_date and absence.end_date >= p_start_date) as absences,
      (select count(*)::integer from public.rh_hour_justifications justification join public.rh_weekly_records weekly on weekly.id = justification.weekly_record_id
        where justification.employee_id = p_employee_id and weekly.week_start <= p_end_date and weekly.week_end >= p_start_date) as justifications
  )
  select jsonb_build_object(
    'found', exists(select 1 from employee),
    'financial_access', v_financial,
    'profile', coalesce((select jsonb_build_object(
      'id', employee.user_id, 'name', employee.display_name, 'passport', employee.passport,
      'position_id', employee.position_id, 'position', employee.position_name, 'status', employee.status
    ) from employee), 'null'::jsonb),
    'period', jsonb_build_object('start', p_start_date, 'end', p_end_date),
    'journey', jsonb_build_object(
      'worked_minutes', hours.worked_minutes,
      'base_target_minutes', goals.base_target_minutes,
      'leave_minutes', goals.leave_minutes,
      'effective_target_minutes', goals.effective_target_minutes,
      'difference_minutes', hours.worked_minutes - goals.effective_target_minutes,
      'recorded_weeks', goals.recorded_weeks,
      'met_weeks', goals.met_weeks,
      'below_weeks', goals.below_weeks,
      'excused_weeks', goals.excused_weeks
    ),
    'rh', jsonb_build_object('active_warnings', rh.active_warnings, 'absences', rh.absences, 'justifications', rh.justifications),
    'production', case when v_financial then jsonb_build_object(
      'attendance_count', production.attendance_count,
      'item_count', production_items.item_count,
      'total_amount', production.total_amount,
      'ticket_average', case when production.attendance_count = 0 then 0 else round(production.total_amount / production.attendance_count, 2) end
    ) else 'null'::jsonb end,
    'career', jsonb_build_object(
      'promotions', coalesce((select jsonb_agg(jsonb_build_object(
        'from_position', coalesce(previous.name, 'Sem cargo anterior'),
        'to_position', current.name,
        'date', (history.effective_at at time zone 'America/Sao_Paulo')::date
      ) order by history.effective_at desc)
        from public.staff_position_history history
        left join public.staff_positions previous on previous.id = history.from_position_id
        join public.staff_positions current on current.id = history.to_position_id
        where history.employee_id = p_employee_id and history.event_type = 'promotion'
          and history.effective_at >= (p_start_date::timestamp at time zone 'America/Sao_Paulo')
          and history.effective_at < ((p_end_date + 1)::timestamp at time zone 'America/Sao_Paulo')), '[]'::jsonb),
      'completed_courses', case when v_courses then (select count(*)::integer from public.staff_course_records course
        where course.employee_id = p_employee_id and course.status = 'completed'
          and course.completed_at >= (p_start_date::timestamp at time zone 'America/Sao_Paulo')
          and course.completed_at < ((p_end_date + 1)::timestamp at time zone 'America/Sao_Paulo')) else null end
    )
  ) into v_result
  from hours cross join goals cross join production cross join production_items cross join rh;
  return v_result;
end;
$$;

revoke all on function public.hpsm_report_staff_search(text, integer) from public, anon, authenticated, service_role;
revoke all on function public.hpsm_report_overview(date, date) from public, anon, authenticated, service_role;
revoke all on function public.hpsm_report_hr(date, date, bigint, text, text, text, text, integer, integer) from public, anon, authenticated, service_role;
revoke all on function public.hpsm_report_financial(date, date, uuid, bigint, text, text, integer, integer) from public, anon, authenticated, service_role;
revoke all on function public.hpsm_report_team(date, date) from public, anon, authenticated, service_role;
revoke all on function public.hpsm_report_individual(date, date, uuid) from public, anon, authenticated, service_role;

grant execute on function public.hpsm_report_staff_search(text, integer) to authenticated;
grant execute on function public.hpsm_report_overview(date, date) to authenticated;
grant execute on function public.hpsm_report_hr(date, date, bigint, text, text, text, text, integer, integer) to authenticated;
grant execute on function public.hpsm_report_financial(date, date, uuid, bigint, text, text, integer, integer) to authenticated;
grant execute on function public.hpsm_report_team(date, date) to authenticated;
grant execute on function public.hpsm_report_individual(date, date, uuid) to authenticated;

comment on function public.hpsm_report_overview(date, date) is 'Resumo executivo da Fase 8; valores financeiros são omitidos sem attendances.manage.';
comment on function public.hpsm_report_hr(date, date, bigint, text, text, text, text, integer, integer) is 'Jornada administrativa paginada derivada de snapshots e fechamentos semanais canônicos.';
comment on function public.hpsm_report_financial(date, date, uuid, bigint, text, text, integer, integer) is 'Produção, itens e benefícios históricos; requer hr.reports.view e attendances.manage.';
comment on function public.hpsm_report_team(date, date) is 'Agregados administrativos de admissões, promoções, afastamentos e suspensões.';
comment on function public.hpsm_report_individual(date, date, uuid) is 'Consolidação individual do período sem duplicar o Perfil Funcional.';
