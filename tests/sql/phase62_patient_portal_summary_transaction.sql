begin;

create temporary table phase62_context (
  key text primary key,
  value text not null
) on commit drop;

do $$
declare
  v_actor uuid;
  v_attendance_a bigint;
  v_attendance_b bigint;
  v_exam_type bigint;
  v_passport_a text;
  v_passport_b text;
  v_patient_a bigint;
  v_patient_b bigint;
begin
  select profile.user_id into v_actor
  from public.profiles profile
  order by profile.created_at, profile.user_id
  limit 1;

  select exam_type.id into v_exam_type
  from public.exam_types exam_type
  order by exam_type.id
  limit 1;

  if v_actor is null or v_exam_type is null then
    raise exception 'A base não possui profissional ou tipo de exame para o teste.';
  end if;

  select lpad(candidate::text, 4, '0') into v_passport_a
  from generate_series(1, 9999) candidate
  where not exists (select 1 from public.patients patient where patient.passport = lpad(candidate::text, 4, '0'))
  order by candidate desc
  limit 1;

  insert into public.patients (passport, name, phone, birth_date)
  values (v_passport_a, 'Paciente Resumo A', '(055) 111-111', date '1991-01-01')
  returning id into v_patient_a;

  select lpad(candidate::text, 4, '0') into v_passport_b
  from generate_series(1, 9999) candidate
  where not exists (select 1 from public.patients patient where patient.passport = lpad(candidate::text, 4, '0'))
  order by candidate desc
  limit 1;

  insert into public.patients (passport, name, phone, birth_date)
  values (v_passport_b, 'Paciente Resumo B', '(055) 222-222', date '1992-02-02')
  returning id into v_patient_b;

  insert into public.attendances (
    patient_id, patient_name, patient_passport, status, subtotal, discount, performed_by, created_at
  ) values (
    v_patient_a, 'Paciente Resumo A', v_passport_a, 'completed', 120, 20, v_actor, clock_timestamp() - interval '2 days'
  ) returning id into v_attendance_a;

  insert into public.attendances (
    patient_id, patient_name, patient_passport, status, subtotal, discount, performed_by, created_at
  ) values (
    v_patient_a, 'Paciente Resumo A', v_passport_a, 'completed', 300.50, 50, v_actor, clock_timestamp() - interval '1 day'
  );

  insert into public.attendances (
    patient_id, patient_name, patient_passport, status, subtotal, discount, performed_by,
    cancelled_by, cancelled_at, created_at
  ) values (
    v_patient_a, 'Paciente Resumo A', v_passport_a, 'cancelled', 999, 0, v_actor,
    v_actor, clock_timestamp(), clock_timestamp()
  );

  insert into public.attendances (
    patient_id, patient_name, patient_passport, status, subtotal, discount, performed_by, created_at
  ) values (
    v_patient_b, 'Paciente Resumo B', v_passport_b, 'completed', 800, 23, v_actor, clock_timestamp()
  ) returning id into v_attendance_b;

  insert into public.patient_health_plan_requests (
    patient_id, attendance_id, status, reviewed_by, reviewed_at, coverage_start, coverage_end
  ) values (
    v_patient_a, v_attendance_a, 'approved', v_actor, clock_timestamp(),
    clock_timestamp() - interval '1 day', clock_timestamp() + interval '29 days'
  );

  insert into public.patient_health_plan_requests (patient_id, attendance_id)
  values (v_patient_b, v_attendance_b);

  insert into public.clinical_exams (
    patient_id, exam_type_id, status, requested_by, responsible_professional_id, indication, requested_at
  )
  select
    v_patient_a,
    v_exam_type,
    'requested',
    v_actor,
    v_actor,
    'Avaliação clínica',
    clock_timestamp() - (offset_number || ' hours')::interval
  from generate_series(1, 4) offset_number;

  insert into public.clinical_exams (
    patient_id, exam_type_id, status, requested_by, responsible_professional_id, indication, requested_at
  ) values (
    v_patient_b, v_exam_type, 'requested', v_actor, v_actor, 'Avaliação clínica', clock_timestamp()
  );

  insert into public.clinical_casts (
    patient_id, body_region, laterality, status, applied_at, applied_by,
    expected_removal_at, created_by
  ) values
    (v_patient_a, 'forearm', 'right', 'in_use', clock_timestamp() - interval '8 days', v_actor, clock_timestamp() - interval '1 day', v_actor),
    (v_patient_a, 'leg', 'left', 'in_use', clock_timestamp() - interval '2 days', v_actor, clock_timestamp() + interval '5 days', v_actor),
    (v_patient_b, 'wrist', 'right', 'in_use', clock_timestamp() - interval '1 day', v_actor, clock_timestamp() + interval '8 days', v_actor);

  insert into public.clinical_casts (
    patient_id, body_region, laterality, status, applied_at, applied_by,
    expected_removal_at, removed_at, removed_by, created_by
  ) values (
    v_patient_a, 'hand', 'left', 'removed', clock_timestamp() - interval '20 days', v_actor,
    clock_timestamp() - interval '10 days', clock_timestamp() - interval '11 days', v_actor, v_actor
  );

  insert into public.patient_portal_sessions (patient_id, token_hash, expires_at)
  values
    (v_patient_a, repeat('a', 64), clock_timestamp() + interval '1 hour'),
    (v_patient_b, repeat('b', 64), clock_timestamp() + interval '1 hour');

  insert into phase62_context values
    ('passport_a', v_passport_a),
    ('passport_b', v_passport_b);
end;
$$;

grant select on phase62_context to service_role;
set local role service_role;

do $$
declare
  v_a jsonb := public.patient_portal_summary(repeat('a', 64));
  v_b jsonb := public.patient_portal_summary(repeat('b', 64));
  v_passport_a text := (select value from phase62_context where key = 'passport_a');
  v_passport_b text := (select value from phase62_context where key = 'passport_b');
begin
  if not coalesce((v_a ->> 'authenticated')::boolean, false)
     or v_a #>> '{patient,passport}' <> v_passport_a
     or v_a #>> '{patient,name}' <> 'Paciente Resumo A' then
    raise exception 'Resumo A não resolveu a identidade correta.';
  end if;
  if (v_a -> 'patient') ? 'id' or (v_a -> 'patient') ? 'birth_date' then
    raise exception 'Resumo expôs identificador interno ou nascimento.';
  end if;
  if (v_a #>> '{summary,total_attendances}')::integer <> 2
     or (v_a #>> '{summary,lifetime_spent}')::numeric <> 350.50
     or (v_a #>> '{summary,last_attendance,total}')::numeric <> 250.50 then
    raise exception 'Total financeiro ou último atendimento do Paciente A está incorreto: %', v_a -> 'summary';
  end if;
  if v_a #>> '{health_plan,status}' <> 'active' then
    raise exception 'Plano ativo do Paciente A não foi resolvido.';
  end if;
  if jsonb_array_length(v_a -> 'recent_exams') <> 3 then
    raise exception 'O resumo não limitou exames recentes a três.';
  end if;
  if jsonb_array_length(v_a -> 'active_casts') <> 2
     or v_a #>> '{active_casts,0,body_region}' <> 'forearm'
     or v_a #>> '{active_casts,1,body_region}' <> 'leg' then
    raise exception 'Gessos ativos não foram isolados ou ordenados pela retirada.';
  end if;

  if not coalesce((v_b ->> 'authenticated')::boolean, false)
     or v_b #>> '{patient,passport}' <> v_passport_b
     or v_b #>> '{patient,passport}' = v_passport_a
     or (v_b #>> '{summary,total_attendances}')::integer <> 1
     or (v_b #>> '{summary,lifetime_spent}')::numeric <> 777
     or v_b #>> '{health_plan,status}' <> 'awaiting_confirmation'
     or jsonb_array_length(v_b -> 'active_casts') <> 1 then
    raise exception 'Resumo B recebeu dados incorretos ou vazou informações do Paciente A.';
  end if;

  if not public.patient_portal_revoke_session(repeat('a', 64)) then
    raise exception 'Logout do Paciente A não revogou a sessão.';
  end if;
  if coalesce((public.patient_portal_summary(repeat('a', 64)) ->> 'authenticated')::boolean, false) then
    raise exception 'Resumo do Paciente A permaneceu acessível após logout.';
  end if;
  if public.patient_portal_summary(repeat('b', 64)) #>> '{patient,passport}' <> v_passport_b then
    raise exception 'A troca A → B não preservou o isolamento da sessão B.';
  end if;
end;
$$;

reset role;

do $$
begin
  if has_function_privilege('anon', 'public.patient_portal_summary(text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.patient_portal_summary(text)', 'EXECUTE') then
    raise exception 'RPC de resumo foi exposta ao cliente público.';
  end if;
  if not has_function_privilege('service_role', 'public.patient_portal_summary(text)', 'EXECUTE') then
    raise exception 'Backend não recebeu execução da RPC de resumo.';
  end if;
end;
$$;

rollback;

select jsonb_build_object(
  'phase', '6.2',
  'status', 'ok',
  'attendance_total', 2,
  'lifetime_spent', 350.50,
  'patient_a_to_b_isolated', true,
  'residue', false
) as result;
