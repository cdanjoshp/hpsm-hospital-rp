begin;

create temporary table phase105_context (
  key text primary key,
  value text not null
) on commit drop;

do $$
declare
  v_actor uuid;
  v_session uuid;
  v_responsible_passport text;
  v_existing_passport text;
  v_pending_passport text;
  v_review_passport text;
  v_responsible bigint;
  v_existing bigint;
  v_review bigint;
begin
  select profile.user_id, session.id into v_actor, v_session
  from public.profiles profile
  join public.staff_positions position on position.id = profile.position_id
  join auth.sessions session on session.user_id = profile.user_id
  where profile.status = 'active'
    and not profile.must_change_password
    and private.has_permission(profile.user_id, 'partnerships.manage')
    and private.has_permission(profile.user_id, 'attendances.create')
    and private.has_permission(profile.user_id, 'attendances.manage')
    and private.has_permission(profile.user_id, 'hr.reports.view')
    and (session.not_after is null or session.not_after > now())
  order by position.level desc, session.created_at desc
  limit 1;
  if v_actor is null or v_session is null then
    raise exception 'A Fase 10.5 requer uma sessão administrativa ativa.';
  end if;

  select lpad(candidate::text, 4, '0') into v_responsible_passport
  from generate_series(1, 9999) candidate
  where not exists (select 1 from public.patients where passport = lpad(candidate::text, 4, '0'))
  order by candidate desc limit 1;
  select lpad(candidate::text, 4, '0') into v_existing_passport
  from generate_series(1, 9999) candidate
  where lpad(candidate::text, 4, '0') <> v_responsible_passport
    and not exists (select 1 from public.patients where passport = lpad(candidate::text, 4, '0'))
  order by candidate desc limit 1;
  select lpad(candidate::text, 4, '0') into v_pending_passport
  from generate_series(1, 9999) candidate
  where lpad(candidate::text, 4, '0') not in (v_responsible_passport, v_existing_passport)
    and not exists (select 1 from public.patients where passport = lpad(candidate::text, 4, '0'))
  order by candidate desc limit 1;
  select lpad(candidate::text, 4, '0') into v_review_passport
  from generate_series(1, 9999) candidate
  where lpad(candidate::text, 4, '0') not in (v_responsible_passport, v_existing_passport, v_pending_passport)
    and not exists (select 1 from public.patients where passport = lpad(candidate::text, 4, '0'))
  order by candidate desc limit 1;

  insert into public.patients (passport, name, phone, birth_date, created_by, updated_by)
  values (v_responsible_passport, 'Responsável Parceria Fase Dez Cinco', '(055) 111-111', date '1985-02-10', v_actor, v_actor)
  returning id into v_responsible;
  insert into public.patients (passport, name, phone, birth_date, created_by, updated_by)
  values (v_existing_passport, 'Beneficiário Existente Fase Dez Cinco', '(055) 222-222', date '1990-04-11', v_actor, v_actor)
  returning id into v_existing;
  insert into public.patients (passport, name, phone, birth_date, created_by, updated_by)
  values (v_review_passport, 'Nome Canônico Diferente', '(055) 333-333', date '1992-06-12', v_actor, v_actor)
  returning id into v_review;

  insert into phase105_context values
    ('actor', v_actor::text), ('session', v_session::text),
    ('responsible', v_responsible::text), ('responsible_passport', v_responsible_passport),
    ('existing', v_existing::text), ('existing_passport', v_existing_passport),
    ('pending_passport', v_pending_passport), ('review', v_review::text), ('review_passport', v_review_passport),
    ('portal_token', repeat('5', 64));
end;
$$;

grant select, insert, update on phase105_context to authenticated, service_role;
set local role authenticated;

do $$
declare
  v_actor uuid := (select value::uuid from phase105_context where key = 'actor');
  v_session uuid := (select value::uuid from phase105_context where key = 'session');
  v_partnership bigint;
  v_import jsonb;
  v_members jsonb;
  v_pending_id bigint;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_actor, 'role', 'authenticated', 'session_id', v_session)::text, true);
  v_partnership := public.create_partnership(
    'Parceria Transacional Fase 10.5',
    'Registro temporário para comprovar o fluxo integral.',
    (select value::bigint from phase105_context where key = 'responsible')
  );
  insert into phase105_context values ('partnership', v_partnership::text);

  v_import := public.import_partnership_people(v_partnership, jsonb_build_array(
    jsonb_build_object('passport', (select value from phase105_context where key = 'existing_passport'), 'name', 'Beneficiário Existente Fase Dez Cinco'),
    jsonb_build_object('passport', (select value from phase105_context where key = 'pending_passport'), 'name', 'Beneficiário Futuro Fase Dez Cinco'),
    jsonb_build_object('passport', (select value from phase105_context where key = 'review_passport'), 'name', 'Nome Informado Incompatível'),
    jsonb_build_object('passport', 'inválido', 'name', '')
  ), 'batch');

  if (v_import #>> '{summary,linked}')::integer <> 1
     or (v_import #>> '{summary,pending_registration}')::integer <> 1
     or (v_import #>> '{summary,name_review}')::integer <> 1
     or (v_import #>> '{summary,invalid}')::integer <> 1 then
    raise exception 'Importação parcial divergente: %', v_import;
  end if;

  -- Repetição do paciente já vinculado não duplica a associação.
  v_import := public.import_partnership_people(v_partnership, jsonb_build_array(
    jsonb_build_object('passport', (select value from phase105_context where key = 'existing_passport'), 'name', 'Beneficiário Existente Fase Dez Cinco')
  ), 'individual');
  if (v_import #>> '{summary,already_linked}')::integer <> 1 then
    raise exception 'Importação idempotente não reconheceu vínculo existente: %', v_import;
  end if;

  v_members := public.hpsm_partnership_member_page(v_partnership, 'name_review', null, 20, 0);
  select (item ->> 'id')::bigint into v_pending_id
  from jsonb_array_elements(v_members -> 'items') item
  where item ->> 'status' = 'name_review'
  limit 1;
  insert into phase105_context values ('review_pending', v_pending_id::text);

  if (public.hpsm_partnership_detail(v_partnership) #>> '{partnership,responsible,passport}')
      <> (select value from phase105_context where key = 'responsible_passport') then
    raise exception 'Responsável principal não foi preservado.';
  end if;

  begin
    insert into public.patient_partnerships (patient_id, partnership_id, linked_by_type, linked_by_user_id)
    values ((select value::bigint from phase105_context where key = 'responsible'), v_partnership, 'professional', v_actor);
    raise exception 'Escrita direta autenticada foi aceita.';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;

-- Todo cadastro canônico resolve automaticamente o pré-beneficiário pelo passaporte.
do $$
declare
  v_actor uuid := (select value::uuid from phase105_context where key = 'actor');
  v_patient bigint;
begin
  insert into public.patients (passport, name, phone, birth_date, created_by, updated_by)
  values (
    (select value from phase105_context where key = 'pending_passport'),
    'Beneficiário Futuro Fase Dez Cinco', '(055) 444-444', date '1994-08-13', v_actor, v_actor
  ) returning id into v_patient;
  insert into phase105_context values ('resolved_patient', v_patient::text);
  if not exists (
    select 1 from public.patient_partnerships
    where patient_id = v_patient
      and partnership_id = (select value::bigint from phase105_context where key = 'partnership')
      and status = 'active' and linked_by_type = 'system'
  ) then raise exception 'Cadastro canônico não resolveu o pré-beneficiário.'; end if;
  if not exists (
    select 1 from public.partnership_pending_beneficiaries
    where passport = (select value from phase105_context where key = 'pending_passport')
      and status = 'resolved' and resolved_patient_id = v_patient
  ) then raise exception 'Pendência resolvida perdeu o histórico.'; end if;
end;
$$;

set local role service_role;
do $$
declare
  v_login jsonb;
  v_page jsonb;
  v_members jsonb;
begin
  v_login := public.patient_portal_create_session(
    (select value from phase105_context where key = 'responsible_passport'),
    date '1985-02-10',
    (select value from phase105_context where key = 'portal_token'),
    repeat('a', 64), repeat('b', 64)
  );
  if not coalesce((v_login ->> 'ok')::boolean, false) then raise exception 'Responsável não autenticou no Portal.'; end if;
  v_page := public.patient_portal_partnership_page((select value from phase105_context where key = 'portal_token'));
  if jsonb_array_length(v_page -> 'items') <> 1
     or v_page #>> '{items,0,id}' <> (select value from phase105_context where key = 'partnership') then
    raise exception 'Portal não isolou a parceria do responsável: %', v_page;
  end if;
  v_members := public.patient_portal_partnership_member_page(
    (select value from phase105_context where key = 'portal_token'),
    (select value::bigint from phase105_context where key = 'partnership'), 'all', null, 20, 0
  );
  if (v_members -> 'items' -> 0) ? 'patient_id'
     or (v_members -> 'items' -> 0) ? 'phone'
     or (v_members -> 'items' -> 0) ? 'birth_date' then
    raise exception 'Portal expôs dados além do mínimo permitido: %', v_members;
  end if;
end;
$$;
reset role;

set local role authenticated;
do $$
declare
  v_actor uuid := (select value::uuid from phase105_context where key = 'actor');
  v_session uuid := (select value::uuid from phase105_context where key = 'session');
  v_partnership bigint := (select value::bigint from phase105_context where key = 'partnership');
  v_patient bigint := (select value::bigint from phase105_context where key = 'existing');
  v_service bigint;
  v_attendance bigint;
  v_history jsonb;
  v_report jsonb;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_actor, 'role', 'authenticated', 'session_id', v_session)::text, true);
  if not public.review_partnership_pending((select value::bigint from phase105_context where key = 'review_pending'), 'confirm', null) then
    raise exception 'Revisão interna não confirmou o vínculo.';
  end if;
  select id into v_service from public.service_catalog where active order by id limit 1;
  if v_service is null then raise exception 'Catálogo necessário para o teste de atendimento.'; end if;
  v_attendance := public.create_attendance(v_patient, jsonb_build_array(jsonb_build_object('service_id', v_service, 'quantity', 1)), null, 'parceiros_hp', v_partnership);
  v_history := public.hpsm_attendance_history_page(20, 0, v_attendance);
  if v_history #>> '{items,0,partnership_id}' <> v_partnership::text
     or v_history #>> '{items,0,partnership_name}' <> 'Parceria Transacional Fase 10.5' then
    raise exception 'Atendimento perdeu o snapshot da parceria: %', v_history;
  end if;
  v_report := public.hpsm_report_partnerships(current_date - 1, current_date + 1);
  if not exists (
    select 1 from jsonb_array_elements(v_report) item
    where item ->> 'partnership_id' = v_partnership::text
      and (item ->> 'attendance_count')::integer >= 1
  ) then raise exception 'Relatório financeiro não agregou a parceria: %', v_report; end if;

  if not public.set_partnership_status(v_partnership, 'inactive', 'Encerramento temporário do teste transacional.') then
    raise exception 'Inativação falhou.';
  end if;
  begin
    perform public.create_attendance(v_patient, jsonb_build_array(jsonb_build_object('service_id', v_service, 'quantity', 1)), null, 'parceiros_hp', v_partnership);
    raise exception 'Parceria inativa continuou elegível.';
  exception when invalid_parameter_value then null;
  end;
end;
$$;
reset role;

set local role service_role;
do $$
begin
  begin
    perform public.patient_portal_import_partnership_people(
      (select value from phase105_context where key = 'portal_token'),
      (select value::bigint from phase105_context where key = 'partnership'),
      jsonb_build_array(jsonb_build_object('passport', '1', 'name', 'Bloqueado')), 'individual'
    );
    raise exception 'Portal alterou parceria inativa.';
  exception when invalid_parameter_value then null;
  end;
end;
$$;
reset role;

do $$
begin
  if has_table_privilege('authenticated', 'public.partnerships', 'SELECT')
     or has_table_privilege('service_role', 'public.patient_partnerships', 'SELECT')
     or has_function_privilege('authenticated', 'public.patient_portal_partnership_page(text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.hpsm_partnership_page(text,text,integer,integer)', 'EXECUTE') then
    raise exception 'Superfície de Parcerias recebeu privilégio direto indevido.';
  end if;
  if not has_function_privilege('authenticated', 'public.hpsm_partnership_page(text,text,integer,integer)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.patient_portal_partnership_page(text)', 'EXECUTE') then
    raise exception 'RPCs autorizadas não receberam os privilégios esperados.';
  end if;
end;
$$;

rollback;

select jsonb_build_object(
  'phase', '10.5',
  'status', 'ok',
  'partial_import', true,
  'automatic_resolution', true,
  'portal_isolated', true,
  'inactive_revocation', true,
  'attendance_snapshot', true,
  'report_aggregation', true,
  'residue', false
) as result;
