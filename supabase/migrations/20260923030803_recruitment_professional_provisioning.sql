-- HPSM pós-GO: candidatura aprovada provisiona uma única conta profissional.
-- Candidaturas antigas permanecem sem vínculo e não são provisionadas retroativamente.

do $$
begin
  if exists (
    select 1
    from public.profiles profile
    group by lpad(profile.passport, 4, '0')
    having count(*) > 1
  ) then
    raise exception 'Existem profissionais com passaportes canônicos duplicados.';
  end if;
end;
$$;

create unique index profiles_passport_canonical_unique_idx
  on public.profiles ((lpad(passport, 4, '0')));

alter table public.recruitment_applications
  add column professional_user_id uuid,
  add column professional_passport text collate "C",
  add column initial_position_id bigint,
  add column professional_created_at timestamptz,
  add column provisioning_state text not null default 'not_started',
  add column provisioning_token uuid,
  add column provisioning_auth_user_id uuid,
  add column provisioning_started_at timestamptz,
  add column provisioning_finished_at timestamptz,
  add column provisioning_attempts integer not null default 0,
  add column provisioning_error_code text;

alter table public.recruitment_applications
  add constraint recruitment_professional_user_fkey
    foreign key (professional_user_id)
    references public.profiles(user_id)
    on update cascade
    on delete restrict,
  add constraint recruitment_initial_position_fkey
    foreign key (initial_position_id)
    references public.staff_positions(id)
    on update cascade
    on delete restrict,
  add constraint recruitment_provisioning_auth_user_fkey
    foreign key (provisioning_auth_user_id)
    references auth.users(id)
    on delete set null,
  add constraint recruitment_professional_passport_format
    check (professional_passport is null or professional_passport ~ '^[0-9]{4}$'),
  add constraint recruitment_provisioning_state_valid
    check (provisioning_state in ('not_started', 'in_progress', 'failed', 'completed')),
  add constraint recruitment_provisioning_attempts_valid
    check (provisioning_attempts >= 0),
  add constraint recruitment_provisioning_error_code_valid
    check (
      provisioning_error_code is null
      or provisioning_error_code ~ '^[a-z0-9_]{2,80}$'
    ),
  add constraint recruitment_provisioning_state_consistency
    check (
      (
        provisioning_state = 'not_started'
        and professional_user_id is null
        and professional_passport is null
        and initial_position_id is null
        and professional_created_at is null
        and provisioning_token is null
        and provisioning_auth_user_id is null
        and provisioning_started_at is null
        and provisioning_finished_at is null
        and provisioning_attempts = 0
        and provisioning_error_code is null
      )
      or (
        provisioning_state = 'in_progress'
        and professional_user_id is null
        and professional_passport is not null
        and initial_position_id is null
        and professional_created_at is null
        and provisioning_token is not null
        and provisioning_started_at is not null
        and provisioning_finished_at is null
        and provisioning_attempts > 0
        and provisioning_error_code is null
      )
      or (
        provisioning_state = 'failed'
        and professional_user_id is null
        and professional_passport is not null
        and initial_position_id is null
        and professional_created_at is null
        and provisioning_token is not null
        and provisioning_started_at is not null
        and provisioning_finished_at is not null
        and provisioning_attempts > 0
        and provisioning_error_code is not null
      )
      or (
        provisioning_state = 'completed'
        and professional_user_id is not null
        and professional_passport is not null
        and initial_position_id is not null
        and professional_created_at is not null
        and provisioning_token is not null
        and provisioning_auth_user_id = professional_user_id
        and provisioning_started_at is not null
        and provisioning_finished_at is not null
        and provisioning_attempts > 0
        and provisioning_error_code is null
      )
    );

create unique index recruitment_professional_user_unique_idx
  on public.recruitment_applications (professional_user_id)
  where professional_user_id is not null;

create unique index recruitment_professional_passport_unique_idx
  on public.recruitment_applications (professional_passport)
  where professional_passport is not null;

create index recruitment_initial_position_idx
  on public.recruitment_applications (initial_position_id)
  where initial_position_id is not null;

create index recruitment_provisioning_auth_user_idx
  on public.recruitment_applications (provisioning_auth_user_id)
  where provisioning_auth_user_id is not null;

create or replace function public.begin_recruitment_professional_provisioning(
  p_application_id uuid,
  p_actor_id uuid,
  p_provisioning_token uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_application public.recruitment_applications;
  v_passport text;
  v_level integer := coalesce(private.current_position_level(p_actor_id), 0);
begin
  if p_application_id is null or p_actor_id is null or p_provisioning_token is null then
    raise exception using errcode = '22023', message = 'Solicitação de provisionamento inválida.';
  end if;
  if not private.has_permission(p_actor_id, 'recruitment.manage')
     or v_level not between 11 and 14 then
    raise exception using errcode = '42501', message = 'Você não possui permissão para aprovar candidaturas.';
  end if;

  select * into v_application
  from public.recruitment_applications
  where id = p_application_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Candidatura não encontrada.';
  end if;

  if v_application.provisioning_state = 'completed' then
    return jsonb_build_object(
      'application_id', v_application.id,
      'state', 'completed',
      'replayed', true,
      'professional_user_id', v_application.professional_user_id,
      'professional_passport', v_application.professional_passport,
      'initial_position_id', v_application.initial_position_id,
      'professional_created_at', v_application.professional_created_at
    );
  end if;

  if v_application.status not in ('submitted', 'under_review', 'interview') then
    raise exception using errcode = 'P0002', message = 'Candidatura não está disponível para aprovação.';
  end if;
  if v_application.passport !~ '^[0-9]{1,4}$' then
    raise exception using errcode = '22023', message = 'O passaporte da candidatura é inválido para cadastro profissional.';
  end if;
  if char_length(btrim(v_application.full_name)) not between 2 and 80 then
    raise exception using errcode = '22023', message = 'O nome da candidatura é incompatível com o cadastro profissional.';
  end if;

  v_passport := lpad(v_application.passport, 4, '0');

  if exists (
    select 1
    from public.profiles profile
    where lpad(profile.passport, 4, '0') = v_passport
  ) then
    raise exception using
      errcode = '23505',
      message = format('Já existe um profissional cadastrado com o passaporte %s.', v_passport);
  end if;

  if v_application.provisioning_state = 'in_progress'
     and v_application.provisioning_started_at > clock_timestamp() - interval '5 minutes'
     and v_application.provisioning_token is distinct from p_provisioning_token then
    raise exception using errcode = '55P03', message = 'O provisionamento desta candidatura já está em andamento.';
  end if;

  update public.recruitment_applications
  set professional_passport = v_passport,
      provisioning_state = 'in_progress',
      provisioning_token = p_provisioning_token,
      provisioning_started_at = clock_timestamp(),
      provisioning_finished_at = null,
      provisioning_attempts = provisioning_attempts + 1,
      provisioning_error_code = null
  where id = v_application.id
  returning * into v_application;

  return jsonb_build_object(
    'application_id', v_application.id,
    'state', v_application.provisioning_state,
    'replayed', false,
    'full_name', btrim(v_application.full_name),
    'professional_passport', v_application.professional_passport,
    'auth_user_id', v_application.provisioning_auth_user_id,
    'attempt', v_application.provisioning_attempts
  );
end;
$$;

create or replace function public.attach_recruitment_provisioning_auth_user(
  p_application_id uuid,
  p_actor_id uuid,
  p_provisioning_token uuid,
  p_auth_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_application public.recruitment_applications;
  v_level integer := coalesce(private.current_position_level(p_actor_id), 0);
begin
  if not private.has_permission(p_actor_id, 'recruitment.manage')
     or v_level not between 11 and 14 then
    raise exception using errcode = '42501', message = 'Você não possui permissão para aprovar candidaturas.';
  end if;
  if p_auth_user_id is null or not exists (select 1 from auth.users where id = p_auth_user_id) then
    raise exception using errcode = 'P0002', message = 'Usuário Auth não localizado.';
  end if;

  select * into v_application
  from public.recruitment_applications
  where id = p_application_id
  for update;

  if not found
     or v_application.provisioning_state <> 'in_progress'
     or v_application.provisioning_token is distinct from p_provisioning_token then
    raise exception using errcode = '40001', message = 'O provisionamento não está mais ativo.';
  end if;
  if v_application.provisioning_auth_user_id is not null
     and v_application.provisioning_auth_user_id <> p_auth_user_id then
    raise exception using errcode = '40001', message = 'A candidatura já possui outro usuário Auth em reconciliação.';
  end if;

  update public.recruitment_applications
  set provisioning_auth_user_id = p_auth_user_id
  where id = p_application_id;

  return jsonb_build_object(
    'application_id', p_application_id,
    'auth_user_id', p_auth_user_id,
    'state', 'in_progress'
  );
end;
$$;

create or replace function public.complete_recruitment_professional_provisioning(
  p_application_id uuid,
  p_actor_id uuid,
  p_provisioning_token uuid,
  p_auth_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_application public.recruitment_applications;
  v_position public.staff_positions;
  v_profile public.profiles;
  v_decision_id bigint;
  v_decided_at timestamptz := clock_timestamp();
  v_actor_passport text;
  v_level integer := coalesce(private.current_position_level(p_actor_id), 0);
begin
  if not private.has_permission(p_actor_id, 'recruitment.manage')
     or v_level not between 11 and 14 then
    raise exception using errcode = '42501', message = 'Você não possui permissão para aprovar candidaturas.';
  end if;

  select * into v_application
  from public.recruitment_applications
  where id = p_application_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Candidatura não encontrada.';
  end if;

  if v_application.provisioning_state = 'completed'
     and v_application.professional_user_id = p_auth_user_id then
    select decision.id into v_decision_id
    from public.recruitment_decisions decision
    where decision.application_id = v_application.id
      and decision.decision = 'approved'
    order by decision.decided_at desc, decision.id desc
    limit 1;
    return jsonb_build_object(
      'application_id', v_application.id,
      'decision_id', v_decision_id,
      'decision', 'approved',
      'decided_by', v_application.reviewed_by,
      'decided_at', v_application.reviewed_at,
      'professional_user_id', v_application.professional_user_id,
      'professional_passport', v_application.professional_passport,
      'professional_name', v_application.full_name,
      'initial_position_id', v_application.initial_position_id,
      'professional_created_at', v_application.professional_created_at,
      'replayed', true
    );
  end if;

  if v_application.status not in ('submitted', 'under_review', 'interview')
     or v_application.provisioning_state <> 'in_progress'
     or v_application.provisioning_token is distinct from p_provisioning_token
     or v_application.provisioning_auth_user_id is distinct from p_auth_user_id then
    raise exception using errcode = '40001', message = 'O provisionamento não está mais ativo.';
  end if;

  select * into v_position
  from public.staff_positions
  where level = 1 and active and official
  for share;

  if not found then
    raise exception using errcode = 'P0002', message = 'O cargo inicial Estagiário de Enfermagem não está disponível.';
  end if;

  insert into public.profiles (
    user_id,
    passport,
    display_name,
    position_id,
    role_code,
    status,
    must_change_password,
    created_by,
    updated_by
  ) values (
    p_auth_user_id,
    v_application.professional_passport,
    btrim(v_application.full_name),
    v_position.id,
    'funcionario',
    'active',
    true,
    p_actor_id,
    p_actor_id
  )
  returning * into v_profile;

  update public.recruitment_applications
  set status = 'approved',
      review_notes = null,
      reviewed_by = p_actor_id,
      reviewed_at = v_decided_at,
      professional_user_id = v_profile.user_id,
      initial_position_id = v_position.id,
      professional_created_at = v_profile.created_at,
      provisioning_state = 'completed',
      provisioning_finished_at = v_decided_at,
      provisioning_error_code = null
  where id = v_application.id;

  insert into public.recruitment_decisions (
    application_id, decision, reason, decided_by, decided_at
  ) values (
    v_application.id, 'approved', null, p_actor_id, v_decided_at
  ) returning id into v_decision_id;

  select profile.passport into v_actor_passport
  from public.profiles profile
  where profile.user_id = p_actor_id;

  insert into public.audit_logs (
    actor_user_id,
    actor_passport,
    action,
    entity_name,
    entity_id,
    old_values,
    new_values
  ) values (
    p_actor_id,
    v_actor_passport,
    'RECRUITMENT_PROFESSIONAL_PROVISIONED',
    'recruitment_applications',
    v_application.id::text,
    null,
    jsonb_build_object(
      'application_id', v_application.id,
      'professional_user_id', v_profile.user_id,
      'professional_passport', v_profile.passport,
      'initial_position_id', v_position.id,
      'origin', 'RECRUITMENT_APPLICATION',
      'provisioning_state', 'completed'
    )
  );

  return jsonb_build_object(
    'application_id', v_application.id,
    'decision_id', v_decision_id,
    'decision', 'approved',
    'reason', null,
    'decided_by', p_actor_id,
    'decided_at', v_decided_at,
    'professional_user_id', v_profile.user_id,
    'professional_passport', v_profile.passport,
    'professional_name', v_profile.display_name,
    'initial_position_id', v_position.id,
    'initial_position_name', v_position.name,
    'professional_created_at', v_profile.created_at,
    'must_change_password', v_profile.must_change_password,
    'replayed', false
  );
end;
$$;

create or replace function public.fail_recruitment_professional_provisioning(
  p_application_id uuid,
  p_actor_id uuid,
  p_provisioning_token uuid,
  p_error_code text,
  p_auth_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_error_code text := lower(btrim(coalesce(p_error_code, '')));
  v_application public.recruitment_applications;
  v_level integer := coalesce(private.current_position_level(p_actor_id), 0);
begin
  if not private.has_permission(p_actor_id, 'recruitment.manage')
     or v_level not between 11 and 14 then
    raise exception using errcode = '42501', message = 'Você não possui permissão para aprovar candidaturas.';
  end if;
  if v_error_code !~ '^[a-z0-9_]{2,80}$' then
    v_error_code := 'provisioning_failed';
  end if;

  select * into v_application
  from public.recruitment_applications
  where id = p_application_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Candidatura não encontrada.';
  end if;
  if v_application.provisioning_state = 'completed' then
    return jsonb_build_object('application_id', v_application.id, 'state', 'completed');
  end if;
  if v_application.provisioning_state <> 'in_progress'
     or v_application.provisioning_token is distinct from p_provisioning_token then
    raise exception using errcode = '40001', message = 'O provisionamento não está mais ativo.';
  end if;
  if v_application.provisioning_auth_user_id is not null
     and p_auth_user_id is not null
     and v_application.provisioning_auth_user_id <> p_auth_user_id then
    raise exception using errcode = '40001', message = 'A candidatura já possui outro usuário Auth em reconciliação.';
  end if;
  if p_auth_user_id is not null
     and not exists (select 1 from auth.users where id = p_auth_user_id) then
    raise exception using errcode = 'P0002', message = 'Usuário Auth não localizado para reconciliação.';
  end if;

  update public.recruitment_applications
  set provisioning_state = 'failed',
      provisioning_auth_user_id = coalesce(provisioning_auth_user_id, p_auth_user_id),
      provisioning_finished_at = clock_timestamp(),
      provisioning_error_code = v_error_code
  where id = v_application.id;

  return jsonb_build_object(
    'application_id', v_application.id,
    'state', 'failed',
    'error_code', v_error_code
  );
end;
$$;

create or replace function public.decide_recruitment_application(
  p_application_id uuid,
  p_decision text,
  p_reason text,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_decided_at timestamptz := clock_timestamp();
  v_reason text;
  v_decision_id bigint;
  v_level integer := coalesce(private.current_position_level(p_actor_id), 0);
begin
  if not private.has_permission(p_actor_id, 'recruitment.manage')
     or v_level not between 11 and 14 then
    raise exception using errcode = '42501', message = 'Apenas os cargos 11 a 14 podem decidir candidaturas.';
  end if;
  if p_decision = 'approved' then
    raise exception using errcode = '22023', message = 'A aprovação exige o provisionamento profissional automático.';
  end if;
  if p_decision <> 'rejected' then
    raise exception using errcode = '22023', message = 'Decisão inválida.';
  end if;

  v_reason := btrim(coalesce(p_reason, ''));
  if char_length(v_reason) not between 10 and 2000 then
    raise exception using errcode = '22023', message = 'Informe um motivo de recusa entre 10 e 2000 caracteres.';
  end if;

  update public.recruitment_applications
  set status = 'rejected',
      review_notes = v_reason,
      reviewed_by = p_actor_id,
      reviewed_at = v_decided_at
  where id = p_application_id
    and status in ('submitted', 'under_review', 'interview')
    and provisioning_state in ('not_started', 'failed');

  if not found then
    raise exception using errcode = 'P0002', message = 'Candidatura não encontrada, já decidida ou em provisionamento.';
  end if;

  insert into public.recruitment_decisions (
    application_id, decision, reason, decided_by, decided_at
  ) values (
    p_application_id, 'rejected', v_reason, p_actor_id, v_decided_at
  ) returning id into v_decision_id;

  return jsonb_build_object(
    'application_id', p_application_id,
    'decision_id', v_decision_id,
    'decision', 'rejected',
    'reason', v_reason,
    'decided_by', p_actor_id,
    'decided_at', v_decided_at
  );
end;
$$;

create or replace function private.provision_professional_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_registration_date date := (new.created_at at time zone 'America/Sao_Paulo')::date;
begin
  if new.must_change_password then
    return new;
  end if;

  insert into public.professional_identities (user_id, crm_code, registration_date)
  values (
    new.user_id,
    private.hpsm_build_internal_crm(new.passport, v_registration_date),
    v_registration_date
  )
  on conflict (user_id) do nothing;

  return new;
end;
$$;

drop trigger if exists profiles_provision_professional_identity on public.profiles;
create trigger profiles_provision_professional_identity
after insert or update of must_change_password on public.profiles
for each row execute function private.provision_professional_identity();

revoke all on function public.begin_recruitment_professional_provisioning(uuid, uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.attach_recruitment_provisioning_auth_user(uuid, uuid, uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.complete_recruitment_professional_provisioning(uuid, uuid, uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.fail_recruitment_professional_provisioning(uuid, uuid, uuid, text, uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.provision_professional_identity()
  from public, anon, authenticated, service_role;

grant execute on function public.begin_recruitment_professional_provisioning(uuid, uuid, uuid)
  to service_role;
grant execute on function public.attach_recruitment_provisioning_auth_user(uuid, uuid, uuid, uuid)
  to service_role;
grant execute on function public.complete_recruitment_professional_provisioning(uuid, uuid, uuid, uuid)
  to service_role;
grant execute on function public.fail_recruitment_professional_provisioning(uuid, uuid, uuid, text, uuid)
  to service_role;

comment on column public.recruitment_applications.professional_user_id is
  'Vínculo imutável da candidatura com o profile criado após uma nova aprovação.';
comment on column public.recruitment_applications.professional_passport is
  'Snapshot canônico de quatro dígitos usado no provisionamento profissional.';
comment on column public.recruitment_applications.provisioning_state is
  'Estado técnico recuperável do provisionamento; não retroage sobre aprovações antigas.';
comment on function public.complete_recruitment_professional_provisioning(uuid, uuid, uuid, uuid) is
  'Finaliza atomicamente profile, cargo inicial, aprovação, vínculo e auditoria após o Auth seguro.';

notify pgrst, 'reload schema';
