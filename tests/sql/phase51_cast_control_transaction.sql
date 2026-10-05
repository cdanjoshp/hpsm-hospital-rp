begin;

do $$
declare
  v_actor uuid;
  v_manager uuid;
  v_actor_session uuid;
  v_manager_session uuid;
  v_patient bigint;
  v_other_patient bigint;
  v_attendance bigint;
  v_service bigint;
  v_cast bigint;
  v_second_cast bigint;
  v_cancelled_cast bigint;
  v_expected timestamptz;
  v_blocked boolean;
  v_before integer;
begin
  select profile.user_id into v_actor
  from public.profiles profile
  join public.staff_positions position on position.id = profile.position_id
  where profile.status = 'active' and position.official and position.level between 1 and 10
    and private.has_permission(profile.user_id, 'casts.create')
    and private.has_permission(profile.user_id, 'casts.remove')
  order by position.level, profile.created_at
  limit 1;

  select profile.user_id into v_manager
  from public.profiles profile
  join public.staff_positions position on position.id = profile.position_id
  where profile.status = 'active' and position.official and position.level between 11 and 14
    and private.has_permission(profile.user_id, 'casts.manage')
  order by position.level desc, profile.created_at
  limit 1;

  if v_actor is null or v_manager is null then
    raise exception 'A Fase 5.1 requer um profissional operacional e um gestor ativos.';
  end if;

  select session.id into v_actor_session
  from auth.sessions session
  where session.user_id = v_actor and (session.not_after is null or session.not_after > now())
  order by session.created_at desc limit 1;
  select session.id into v_manager_session
  from auth.sessions session
  where session.user_id = v_manager and (session.not_after is null or session.not_after > now())
  order by session.created_at desc limit 1;
  if v_actor_session is null or v_manager_session is null then
    raise exception 'A Fase 5.1 requer sessões de teste ativas.';
  end if;

  select patient.id into v_patient from public.patients patient order by patient.id limit 1;
  select patient.id into v_other_patient from public.patients patient where patient.id <> v_patient order by patient.id limit 1;
  if v_patient is null or v_other_patient is null then
    raise exception 'A Fase 5.1 requer dois pacientes existentes para validar o vínculo.';
  end if;

  select catalog.id into v_service
  from public.service_catalog catalog
  where upper(btrim(catalog.name)) = 'GESSO'
  order by catalog.id limit 1;
  if v_service is null then raise exception 'Item canônico GESSO não localizado.'; end if;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_actor, 'session_id', v_actor_session)::text, true);
  select count(*)::integer into v_before from public.clinical_casts;

  insert into public.attendances (
    patient_name, patient_passport, status, subtotal, discount, performed_by, patient_id
  )
  select patient.name, patient.passport, 'completed', catalog.unit_price, 0, v_actor, patient.id
  from public.patients patient
  cross join public.service_catalog catalog
  where patient.id = v_patient and catalog.id = v_service
  returning id into v_attendance;

  insert into public.attendance_items (attendance_id, service_id, service_name, unit_price, quantity)
  select v_attendance, catalog.id, catalog.name, catalog.unit_price, 1
  from public.service_catalog catalog where catalog.id = v_service;

  if (select count(*)::integer from public.clinical_casts) <> v_before then
    raise exception 'A venda financeira criou um registro clínico automaticamente.';
  end if;

  v_blocked := false;
  begin
    perform public.create_clinical_cast(
      v_other_patient, v_attendance, 'arm', 'right', 'male', now(), now() + interval '14 days', null, false
    );
  exception when others then v_blocked := true;
  end;
  if not v_blocked then raise exception 'Atendimento de outro paciente foi aceito.'; end if;

  v_cast := public.create_clinical_cast(
    v_patient, v_attendance, 'arm', 'right', 'male', now(), now() + interval '14 days',
    'Imobilização clínica inicial.', false
  );
  if not exists (
    select 1 from public.clinical_casts cast_record
    where cast_record.id = v_cast and cast_record.status = 'in_use'
      and cast_record.patient_id = v_patient and cast_record.attendance_id = v_attendance
      and cast_record.applied_by = v_actor and cast_record.created_by = v_actor
  ) then raise exception 'Aplicação não foi registrada corretamente.'; end if;

  v_blocked := false;
  begin
    perform public.create_clinical_cast(
      v_patient, null, 'arm', 'right', 'male', now(), now() + interval '10 days', null, false
    );
  exception when unique_violation then v_blocked := true;
  end;
  if not v_blocked then raise exception 'Duplicidade ativa silenciosa foi aceita.'; end if;

  v_second_cast := public.create_clinical_cast(
    v_patient, null, 'leg', 'left', 'male', now(), now() + interval '7 days', null, false
  );
  perform public.create_clinical_cast(
    v_patient, null, 'arm', 'right', 'male', now(), now() + interval '21 days', null, true
  );
  if (select count(*) from public.clinical_casts where patient_id = v_patient and status = 'in_use') < 3 then
    raise exception 'Múltiplas regiões ou confirmação explícita não foram preservadas.';
  end if;

  v_expected := now() + interval '18 days';
  perform public.update_clinical_cast_expected_removal(v_cast, v_expected, 'Extensão planejada após reavaliação.');
  if not exists (
    select 1 from public.audit_logs log
    where log.entity_name = 'clinical_casts' and log.entity_id = v_cast::text
      and log.action = 'CAST_EXPECTED_REMOVAL_CHANGED'
      and log.old_values ? 'expected_removal_at'
      and log.new_values->>'reason' = 'Extensão planejada após reavaliação.'
  ) then raise exception 'Alteração de previsão não preservou auditoria e motivo.'; end if;

  perform public.remove_clinical_cast(v_cast, now() + interval '2 days', 'Retirada antecipada registrada.');
  if not exists (
    select 1 from public.clinical_casts cast_record
    where cast_record.id = v_cast and cast_record.status = 'removed'
      and cast_record.removed_by = v_actor and cast_record.removed_at < cast_record.expected_removal_at
  ) then raise exception 'Retirada antecipada não foi registrada.'; end if;

  v_blocked := false;
  begin
    perform public.remove_clinical_cast(v_cast, now() + interval '3 days', null);
  exception when others then v_blocked := true;
  end;
  if not v_blocked then raise exception 'A segunda retirada não foi bloqueada.'; end if;

  perform public.remove_clinical_cast(v_second_cast, now() + interval '9 days', 'Retirada posterior à previsão.');
  if (select status from public.clinical_casts where id = v_second_cast) <> 'removed' then
    raise exception 'Retirada posterior à previsão falhou.';
  end if;

  v_cancelled_cast := public.create_clinical_cast(
    v_patient, null, 'wrist', 'left', 'female', now(), now() + interval '5 days', null, false
  );
  v_blocked := false;
  begin
    perform public.cancel_clinical_cast(v_cancelled_cast, 'Teste operacional sem gestão.');
  exception when insufficient_privilege then v_blocked := true;
  end;
  if not v_blocked then raise exception 'Profissional operacional cancelou sem casts.manage.'; end if;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_manager, 'session_id', v_manager_session)::text, true);
  perform public.cancel_clinical_cast(v_cancelled_cast, 'Registro criado apenas para validação transacional.');
  if not exists (
    select 1 from public.clinical_casts cast_record
    where cast_record.id = v_cancelled_cast and cast_record.status = 'cancelled'
      and cast_record.cancelled_by = v_manager and cast_record.cancellation_reason is not null
  ) then raise exception 'Cancelamento auditado falhou.'; end if;

  if not exists (
    select 1 from public.audit_logs log
    where log.entity_name = 'clinical_casts' and log.entity_id = v_cast::text and log.action = 'CAST_APPLIED'
  ) or not exists (
    select 1 from public.audit_logs log
    where log.entity_name = 'clinical_casts' and log.entity_id = v_cast::text and log.action = 'CAST_REMOVED'
  ) or not exists (
    select 1 from public.audit_logs log
    where log.entity_name = 'clinical_casts' and log.entity_id = v_cancelled_cast::text and log.action = 'CAST_CANCELLED'
  ) then raise exception 'Auditoria essencial do fluxo ficou incompleta.'; end if;

  perform set_config('request.jwt.claims', '{}'::jsonb::text, true);
  v_blocked := false;
  begin
    perform public.clinical_cast_page(null, null, 20, 0);
  exception when insufficient_privilege then v_blocked := true;
  end;
  if not v_blocked then raise exception 'Consulta sem autenticação não foi bloqueada.'; end if;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_actor, 'session_id', v_actor_session)::text, true);
end;
$$;

-- A leitura direta autorizada continua funcional sob RLS; escritas seguem exclusivas das RPCs.
set local role authenticated;
do $$
begin
  perform count(*) from public.clinical_casts;
end;
$$;
reset role;

rollback;
