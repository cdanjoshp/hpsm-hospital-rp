begin;

do $$
declare
  v_manager uuid;
  v_manager_session uuid;
  v_common uuid;
  v_common_session uuid;
  v_patient bigint;
  v_reference public.clinical_cast_references;
  v_cast bigint;
  v_snapshot_id text;
  v_snapshot_description text;
  v_blocked boolean;
begin
  select profile.user_id, session.id
  into v_manager, v_manager_session
  from public.profiles profile
  join public.staff_positions position on position.id = profile.position_id
  join lateral (
    select auth_session.id
    from auth.sessions auth_session
    where auth_session.user_id = profile.user_id
      and (auth_session.not_after is null or auth_session.not_after > now())
    order by auth_session.created_at desc limit 1
  ) session on true
  where profile.status = 'active'
    and position.level between 11 and 14
    and private.has_permission(profile.user_id, 'casts.manage')
  order by position.level desc, profile.created_at
  limit 1;

  select profile.user_id, session.id
  into v_common, v_common_session
  from public.profiles profile
  join public.staff_positions position on position.id = profile.position_id
  join lateral (
    select auth_session.id
    from auth.sessions auth_session
    where auth_session.user_id = profile.user_id
      and (auth_session.not_after is null or auth_session.not_after > now())
    order by auth_session.created_at desc limit 1
  ) session on true
  where profile.status = 'active'
    and position.level between 1 and 10
    and private.has_permission(profile.user_id, 'casts.create')
  order by position.level, profile.created_at
  limit 1;

  select patient.id into v_patient from public.patients patient order by patient.id limit 1;
  if v_manager is null or v_manager_session is null or v_common is null or v_common_session is null or v_patient is null then
    raise exception 'O teste requer gestor, profissional comum, sessões ativas e paciente.';
  end if;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_manager, 'session_id', v_manager_session)::text, true);
  select * into v_reference
  from public.clinical_cast_references reference
  where reference.body_model = 'male' and reference.body_region = 'rib' and reference.laterality = 'not_applicable';
  if not found then raise exception 'Referência masculina de costela não localizada.'; end if;

  perform public.upsert_clinical_cast_reference(
    v_reference.id, v_reference.body_model, v_reference.body_region, v_reference.laterality,
    '659 / TESTE', 'Jaqueta 659 · teste transacional', true
  );

  v_cast := public.create_clinical_cast(
    v_patient, null, 'rib', 'not_applicable', 'male', now(), now() + interval '7 days',
    'Validação transacional do snapshot.', true
  );
  select cast_record.game_reference_snapshot, cast_record.reference_description_snapshot
  into v_snapshot_id, v_snapshot_description
  from public.clinical_casts cast_record where cast_record.id = v_cast;
  if v_snapshot_id <> '659 / TESTE' or v_snapshot_description <> 'Jaqueta 659 · teste transacional' then
    raise exception 'A aplicação não congelou a referência vigente.';
  end if;

  perform public.upsert_clinical_cast_reference(
    v_reference.id, v_reference.body_model, v_reference.body_region, v_reference.laterality,
    '659 / ALTERADO', 'Descrição alterada depois da aplicação', true
  );
  if not exists (
    select 1 from public.clinical_casts cast_record
    where cast_record.id = v_cast
      and cast_record.game_reference_snapshot = v_snapshot_id
      and cast_record.reference_description_snapshot = v_snapshot_description
  ) then raise exception 'A edição do catálogo reescreveu o snapshot histórico.'; end if;

  v_blocked := false;
  begin
    perform public.create_clinical_cast(
      v_patient, null, 'arm', 'right', now(), now() + interval '7 days', null, true
    );
  exception when others then v_blocked := true;
  end;
  if not v_blocked then raise exception 'A assinatura antiga criou gesso sem modelo.'; end if;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_common, 'session_id', v_common_session)::text, true);
  v_blocked := false;
  begin
    perform public.upsert_clinical_cast_reference(
      v_reference.id, v_reference.body_model, v_reference.body_region, v_reference.laterality,
      'BLOQUEAR', 'Profissional comum não pode editar', true
    );
  exception when insufficient_privilege then v_blocked := true;
  end;
  if not v_blocked then raise exception 'Profissional comum editou referência de gesso.'; end if;


end;
$$;

rollback;
