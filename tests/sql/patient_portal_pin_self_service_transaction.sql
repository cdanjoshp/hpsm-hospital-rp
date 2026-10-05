-- Execute após 20260923152912_patient_portal_pin_and_self_service.sql.
-- Valida o fluxo real e sempre encerra com rollback.
begin;

do $validation$
declare
  v_patient public.patients%rowtype;
  v_result jsonb;
  v_profile jsonb;
  v_hash text;
  v_allergies text;
  v_origin text := encode(extensions.digest(gen_random_uuid()::text, 'sha256'), 'hex');
  v_client text := encode(extensions.digest(gen_random_uuid()::text, 'sha256'), 'hex');
  v_token_one text := encode(extensions.digest(gen_random_uuid()::text, 'sha256'), 'hex');
  v_token_two text := encode(extensions.digest(gen_random_uuid()::text, 'sha256'), 'hex');
begin
  select patient.* into strict v_patient
  from public.patients patient
  where not exists (
    select 1 from private.patient_portal_credentials credential
    where credential.patient_id = patient.id
  )
  order by patient.id desc
  limit 1;

  v_allergies := case
    when v_patient.allergies is distinct from 'Não possui - validação'
      then 'Não possui - validação'
    else 'Não possui - validação 2'
  end;

  v_result := public.patient_portal_access_state(v_patient.passport, v_origin, v_client);
  if v_result ->> 'found' <> 'true' or v_result ->> 'has_pin' <> 'false' then
    raise exception 'Falha na descoberta do primeiro acesso.';
  end if;

  v_result := public.patient_portal_create_pin_session(
    v_patient.passport, '4827', '4827', v_token_one, v_origin, v_client
  );
  if v_result ->> 'ok' <> 'true' then raise exception 'Falha na criação do PIN.'; end if;

  select credential.pin_hash into strict v_hash
  from private.patient_portal_credentials credential
  where credential.patient_id = v_patient.id;
  if v_hash = '4827' or v_hash <> extensions.crypt('4827', v_hash) then
    raise exception 'O PIN não foi protegido com bcrypt.';
  end if;

  v_result := public.patient_portal_create_session(
    v_patient.passport, '0000', v_token_two, v_origin, v_client
  );
  if v_result ->> 'code' <> 'invalid_pin' then raise exception 'PIN incorreto foi aceito.'; end if;

  v_token_two := encode(extensions.digest(gen_random_uuid()::text, 'sha256'), 'hex');
  v_result := public.patient_portal_create_session(
    v_patient.passport, '4827', v_token_two, v_origin, v_client
  );
  if v_result ->> 'ok' <> 'true' then raise exception 'PIN correto foi recusado.'; end if;

  v_profile := public.patient_portal_update_profile(
    v_token_two,
    v_patient.name,
    v_patient.phone,
    v_patient.birth_date,
    v_patient.emergency_contact_name,
    v_patient.emergency_contact_phone,
    v_allergies
  );
  if v_profile #>> '{patient,passport}' <> v_patient.passport then
    raise exception 'O passaporte foi alterado pela autogestão.';
  end if;
  if not exists (
    select 1 from public.audit_logs audit
    where audit.action = 'PATIENT_PORTAL_PROFILE_UPDATED'
      and audit.entity_id = v_patient.id::text
      and audit.new_values ->> 'origin' = 'patient_portal'
      and audit.new_values ->> 'allergies' = v_allergies
  ) then
    raise exception 'A atualização cadastral não foi auditada corretamente.';
  end if;

  if not private.partnership_patient_can_use_portal(v_patient.id) then
    raise exception 'Paciente canônico foi bloqueado como responsável.';
  end if;

  if to_regprocedure('public.patient_portal_create_session(text,date,text,text,text)') is not null then
    raise exception 'A assinatura antiga por data de nascimento ainda existe.';
  end if;
  if has_function_privilege('anon', 'public.patient_portal_create_session(text,text,text,text,text)', 'EXECUTE') then
    raise exception 'anon não pode executar a autenticação do Portal.';
  end if;
  if not has_function_privilege('service_role', 'public.patient_portal_create_session(text,text,text,text,text)', 'EXECUTE') then
    raise exception 'service_role precisa executar a autenticação do Portal.';
  end if;
end;
$validation$;

rollback;
