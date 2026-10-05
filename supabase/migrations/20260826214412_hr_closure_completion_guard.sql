create or replace function public.finalize_hr_week_closure(
  p_week_start date,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_closure public.rh_week_closures;
  v_count integer;
  v_deficits integer;
begin
  if not private.is_director_user(p_actor_id) then
    raise exception using errcode = '42501', message = 'Apenas a Diretoria pode confirmar o fechamento.';
  end if;
  if p_week_start is null or extract(isodow from p_week_start) <> 1 then
    raise exception using errcode = '22023', message = 'Semana inválida.';
  end if;

  select * into v_closure
  from public.rh_week_closures
  where week_start = p_week_start
  for update;
  if not found or v_closure.status not in ('open', 'reopened') then
    raise exception using errcode = 'P0002', message = 'A semana não está disponível para fechamento.';
  end if;
  if v_closure.week_end > (now() at time zone 'America/Sao_Paulo')::date then
    raise exception using errcode = '22023', message = 'A semana ainda não terminou.';
  end if;
  if exists (
    select 1
    from public.profiles profile
    where profile.role_code <> 'diretor_geral'
      and profile.status = 'active'
      and not exists (
        select 1 from public.rh_weekly_records record
        where record.closure_id = v_closure.id
          and record.employee_id = profile.user_id
      )
  ) then
    raise exception using errcode = 'P0001', message = 'Ainda existem colaboradores ativos sem apuração nesta semana.';
  end if;
  if exists (
    select 1 from public.rh_weekly_records
    where closure_id = v_closure.id and closure_status = 'justification_pending'
  ) then
    raise exception using errcode = 'P0001', message = 'Ainda existem justificativas enviadas aguardando análise.';
  end if;

  select count(*)::integer,
         count(*) filter (where remaining_deficit_minutes > 0)::integer
  into v_count, v_deficits
  from public.rh_weekly_records
  where closure_id = v_closure.id;
  if v_count = 0 then
    raise exception using errcode = 'P0001', message = 'Nenhum colaborador foi apurado nesta semana.';
  end if;

  update public.rh_weekly_records
  set closure_status = 'closed',
      closed_by = p_actor_id,
      closed_at = now(),
      updated_at = now()
  where closure_id = v_closure.id;

  update public.rh_week_closures
  set status = 'closed',
      closed_by = p_actor_id,
      closed_at = now(),
      updated_at = now()
  where id = v_closure.id
  returning * into v_closure;

  return jsonb_build_object(
    'closure', to_jsonb(v_closure),
    'records', v_count,
    'deficits', v_deficits
  );
end;
$$;

revoke all on function public.finalize_hr_week_closure(date, uuid) from public, anon, authenticated, service_role;
grant execute on function public.finalize_hr_week_closure(date, uuid) to service_role;
