begin;

create temporary table phase7_context (
  key text primary key,
  value text not null
) on commit drop;

do $$
declare
  v_actor uuid;
  v_actor_session uuid;
  v_limited uuid;
  v_limited_session uuid;
  v_patient bigint;
  v_passport text;
  v_service bigint;
  v_application uuid;
  v_discord text;
  v_index integer;
  v_permission text;
begin
  select profile.user_id, session.id into v_actor, v_actor_session
  from public.profiles profile
  join public.staff_positions position on position.id = profile.position_id
  join auth.sessions session on session.user_id = profile.user_id
  where profile.status = 'active'
    and position.active
    and position.level between 11 and 14
    and (session.not_after is null or session.not_after > now())
  order by position.level desc, session.created_at desc
  limit 1;

  select profile.user_id, session.id into v_limited, v_limited_session
  from public.profiles profile
  join public.staff_positions position on position.id = profile.position_id
  join auth.sessions session on session.user_id = profile.user_id
  where profile.status = 'active'
    and position.active
    and position.level between 1 and 10
    and not private.has_permission(profile.user_id, 'catalog.manage')
    and not private.has_permission(profile.user_id, 'recruitment.manage')
    and (session.not_after is null or session.not_after > now())
  order by position.level, session.created_at desc
  limit 1;

  if v_actor is null or v_actor_session is null or v_limited is null or v_limited_session is null then
    raise exception 'A Fase 7 requer sessões ativas de um gestor e de um profissional operacional.';
  end if;

  foreach v_permission in array array[
    'patients.view', 'hr.team.view', 'attendances.manage', 'catalog.manage', 'recruitment.manage'
  ] loop
    insert into public.user_permission_grants (
      user_id, permission_code, grant_kind, valid_from, expires_at, reason, granted_by
    ) values (
      v_actor, v_permission,
      case when v_permission = 'patients.view' then 'individual' else 'temporary' end,
      clock_timestamp() - interval '1 minute',
      case when v_permission = 'patients.view' then null else clock_timestamp() + interval '1 hour' end,
      'Validação transacional da Busca Global da Fase 7.', v_actor
    );
  end loop;

  -- Uma concessão expirada não pode abrir o catálogo para o profissional limitado.
  insert into public.user_permission_grants (
    user_id, permission_code, grant_kind, valid_from, expires_at, reason, granted_by
  ) values (
    v_limited, 'catalog.manage', 'temporary', clock_timestamp() - interval '2 hours',
    clock_timestamp() - interval '1 hour', 'Permissão expirada usada no teste da Fase 7.', v_actor
  );

  for v_index in 1..6 loop
    select lpad(candidate::text, 4, '0') into v_passport
    from generate_series(1, 9999) candidate
    where not exists (select 1 from public.patients patient where patient.passport = lpad(candidate::text, 4, '0'))
      and not exists (select 1 from phase7_context context where context.key like 'passport_%' and context.value = lpad(candidate::text, 4, '0'))
    order by candidate desc limit 1;

    insert into public.patients (passport, name, phone, birth_date)
    values (
      v_passport, 'Paciente Busca Fase Sete ' || v_index,
      '(055) 770-' || lpad(v_index::text, 3, '0'), date '1990-01-01'
    )
    returning id into v_patient;
    insert into phase7_context values ('patient_' || v_index, v_patient::text), ('passport_' || v_index, v_passport);
  end loop;

  insert into public.attendances (
    patient_id, patient_name, patient_passport, status, subtotal, discount, performed_by
  ) values (
    (select value::bigint from phase7_context where key = 'patient_1'),
    'Paciente Busca Fase Sete 1', (select value from phase7_context where key = 'passport_1'),
    'completed', 725.50, 25.50, v_actor
  );

  insert into public.service_catalog (code, icon, name, category, unit_price, active, sort_order, created_by, updated_by)
  values ('fase7_raio_x', '🩻', 'Raio-X Financeiro Busca Fase Sete', 'Imagem financeira', 2500, true, 97, v_actor, v_actor)
  returning id into v_service;

  select lpad(candidate::text, 4, '0') into v_passport
  from generate_series(1, 9999) candidate
  where not exists (select 1 from public.recruitment_applications application where application.passport = lpad(candidate::text, 4, '0'))
    and not exists (select 1 from public.patients patient where patient.passport = lpad(candidate::text, 4, '0'))
  order by candidate desc limit 1;
  select lpad(candidate::text, 18, '7') into v_discord
  from generate_series(1, 9999) candidate
  where not exists (select 1 from public.recruitment_applications application where application.discord_id = lpad(candidate::text, 18, '7'))
  order by candidate desc limit 1;

  insert into public.recruitment_applications (
    full_name, passport, birth_day, birth_month, city_phone, discord_id, availability,
    prior_experience, experience_summary, interest_area, motivation, external_calls
  ) values (
    'Candidato Busca Fase Sete', v_passport, 7, 7, '(055) 777-777', v_discord,
    array['morning'], false, null, 'clinical_care',
    'Quero colaborar com o atendimento e com a operação do hospital durante o roleplay.', 'full'
  ) returning id into v_application;

  insert into phase7_context values
    ('actor', v_actor::text), ('actor_session', v_actor_session::text),
    ('limited', v_limited::text), ('limited_session', v_limited_session::text),
    ('service', v_service::text), ('application', v_application::text);
end;
$$;

grant select on phase7_context to authenticated;
set local role authenticated;

do $$
declare
  v_actor uuid := (select value::uuid from phase7_context where key = 'actor');
  v_actor_session uuid := (select value::uuid from phase7_context where key = 'actor_session');
  v_limited uuid := (select value::uuid from phase7_context where key = 'limited');
  v_limited_session uuid := (select value::uuid from phase7_context where key = 'limited_session');
  v_exact_patient text := (select value from phase7_context where key = 'patient_1');
  v_exact_passport text := (select value from phase7_context where key = 'passport_1');
  v_result jsonb;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_actor, 'session_id', v_actor_session)::text, true);

  v_result := public.hpsm_global_search('Busca Fase Sete', 99);
  if (select count(*) from jsonb_array_elements(v_result -> 'items') item where item ->> 'category' = 'patients') <> 5
     or (select count(*) from jsonb_array_elements(v_result -> 'items') item where item ->> 'category' = 'attendances') <> 1
     or (select count(*) from jsonb_array_elements(v_result -> 'items') item where item ->> 'category' = 'catalog') <> 1
     or (select count(*) from jsonb_array_elements(v_result -> 'items') item where item ->> 'category' = 'applications') <> 1 then
    raise exception 'Categorias autorizadas ou limite de cinco divergiram: %', v_result;
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_result -> 'items') item
    group by item ->> 'category', item ->> 'id' having count(*) > 1
  ) then raise exception 'A Busca Global retornou itens duplicados.'; end if;
  if v_result::text like '%birth_date%'
     or v_result::text like '%phone%'
     or v_result::text like '%review_notes%'
     or v_result::text like '%permission%'
     or v_result::text like '%clinical%' then
    raise exception 'A Busca Global vazou campo sensível ou clínico: %', v_result;
  end if;

  v_result := public.hpsm_global_search(v_exact_passport, 5);
  if v_result #>> '{items,0,category}' <> 'patients'
     or v_result #>> '{items,0,id}' <> v_exact_patient
     or v_result #>> '{items,0,subtitle}' not like '%' || v_exact_passport || '%' then
    raise exception 'Passaporte exato ou zeros à esquerda perderam prioridade: %', v_result;
  end if;

  v_result := public.hpsm_global_search('Raio-X', 5);
  if jsonb_array_length(v_result -> 'items') < 1
     or exists (select 1 from jsonb_array_elements(v_result -> 'items') item where item ->> 'category' <> 'catalog') then
    raise exception 'Raio-X deixou de ser exclusivamente um resultado financeiro do catálogo: %', v_result;
  end if;

  v_result := public.hpsm_global_search((select passport from public.profiles where user_id = v_actor), 5);
  if not exists (
    select 1 from jsonb_array_elements(v_result -> 'items') item
    where item ->> 'category' = 'professionals' and item ->> 'id' = v_actor::text
  ) then raise exception 'Profissional autorizado não apareceu por passaporte: %', v_result; end if;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_limited, 'session_id', v_limited_session)::text, true);
  v_result := public.hpsm_global_search('Raio-X Financeiro Busca Fase Sete', 5);
  if jsonb_array_length(v_result -> 'items') <> 0 then
    raise exception 'Concessão expirada abriu o catálogo para usuário sem permissão: %', v_result;
  end if;
end;
$$;

reset role;

do $$
begin
  if has_function_privilege('anon', 'public.hpsm_global_search(text,integer)', 'EXECUTE')
     or has_function_privilege('service_role', 'public.hpsm_global_search(text,integer)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.hpsm_global_search(text,integer)', 'EXECUTE') then
    raise exception 'Privilégios da Busca Global estão incorretos.';
  end if;
end;
$$;

rollback;

select jsonb_build_object(
  'phase', '7', 'status', 'ok', 'max_per_category', 5, 'effective_permissions', true,
  'exact_passport_first', true, 'clinical_search', false, 'residue', false
) as result;
