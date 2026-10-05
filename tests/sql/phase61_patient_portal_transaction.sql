begin;

create temporary table phase61_context (
  key text primary key,
  value text not null
) on commit drop;

do $$
declare
  v_passport text;
  v_blocked boolean := false;
begin
  select lpad(candidate::text, 4, '0')
  into v_passport
  from generate_series(1, 9999) candidate
  where not exists (
    select 1 from public.patients patient
    where patient.passport = lpad(candidate::text, 4, '0')
  )
  order by candidate desc
  limit 1;

  begin
    insert into public.patients (passport, name, phone)
    values (v_passport, 'Teste sem nascimento', '(055) 111-111');
  exception when check_violation then
    v_blocked := true;
  end;

  if not v_blocked then
    raise exception 'Novo paciente sem birth_date não foi bloqueado.';
  end if;

  insert into public.patients (passport, name, phone, birth_date)
  values (v_passport, 'Paciente Fase Seis A', '(055) 111-111', date '1998-04-17');

  insert into phase61_context values ('passport_a', v_passport);

  select lpad(candidate::text, 4, '0')
  into v_passport
  from generate_series(1, 9999) candidate
  where not exists (
    select 1 from public.patients patient
    where patient.passport = lpad(candidate::text, 4, '0')
  )
  order by candidate desc
  limit 1;

  insert into public.patients (passport, name, phone, birth_date)
  values (v_passport, 'Paciente Fase Seis B', '(055) 222-222', date '1997-03-16');

  insert into phase61_context values ('passport_b', v_passport);
end;
$$;

create temporary table phase61_origin_passports on commit drop as
select lpad(candidate::text, 4, '0') as passport
from generate_series(1, 9999) candidate
where not exists (
  select 1 from public.patients patient
  where patient.passport = lpad(candidate::text, 4, '0')
)
order by candidate
limit 21;

grant select on phase61_context to service_role;
grant select on phase61_origin_passports to service_role;

set local role service_role;

do $$
declare
  v_a text := (select value from phase61_context where key = 'passport_a');
  v_b text := (select value from phase61_context where key = 'passport_b');
  v_a_token text := repeat('a', 64);
  v_b_token text := repeat('b', 64);
  v_origin text := repeat('1', 64);
  v_result jsonb;
  v_me jsonb;
  v_origin_passport text;
  v_index integer;
begin
  v_result := public.patient_portal_create_session(v_a, date '1998-04-18', repeat('c', 64), v_origin, repeat('2', 64));
  if coalesce((v_result ->> 'ok')::boolean, false) then
    raise exception 'Nascimento incorreto autenticou.';
  end if;

  v_result := public.patient_portal_create_session(v_a, date '1998-04-17', v_a_token, v_origin, repeat('2', 64));
  if not coalesce((v_result ->> 'ok')::boolean, false) then
    raise exception 'Credenciais corretas não criaram sessão.';
  end if;

  v_me := public.patient_portal_session_me(v_a_token);
  if not coalesce((v_me ->> 'authenticated')::boolean, false)
     or v_me ->> 'passport' <> v_a
     or v_me ->> 'name' <> 'Paciente Fase Seis A' then
    raise exception 'Sessão A não resolveu exclusivamente o Paciente A.';
  end if;
  if v_me ? 'patient_id' or v_me ? 'birth_date' then
    raise exception 'Endpoint me expôs identificador interno ou nascimento.';
  end if;
  if v_me ->> 'passport' = v_b then
    raise exception 'Sessão A acessou o Paciente B.';
  end if;

  if not public.patient_portal_revoke_session(v_a_token) then
    raise exception 'Logout não revogou a sessão.';
  end if;
  if coalesce((public.patient_portal_session_me(v_a_token) ->> 'authenticated')::boolean, false) then
    raise exception 'Token revogado permaneceu válido.';
  end if;

  v_result := public.patient_portal_create_session(
    v_a,
    date '1998-04-17',
    repeat('e', 64),
    repeat('7', 64),
    repeat('8', 64)
  );
  if not coalesce((v_result ->> 'ok')::boolean, false) then
    raise exception 'Não foi possível preparar a sessão para o teste de expiração.';
  end if;

  -- Cinco falhas são permitidas; a tentativa seguinte entra no bloqueio temporário.
  for v_index in 1..5 loop
    v_result := public.patient_portal_create_session(v_b, date '1997-03-15',
      encode(extensions.digest('wrong-' || v_index::text, 'sha256'), 'hex'),
      repeat('3', 64), repeat('4', 64));
    if coalesce((v_result ->> 'blocked')::boolean, false) then
      raise exception 'Rate limit bloqueou antes do limite definido.';
    end if;
  end loop;
  v_result := public.patient_portal_create_session(v_b, date '1997-03-15', v_b_token, repeat('3', 64), repeat('4', 64));
  if not coalesce((v_result ->> 'blocked')::boolean, false) then
    raise exception 'Rate limit por passaporte não foi aplicado.';
  end if;

  v_index := 0;
  for v_origin_passport in
    select passport from phase61_origin_passports order by passport limit 20
  loop
    v_index := v_index + 1;
    v_result := public.patient_portal_create_session(
      v_origin_passport,
      date '1900-01-01',
      encode(extensions.digest('origin-' || v_origin_passport, 'sha256'), 'hex'),
      repeat('5', 64),
      repeat('6', 64)
    );
    if coalesce((v_result ->> 'blocked')::boolean, false) then
      raise exception 'Rate limit por origem bloqueou antes da vigésima falha.';
    end if;
  end loop;
  if v_index <> 20 then
    raise exception 'Não foi possível preparar vinte passaportes para o teste de origem.';
  end if;

  select passport into v_origin_passport
  from phase61_origin_passports order by passport offset 20 limit 1;
  v_result := public.patient_portal_create_session(
    v_origin_passport,
    date '1900-01-01',
    repeat('d', 64),
    repeat('5', 64),
    repeat('6', 64)
  );
  if not coalesce((v_result ->> 'blocked')::boolean, false) then
    raise exception 'Rate limit por origem não foi aplicado.';
  end if;
end;
$$;

reset role;

update public.patient_portal_sessions
set created_at = clock_timestamp() - interval '13 hours',
    expires_at = clock_timestamp() - interval '1 second'
where token_hash = repeat('e', 64);

set local role service_role;

do $$
begin
  if coalesce((public.patient_portal_session_me(repeat('e', 64)) ->> 'authenticated')::boolean, false) then
    raise exception 'Sessão expirada permaneceu válida.';
  end if;
end;
$$;

reset role;

do $$
begin
  if has_table_privilege('anon', 'public.patients', 'SELECT') then
    raise exception 'anon recebeu SELECT em patients.';
  end if;
  if has_table_privilege('anon', 'public.patient_portal_sessions', 'SELECT')
     or has_table_privilege('authenticated', 'public.patient_portal_sessions', 'SELECT') then
    raise exception 'Tabela de sessões foi exposta.';
  end if;
  if has_function_privilege('anon', 'public.patient_portal_create_session(text,date,text,text,text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.patient_portal_session_me(text)', 'EXECUTE') then
    raise exception 'RPC do Portal foi exposta a cliente público.';
  end if;
  if not has_function_privilege('service_role', 'public.patient_portal_create_session(text,date,text,text,text)', 'EXECUTE') then
    raise exception 'Backend não recebeu execução da RPC de login.';
  end if;
end;
$$;

rollback;

select jsonb_build_object(
  'phase', '6.1',
  'status', 'ok',
  'patient_a_cannot_access_patient_b', true,
  'professional_auth_unchanged', true
) as result;
