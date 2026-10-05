begin;

create temporary table post1_plan_context (
  key text primary key,
  value text not null
) on commit drop;

do $$
declare
  v_actor uuid;
  v_actor_session uuid;
  v_limited uuid;
  v_limited_session uuid;
  v_passport text;
  v_patient bigint;
begin
  select profile.user_id, session.id
  into v_actor, v_actor_session
  from public.profiles profile
  join auth.sessions session on session.user_id = profile.user_id
  where profile.status = 'active'
    and not profile.must_change_password
    and private.has_permission(profile.user_id, 'healthplans.review')
    and private.current_position_level(profile.user_id) between 11 and 14
    and (session.not_after is null or session.not_after > now())
  order by session.created_at desc
  limit 1;

  select profile.user_id, session.id
  into v_limited, v_limited_session
  from public.profiles profile
  join auth.sessions session on session.user_id = profile.user_id
  where profile.status = 'active'
    and not profile.must_change_password
    and coalesce(private.current_position_level(profile.user_id), 0) not between 11 and 14
    and (session.not_after is null or session.not_after > now())
  order by session.created_at desc
  limit 1;

  if v_actor is null or v_limited is null then
    raise exception 'Sessões de teste dos níveis administrativo e limitado não estão disponíveis.';
  end if;

  select lpad(number::text, 4, '0')
  into v_passport
  from generate_series(1, 9999) number
  where not exists (
    select 1 from public.patients patient where patient.passport = lpad(number::text, 4, '0')
  )
  order by number desc
  limit 1;

  insert into public.patients (passport, name, phone, birth_date)
  values (v_passport, 'Regressão Plano Administrativo', '(055) 610-010', date '1990-01-01')
  returning id into v_patient;

  insert into post1_plan_context (key, value) values
    ('actor', v_actor::text),
    ('actor_session', v_actor_session::text),
    ('limited', v_limited::text),
    ('limited_session', v_limited_session::text),
    ('patient', v_patient::text),
    ('first_date', (timezone('America/Sao_Paulo', now())::date + 45)::text),
    ('second_date', (timezone('America/Sao_Paulo', now())::date + 75)::text);
end;
$$;

grant select, insert, update on post1_plan_context to authenticated;
grant select on post1_plan_context to service_role;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', (select value from post1_plan_context where key = 'actor'),
    'session_id', (select value from post1_plan_context where key = 'actor_session'),
    'role', 'authenticated'
  )::text,
  true
);
set local role authenticated;

do $$
declare
  v_patient bigint := (select value::bigint from post1_plan_context where key = 'patient');
  v_first_date date := (select value::date from post1_plan_context where key = 'first_date');
  v_result jsonb;
begin
  v_result := public.admin_set_patient_health_plan(v_patient, v_first_date);
  if v_result ->> 'action' <> 'grant'
     or v_result ->> 'status' <> 'active'
     or (v_result ->> 'financial_value')::numeric <> 0
     or (v_result ->> 'valid_until')::timestamptz < v_first_date::timestamptz then
    raise exception 'A concessão administrativa não retornou o estado esperado: %', v_result;
  end if;
end;
$$;

reset role;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', (select value from post1_plan_context where key = 'limited'),
    'session_id', (select value from post1_plan_context where key = 'limited_session'),
    'role', 'authenticated'
  )::text,
  true
);
set local role authenticated;

do $$
declare
  v_patient bigint := (select value::bigint from post1_plan_context where key = 'patient');
  v_second_date date := (select value::date from post1_plan_context where key = 'second_date');
begin
  begin
    perform public.admin_set_patient_health_plan(v_patient, v_second_date);
    raise exception 'Um cargo fora dos níveis 11 a 14 alterou o plano.';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

reset role;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', (select value from post1_plan_context where key = 'actor'),
    'session_id', (select value from post1_plan_context where key = 'actor_session'),
    'role', 'authenticated'
  )::text,
  true
);
set local role authenticated;

do $$
declare
  v_patient bigint := (select value::bigint from post1_plan_context where key = 'patient');
  v_second_date date := (select value::date from post1_plan_context where key = 'second_date');
  v_result jsonb;
begin
  v_result := public.admin_set_patient_health_plan(v_patient, v_second_date);
  if v_result ->> 'action' <> 'expiry_adjustment'
     or (v_result ->> 'financial_value')::numeric <> 0 then
    raise exception 'O ajuste de vencimento não retornou o estado esperado: %', v_result;
  end if;
end;
$$;

reset role;
set local role service_role;

do $$
declare
  v_patient bigint := (select value::bigint from post1_plan_context where key = 'patient');
  v_first_date date := (select value::date from post1_plan_context where key = 'first_date');
  v_second_date date := (select value::date from post1_plan_context where key = 'second_date');
  v_latest public.patient_health_plan_requests%rowtype;
begin
  if (select count(*) from public.patient_health_plan_requests where patient_id = v_patient) <> 2 then
    raise exception 'As ações administrativas não foram registradas de forma append-only.';
  end if;

  if exists (
    select 1
    from public.patient_health_plan_requests request
    where request.patient_id = v_patient
      and (request.attendance_id is not null
        or request.origin <> 'administrative'
        or request.status <> 'approved'
        or request.administrative_action not in ('grant', 'expiry_adjustment'))
  ) then
    raise exception 'O histórico administrativo contém origem financeira ou estado inválido.';
  end if;

  if (select count(*) from public.attendances where patient_id = v_patient) <> 0
     or exists (
       select 1 from public.attendance_items item
       join public.attendances attendance on attendance.id = item.attendance_id
       where attendance.patient_id = v_patient
     ) then
    raise exception 'A ação administrativa criou atendimento ou item financeiro.';
  end if;

  select request.* into v_latest
  from public.patient_health_plan_requests request
  where request.patient_id = v_patient
  order by request.reviewed_at desc, request.id desc
  limit 1;

  if v_latest.administrative_action <> 'expiry_adjustment'
     or (v_latest.coverage_end at time zone 'America/Sao_Paulo')::date <> v_second_date then
    raise exception 'A validade canônica não corresponde ao ajuste mais recente.';
  end if;

  if not exists (
    select 1 from public.patient_health_plan_requests request
    where request.patient_id = v_patient
      and request.administrative_action = 'grant'
      and (request.coverage_end at time zone 'America/Sao_Paulo')::date = v_first_date
  ) then
    raise exception 'A concessão original foi sobrescrita em vez de preservada.';
  end if;

  if not exists (
    select 1 from public.patient_directory directory
    where directory.id = v_patient
      and directory.plan_status = 'active'
      and (directory.plan_valid_until at time zone 'America/Sao_Paulo')::date = v_second_date
  ) then
    raise exception 'O perfil do paciente não refletiu o ajuste administrativo.';
  end if;
end;
$$;

reset role;
rollback;

select jsonb_build_object(
  'feature', 'administrative_health_plan',
  'status', 'ok',
  'levels', '11-14',
  'append_only', true,
  'financial_value', 0,
  'attendance_created', false,
  'residue', false
) as result;
