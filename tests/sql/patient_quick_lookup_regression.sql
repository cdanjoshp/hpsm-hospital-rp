begin;

do $$
declare
  v_actor uuid;
  v_session uuid;
  v_patient_passport text;
  v_missing_passport text;
  v_existing jsonb;
  v_missing jsonb;
begin
  select profile.user_id, session.id
  into v_actor, v_session
  from public.profiles profile
  join auth.sessions session on session.user_id = profile.user_id
  where profile.status = 'active'
    and private.has_permission(profile.user_id, 'patients.view')
    and (session.not_after is null or session.not_after > now())
  order by session.created_at desc
  limit 1;

  select patient.passport
  into v_patient_passport
  from public.patients patient
  order by patient.id
  limit 1;

  select lpad(candidate::text, 4, '0')
  into v_missing_passport
  from generate_series(0, 9999) candidate
  where not exists (
    select 1
    from public.patients patient
    where patient.passport = lpad(candidate::text, 4, '0')
  )
  limit 1;

  if v_actor is null or v_session is null or v_patient_passport is null or v_missing_passport is null then
    raise exception 'A regressão requer sessão operacional, paciente e passaporte livre.';
  end if;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', v_actor, 'session_id', v_session)::text,
    true
  );

  v_existing := public.hpsm_patient_quick_lookup(v_patient_passport, 8);
  v_missing := public.hpsm_patient_quick_lookup(v_missing_passport, 8);

  if jsonb_array_length(v_existing) < 1
     or v_existing #>> '{0,passport}' <> v_patient_passport
     or v_existing #> '{0,health_plan}' is null then
    raise exception 'A busca não retornou o paciente e o estado do plano esperados.';
  end if;

  if v_missing <> '[]'::jsonb then
    raise exception 'Passaporte inexistente não retornou uma lista vazia.';
  end if;

  if has_function_privilege('anon', 'public.hpsm_patient_quick_lookup(text,integer)', 'EXECUTE')
     or has_function_privilege('service_role', 'public.hpsm_patient_quick_lookup(text,integer)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.hpsm_patient_quick_lookup(text,integer)', 'EXECUTE') then
    raise exception 'Privilégios da busca rápida divergiram do contrato autenticado.';
  end if;
end;
$$;

rollback;

select jsonb_build_object(
  'status', 'ok',
  'existing_patient', true,
  'missing_patient', true,
  'plan_state', true,
  'permissions', true,
  'residue', false
) as result;
