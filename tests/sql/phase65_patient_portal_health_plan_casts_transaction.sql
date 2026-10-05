begin;

create temporary table phase65_context (
  key text primary key,
  value text not null
) on commit drop;

do $$
declare
  v_actor uuid;
  v_attendance bigint;
  v_gesso_service bigint;
  v_patient_a bigint;
  v_patient_b bigint;
  v_patient_expired bigint;
  v_patient_pending bigint;
  v_patient_none bigint;
  v_patient_financial bigint;
  v_passport text;
  v_token_a text := repeat(md5(txid_current()::text || ':65:a'), 2);
  v_token_b text := repeat(md5(txid_current()::text || ':65:b'), 2);
  v_token_expired_plan text := repeat(md5(txid_current()::text || ':65:expired-plan'), 2);
  v_token_pending text := repeat(md5(txid_current()::text || ':65:pending'), 2);
  v_token_none text := repeat(md5(txid_current()::text || ':65:none'), 2);
  v_token_financial text := repeat(md5(txid_current()::text || ':65:financial'), 2);
  v_token_session_expired text := repeat(md5(txid_current()::text || ':65:session-expired'), 2);
begin
  select profile.user_id into v_actor
  from public.profiles profile
  order by profile.created_at, profile.user_id
  limit 1;
  if v_actor is null then raise exception 'A base não possui profissional para o teste 6.5.'; end if;

  select catalog.id into v_gesso_service
  from public.service_catalog catalog
  where upper(btrim(catalog.name)) = 'GESSO'
  order by catalog.id
  limit 1;
  if v_gesso_service is null then raise exception 'O serviço financeiro GESSO não foi localizado.'; end if;

  select lpad(candidate::text, 4, '0') into v_passport from generate_series(1, 9999) candidate
  where not exists (select 1 from public.patients patient where patient.passport = lpad(candidate::text, 4, '0'))
  order by candidate desc limit 1;
  insert into public.patients (passport, name, phone, birth_date)
  values (v_passport, 'Paciente Portal 65 A', '(055) 650-001', date '1990-01-01') returning id into v_patient_a;

  select lpad(candidate::text, 4, '0') into v_passport from generate_series(1, 9999) candidate
  where not exists (select 1 from public.patients patient where patient.passport = lpad(candidate::text, 4, '0'))
  order by candidate desc limit 1;
  insert into public.patients (passport, name, phone, birth_date)
  values (v_passport, 'Paciente Portal 65 B', '(055) 650-002', date '1991-02-02') returning id into v_patient_b;

  select lpad(candidate::text, 4, '0') into v_passport from generate_series(1, 9999) candidate
  where not exists (select 1 from public.patients patient where patient.passport = lpad(candidate::text, 4, '0'))
  order by candidate desc limit 1;
  insert into public.patients (passport, name, phone, birth_date)
  values (v_passport, 'Paciente Portal 65 Expirado', '(055) 650-003', date '1992-03-03') returning id into v_patient_expired;

  select lpad(candidate::text, 4, '0') into v_passport from generate_series(1, 9999) candidate
  where not exists (select 1 from public.patients patient where patient.passport = lpad(candidate::text, 4, '0'))
  order by candidate desc limit 1;
  insert into public.patients (passport, name, phone, birth_date)
  values (v_passport, 'Paciente Portal 65 Pendente', '(055) 650-004', date '1993-04-04') returning id into v_patient_pending;

  select lpad(candidate::text, 4, '0') into v_passport from generate_series(1, 9999) candidate
  where not exists (select 1 from public.patients patient where patient.passport = lpad(candidate::text, 4, '0'))
  order by candidate desc limit 1;
  insert into public.patients (passport, name, phone, birth_date)
  values (v_passport, 'Paciente Portal 65 Sem Plano', '(055) 650-005', date '1994-05-05') returning id into v_patient_none;

  select lpad(candidate::text, 4, '0') into v_passport from generate_series(1, 9999) candidate
  where not exists (select 1 from public.patients patient where patient.passport = lpad(candidate::text, 4, '0'))
  order by candidate desc limit 1;
  insert into public.patients (passport, name, phone, birth_date)
  values (v_passport, 'Paciente Portal 65 Venda Gesso', '(055) 650-006', date '1995-06-06') returning id into v_patient_financial;

  insert into public.attendances (patient_id, patient_name, patient_passport, status, subtotal, discount, performed_by, created_at)
  select v_patient_a, 'Paciente Portal 65 A', patient.passport, 'completed', 100, 0, v_actor, clock_timestamp() - interval '90 days'
  from public.patients patient where patient.id = v_patient_a returning id into v_attendance;
  insert into public.patient_health_plan_requests (patient_id, attendance_id, status, reviewed_by, reviewed_at, coverage_start, coverage_end)
  values (v_patient_a, v_attendance, 'approved', v_actor, clock_timestamp() - interval '89 days', clock_timestamp() - interval '89 days', clock_timestamp() - interval '59 days');

  insert into public.attendances (patient_id, patient_name, patient_passport, status, subtotal, discount, performed_by, created_at)
  select v_patient_a, 'Paciente Portal 65 A', patient.passport, 'completed', 100, 0, v_actor, clock_timestamp() - interval '5 days'
  from public.patients patient where patient.id = v_patient_a returning id into v_attendance;
  insert into public.patient_health_plan_requests (patient_id, attendance_id, status, reviewed_by, reviewed_at, coverage_start, coverage_end)
  values (v_patient_a, v_attendance, 'approved', v_actor, clock_timestamp() - interval '4 days', clock_timestamp() - interval '4 days', clock_timestamp() + interval '26 days');

  insert into public.attendances (patient_id, patient_name, patient_passport, status, subtotal, discount, performed_by, created_at)
  select v_patient_a, 'Paciente Portal 65 A', patient.passport, 'completed', 100, 0, v_actor, clock_timestamp() - interval '2 days'
  from public.patients patient where patient.id = v_patient_a returning id into v_attendance;
  insert into public.patient_health_plan_requests (patient_id, attendance_id, status, reviewed_by, reviewed_at, rejection_reason)
  values (v_patient_a, v_attendance, 'rejected', v_actor, clock_timestamp() - interval '1 day', 'SEGREDO PLANO 65 NÃO PODE SAIR');

  insert into public.attendances (patient_id, patient_name, patient_passport, status, subtotal, discount, performed_by)
  select v_patient_b, 'Paciente Portal 65 B', patient.passport, 'completed', 100, 0, v_actor
  from public.patients patient where patient.id = v_patient_b returning id into v_attendance;
  insert into public.patient_health_plan_requests (patient_id, attendance_id, status, reviewed_by, reviewed_at, coverage_start, coverage_end)
  values (v_patient_b, v_attendance, 'approved', v_actor, clock_timestamp(), clock_timestamp(), clock_timestamp() + interval '30 days');

  insert into public.attendances (patient_id, patient_name, patient_passport, status, subtotal, discount, performed_by)
  select v_patient_expired, 'Paciente Portal 65 Expirado', patient.passport, 'completed', 100, 0, v_actor
  from public.patients patient where patient.id = v_patient_expired returning id into v_attendance;
  insert into public.patient_health_plan_requests (patient_id, attendance_id, status, reviewed_by, reviewed_at, coverage_start, coverage_end)
  values (v_patient_expired, v_attendance, 'approved', v_actor, clock_timestamp() - interval '40 days', clock_timestamp() - interval '40 days', clock_timestamp() - interval '10 days');

  insert into public.attendances (patient_id, patient_name, patient_passport, status, subtotal, discount, performed_by)
  select v_patient_pending, 'Paciente Portal 65 Pendente', patient.passport, 'completed', 100, 0, v_actor
  from public.patients patient where patient.id = v_patient_pending returning id into v_attendance;
  insert into public.patient_health_plan_requests (patient_id, attendance_id) values (v_patient_pending, v_attendance);

  insert into public.clinical_casts (
    patient_id, body_region, laterality, status, applied_at, applied_by, expected_removal_at,
    application_notes, created_by, updated_at
  ) values
    (v_patient_a, 'forearm', 'right', 'in_use', clock_timestamp() - interval '8 days', v_actor,
      clock_timestamp() - interval '1 day', 'SEGREDO APLICAÇÃO 65', v_actor, clock_timestamp() - interval '8 days'),
    (v_patient_a, 'leg', 'left', 'in_use', clock_timestamp() - interval '2 days', v_actor,
      clock_timestamp() + interval '5 days', null, v_actor, clock_timestamp() - interval '2 days'),
    (v_patient_b, 'wrist', 'right', 'in_use', clock_timestamp() - interval '1 day', v_actor,
      clock_timestamp() + interval '8 days', null, v_actor, clock_timestamp() - interval '1 day');

  insert into public.clinical_casts (
    patient_id, body_region, laterality, status, applied_at, applied_by, expected_removal_at,
    removed_at, removed_by, removal_notes, created_by, updated_at
  ) values (
    v_patient_a, 'hand', 'left', 'removed', clock_timestamp() - interval '20 days', v_actor,
    clock_timestamp() - interval '10 days', clock_timestamp() - interval '11 days', v_actor,
    'SEGREDO RETIRADA 65', v_actor, clock_timestamp() - interval '11 days'
  );

  insert into public.clinical_casts (
    patient_id, body_region, laterality, status, applied_at, applied_by, expected_removal_at,
    cancelled_at, cancelled_by, cancellation_reason, created_by, updated_at
  ) values (
    v_patient_a, 'foot', 'right', 'cancelled', clock_timestamp() - interval '9 days', v_actor,
    clock_timestamp() + interval '5 days', clock_timestamp() - interval '8 days', v_actor,
    'SEGREDO CANCELAMENTO 65', v_actor, clock_timestamp() - interval '8 days'
  );

  insert into public.attendances (patient_id, patient_name, patient_passport, status, subtotal, discount, performed_by)
  select v_patient_financial, 'Paciente Portal 65 Venda Gesso', patient.passport, 'completed', catalog.unit_price, 0, v_actor
  from public.patients patient cross join public.service_catalog catalog
  where patient.id = v_patient_financial and catalog.id = v_gesso_service
  returning id into v_attendance;
  insert into public.attendance_items (attendance_id, service_id, service_name, unit_price, quantity)
  select v_attendance, catalog.id, catalog.name, catalog.unit_price, 1
  from public.service_catalog catalog where catalog.id = v_gesso_service;

  insert into public.patient_portal_sessions (patient_id, token_hash, created_at, expires_at)
  values
    (v_patient_a, v_token_a, clock_timestamp(), clock_timestamp() + interval '1 hour'),
    (v_patient_b, v_token_b, clock_timestamp(), clock_timestamp() + interval '1 hour'),
    (v_patient_expired, v_token_expired_plan, clock_timestamp(), clock_timestamp() + interval '1 hour'),
    (v_patient_pending, v_token_pending, clock_timestamp(), clock_timestamp() + interval '1 hour'),
    (v_patient_none, v_token_none, clock_timestamp(), clock_timestamp() + interval '1 hour'),
    (v_patient_financial, v_token_financial, clock_timestamp(), clock_timestamp() + interval '1 hour'),
    (v_patient_a, v_token_session_expired, clock_timestamp() - interval '2 hours', clock_timestamp() - interval '1 hour');

  insert into phase65_context values
    ('token_a', v_token_a), ('token_b', v_token_b),
    ('token_expired_plan', v_token_expired_plan), ('token_pending', v_token_pending),
    ('token_none', v_token_none), ('token_financial', v_token_financial),
    ('token_session_expired', v_token_session_expired);
end;
$$;

grant select on phase65_context to service_role;
set local role service_role;

do $$
declare
  v_token_a text := (select value from phase65_context where key = 'token_a');
  v_token_b text := (select value from phase65_context where key = 'token_b');
  v_plan_a jsonb;
  v_plan_b jsonb;
  v_plan_page_2 jsonb;
  v_cast_a jsonb;
  v_cast_b jsonb;
  v_cast_page_2 jsonb;
begin
  v_plan_a := public.patient_portal_health_plan_page(v_token_a, null, null, 2);
  v_plan_b := public.patient_portal_health_plan_page(v_token_b);
  if v_plan_a #>> '{current,status}' <> 'active'
     or v_plan_b #>> '{current,status}' <> 'active'
     or jsonb_array_length(v_plan_a -> 'items') <> 2
     or v_plan_a -> 'next_cursor' = 'null'::jsonb then
    raise exception 'Estado atual ou paginação do plano está incorreto: %', v_plan_a;
  end if;
  if v_plan_a::text like '%SEGREDO PLANO 65%'
     or v_plan_a::text like '%rejection_reason%'
     or v_plan_a::text like '%attendance_id%'
     or v_plan_a::text like '%patient_id%'
     or v_plan_a::text like '%Paciente Portal 65 B%' then
    raise exception 'Plano do Paciente A vazou campo interno ou dados do Paciente B: %', v_plan_a;
  end if;

  v_plan_page_2 := public.patient_portal_health_plan_page(
    v_token_a,
    (v_plan_a #>> '{next_cursor,occurred_at}')::timestamptz,
    (v_plan_a #>> '{next_cursor,id}')::bigint,
    2
  );
  if exists (
    select 1 from jsonb_array_elements(v_plan_a -> 'items') first_page
    join jsonb_array_elements(v_plan_page_2 -> 'items') second_page
      on first_page ->> 'key' = second_page ->> 'key'
  ) then raise exception 'Paginação do plano repetiu movimentações.'; end if;

  if public.patient_portal_health_plan_page((select value from phase65_context where key = 'token_expired_plan')) #>> '{current,status}' <> 'expired'
     or public.patient_portal_health_plan_page((select value from phase65_context where key = 'token_pending')) #>> '{current,status}' <> 'awaiting_confirmation'
     or public.patient_portal_health_plan_page((select value from phase65_context where key = 'token_none')) #>> '{current,status}' <> 'none' then
    raise exception 'Estados expirado, aguardando confirmação e sem plano divergiram da regra canônica.';
  end if;
  if public.patient_portal_summary(v_token_a) #>> '{health_plan,status}' <> v_plan_a #>> '{current,status}' then
    raise exception 'Resumo e área de plano divergiram.';
  end if;

  v_cast_a := public.patient_portal_cast_page(v_token_a, null, null, 1);
  v_cast_b := public.patient_portal_cast_page(v_token_b);
  if jsonb_array_length(v_cast_a -> 'active_casts') <> 2
     or v_cast_a #>> '{active_casts,0,body_region}' <> 'forearm'
     or jsonb_array_length(v_cast_a -> 'history') <> 1
     or v_cast_a -> 'next_cursor' = 'null'::jsonb then
    raise exception 'Gessos ativos, ordenação ou paginação estão incorretos: %', v_cast_a;
  end if;
  if jsonb_array_length(v_cast_b -> 'active_casts') <> 1
     or v_cast_b #>> '{active_casts,0,body_region}' <> 'wrist'
     or v_cast_a::text like '%wrist%'
     or v_cast_a::text like '%SEGREDO%'
     or v_cast_a::text like '%patient_id%'
     or v_cast_a::text like '%application_notes%'
     or v_cast_a::text like '%removal_notes%'
     or v_cast_a::text like '%cancellation_reason%' then
    raise exception 'Área de gessos vazou dados entre pacientes ou campos clínicos internos.';
  end if;

  v_cast_page_2 := public.patient_portal_cast_page(
    v_token_a,
    (v_cast_a #>> '{next_cursor,occurred_at}')::timestamptz,
    (v_cast_a #>> '{next_cursor,id}')::bigint,
    1
  );
  if exists (
    select 1 from jsonb_array_elements(v_cast_a -> 'history') first_page
    join jsonb_array_elements(v_cast_page_2 -> 'history') second_page
      on first_page ->> 'key' = second_page ->> 'key'
  ) then raise exception 'Paginação dos gessos repetiu registros.'; end if;

  if jsonb_array_length(public.patient_portal_cast_page(
    (select value from phase65_context where key = 'token_financial')
  ) -> 'active_casts') <> 0 then
    raise exception 'A venda financeira de GESSO foi tratada como registro clínico.';
  end if;

  if coalesce((public.patient_portal_health_plan_page(
       (select value from phase65_context where key = 'token_session_expired')
     ) ->> 'authenticated')::boolean, true)
     or coalesce((public.patient_portal_cast_page(repeat('0', 64)) ->> 'authenticated')::boolean, true) then
    raise exception 'Sessão expirada ou inexistente permaneceu autorizada.';
  end if;
end;
$$;

reset role;

do $$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'public.patient_portal_health_plan_page(text,timestamp with time zone,bigint,integer)',
    'public.patient_portal_cast_page(text,timestamp with time zone,bigint,integer)'
  ] loop
    if has_function_privilege('anon', v_signature, 'EXECUTE')
       or has_function_privilege('authenticated', v_signature, 'EXECUTE') then
      raise exception 'RPC % foi exposta ao cliente público.', v_signature;
    end if;
    if not has_function_privilege('service_role', v_signature, 'EXECUTE') then
      raise exception 'Backend perdeu execução da RPC %.', v_signature;
    end if;
  end loop;
end;
$$;

rollback;

select jsonb_build_object(
  'phase', '6.5', 'status', 'ok', 'plan_states', 4, 'multiple_active_casts', true,
  'patient_a_to_b_isolated', true, 'financial_is_not_clinical', true,
  'service_only', true, 'residue', false
) as result;
