begin;

create temporary table post_go_patient_registration_context as
select
  profile.user_id,
  session.id as session_id,
  (
    select lpad(candidate::text, 4, '0')
    from generate_series(0, 9999) candidate
    where not exists (
      select 1
      from public.patients patient
      where patient.passport = lpad(candidate::text, 4, '0')
    )
    limit 1
  ) as passport
from public.profiles profile
join auth.sessions session on session.user_id = profile.user_id
where profile.status = 'active'
  and not profile.must_change_password
  and private.has_permission(profile.user_id, 'patients.view')
  and (session.not_after is null or session.not_after > now())
order by session.created_at desc
limit 1;

do $$
begin
  if not exists (
    select 1
    from post_go_patient_registration_context
    where user_id is not null
      and session_id is not null
      and passport is not null
  ) then
    raise exception 'A regressão requer sessão operacional e passaporte livre.';
  end if;
end;
$$;

grant select on post_go_patient_registration_context to authenticated;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', (select user_id from post_go_patient_registration_context),
    'role', 'authenticated',
    'session_id', (select session_id from post_go_patient_registration_context)
  )::text,
  true
);

set local role authenticated;

insert into public.patients (
  passport,
  name,
  phone,
  birth_date,
  emergency_contact_name,
  emergency_contact_phone,
  allergies,
  created_by,
  updated_by
)
select
  passport,
  'Regressão Cadastro Paciente',
  null,
  date '2000-01-01',
  null,
  null,
  'Não possui',
  user_id,
  user_id
from post_go_patient_registration_context;

do $$
declare
  v_passport text := (select passport from post_go_patient_registration_context);
begin
  if not exists (
    select 1
    from public.patients
    where passport = v_passport
      and name = 'Regressão Cadastro Paciente'
  ) then
    raise exception 'Cadastro autenticado não persistiu o paciente canônico.';
  end if;

  if has_function_privilege(
    'authenticated',
    'private.normalize_patient_passport(text)',
    'EXECUTE'
  ) then
    raise exception 'Helper privado de passaporte foi exposto ao papel autenticado.';
  end if;
end;
$$;

reset role;
rollback;

select jsonb_build_object(
  'status', 'ok',
  'authenticated_insert', true,
  'canonical_passport', true,
  'private_helper_exposed', false,
  'residue', false
) as result;
