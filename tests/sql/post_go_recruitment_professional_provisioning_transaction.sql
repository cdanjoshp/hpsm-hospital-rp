begin;

create temporary table recruitment_provisioning_context as
with candidates as (
  select candidate,
         candidate::text as raw_passport,
         lpad(candidate::text, 4, '0') as canonical_passport
  from generate_series(100, 999) candidate
  where not exists (
    select 1 from public.profiles profile
    where lpad(profile.passport, 4, '0') = lpad(candidate::text, 4, '0')
  )
  and not exists (
    select 1 from public.recruitment_applications application
    where application.passport in (candidate::text, lpad(candidate::text, 4, '0'))
  )
  order by candidate
  limit 3
), numbered as (
  select *, row_number() over (order by candidate) as position
  from candidates
)
select
  (
    select profile.user_id
    from public.profiles profile
    join public.staff_positions staff_position on staff_position.id = profile.position_id
    where profile.status = 'active'
      and not profile.must_change_password
      and staff_position.level between 11 and 14
      and private.has_permission(profile.user_id, 'recruitment.manage')
    order by staff_position.level desc, profile.created_at
    limit 1
  ) as actor_id,
  (
    select profile.user_id
    from public.profiles profile
    where profile.status = 'active'
      and not profile.must_change_password
      and not private.has_permission(profile.user_id, 'recruitment.manage')
    order by profile.created_at
    limit 1
  ) as unauthorized_actor_id,
  (select raw_passport from numbered where position = 1) as raw_passport,
  (select canonical_passport from numbered where position = 1) as canonical_passport,
  (select raw_passport from numbered where position = 2) as rejected_passport,
  (select raw_passport from numbered where position = 3) as retry_passport,
  gen_random_uuid() as auth_user_id,
  gen_random_uuid() as application_id,
  gen_random_uuid() as duplicate_application_id,
  gen_random_uuid() as rejected_application_id,
  gen_random_uuid() as retry_application_id,
  gen_random_uuid() as provisioning_token,
  gen_random_uuid() as retry_token_one,
  gen_random_uuid() as retry_token_two,
  (
    select count(*)
    from public.recruitment_applications
    where status = 'approved'
      and professional_user_id is null
      and provisioning_state = 'not_started'
  ) as legacy_approved_count;

do $$
begin
  if not exists (
    select 1
    from recruitment_provisioning_context
    where actor_id is not null
      and raw_passport is not null
      and rejected_passport is not null
      and retry_passport is not null
  ) then
    raise exception 'A regressão requer Diretor autorizado e três passaportes livres.';
  end if;
end;
$$;

insert into public.recruitment_applications (
  id, full_name, passport, birth_day, birth_month, city_phone, discord_id,
  availability, prior_experience, experience_summary, interest_area,
  motivation, external_calls
)
select
  application_id,
  'Profissional Automático de Teste',
  raw_passport,
  1,
  1,
  '(055) 000-000',
  '90000000000000' || raw_passport,
  array['morning']::text[],
  false,
  null,
  'nursing',
  'Motivação de teste suficientemente longa para validar o provisionamento automático.',
  'partial'
from recruitment_provisioning_context;

do $$
declare
  v_context recruitment_provisioning_context%rowtype;
  v_started jsonb;
  v_completed jsonb;
begin
  select * into v_context from recruitment_provisioning_context;

  v_started := public.begin_recruitment_professional_provisioning(
    v_context.application_id,
    v_context.actor_id,
    v_context.provisioning_token
  );

  if v_started ->> 'state' <> 'in_progress'
     or v_started ->> 'professional_passport' <> v_context.canonical_passport then
    raise exception '503 não foi normalizado para passaporte profissional de quatro dígitos.';
  end if;

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) values (
    '00000000-0000-0000-0000-000000000000',
    v_context.auth_user_id,
    'authenticated',
    'authenticated',
    'recruitment-' || v_context.auth_user_id::text || '@test.invalid',
    '',
    clock_timestamp(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object(
      'passport', v_context.canonical_passport,
      'origin', 'RECRUITMENT_APPLICATION',
      'recruitment_application_id', v_context.application_id
    ),
    clock_timestamp(),
    clock_timestamp()
  );

  perform public.attach_recruitment_provisioning_auth_user(
    v_context.application_id,
    v_context.actor_id,
    v_context.provisioning_token,
    v_context.auth_user_id
  );

  v_completed := public.complete_recruitment_professional_provisioning(
    v_context.application_id,
    v_context.actor_id,
    v_context.provisioning_token,
    v_context.auth_user_id
  );

  if v_completed ->> 'decision' <> 'approved'
     or v_completed ->> 'professional_user_id' <> v_context.auth_user_id::text
     or v_completed ->> 'professional_passport' <> v_context.canonical_passport
     or not (v_completed ->> 'must_change_password')::boolean then
    raise exception 'A aprovação não concluiu Auth/profile/vínculo/primeiro acesso.';
  end if;

  if not exists (
    select 1
    from public.profiles profile
    join public.staff_positions staff_position on staff_position.id = profile.position_id
    where profile.user_id = v_context.auth_user_id
      and profile.passport = v_context.canonical_passport
      and profile.display_name = 'Profissional Automático de Teste'
      and profile.status = 'active'
      and profile.must_change_password
      and staff_position.level = 1
      and staff_position.name = 'Estagiário de Enfermagem'
  ) then
    raise exception 'Profile não recebeu o cargo inicial canônico.';
  end if;

  if exists (
    select 1 from public.professional_identities
    where user_id = v_context.auth_user_id
  ) then
    raise exception 'CRM/identidade foi criado antes da conclusão do primeiro acesso.';
  end if;

  perform public.complete_recruitment_professional_provisioning(
    v_context.application_id,
    v_context.actor_id,
    v_context.provisioning_token,
    v_context.auth_user_id
  );
  perform public.begin_recruitment_professional_provisioning(
    v_context.application_id,
    v_context.actor_id,
    gen_random_uuid()
  );

  if (select count(*) from public.profiles where user_id = v_context.auth_user_id) <> 1
     or (select count(*) from public.recruitment_decisions where application_id = v_context.application_id and decision = 'approved') <> 1 then
    raise exception 'Retry criou profile ou decisão duplicada.';
  end if;

  update public.profiles
  set must_change_password = false,
      updated_by = v_context.auth_user_id
  where user_id = v_context.auth_user_id;

  if (select count(*) from public.professional_identities where user_id = v_context.auth_user_id) <> 1 then
    raise exception 'Primeiro acesso não iniciou a identidade profissional idempotente.';
  end if;

  if not exists (
    select 1
    from public.audit_logs audit
    where audit.action = 'RECRUITMENT_PROFESSIONAL_PROVISIONED'
      and audit.entity_id = v_context.application_id::text
      and audit.new_values ->> 'professional_user_id' = v_context.auth_user_id::text
      and audit.new_values ->> 'origin' = 'RECRUITMENT_APPLICATION'
      and audit.new_values::text !~* 'password|senha'
  ) then
    raise exception 'Auditoria sem senha não registrou o provisionamento.';
  end if;
end;
$$;

insert into public.recruitment_applications (
  id, full_name, passport, birth_day, birth_month, city_phone, discord_id,
  availability, prior_experience, interest_area, motivation, external_calls
)
select
  duplicate_application_id,
  'Duplicidade Canônica de Teste',
  canonical_passport,
  2,
  2,
  '(055) 000-001',
  '91000000000000' || raw_passport,
  array['afternoon']::text[],
  false,
  'nursing',
  'Motivação de teste suficientemente longa para validar o bloqueio de duplicidade.',
  'partial'
from recruitment_provisioning_context;

do $$
declare
  v_context recruitment_provisioning_context%rowtype;
begin
  select * into v_context from recruitment_provisioning_context;
  begin
    perform public.begin_recruitment_professional_provisioning(
      v_context.duplicate_application_id,
      v_context.actor_id,
      gen_random_uuid()
    );
    raise exception 'Passaporte canônico duplicado foi aceito.';
  exception
    when unique_violation then null;
  end;
end;
$$;

insert into public.recruitment_applications (
  id, full_name, passport, birth_day, birth_month, city_phone, discord_id,
  availability, prior_experience, interest_area, motivation, external_calls
)
select
  rejected_application_id,
  'Recusa Sem Conta de Teste',
  rejected_passport,
  3,
  3,
  '(055) 000-002',
  '92000000000000' || rejected_passport,
  array['evening']::text[],
  false,
  'nursing',
  'Motivação de teste suficientemente longa para confirmar que a recusa não cria conta.',
  'unavailable'
from recruitment_provisioning_context;

do $$
declare
  v_context recruitment_provisioning_context%rowtype;
begin
  select * into v_context from recruitment_provisioning_context;
  perform public.decide_recruitment_application(
    v_context.rejected_application_id,
    'rejected',
    'Recusa de regressão sem criação de conta profissional.',
    v_context.actor_id
  );

  if exists (
    select 1 from public.profiles
    where lpad(passport, 4, '0') = lpad(v_context.rejected_passport, 4, '0')
  ) then
    raise exception 'Recusa criou profissional indevidamente.';
  end if;
end;
$$;

insert into public.recruitment_applications (
  id, full_name, passport, birth_day, birth_month, city_phone, discord_id,
  availability, prior_experience, interest_area, motivation, external_calls
)
select
  retry_application_id,
  'Retry Recuperável de Teste',
  retry_passport,
  4,
  4,
  '(055) 000-003',
  '93000000000000' || retry_passport,
  array['overnight']::text[],
  false,
  'nursing',
  'Motivação de teste suficientemente longa para confirmar o retry recuperável.',
  'full'
from recruitment_provisioning_context;

do $$
declare
  v_context recruitment_provisioning_context%rowtype;
begin
  select * into v_context from recruitment_provisioning_context;

  perform public.begin_recruitment_professional_provisioning(
    v_context.retry_application_id,
    v_context.actor_id,
    v_context.retry_token_one
  );
  perform public.fail_recruitment_professional_provisioning(
    v_context.retry_application_id,
    v_context.actor_id,
    v_context.retry_token_one,
    'auth_unavailable',
    null
  );
  perform public.begin_recruitment_professional_provisioning(
    v_context.retry_application_id,
    v_context.actor_id,
    v_context.retry_token_two
  );

  if not exists (
    select 1 from public.recruitment_applications
    where id = v_context.retry_application_id
      and status = 'submitted'
      and provisioning_state = 'in_progress'
      and provisioning_attempts = 2
      and provisioning_token = v_context.retry_token_two
  ) then
    raise exception 'Falha parcial não ficou disponível para retry idempotente.';
  end if;

  if v_context.unauthorized_actor_id is not null then
    begin
      perform public.begin_recruitment_professional_provisioning(
        v_context.retry_application_id,
        v_context.unauthorized_actor_id,
        gen_random_uuid()
      );
      raise exception 'Usuário sem permissão iniciou provisionamento.';
    exception
      when insufficient_privilege then null;
    end;
  end if;

  if (
    select count(*)
    from public.recruitment_applications
    where status = 'approved'
      and professional_user_id is null
      and provisioning_state = 'not_started'
  ) <> v_context.legacy_approved_count then
    raise exception 'Aprovações antigas foram alteradas retroativamente.';
  end if;
end;
$$;

rollback;

select jsonb_build_object(
  'status', 'ok',
  'approval_profile_link', true,
  'passport_503_to_0503', true,
  'duplicate_guard', true,
  'retry_idempotent', true,
  'rejection_isolated', true,
  'identity_after_first_access', true,
  'legacy_approvals_preserved', true,
  'residue', false
) as result;
