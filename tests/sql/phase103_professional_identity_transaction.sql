begin;

create temporary table phase103_context as
with candidates as (
  select profile.user_id, profile.passport, session.id as session_id, position.level
  from public.profiles profile
  join public.staff_positions position on position.id = profile.position_id
  join lateral (
    select active_session.id
    from auth.sessions active_session
    where active_session.user_id = profile.user_id
      and (active_session.not_after is null or active_session.not_after > now())
    order by active_session.created_at desc
    limit 1
  ) session on true
  where profile.status = 'active' and not profile.must_change_password
), director as (
  select * from candidates where level = 14 limit 1
), ordinary as (
  select * from candidates where level < 14 order by level limit 1
)
select user_id, passport, session_id, level, 'director'::text as kind from director
union all
select user_id, passport, session_id, level, 'ordinary'::text as kind from ordinary;

do $$ begin
  if (select count(*) from phase103_context) <> 2 then
    raise exception 'A Fase 10.3 requer sessoes ativas do Diretor Geral e de um profissional comum.';
  end if;
  if private.hpsm_build_internal_crm('0532', date '2026-09-14') <> '05321409' then
    raise exception 'CRM 0532/14-09 incorreto.';
  end if;
  if private.hpsm_build_internal_crm('7', date '2026-01-03') <> '00070301' then
    raise exception 'CRM 7/03-01 incorreto.';
  end if;
end $$;

update public.professional_identities
set status = 'pending', signature_image_path = null, rubric_image_path = null,
    signature_file_size = null, rubric_file_size = null, generation_version = 0,
    current_generation_id = null, generation_operation = null, generation_started_at = null,
    signature_generated_at = null, signature_generated_by = null,
    signature_regenerated_at = null, signature_regenerated_by = null,
    signature_regeneration_reason = null, last_failure_code = null, identity_locked = true
where user_id = (select user_id from phase103_context where kind = 'ordinary');

grant select on phase103_context to authenticated;
select set_config('request.jwt.claims', jsonb_build_object('sub', user_id, 'role', 'authenticated', 'session_id', session_id)::text, true)
from phase103_context where kind = 'ordinary';
set local role authenticated;
do $$
declare
  v_target uuid := (select user_id from phase103_context where kind = 'ordinary');
begin
  if not exists (select 1 from public.professional_identities where user_id = v_target) then
    raise exception 'Profissional nao visualizou a propria identidade.';
  end if;
  begin
    update public.professional_identities set crm_code = '99990101' where user_id = v_target;
    raise exception 'Escrita direta na identidade foi aceita.';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.professional_identity_generation_context(v_target, 'regenerate');
    raise exception 'Usuario comum recebeu contexto de regeneracao.';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.correct_professional_identity_crm(v_target, current_date, 'Teste indevido de usuario comum');
    raise exception 'Usuario comum corrigiu CRM.';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

do $$
declare
  v_target uuid := (select user_id from phase103_context where kind = 'ordinary');
  v_generation uuid := gen_random_uuid();
  v_actor uuid := v_target;
  v_result jsonb;
begin
  v_result := public.begin_professional_identity_generation(v_target, v_actor, 'initial', v_generation, null);
  if (v_result ->> 'status') <> 'generating' or (v_result ->> 'replayed')::boolean then
    raise exception 'Geracao inicial nao iniciou.';
  end if;
  perform public.complete_professional_identity_generation(
    v_target, v_actor, v_generation,
    format('professionals/%s/%s/signature.png', v_target, v_generation), 1024,
    format('professionals/%s/%s/rubric.png', v_target, v_generation), 768
  );
  if not exists (select 1 from public.professional_identities where user_id = v_target and status = 'active' and generation_version = 1) then
    raise exception 'Identidade inicial nao ficou ativa.';
  end if;
  if (select count(*) from public.audit_logs where entity_name = 'professional_identities' and entity_id = v_target::text and action in ('IDENTITY_CRM_CREATED','IDENTITY_SIGNATURE_CREATED','IDENTITY_RUBRIC_CREATED')) <> 3 then
    raise exception 'Auditoria inicial incompleta.';
  end if;
end $$;

select set_config('request.jwt.claims', jsonb_build_object('sub', user_id, 'role', 'authenticated', 'session_id', session_id)::text, true)
from phase103_context where kind = 'director';
set local role authenticated;
do $$
declare
  v_target uuid := (select user_id from phase103_context where kind = 'ordinary');
  v_before text := (select crm_code from public.professional_identities where user_id = v_target);
  v_date date := (select registration_date + 1 from public.professional_identities where user_id = v_target);
begin
  perform public.correct_professional_identity_crm(v_target, v_date, 'Correcao transacional da data base');
  if (select crm_code from public.professional_identities where user_id = v_target) = v_before then
    raise exception 'Diretor Geral nao corrigiu o CRM.';
  end if;
  perform public.prepare_professional_identity_regeneration(v_target, 'Padronizacao transacional da assinatura');
end $$;
reset role;

do $$
declare
  v_target uuid := (select user_id from phase103_context where kind = 'ordinary');
  v_actor uuid := (select user_id from phase103_context where kind = 'director');
  v_generation uuid := gen_random_uuid();
  v_crm text := (select crm_code from public.professional_identities where user_id = v_target);
begin
  perform public.begin_professional_identity_generation(v_target, v_actor, 'regenerate', v_generation, 'Padronizacao transacional da assinatura');
  perform public.complete_professional_identity_generation(
    v_target, v_actor, v_generation,
    format('professionals/%s/%s/signature.png', v_target, v_generation), 1100,
    format('professionals/%s/%s/rubric.png', v_target, v_generation), 800
  );
  if (select crm_code from public.professional_identities where user_id = v_target) <> v_crm then
    raise exception 'Regeneracao alterou o CRM.';
  end if;
  if (select count(*) from public.audit_logs where entity_name = 'professional_identities' and entity_id = v_target::text and action in ('IDENTITY_CRM_CORRECTED','IDENTITY_SIGNATURE_REGENERATED','IDENTITY_RUBRIC_REGENERATED')) < 3 then
    raise exception 'Auditoria administrativa incompleta.';
  end if;

  v_generation := gen_random_uuid();
  perform public.begin_professional_identity_generation(v_target, v_actor, 'regenerate', v_generation, 'Simulacao segura de falha da IA');
  perform public.fail_professional_identity_generation(v_target, v_generation, 'simulated_failure');
  if not exists (select 1 from public.professional_identities where user_id = v_target and status = 'active' and last_failure_code = 'simulated_failure') then
    raise exception 'Falha de regeneracao removeu a identidade ativa.';
  end if;
end $$;

do $$ begin
  if not exists (select 1 from storage.buckets where id = 'professional-identities' and not public and file_size_limit = 5242880) then
    raise exception 'Bucket privado da identidade nao foi configurado.';
  end if;
end $$;

rollback;

select jsonb_build_object(
  'phase', '10.3',
  'status', 'ok',
  'crm_examples', true,
  'ordinary_user_blocked', true,
  'director_actions_allowed', true,
  'initial_and_regeneration_audited', true,
  'failure_preserved_active_identity', true,
  'private_storage', true,
  'residue', false
) as result;
