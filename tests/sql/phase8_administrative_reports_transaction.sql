begin;

create temporary table phase8_context (
  key text primary key,
  value text not null
) on commit drop;

do $$
declare
  v_full_actor uuid;
  v_full_session uuid;
  v_partial_actor uuid;
  v_partial_session uuid;
  v_target uuid;
  v_closure_one bigint;
  v_closure_two bigint;
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

  select profile.user_id, session.id into v_partial_actor, v_partial_session
  from public.profiles profile
  join public.staff_positions position on position.id = profile.position_id
  join auth.sessions session on session.user_id = profile.user_id
  where profile.status = 'active'
    and profile.role_code <> 'diretor_geral'
    and not private.has_permission(profile.user_id, 'hr.reports.view')
    and not private.has_permission(profile.user_id, 'attendances.manage')
    and (session.not_after is null or session.not_after > now())
  order by position.level, session.created_at desc
  limit 1;

  if v_full_actor is null or v_full_session is null or v_partial_actor is null or v_partial_session is null then
    raise exception 'A Fase 8 requer sessões ativas de um diretor e de um profissional sem relatórios.';
  end if;
  v_target := v_partial_actor;

  insert into public.user_permission_grants (
    user_id, permission_code, grant_kind, valid_from, expires_at, reason, granted_by
  ) values
    (v_partial_actor, 'hr.reports.view', 'temporary', clock_timestamp() - interval '1 minute', clock_timestamp() + interval '1 hour', 'Validação transacional da Fase 8.', v_full_actor),
    (v_partial_actor, 'attendances.manage', 'temporary', clock_timestamp() - interval '2 hours', clock_timestamp() - interval '1 hour', 'Concessão expirada da Fase 8.', v_full_actor);

  insert into public.rh_hour_snapshots (
    employee_id, reference_month, reading_date, total_minutes, note, created_by, updated_by
  ) values
    (v_target, date '2026-07-01', date '2026-07-12', 100, 'Baseline de teste da Fase 8.', v_full_actor, v_full_actor),
    (v_target, date '2026-07-01', date '2026-07-19', 460, 'Meta ajustada cumprida.', v_full_actor, v_full_actor),
    (v_target, date '2026-07-01', date '2026-07-26', 880, 'Semana abaixo da meta.', v_full_actor, v_full_actor);

  insert into public.rh_week_closures (
    week_start, week_end, status, started_by, started_at, closed_by, closed_at
  ) values (
    date '2026-07-13', date '2026-07-19', 'closed', v_full_actor,
    timestamptz '2026-07-20 10:00:00-03', v_full_actor, timestamptz '2026-07-20 10:05:00-03'
  ) returning id into v_closure_one;
  insert into public.rh_week_closures (
    week_start, week_end, status, started_by, started_at, closed_by, closed_at
  ) values (
    date '2026-07-20', date '2026-07-26', 'closed', v_full_actor,
    timestamptz '2026-07-27 10:00:00-03', v_full_actor, timestamptz '2026-07-27 10:05:00-03'
  ) returning id into v_closure_two;

  insert into public.rh_absence_requests (
    employee_id, start_date, end_date, reason, status, approval_effect,
    reviewed_by, reviewed_at, review_note
  ) values (
    v_target, date '2026-07-13', date '2026-07-19',
    'Afastamento representativo para validar a meta efetiva.', 'approved', 'weekly_adjustment',
    v_full_actor, timestamptz '2026-07-12 12:00:00-03', 'Abono parcial aprovado para o teste.'
  ) returning id into v_absence;

  insert into public.rh_leave_week_adjustments (
    leave_request_id, employee_id, week_start, deducted_minutes, approved_by, approved_at
  ) values (v_absence, v_target, date '2026-07-13', 240, v_full_actor, timestamptz '2026-07-12 12:00:00-03');

  insert into public.rh_weekly_records (
    employee_id, closure_id, week_start, week_end, cycle_month,
    base_required_minutes, leave_deduction_minutes, required_minutes, worked_minutes,
    deficit_minutes, justification_minutes, remaining_deficit_minutes,
    status, closure_status, absence_request_id, closed_by, closed_at
  ) values
    (v_target, v_closure_one, date '2026-07-13', date '2026-07-19', date '2026-07-01',
      600, 240, 360, 360, 0, 0, 0, 'met', 'closed', v_absence, v_full_actor, timestamptz '2026-07-20 10:05:00-03'),
    (v_target, v_closure_two, date '2026-07-20', date '2026-07-26', date '2026-07-01',
      600, 0, 600, 420, 180, 0, 180, 'deficit', 'closed', null, v_full_actor, timestamptz '2026-07-27 10:05:00-03');

  select id into v_service_one from public.service_catalog order by id limit 1;
  select id into v_service_two from public.service_catalog where id <> v_service_one order by id limit 1;
  if v_service_one is null or v_service_two is null then raise exception 'Catálogo insuficiente para o teste financeiro.'; end if;

  insert into public.attendances (
    patient_id, patient_name, patient_passport, status, subtotal, discount, performed_by,
    plan_code, plan_name, created_at
  ) values (
    null, 'Venda avulsa', '—', 'completed', 400.00, 49.50, v_target,
    'plano_saude', 'Plano de Saúde', timestamptz '2026-07-15 15:00:00-03'
  ) returning id into v_attendance;
  insert into public.attendance_items (
    attendance_id, service_id, service_name, unit_price, quantity, discount_percent, created_at
  ) values
    (v_attendance, v_service_one, 'Item Histórico Seguro', 100.00, 2, 10.00, timestamptz '2026-07-15 15:00:00-03'),
    (v_attendance, v_service_two, 'Procedimento Histórico Seguro', 170.50, 1, 0.00, timestamptz '2026-07-15 15:00:00-03');

  insert into public.attendances (
    patient_id, patient_name, patient_passport, status, subtotal, discount, performed_by,
    cancelled_by, cancelled_at, created_at
  ) values (
    null, 'Venda avulsa', '—', 'cancelled', 999.00, 0, v_target,
    v_full_actor, timestamptz '2026-07-16 16:00:00-03', timestamptz '2026-07-16 15:00:00-03'
  ) returning id into v_cancelled;

  update public.service_catalog set unit_price = unit_price + 99999 where id in (v_service_one, v_service_two);

  insert into phase8_context values
    ('full_actor', v_full_actor::text), ('full_session', v_full_session::text),
    ('partial_actor', v_partial_actor::text), ('partial_session', v_partial_session::text),
    ('target', v_target::text), ('attendance', v_attendance::text), ('cancelled', v_cancelled::text);
end;
$$;

grant select on phase8_context to authenticated;
set local role authenticated;

do $$
declare
  v_actor uuid := (select value::uuid from phase8_context where key = 'full_actor');
  v_session uuid := (select value::uuid from phase8_context where key = 'full_session');
  v_target uuid := (select value::uuid from phase8_context where key = 'target');
  v_hr jsonb;
  v_below jsonb;
  v_financial jsonb;
  v_individual jsonb;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_actor, 'session_id', v_session)::text, true);

  v_hr := public.hpsm_report_hr(date '2026-07-13', date '2026-07-19', null, 'all', (select passport from public.profiles where user_id = v_target), 'name', 'asc', 1, 25);
  if v_hr #>> '{items,0,id}' <> v_target::text
     or (v_hr #>> '{items,0,worked_minutes}')::integer <> 360
     or (v_hr #>> '{items,0,base_target_minutes}')::integer <> 600
     or (v_hr #>> '{items,0,leave_minutes}')::integer <> 240
     or (v_hr #>> '{items,0,effective_target_minutes}')::integer <> 360
     or (v_hr #>> '{items,0,difference_minutes}')::integer <> 0
     or v_hr #>> '{items,0,goal_status}' <> 'met' then
    raise exception 'Meta efetiva 10h - 4h = 6h não foi cumprida corretamente: %', v_hr;
  end if;

  v_below := public.hpsm_report_hr(date '2026-07-20', date '2026-07-26', null, 'all', (select passport from public.profiles where user_id = v_target), 'difference', 'asc', 1, 25);
  if (v_below #>> '{items,0,worked_minutes}')::integer <> 420
     or (v_below #>> '{items,0,effective_target_minutes}')::integer <> 600
     or (v_below #>> '{items,0,difference_minutes}')::integer <> -180
     or v_below #>> '{items,0,goal_status}' <> 'below' then
    raise exception 'Semana abaixo da meta não retornou -3h: %', v_below;
  end if;

  v_financial := public.hpsm_report_financial(date '2026-07-13', date '2026-07-19', v_target, null, 'value', 'desc', 1, 25);
  if (v_financial #>> '{summary,attendance_count}')::integer <> 1
     or (v_financial #>> '{summary,total_amount}')::numeric <> 350.50
     or (v_financial #>> '{summary,item_count}')::integer <> 3
     or (v_financial #>> '{production,0,attendance_count}')::integer <> 1
     or (v_financial #>> '{production,0,total_amount}')::numeric <> 350.50
     or not exists (
       select 1 from jsonb_array_elements(v_financial -> 'top_items') item
       where item ->> 'name' = 'Item Histórico Seguro' and (item ->> 'total_amount')::numeric = 180.00
     ) then
    raise exception 'Financeiro duplicou atendimento, incluiu cancelado ou perdeu preço histórico: %', v_financial;
  end if;
  if not exists (
    select 1 from jsonb_array_elements(v_financial -> 'benefits') benefit
    where benefit ->> 'code' = 'plano_saude'
      and (benefit ->> 'discount_amount')::numeric = 49.50
      and (benefit ->> 'total_amount')::numeric = 350.50
  ) then raise exception 'Benefício/desconto histórico divergente: %', v_financial; end if;

  v_individual := public.hpsm_report_individual(date '2026-07-13', date '2026-07-19', v_target);
  if not coalesce((v_individual ->> 'found')::boolean, false)
     or (v_individual #>> '{journey,effective_target_minutes}')::integer <> 360
     or (v_individual #>> '{production,total_amount}')::numeric <> 350.50 then
    raise exception 'Relatório individual divergiu das fontes canônicas: %', v_individual;
  end if;
end;
$$;

do $$
declare
  v_actor uuid := (select value::uuid from phase8_context where key = 'partial_actor');
  v_session uuid := (select value::uuid from phase8_context where key = 'partial_session');
  v_target uuid := (select value::uuid from phase8_context where key = 'target');
  v_overview jsonb;
  v_individual jsonb;
  v_denied boolean := false;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_actor, 'session_id', v_session)::text, true);
  v_overview := public.hpsm_report_overview(date '2026-07-13', date '2026-07-19');
  v_individual := public.hpsm_report_individual(date '2026-07-13', date '2026-07-19', v_target);
  if coalesce((v_overview ->> 'financial_access')::boolean, true)
     or v_overview ? 'total_amount'
     or v_overview ? 'attendance_count'
     or coalesce((v_individual ->> 'financial_access')::boolean, true)
     or v_individual -> 'production' <> 'null'::jsonb then
    raise exception 'Usuário parcial recebeu dados financeiros: %, %', v_overview, v_individual;
  end if;

  begin
    perform public.hpsm_report_financial(date '2026-07-13', date '2026-07-19', null, null, 'value', 'desc', 1, 25);
  exception when insufficient_privilege then
    v_denied := true;
  end;
  if not v_denied then raise exception 'Concessão financeira expirada continuou autorizada.'; end if;
end;
$$;

reset role;

do $$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'public.hpsm_report_staff_search(text,integer)',
    'public.hpsm_report_overview(date,date)',
    'public.hpsm_report_hr(date,date,bigint,text,text,text,text,integer,integer)',
    'public.hpsm_report_financial(date,date,uuid,bigint,text,text,integer,integer)',
    'public.hpsm_report_team(date,date)',
    'public.hpsm_report_individual(date,date,uuid)'
  ] loop
    if has_function_privilege('anon', v_signature, 'EXECUTE')
       or has_function_privilege('service_role', v_signature, 'EXECUTE')
       or not has_function_privilege('authenticated', v_signature, 'EXECUTE') then
      raise exception 'Privilégios incorretos para %.', v_signature;
    end if;
  end loop;
end;
$$;

rollback;

select jsonb_build_object(
  'phase', '8', 'status', 'ok', 'adjusted_goal', true, 'below_goal', true,
  'historical_prices', true, 'walk_in_sale', true, 'cancelled_excluded', true,
  'partial_permission', true, 'expired_grant_blocked', true, 'residue', false
) as result;
