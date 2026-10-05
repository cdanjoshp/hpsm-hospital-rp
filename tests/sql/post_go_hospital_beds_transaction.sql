begin;

do $$
declare
  v_actor uuid;
  v_session uuid;
  v_patient bigint;
  v_other_patient bigint;
  v_bed_one bigint;
  v_bed_two bigint;
  v_hpsm bigint;
  v_external_one bigint;
  v_external_two bigint;
  v_blocked boolean;
begin
  if (select count(*) from public.hospital_beds where active) <> 10 then
    raise exception 'Os dez leitos canônicos não foram configurados.';
  end if;

  select profile.user_id into v_actor
  from public.profiles profile
  join public.staff_positions position on position.id = profile.position_id
  where profile.status = 'active' and not profile.must_change_password
    and position.official and position.level between 11 and 14
    and private.has_permission(profile.user_id, 'hospitalizations.create')
    and private.has_permission(profile.user_id, 'hospitalizations.update')
    and private.has_permission(profile.user_id, 'hospitalizations.discharge')
    and private.has_permission(profile.user_id, 'hospitalizations.history')
  order by position.level desc, profile.created_at limit 1;
  select session.id into v_session from auth.sessions session
  where session.user_id = v_actor and (session.not_after is null or session.not_after > now())
  order by session.created_at desc limit 1;
  select patient.id into v_patient from public.patients patient order by patient.id limit 1;
  select patient.id into v_other_patient from public.patients patient where patient.id <> v_patient order by patient.id limit 1;
  select id into v_bed_one from public.hospital_beds where number = 1;
  select id into v_bed_two from public.hospital_beds where number = 2;
  if v_actor is null or v_session is null or v_patient is null or v_other_patient is null then
    raise exception 'O teste requer gestor com sessão ativa e dois pacientes.';
  end if;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_actor, 'session_id', v_session)::text, true);

  v_hpsm := public.create_hospitalization(v_bed_one, 'hpsm', v_patient, null, null, now() - interval '2 hours', 'Observação hospitalar.', 'Teste transacional.');

  v_blocked := false;
  begin
    perform public.create_hospitalization(v_bed_one, 'hpsm', v_other_patient, null, null, now(), 'Outro registro.', null);
  exception when unique_violation then v_blocked := true;
  end;
  if not v_blocked then raise exception 'A dupla ocupação do leito foi aceita.'; end if;

  v_blocked := false;
  begin
    perform public.create_hospitalization(v_bed_two, 'hpsm', v_patient, null, null, now(), 'Outro registro.', null);
  exception when unique_violation then v_blocked := true;
  end;
  if not v_blocked then raise exception 'O mesmo paciente HPSM ficou ativo em dois leitos.'; end if;

  perform public.discharge_hospitalization(v_hpsm, now());
  if (select status from public.hospitalizations where id = v_hpsm) <> 'discharged' then raise exception 'A alta não foi registrada.'; end if;

  v_external_one := public.create_hospitalization(v_bed_one, 'hp_norte', null, 'Paciente Externo Igual', null, now(), 'Transferência externa.', null);
  v_external_two := public.create_hospitalization(v_bed_two, 'hp_norte', null, 'Paciente Externo Igual', null, now(), 'Transferência externa.', null);
  if v_external_one is null or v_external_two is null then raise exception 'Pacientes externos homônimos foram bloqueados.'; end if;
  if exists (select 1 from public.patients where name = 'Paciente Externo Igual') then raise exception 'A origem externa criou paciente HPSM automaticamente.'; end if;

  perform public.cancel_hospitalization(v_external_one, 'Registro criado somente para teste transacional.');
  if (select status from public.hospitalizations where id = v_external_one) <> 'cancelled' then raise exception 'O cancelamento não liberou o leito.'; end if;
  if not exists (select 1 from public.audit_logs where entity_name = 'hospitalizations' and entity_id = v_hpsm::text and action = 'HOSPITALIZATION_DISCHARGED') then raise exception 'Auditoria da alta ausente.'; end if;
  if not exists (select 1 from public.audit_logs where entity_name = 'hospitalizations' and entity_id = v_external_one::text and action = 'HOSPITALIZATION_CANCELLED') then raise exception 'Auditoria do cancelamento ausente.'; end if;

  if (public.hospital_bed_board()->>'total')::integer <> 10 then raise exception 'O mapa de leitos não retornou dez leitos.'; end if;
  if (public.hospitalization_history_page(null, null, null, null, null, null, 20, 0)->>'total')::integer < 3 then raise exception 'O histórico não preservou as internações do teste.'; end if;
end;
$$;

rollback;
