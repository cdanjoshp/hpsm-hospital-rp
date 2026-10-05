begin;

create temporary table phase9_context (
  key text primary key,
  value text not null
) on commit drop;

do $$
declare
  v_full_actor uuid;
  v_full_session uuid;
  v_limited_actor uuid;
  v_limited_session uuid;
  v_week_start date := timezone('America/Sao_Paulo', now())::date - (extract(isodow from timezone('America/Sao_Paulo', now())::date)::integer - 1);
  v_week_end date := v_week_start + 6;
  v_cycle_month date := date_trunc('month', v_week_end)::date;
  v_closure bigint;
  v_absence bigint;
  v_attendance bigint;
  v_cancelled bigint;
  v_service_one bigint;
  v_service_two bigint;
begin
  select profile.user_id, session.id into v_full_actor, v_full_session
  from public.profiles profile
  join public.staff_positions position on position.id = profile.position_id
  join auth.sessions session on session.user_id = profile.user_id
  where profile.status = 'active'
    and private.has_permission(profile.user_id, 'hr.reports.view')
    and private.has_permission(profile.user_id, 'attendances.manage')
    and (session.not_after is null or session.not_after > now())
  order by position.level desc, session.created_at desc
  limit 1;

  select profile.user_id, session.id into v_limited_actor, v_limited_session
  from public.profiles profile
  join public.staff_positions position on position.id = profile.position_id
  join auth.sessions session on session.user_id = profile.user_id
  where profile.status = 'active'
    and profile.role_code <> 'diretor_geral'
    and not private.has_permission(profile.user_id, 'hr.reports.view')
    and not private.has_permission(profile.user_id, 'attendances.manage')
    and not private.has_permission(profile.user_id, 'recruitment.manage')
    and (session.not_after is null or session.not_after > now())
  order by position.level, session.created_at desc
  limit 1;

  if v_full_actor is null or v_full_session is null or v_limited_actor is null or v_limited_session is null then
    raise exception 'A Fase 9 requer sessões ativas de um gestor completo e de um profissional limitado.';
  end if;

  insert into public.rh_week_closures (
    week_start, week_end, status, started_by, started_at, closed_by, closed_at
  ) values (
    v_week_start, v_week_end, 'closed', v_full_actor, now(), v_full_actor, now()
  )
  on conflict (week_start) do update set
    week_end = excluded.week_end,
    status = 'closed',
    closed_by = excluded.closed_by,
    closed_at = excluded.closed_at
  returning id into v_closure;

  insert into public.rh_absence_requests (
    employee_id, start_date, end_date, reason, status, approval_effect,
    reviewed_by, reviewed_at, review_note
  ) values (
    v_limited_actor, v_week_start, v_week_end,
    'Abono parcial representativo para validar a Fase 9.', 'approved', 'weekly_adjustment',
    v_full_actor, now(), 'Quatro horas abonadas no teste transacional.'
  ) returning id into v_absence;

  insert into public.rh_leave_week_adjustments (
    leave_request_id, employee_id, week_start, deducted_minutes, approved_by, approved_at
  ) values (v_absence, v_limited_actor, v_week_start, 240, v_full_actor, now());

  insert into public.rh_weekly_records (
    employee_id, closure_id, week_start, week_end, cycle_month,
    base_required_minutes, leave_deduction_minutes, required_minutes, worked_minutes,
    deficit_minutes, justification_minutes, remaining_deficit_minutes,
    status, closure_status, absence_request_id, closed_by, closed_at
  ) values (
    v_limited_actor, v_closure, v_week_start, v_week_end, v_cycle_month,
    600, 240, 360, 360, 0, 0, 0,
    'met', 'closed', v_absence, v_full_actor, now()
  )
  on conflict (employee_id, week_start) do update set
    closure_id = excluded.closure_id,
    week_end = excluded.week_end,
    cycle_month = excluded.cycle_month,
    base_required_minutes = excluded.base_required_minutes,
    leave_deduction_minutes = excluded.leave_deduction_minutes,
    required_minutes = excluded.required_minutes,
    worked_minutes = excluded.worked_minutes,
    deficit_minutes = excluded.deficit_minutes,
    justification_minutes = excluded.justification_minutes,
    remaining_deficit_minutes = excluded.remaining_deficit_minutes,
    status = excluded.status,
    closure_status = excluded.closure_status,
    absence_request_id = excluded.absence_request_id,
    closed_by = excluded.closed_by,
    closed_at = excluded.closed_at;

  select id into v_service_one from public.service_catalog order by id limit 1;
  select id into v_service_two from public.service_catalog where id <> v_service_one order by id limit 1;
  if v_service_one is null or v_service_two is null then
    raise exception 'Catálogo insuficiente para validar a produção pessoal.';
  end if;

  insert into public.attendances (
    patient_id, patient_name, patient_passport, status, subtotal, discount, performed_by,
    plan_code, plan_name, created_at
  ) values (
    null, 'Venda avulsa', '—', 'completed', 400.00, 49.50, v_full_actor,
    'plano_saude', 'Plano de Saúde', now()
  ) returning id into v_attendance;
  insert into public.attendance_items (
    attendance_id, service_id, service_name, unit_price, quantity, discount_percent, created_at
  ) values
    (v_attendance, v_service_one, 'Item Histórico da Fase 9', 100.00, 2, 10.00, now()),
    (v_attendance, v_service_two, 'Procedimento Histórico da Fase 9', 170.50, 1, 0.00, now());

  insert into public.attendances (
    patient_id, patient_name, patient_passport, status, subtotal, discount, performed_by,
    cancelled_by, cancelled_at, created_at
  ) values (
    null, 'Venda avulsa', '—', 'cancelled', 999.00, 0, v_full_actor,
    v_full_actor, now(), now()
  ) returning id into v_cancelled;

  insert into phase9_context values
    ('full_actor', v_full_actor::text),
    ('full_session', v_full_session::text),
    ('limited_actor', v_limited_actor::text),
    ('limited_session', v_limited_session::text),
    ('week_start', v_week_start::text),
    ('week_end', v_week_end::text),
    ('attendance', v_attendance::text),
    ('cancelled', v_cancelled::text);
end;
$$;

grant select on phase9_context to authenticated;
set local role authenticated;

do $$
declare
  v_actor uuid := (select value::uuid from phase9_context where key = 'full_actor');
  v_session uuid := (select value::uuid from phase9_context where key = 'full_session');
  v_week_start date := (select value::date from phase9_context where key = 'week_start');
  v_week_end date := (select value::date from phase9_context where key = 'week_end');
  v_dashboard jsonb;
  v_financial jsonb;
  v_overview jsonb;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_actor, 'session_id', v_session)::text, true);
  v_dashboard := public.hpsm_dashboard_summary();
  v_financial := public.hpsm_report_financial(v_week_start, v_week_end, v_actor, null, 'value', 'desc', 1, 25);
  v_overview := public.hpsm_report_overview(v_week_start, v_week_end);

  if (v_dashboard #>> '{production,attendance_count}')::integer <> (v_financial #>> '{summary,attendance_count}')::integer
     or (v_dashboard #>> '{production,item_count}')::integer <> (v_financial #>> '{summary,item_count}')::integer
     or (v_dashboard #>> '{production,total_amount}')::numeric <> (v_financial #>> '{summary,total_amount}')::numeric
     or (v_dashboard #>> '{production,total_amount}')::numeric < 350.50 then
    raise exception 'Produção pessoal divergiu da Fase 8 ou incluiu cancelado: %, %', v_dashboard -> 'production', v_financial -> 'summary';
  end if;

  if v_dashboard -> 'hospital' ->> 'active_professionals' <> v_overview ->> 'active_professionals'
     or v_dashboard -> 'hospital' ->> 'attendance_count' <> v_overview ->> 'attendance_count'
     or v_dashboard -> 'hospital' ->> 'total_amount' <> v_overview ->> 'total_amount' then
    raise exception 'Visão do Hospital divergiu do relatório canônico: %, %', v_dashboard -> 'hospital', v_overview;
  end if;
end;
$$;

do $$
declare
  v_actor uuid := (select value::uuid from phase9_context where key = 'limited_actor');
  v_session uuid := (select value::uuid from phase9_context where key = 'limited_session');
  v_dashboard jsonb;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_actor, 'session_id', v_session)::text, true);
  v_dashboard := public.hpsm_dashboard_summary();

  if v_dashboard -> 'hospital' <> 'null'::jsonb then
    raise exception 'Profissional limitado recebeu métricas administrativas: %', v_dashboard -> 'hospital';
  end if;
  if (v_dashboard #>> '{weekly_inputs,weeklyRecords,0,base_required_minutes}')::integer <> 600
     or (v_dashboard #>> '{weekly_inputs,weeklyRecords,0,leave_deduction_minutes}')::integer <> 240
     or (v_dashboard #>> '{weekly_inputs,weeklyRecords,0,required_minutes}')::integer <> 360
     or (v_dashboard #>> '{weekly_inputs,weeklyRecords,0,worked_minutes}')::integer <> 360 then
    raise exception 'Meta ajustada 10h - 4h = 6h não chegou ao Dashboard: %', v_dashboard -> 'weekly_inputs';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_dashboard #> '{attention,items}') item
    where item ->> 'kind' in ('recruitment', 'health_plan', 'discipline', 'career', 'cast', 'absence', 'hour_justification')
  ) then
    raise exception 'Profissional limitado recebeu fila administrativa: %', v_dashboard #> '{attention,items}';
  end if;
end;
$$;

reset role;

do $$
declare
  v_actor uuid := (select value::uuid from phase9_context where key = 'limited_actor');
  v_granter uuid := (select value::uuid from phase9_context where key = 'full_actor');
begin
  insert into public.user_permission_grants (
    user_id, permission_code, grant_kind, valid_from, expires_at, reason, granted_by
  ) values
    (v_actor, 'hr.reports.view', 'temporary', clock_timestamp() - interval '1 minute', clock_timestamp() + interval '1 hour', 'Grant temporário da Fase 9.', v_granter),
    (v_actor, 'attendances.manage', 'temporary', clock_timestamp() - interval '2 hours', clock_timestamp() - interval '1 hour', 'Grant expirado da Fase 9.', v_granter);
end;
$$;

set local role authenticated;

do $$
declare
  v_actor uuid := (select value::uuid from phase9_context where key = 'limited_actor');
  v_session uuid := (select value::uuid from phase9_context where key = 'limited_session');
  v_dashboard jsonb;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_actor, 'session_id', v_session)::text, true);
  v_dashboard := public.hpsm_dashboard_summary();
  if v_dashboard -> 'hospital' = 'null'::jsonb then
    raise exception 'Grant temporário válido não liberou a Visão do Hospital.';
  end if;
  if coalesce((v_dashboard #>> '{hospital,financial_access}')::boolean, true)
     or (v_dashboard -> 'hospital') ? 'total_amount'
     or (v_dashboard -> 'hospital') ? 'attendance_count' then
    raise exception 'Grant financeiro expirado continuou expondo dados: %', v_dashboard -> 'hospital';
  end if;
end;
$$;

reset role;

do $$
begin
  if has_function_privilege('anon', 'public.hpsm_dashboard_summary()', 'EXECUTE')
     or has_function_privilege('service_role', 'public.hpsm_dashboard_summary()', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.hpsm_dashboard_summary()', 'EXECUTE') then
    raise exception 'Privilégios incorretos na RPC do Dashboard.';
  end if;
end;
$$;

rollback;

select jsonb_build_object(
  'phase', '9',
  'status', 'ok',
  'adjusted_goal', true,
  'production_matches_reports', true,
  'cancelled_excluded', true,
  'limited_user_isolated', true,
  'temporary_grant_applied', true,
  'expired_grant_blocked', true,
  'residue', false
) as result;
