begin;

create temporary table optional_patient_phone_context (
  patient_id bigint primary key,
  passport text not null
) on commit drop;

do $$
declare
  v_passport text;
  v_patient_id bigint;
  v_invalid_rejected boolean := false;
begin
  select lpad(candidate::text, 4, '0')
  into v_passport
  from generate_series(0, 9999) candidate
  where not exists (select 1 from public.patients patient where patient.passport = lpad(candidate::text, 4, '0'))
    and not exists (select 1 from public.profiles profile where profile.passport = lpad(candidate::text, 4, '0'))
  order by candidate desc
  limit 1;

  if v_passport is null then
    raise exception 'Não há passaporte disponível para o teste transacional.';
  end if;

  insert into public.patients (passport, name, phone, birth_date)
  values (v_passport, 'Teste telefone opcional', null, date '1990-01-01')
  returning id into v_patient_id;

  insert into optional_patient_phone_context values (v_patient_id, v_passport);

  if (select phone from public.patients where id = v_patient_id) is not null then
    raise exception 'O telefone vazio não foi persistido como NULL.';
  end if;

  update public.patients set phone = '(055) 123-456' where id = v_patient_id;
  if (select phone from public.patients where id = v_patient_id) <> '(055) 123-456' then
    raise exception 'O telefone válido deixou de ser aceito.';
  end if;

  begin
    update public.patients set phone = '123456' where id = v_patient_id;
  exception when check_violation then
    v_invalid_rejected := true;
  end;

  if not v_invalid_rejected then
    raise exception 'O banco aceitou telefone preenchido fora do formato institucional.';
  end if;

  update public.patients set phone = null where id = v_patient_id;
end;
$$;

rollback;

select jsonb_build_object(
  'feature', 'optional_patient_phone',
  'empty_phone_saved_as_null', true,
  'valid_phone_accepted', true,
  'invalid_phone_rejected', true,
  'residue', false
) as result;
