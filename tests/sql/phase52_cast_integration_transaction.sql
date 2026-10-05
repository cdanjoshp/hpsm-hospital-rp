begin;

do $$
declare
  v_manager uuid;
  v_manager_session uuid;
  v_operational uuid;
  v_operational_session uuid;
  v_position_id bigint;
  v_patient bigint;
  v_due_first bigint;
  v_due_second bigint;
  v_cancelled bigint;
  v_summary jsonb;
  v_pending jsonb;
  v_timeline jsonb;
  v_shell_before integer;
  v_shell_after integer;
  v_notifications_before integer;
  v_blocked boolean := false;
begin
  select profile.user_id, profile.position_id into v_manager, v_position_id
  from public.profiles profile
  join public.staff_positions position on position.id = profile.position_id
  where profile.status = 'active'
    and position.official
    and private.has_permission(profile.user_id, 'patients.view')
    and private.has_permission(profile.user_id, 'casts.view')
    and private.has_permission(profile.user_id, 'casts.create')
    and private.has_permission(profile.user_id, 'casts.remove')
    and private.has_permission(profile.user_id, 'casts.manage')
  order by position.level desc, profile.created_at
  limit 1;

  select profile.user_id into v_operational
  from public.profiles profile
  join public.staff_positions position on position.id = profile.position_id
  where profile.status = 'active'
    and position.official
    and private.has_permission(profile.user_id, 'casts.view')
    and not private.has_permission(profile.user_id, 'casts.manage')
  order by position.level, profile.created_at
  limit 1;

  select session.id into v_manager_session
  from auth.sessions session
  where session.user_id = v_manager and (session.not_after is null or session.not_after > now())
  order by session.created_at desc limit 1;
  select session.id into v_operational_session
  from auth.sessions session
  where session.user_id = v_operational and (session.not_after is null or session.not_after > now())
  order by session.created_at desc limit 1;
  select patient.id into v_patient from public.patients patient order by patient.id limit 1;

  if v_manager is null or v_manager_session is null or v_operational is null
     or v_operational_session is null or v_patient is null then
    raise exception 'A Fase 5.2 requer gestor, profissional operacional, sessões e paciente ativos.';
  end if;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_manager, 'session_id', v_manager_session)::text, true);
  select count(*) into v_notifications_before from public.notifications;
  v_shell_before := coalesce((public.hpsm_shell_snapshot()->>'pending_count')::integer, 0);

  v_due_first := public.create_clinical_cast(
    v_patient, null, 'forearm', 'right', 'male', now() - interval '12 days', now() - interval '3 days',
    'Fase 5.2 · primeiro gesso vencido.', true
  );
  v_due_second := public.create_clinical_cast(
    v_patient, null, 'ankle', 'left', 'female', now() - interval '10 days', now() - interval '2 days',
    'Fase 5.2 · segundo gesso vencido.', true
  );
  v_cancelled := public.create_clinical_cast(
    v_patient, null, 'wrist', 'left', 'male', now() - interval '8 days', now() - interval '1 day',
    'Fase 5.2 · gesso para cancelamento.', true
  );

  v_summary := public.patient_active_clinical_casts(v_patient);
  if (select count(*) from jsonb_array_elements(v_summary) item where (item->>'id')::bigint in (v_due_first, v_due_second, v_cancelled)) <> 3 then
    raise exception 'Resumo do paciente não preservou múltiplos gessos ativos.';
  end if;
  if (select ordinality from jsonb_array_elements(v_summary) with ordinality item(value, ordinality) where (value->>'id')::bigint = v_due_first)
     >= (select ordinality from jsonb_array_elements(v_summary) with ordinality item(value, ordinality) where (value->>'id')::bigint = v_due_second) then
    raise exception 'Resumo não foi ordenado pela previsão mais próxima.';
  end if;

  v_pending := public.clinical_cast_overdue_page(250);
  if (select count(*) from jsonb_array_elements(v_pending) item where (item->>'id')::bigint in (v_due_first, v_due_second, v_cancelled)) <> 3 then
    raise exception 'Central não derivou uma pendência por gesso vencido.';
  end if;
  if (select count(distinct (item->>'id')::bigint) from jsonb_array_elements(v_pending) item where (item->>'id')::bigint in (v_due_first, v_due_second, v_cancelled)) <> 3 then
    raise exception 'Central duplicou uma pendência de gesso.';
  end if;
  v_shell_after := coalesce((public.hpsm_shell_snapshot()->>'pending_count')::integer, 0);
  if v_shell_after <> v_shell_before + 3 then
    raise exception 'Contador global não incorporou as três pendências derivadas.';
  end if;

  v_timeline := public.patient_timeline(v_patient, 100);
  if (select count(*) from jsonb_array_elements(v_timeline) event where event->>'type' = 'cast-applied' and (event->>'cast_id')::bigint in (v_due_first, v_due_second, v_cancelled)) <> 3 then
    raise exception 'Timeline não registrou as aplicações de gesso.';
  end if;

  perform public.update_clinical_cast_expected_removal(v_due_first, now() + interval '5 days', 'Reavaliação remove a pendência vencida.');
  v_pending := public.clinical_cast_overdue_page(250);
  if exists (select 1 from jsonb_array_elements(v_pending) item where (item->>'id')::bigint = v_due_first) then
    raise exception 'Previsão futura não resolveu a pendência automaticamente.';
  end if;
  perform public.update_clinical_cast_expected_removal(v_due_first, now() - interval '1 day', 'Nova avaliação recoloca a retirada como vencida.');
  v_pending := public.clinical_cast_overdue_page(250);
  if not exists (select 1 from jsonb_array_elements(v_pending) item where (item->>'id')::bigint = v_due_first) then
    raise exception 'Previsão novamente vencida não recriou a derivação.';
  end if;

  perform public.remove_clinical_cast(v_due_first, now(), 'Retirada registrada pelo teste integrado.');
  perform public.cancel_clinical_cast(v_cancelled, 'Registro cancelado pelo teste integrado.');
  v_pending := public.clinical_cast_overdue_page(250);
  if exists (select 1 from jsonb_array_elements(v_pending) item where (item->>'id')::bigint in (v_due_first, v_cancelled)) then
    raise exception 'Retirada ou cancelamento deixou pendência órfã.';
  end if;

  v_timeline := public.patient_timeline(v_patient, 100);
  if not exists (select 1 from jsonb_array_elements(v_timeline) event where event->>'type' = 'cast-removed' and (event->>'cast_id')::bigint = v_due_first)
     or not exists (select 1 from jsonb_array_elements(v_timeline) event where event->>'type' = 'cast-cancelled' and (event->>'cast_id')::bigint = v_cancelled)
     or (select count(*) from jsonb_array_elements(v_timeline) event where event->>'type' = 'cast-forecast-changed' and (event->>'cast_id')::bigint = v_due_first) <> 2 then
    raise exception 'Timeline de previsão, retirada ou cancelamento ficou incompleta.';
  end if;
  if (select count(*) from public.notifications) <> v_notifications_before then
    raise exception 'O fluxo derivado criou notificação persistente sem agendador.';
  end if;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_operational, 'session_id', v_operational_session)::text, true);
  begin
    perform public.clinical_cast_overdue_page(250);
  exception when insufficient_privilege then
    v_blocked := true;
  end;
  if not v_blocked then
    raise exception 'Profissional sem casts.manage visualizou a fila gerencial.';
  end if;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_manager, 'session_id', v_manager_session)::text, true);
  delete from public.staff_position_permissions
  where position_id = v_position_id and permission_code = 'casts.view';
  delete from public.user_permission_grants
  where user_id = v_manager and permission_code = 'casts.view';
  if private.has_permission(v_manager, 'casts.view') then
    raise exception 'Não foi possível preparar o cenário sem casts.view.';
  end if;
  v_blocked := false;
  begin
    perform public.patient_active_clinical_casts(v_patient);
  exception when insufficient_privilege then
    v_blocked := true;
  end;
  if not v_blocked then
    raise exception 'Usuário sem casts.view consultou os gessos do paciente.';
  end if;
end;
$$;

rollback;
