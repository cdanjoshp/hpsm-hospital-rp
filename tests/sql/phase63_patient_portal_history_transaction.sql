begin;

create temporary table phase63_context (
  key text primary key,
  value text not null
) on commit drop;

do $$
declare
  v_actor uuid;
  v_attendance_a bigint;
  v_attendance_plan_2 bigint;
  v_attendance_pending bigint;
  v_attendance_rejected bigint;
  v_exam_type bigint;
  v_passport_a text;
  v_passport_b text;
  v_patient_a bigint;
  v_patient_b bigint;
  v_service_a bigint;
  v_service_b bigint;
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
  values (v_passport_a, 'Paciente Histórico A', '(055) 631-001', date '1991-01-01')
  returning id into v_patient_a;

  select lpad(candidate::text, 4, '0') into v_passport_b
  from generate_series(1, 9999) candidate
  where not exists (select 1 from public.patients patient where patient.passport = lpad(candidate::text, 4, '0'))
  order by candidate desc
  limit 1;

  insert into public.patients (passport, name, phone, birth_date)
  values (v_passport_b, 'Paciente Histórico B', '(055) 631-002', date '1992-02-02')
  returning id into v_patient_b;

  insert into public.service_catalog (code, icon, name, category, unit_price, created_by, updated_by)
  values ('phase63_a_' || txid_current(), '+', 'Serviço histórico 6.3 A ' || txid_current(), 'Teste Portal', 100, v_actor, v_actor)
  returning id into v_service_a;

  insert into public.service_catalog (code, icon, name, category, unit_price, created_by, updated_by)
  values ('phase63_b_' || txid_current(), '+', 'Serviço histórico 6.3 B ' || txid_current(), 'Teste Portal', 100, v_actor, v_actor)
  returning id into v_service_b;

  insert into public.attendances (
    patient_id, patient_name, patient_passport, plan_code, plan_name,
    status, subtotal, discount, performed_by, created_at
  ) values (
    v_patient_a, 'Paciente Histórico A', v_passport_a, 'SNAP63', 'Plano Histórico 6.3',
    'completed', 200, 20, v_actor, clock_timestamp() - interval '1 hour'
  ) returning id into v_attendance_a;

  insert into public.attendance_items (
    attendance_id, service_id, service_name, unit_price, quantity, discount_percent
  ) values
    (v_attendance_a, v_service_a, 'Raio-X histórico', 100, 1, 10),
    (v_attendance_a, v_service_b, 'Gesso histórico', 100, 1, 10);

  update public.service_catalog set unit_price = 999 where id = v_service_a;
  update public.service_catalog set unit_price = 888 where id = v_service_b;

  insert into public.attendances (
    patient_id, patient_name, patient_passport, status, subtotal, discount, performed_by, created_at
  )
  select
    v_patient_a, 'Paciente Histórico A', v_passport_a, 'completed',
    10 + sequence_number, 0, v_actor,
    clock_timestamp() - ((sequence_number + 1) || ' hours')::interval
  from generate_series(1, 23) sequence_number;

  select attendance.id into v_attendance_plan_2
  from public.attendances attendance
  where attendance.patient_id = v_patient_a and attendance.status = 'completed' and attendance.id <> v_attendance_a
  order by attendance.id
  offset 0 limit 1;

  select attendance.id into v_attendance_pending
  from public.attendances attendance
  where attendance.patient_id = v_patient_a and attendance.status = 'completed' and attendance.id <> v_attendance_a
  order by attendance.id
  offset 1 limit 1;

  select attendance.id into v_attendance_rejected
  from public.attendances attendance
  where attendance.patient_id = v_patient_a and attendance.status = 'completed' and attendance.id <> v_attendance_a
  order by attendance.id
  offset 2 limit 1;

  insert into public.attendances (
    patient_id, patient_name, patient_passport, status, subtotal, discount, performed_by,
    cancelled_by, cancelled_at, created_at
  ) values (
    v_patient_a, 'Paciente Histórico A', v_passport_a, 'cancelled', 999, 0, v_actor,
    v_actor, clock_timestamp(), clock_timestamp()
  );

  insert into public.attendances (
    patient_id, patient_name, patient_passport, status, subtotal, discount, performed_by, created_at
  ) values (
    v_patient_b, 'Paciente Histórico B', v_passport_b, 'completed', 800, 23, v_actor, clock_timestamp()
  );

  insert into public.clinical_exams (
    patient_id, exam_type_id, status, requested_by, responsible_professional_id, indication,
    requested_at, started_at, submitted_for_review_at, completed_at, reviewed_by,
    final_report_snapshot
  ) values (
    v_patient_a, v_exam_type, 'completed', v_actor, v_actor, 'Exame concluído no teste',
    clock_timestamp() - interval '6 hours', clock_timestamp() - interval '5 hours',
    clock_timestamp() - interval '4 hours', clock_timestamp() - interval '3 hours', v_actor,
    '{}'::jsonb
  );

  insert into public.clinical_exams (
    patient_id, exam_type_id, status, requested_by, responsible_professional_id, indication, requested_at
  ) values (
    v_patient_a, v_exam_type, 'requested', v_actor, v_actor, 'Exame pendente omitido', clock_timestamp()
  );

  insert into public.clinical_casts (
    patient_id, body_region, laterality, status, applied_at, applied_by,
    expected_removal_at, created_by
  ) values (
    v_patient_a, 'forearm', 'right', 'in_use', clock_timestamp() - interval '8 hours', v_actor,
    clock_timestamp() + interval '7 days', v_actor
  );

  insert into public.clinical_casts (
    patient_id, body_region, laterality, status, applied_at, applied_by,
    expected_removal_at, removed_at, removed_by, created_by
  ) values (
    v_patient_a, 'leg', 'left', 'removed', clock_timestamp() - interval '12 hours', v_actor,
    clock_timestamp() + interval '7 days', clock_timestamp() - interval '2 hours', v_actor, v_actor
  );

  insert into public.clinical_casts (
    patient_id, body_region, laterality, status, applied_at, applied_by,
    expected_removal_at, cancelled_at, cancelled_by, cancellation_reason, created_by
  ) values (
    v_patient_a, 'hand', 'left', 'cancelled', clock_timestamp() - interval '10 hours', v_actor,
    clock_timestamp() + interval '7 days', clock_timestamp() - interval '9 hours', v_actor,
    'Cancelamento de teste', v_actor
  );

  insert into public.patient_health_plan_requests (
    patient_id, attendance_id, status, reviewed_by, reviewed_at, coverage_start, coverage_end
  ) values
    (v_patient_a, v_attendance_a, 'approved', v_actor, clock_timestamp() - interval '14 hours',
      clock_timestamp() - interval '14 hours', clock_timestamp() + interval '30 days'),
    (v_patient_a, v_attendance_plan_2, 'approved', v_actor, clock_timestamp() - interval '13 hours',
      clock_timestamp() - interval '12 hours', clock_timestamp() + interval '60 days');

  insert into public.patient_health_plan_requests (patient_id, attendance_id)
  values (v_patient_a, v_attendance_pending);

  insert into public.patient_health_plan_requests (
    patient_id, attendance_id, status, reviewed_by, reviewed_at, rejection_reason
  ) values (
    v_patient_a, v_attendance_rejected, 'rejected', v_actor, clock_timestamp(),
    'Solicitação rejeitada apenas para validar a omissão.'
  );

  insert into public.patient_portal_sessions (patient_id, token_hash, expires_at)
  values
    (v_patient_a, repeat('c', 64), clock_timestamp() + interval '1 hour'),
    (v_patient_b, repeat('d', 64), clock_timestamp() + interval '1 hour');

  insert into phase63_context values
    ('attendance_a', v_attendance_a::text),
    ('passport_a', v_passport_a),
    ('passport_b', v_passport_b);
end;
$$;

grant select on phase63_context to service_role;
set local role service_role;

do $$
declare
  v_attendance_a bigint := (select value::bigint from phase63_context where key = 'attendance_a');
  v_detail_a jsonb := public.patient_portal_attendance_detail(repeat('c', 64), v_attendance_a);
  v_detail_cross jsonb := public.patient_portal_attendance_detail(repeat('d', 64), v_attendance_a);
  v_history_1 jsonb := public.patient_portal_history_page(repeat('c', 64), null, null, 20);
  v_history_2 jsonb;
  v_list_a jsonb := public.patient_portal_attendance_page(repeat('c', 64), null, null, 20);
  v_list_b jsonb := public.patient_portal_attendance_page(repeat('d', 64), null, null, 20);
  v_summary_a jsonb := public.patient_portal_summary(repeat('c', 64));
begin
  if jsonb_array_length(v_history_1 -> 'items') <> 20 or v_history_1 -> 'next_cursor' = 'null'::jsonb then
    raise exception 'Primeira página do histórico não respeitou o limite/keyset.';
  end if;

  v_history_2 := public.patient_portal_history_page(
    repeat('c', 64),
    (v_history_1 #>> '{next_cursor,occurred_at}')::timestamptz,
    v_history_1 #>> '{next_cursor,key}',
    20
  );

  if exists (
    select 1
    from jsonb_array_elements(v_history_1 -> 'items') first_page
    join jsonb_array_elements(v_history_2 -> 'items') second_page
      on first_page ->> 'key' = second_page ->> 'key'
  ) then
    raise exception 'Paginação do histórico repetiu eventos.';
  end if;

  if exists (
    select 1
    from (
      select
        (item ->> 'occurred_at')::timestamptz as occurred_at,
        lag((item ->> 'occurred_at')::timestamptz) over (order by ordinal) as previous_at
      from jsonb_array_elements(v_history_1 -> 'items') with ordinality source(item, ordinal)
    ) ordered
    where previous_at < occurred_at
  ) then
    raise exception 'Histórico não está ordenado do mais recente para o mais antigo.';
  end if;

  if (
    select count(*) from (
      select item from jsonb_array_elements(v_history_1 -> 'items') item
      union all
      select item from jsonb_array_elements(v_history_2 -> 'items') item
    ) all_events where item ->> 'type' = 'exam'
  ) <> 1 then
    raise exception 'Histórico incluiu exame pendente ou omitiu exame concluído.';
  end if;

  if (
    select count(*) from (
      select item from jsonb_array_elements(v_history_1 -> 'items') item
      union all
      select item from jsonb_array_elements(v_history_2 -> 'items') item
    ) all_events where item ->> 'type' = 'cast'
  ) <> 3 then
    raise exception 'Histórico fabricou/cortou evento de gesso ou incluiu cancelamento.';
  end if;

  if (
    select count(*) from (
      select item from jsonb_array_elements(v_history_1 -> 'items') item
      union all
      select item from jsonb_array_elements(v_history_2 -> 'items') item
    ) all_events where item ->> 'type' = 'health_plan'
  ) <> 2 then
    raise exception 'Histórico incluiu plano pendente/rejeitado ou omitiu aprovação.';
  end if;

  if not coalesce((v_detail_a ->> 'found')::boolean, false)
     or v_detail_a #>> '{attendance,benefit_name}' <> 'Plano Histórico 6.3'
     or (v_detail_a #>> '{attendance,total}')::numeric <> 180
     or jsonb_array_length(v_detail_a #> '{attendance,items}') <> 2
     or exists (
       select 1 from jsonb_array_elements(v_detail_a #> '{attendance,items}') item
       where (item ->> 'unit_price')::numeric <> 100
          or (item ->> 'discount_percent')::numeric <> 10
          or (item ->> 'line_total')::numeric <> 90
     ) then
    raise exception 'Detalhe não preservou snapshots históricos de preço, benefício e desconto: %', v_detail_a;
  end if;

  if coalesce((v_detail_cross ->> 'found')::boolean, true) then
    raise exception 'Paciente B conseguiu localizar atendimento do Paciente A.';
  end if;

  if (v_list_a #>> '{summary,total_attendances}')::integer <> 24
     or v_list_a #>> '{summary,lifetime_spent}' <> v_summary_a #>> '{summary,lifetime_spent}' then
    raise exception 'Lista e resumo divergiram na fonte compartilhada de gastos.';
  end if;

  if v_list_b #>> '{patient,passport}' <> (select value from phase63_context where key = 'passport_b')
     or (v_list_b #>> '{summary,total_attendances}')::integer <> 1
     or (v_list_b #>> '{summary,lifetime_spent}')::numeric <> 777
     or jsonb_array_length(v_list_b -> 'items') <> 1 then
    raise exception 'Lista B recebeu dados incorretos ou dados do Paciente A.';
  end if;

  if not public.patient_portal_revoke_session(repeat('c', 64)) then
    raise exception 'Logout não revogou a sessão A.';
  end if;
  if coalesce((public.patient_portal_history_page(repeat('c', 64)) ->> 'authenticated')::boolean, false)
     or coalesce((public.patient_portal_attendance_page(repeat('c', 64)) ->> 'authenticated')::boolean, false)
     or coalesce((public.patient_portal_attendance_detail(repeat('c', 64), v_attendance_a) ->> 'authenticated')::boolean, false) then
    raise exception 'APIs da fase 6.3 permaneceram acessíveis após logout.';
  end if;
end;
$$;

reset role;

do $$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'public.patient_portal_history_page(text,timestamp with time zone,text,integer)',
    'public.patient_portal_attendance_page(text,timestamp with time zone,bigint,integer)',
    'public.patient_portal_attendance_detail(text,bigint)'
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
  'phase', '6.3',
  'status', 'ok',
  'keyset_pagination', true,
  'historical_snapshots', true,
  'patient_a_to_b_isolated', true,
  'logout_revoked', true,
  'residue', false
) as result;
