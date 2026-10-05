begin;

create temporary table cast_group_context as
select
  profile.user_id as actor_id,
  session.id as session_id,
  (select patient.id from public.patients patient order by patient.id limit 1) as patient_id,
  (
    select reference.game_reference
    from public.clinical_cast_references reference
    where reference.body_model = 'male'
      and reference.body_region = 'arm'
      and reference.laterality = 'left'
      and reference.active
  ) as arm_reference,
  (
    select reference.game_reference
    from public.clinical_cast_references reference
    where reference.body_model = 'female'
      and reference.body_region = 'leg'
      and reference.laterality = 'right'
      and reference.active
  ) as leg_reference
from public.profiles profile
join auth.sessions session on session.user_id = profile.user_id
where profile.status = 'active'
  and not profile.must_change_password
  and private.has_permission(profile.user_id, 'casts.create')
  and private.has_permission(profile.user_id, 'patients.view')
  and (session.not_after is null or session.not_after > now())
order by session.created_at desc
limit 1;

do $$
declare
  v_actor uuid := (select actor_id from cast_group_context);
  v_patient bigint := (select patient_id from cast_group_context);
begin
  if v_actor is null or v_patient is null
     or (select arm_reference from cast_group_context) is null
     or (select leg_reference from cast_group_context) is null then
    raise exception 'A regressão requer sessão operacional, paciente e referências ativas.';
  end if;
end;
$$;

grant select on cast_group_context to authenticated;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', (select actor_id from cast_group_context),
    'role', 'authenticated',
    'session_id', (select session_id from cast_group_context)
  )::text,
  true
);

set local role authenticated;

do $$
declare
  v_patient bigint := (select patient_id from cast_group_context);
  v_region text;
  v_cast_id bigint;
  v_expected_reference text;
  v_detail jsonb;
begin
  v_expected_reference := (select arm_reference from cast_group_context);

  foreach v_region in array array['hand', 'wrist', 'forearm', 'elbow', 'arm'] loop
    v_cast_id := public.create_clinical_cast(
      v_patient, null, v_region, 'left', 'male', now(), now() + interval '7 days', null, true
    );
    v_detail := public.clinical_cast_detail(v_cast_id);
    if v_detail ->> 'body_region' <> v_region
       or v_detail ->> 'reference_body_region_snapshot' <> 'arm'
       or v_detail ->> 'game_reference_snapshot' <> v_expected_reference then
      raise exception 'Parte superior % não reutilizou a referência de braço.', v_region;
    end if;
  end loop;

  v_expected_reference := (select leg_reference from cast_group_context);

  foreach v_region in array array['foot', 'ankle', 'leg', 'knee'] loop
    v_cast_id := public.create_clinical_cast(
      v_patient, null, v_region, 'right', 'female', now(), now() + interval '7 days', null, true
    );
    v_detail := public.clinical_cast_detail(v_cast_id);
    if v_detail ->> 'body_region' <> v_region
       or v_detail ->> 'reference_body_region_snapshot' <> 'leg'
       or v_detail ->> 'game_reference_snapshot' <> v_expected_reference then
      raise exception 'Parte inferior % não reutilizou a referência de perna.', v_region;
    end if;
  end loop;

  begin
    perform public.create_clinical_cast(
      v_patient, null, 'wrist', 'left', 'male', now(), now() + interval '7 days', null, false
    );
    raise exception 'Duplicidade do mesmo grupo de aplicação foi aceita.';
  exception
    when unique_violation then null;
  end;
end;
$$;

reset role;
rollback;

select jsonb_build_object(
  'status', 'ok',
  'upper_group', true,
  'lower_group', true,
  'shared_game_reference', true,
  'group_duplicate_guard', true,
  'residue', false
) as result;
