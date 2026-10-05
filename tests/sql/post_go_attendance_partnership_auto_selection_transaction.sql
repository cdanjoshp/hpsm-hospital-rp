begin;

create temporary table attendance_partnership_context (
  key text primary key,
  value text not null
) on commit drop;

do $$
declare
  v_actor uuid;
  v_session uuid;
  v_passport text;
  v_patient bigint;
  v_valid_partnership bigint;
  v_unlinked_partnership bigint;
  v_inactive_membership_partnership bigint;
  v_inactive_partnership bigint;
  v_service bigint;
  v_suffix text := txid_current()::text;
begin
  select profile.user_id, session.id into v_actor, v_session
  from public.profiles profile
  join public.staff_positions position on position.id = profile.position_id
  join auth.sessions session on session.user_id = profile.user_id
  where profile.status = 'active'
    and not profile.must_change_password
    and private.has_permission(profile.user_id, 'attendances.create')
    and private.has_permission(profile.user_id, 'patients.view')
    and private.has_permission(profile.user_id, 'catalog.view')
    and (session.not_after is null or session.not_after > now())
  order by position.level desc, session.created_at desc
  limit 1;

  if v_actor is null or v_session is null then
    raise exception 'O teste requer uma sessão profissional ativa com acesso a atendimentos.';
  end if;

  select lpad(candidate::text, 4, '0') into v_passport
  from generate_series(1, 9999) candidate
  where not exists (
    select 1 from public.patients where passport = lpad(candidate::text, 4, '0')
  )
  order by candidate desc
  limit 1;

  select id into v_service
  from public.service_catalog
  where active and code <> 'plano_saude_convenio'
  order by id
  limit 1;

  if v_passport is null or v_service is null then
    raise exception 'O teste requer um passaporte livre e um item ativo no catálogo.';
  end if;

  insert into public.patients (passport, name, allergies, created_by, updated_by)
  values (v_passport, 'Paciente Teste Seleção Automática', 'Não possui', v_actor, v_actor)
  returning id into v_patient;

  insert into public.partnerships (name, status, created_by, updated_by)
  values ('Parceria automática válida ' || v_suffix, 'active', v_actor, v_actor)
  returning id into v_valid_partnership;

  insert into public.partnerships (name, status, created_by, updated_by)
  values ('Parceria automática sem vínculo ' || v_suffix, 'active', v_actor, v_actor)
  returning id into v_unlinked_partnership;

  insert into public.partnerships (name, status, created_by, updated_by)
  values ('Parceria automática vínculo inativo ' || v_suffix, 'active', v_actor, v_actor)
  returning id into v_inactive_membership_partnership;

  insert into public.partnerships (
    name, status, created_by, updated_by, deactivated_at, deactivated_by, deactivation_reason
  ) values (
    'Parceria automática inativa ' || v_suffix,
    'inactive', v_actor, v_actor, now(), v_actor, 'Estado inativo para validação transacional.'
  ) returning id into v_inactive_partnership;

  insert into public.patient_partnerships (
    patient_id, partnership_id, linked_by_type, linked_by_user_id
  ) values (
    v_patient, v_valid_partnership, 'professional', v_actor
  );

  insert into public.patient_partnerships (
    patient_id, partnership_id, status, linked_by_type, linked_by_user_id,
    unlinked_at, unlinked_by_type, unlinked_by_user_id, unlink_reason
  ) values (
    v_patient, v_inactive_membership_partnership, 'inactive', 'professional', v_actor,
    now(), 'professional', v_actor, 'Vínculo inativo para validação transacional.'
  );

  insert into public.patient_partnerships (
    patient_id, partnership_id, linked_by_type, linked_by_user_id
  ) values (
    v_patient, v_inactive_partnership, 'professional', v_actor
  );

  insert into attendance_partnership_context values
    ('actor', v_actor::text),
    ('session', v_session::text),
    ('patient', v_patient::text),
    ('service', v_service::text),
    ('valid_partnership', v_valid_partnership::text),
    ('unlinked_partnership', v_unlinked_partnership::text),
    ('inactive_membership_partnership', v_inactive_membership_partnership::text),
    ('inactive_partnership', v_inactive_partnership::text);
end;
$$;

grant select, insert on attendance_partnership_context to authenticated;
set local role authenticated;

do $$
declare
  v_actor uuid := (select value::uuid from attendance_partnership_context where key = 'actor');
  v_session uuid := (select value::uuid from attendance_partnership_context where key = 'session');
  v_patient bigint := (select value::bigint from attendance_partnership_context where key = 'patient');
  v_service bigint := (select value::bigint from attendance_partnership_context where key = 'service');
  v_valid_partnership bigint := (select value::bigint from attendance_partnership_context where key = 'valid_partnership');
  v_attendance bigint;
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', v_actor, 'role', 'authenticated', 'session_id', v_session)::text,
    true
  );

  v_attendance := public.create_attendance(
    v_patient,
    jsonb_build_array(jsonb_build_object('service_id', v_service, 'quantity', 1)),
    null,
    'parceiros_hp',
    v_valid_partnership
  );
  insert into attendance_partnership_context values ('attendance', v_attendance::text);

  begin
    perform public.create_attendance(
      v_patient,
      jsonb_build_array(jsonb_build_object('service_id', v_service, 'quantity', 1)),
      null,
      'parceiros_hp',
      (select value::bigint from attendance_partnership_context where key = 'unlinked_partnership')
    );
    raise exception 'Backend aceitou parceria sem vínculo canônico.';
  exception when sqlstate '22023' then null;
  end;

  begin
    perform public.create_attendance(
      v_patient,
      jsonb_build_array(jsonb_build_object('service_id', v_service, 'quantity', 1)),
      null,
      'parceiros_hp',
      (select value::bigint from attendance_partnership_context where key = 'inactive_membership_partnership')
    );
    raise exception 'Backend aceitou vínculo inativo.';
  exception when sqlstate '22023' then null;
  end;

  begin
    perform public.create_attendance(
      v_patient,
      jsonb_build_array(jsonb_build_object('service_id', v_service, 'quantity', 1)),
      null,
      'parceiros_hp',
      (select value::bigint from attendance_partnership_context where key = 'inactive_partnership')
    );
    raise exception 'Backend aceitou parceria inativa.';
  exception when sqlstate '22023' then null;
  end;
end;
$$;

reset role;

do $$
declare
  v_attendance bigint := (select value::bigint from attendance_partnership_context where key = 'attendance');
  v_partnership bigint := (select value::bigint from attendance_partnership_context where key = 'valid_partnership');
begin
  if not exists (
    select 1
    from public.attendances attendance
    join public.partnerships partnership on partnership.id = attendance.partnership_id
    where attendance.id = v_attendance
      and attendance.plan_code = 'parceiros_hp'
      and attendance.partnership_id = v_partnership
      and attendance.partnership_name = partnership.name
      and attendance.status = 'completed'
  ) then
    raise exception 'Atendimento não preservou o vínculo e o snapshot da parceria.';
  end if;
end;
$$;

rollback;
