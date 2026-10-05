-- HPSM · agregação server-side do relatório de produção.
-- Evita transferir todas as vendas do período para agrupamento no App Server.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function public.hpsm_hr_production(p_month text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_month_start date;
  v_month_last date;
  v_range_start date;
  v_range_end date;
  v_result jsonb;
begin
  if not private.has_permission(v_actor, 'hr.reports.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if p_month is null or p_month !~ '^\d{4}-(0[1-9]|1[0-2])$' then
    raise exception 'Competência inválida.' using errcode = '22023';
  end if;

  v_month_start := to_date(p_month || '-01', 'YYYY-MM-DD');
  if to_char(v_month_start, 'YYYY-MM') <> p_month then
    raise exception 'Competência inválida.' using errcode = '22023';
  end if;

  v_month_last := (v_month_start + interval '1 month - 1 day')::date;
  v_range_start := v_month_start - (extract(isodow from v_month_start)::integer - 1);
  v_range_end := v_month_last + (8 - extract(isodow from v_month_last)::integer);

  select jsonb_build_object(
    'month', p_month,
    'days', coalesce(jsonb_agg(
      jsonb_build_object(
        'employee_id', grouped.employee_id,
        'date', grouped.work_date,
        'attendance_count', grouped.attendance_count,
        'total_amount', grouped.total_amount
      ) order by grouped.work_date, grouped.employee_id
    ), '[]'::jsonb)
  )
  into v_result
  from (
    select
      attendance.performed_by as employee_id,
      (attendance.created_at at time zone 'America/Sao_Paulo')::date as work_date,
      count(*)::integer as attendance_count,
      coalesce(sum(attendance.total), 0) as total_amount
    from public.attendances attendance
    where attendance.status = 'completed'
      and attendance.created_at >= (v_range_start::timestamp at time zone 'America/Sao_Paulo')
      and attendance.created_at < (v_range_end::timestamp at time zone 'America/Sao_Paulo')
    group by attendance.performed_by, (attendance.created_at at time zone 'America/Sao_Paulo')::date
  ) grouped;

  return v_result;
end;
$$;

revoke all on function public.hpsm_hr_production(text)
  from public, anon;
grant execute on function public.hpsm_hr_production(text)
  to authenticated;

comment on function public.hpsm_hr_production(text) is
  'Produção mensal agregada no banco, incluindo as semanas limítrofes usadas pela apuração de RH.';
