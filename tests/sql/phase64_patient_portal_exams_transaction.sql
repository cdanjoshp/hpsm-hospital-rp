begin;

create temporary table phase64_context (
  key text primary key,
  value text not null
) on commit drop;

do $$
declare
  v_actor public.profiles%rowtype;
  v_document_id uuid := gen_random_uuid();
  v_exam_a bigint;
  v_exam_b bigint;
  v_incomplete bigint;
  v_patient_a bigint;
  v_patient_b bigint;
  v_passport_a text;
  v_passport_b text;
  v_snapshot jsonb;
  v_token_a text := repeat(md5(txid_current()::text || ':a'), 2);
  v_token_b text := repeat(md5(txid_current()::text || ':b'), 2);
  v_token_expired text := repeat(md5(txid_current()::text || ':expired'), 2);
  v_type record;
begin
  select profile.* into v_actor from public.profiles profile order by profile.created_at, profile.user_id limit 1;
  if v_actor.user_id is null then raise exception 'A base não possui profissional para o teste 6.4.'; end if;

  select lpad(candidate::text, 4, '0') into v_passport_a
  from generate_series(1, 9999) candidate
  where not exists (select 1 from public.patients patient where patient.passport = lpad(candidate::text, 4, '0'))
  order by candidate desc limit 1;
  insert into public.patients (passport, name, phone, birth_date)
  values (v_passport_a, 'Paciente Portal Exames A', '(055) 641-001', date '1991-01-01')
  returning id into v_patient_a;

  select lpad(candidate::text, 4, '0') into v_passport_b
  from generate_series(1, 9999) candidate
  where not exists (select 1 from public.patients patient where patient.passport = lpad(candidate::text, 4, '0'))
  order by candidate desc limit 1;
  insert into public.patients (passport, name, phone, birth_date)
  values (v_passport_b, 'Paciente Portal Exames B', '(055) 641-002', date '1992-02-02')
  returning id into v_patient_b;

  for v_type in
    select type.id, type.code, type.name, type.category_id, type.result_config,
      category.code as category_code, category.name as category_name
    from public.exam_types type
    join public.exam_categories category on category.id = type.category_id
    where type.code in (
      'raio_x', 'tomografia', 'ressonancia_magnetica', 'ultrassom',
      'hemograma', 'bioquimica', 'tipagem_sanguinea', 'toxicologia',
      'biopsia', 'citologia', 'eletrocardiograma'
    )
    order by type.id
  loop
    v_snapshot := jsonb_build_object(
      'schema', 'hpsm.exam_report_snapshot.v1',
      'patient', jsonb_build_object('id', v_patient_a, 'name', 'Paciente Portal Exames A', 'passport', v_passport_a),
      'exam', jsonb_build_object(
        'id', v_type.id, 'code', v_type.code, 'name', v_type.name,
        'category_id', v_type.category_id, 'category_code', v_type.category_code,
        'category_name', v_type.category_name, 'result_config', coalesce(v_type.result_config, '{}'::jsonb)
      ),
      'indication', 'Validação final do Portal para ' || v_type.name || '.',
      'clinical_context', 'Contexto clínico aprovado.',
      'content', jsonb_build_object(
        'technique', 'Técnica validada.', 'findings', 'Achados finais aprovados.',
        'conclusion', 'Exame concluído.', 'observations', 'Acompanhamento conforme evolução.',
        'result_data', jsonb_build_object('schema', 'phase64.generic.v1', 'notes', 'Resultado representativo.')
      ),
      'report_config', jsonb_build_object(
        'schema', 'hpsm.report_config.v1',
        'fields', jsonb_build_object(
          'technique', jsonb_build_object('label', 'Técnica / Método', 'required', false, 'visible', true),
          'findings', jsonb_build_object('label', 'Achados', 'required', true, 'visible', true),
          'conclusion', jsonb_build_object('label', 'Conclusão', 'required', true, 'visible', true),
          'observations', jsonb_build_object('label', 'Conduta', 'required', false, 'visible', true)
        )
      ),
      'requested_by', jsonb_build_object('id', v_actor.user_id, 'name', v_actor.display_name, 'position', null),
      'executed_by', jsonb_build_object('id', v_actor.user_id, 'name', v_actor.display_name, 'position', null),
      'reviewed_by', jsonb_build_object('id', v_actor.user_id, 'name', v_actor.display_name, 'position', null),
      'dates', jsonb_build_object(
        'requested_at', clock_timestamp() - interval '3 hours',
        'started_at', clock_timestamp() - interval '2 hours',
        'submitted_for_review_at', clock_timestamp() - interval '1 hour',
        'completed_at', clock_timestamp()
      ),
      'images', '[]'::jsonb
    );

    insert into public.clinical_exams (
      patient_id, exam_type_id, status, requested_by, responsible_professional_id, indication,
      requested_at, started_at, submitted_for_review_at, completed_at, reviewed_by,
      technique, findings, conclusion, result_data, final_report_snapshot
    ) values (
      v_patient_a, v_type.id, 'completed', v_actor.user_id, v_actor.user_id,
      'Validação final do Portal para ' || v_type.name || '.',
      clock_timestamp() - interval '3 hours', clock_timestamp() - interval '2 hours',
      clock_timestamp() - interval '1 hour', clock_timestamp(), v_actor.user_id,
      'Técnica validada.', 'Achados finais aprovados.', 'Exame concluído.',
      jsonb_build_object('schema', 'phase64.generic.v1', 'notes', 'Resultado representativo.'), v_snapshot
    ) returning id into v_exam_a;
  end loop;

  if (select count(*) from public.clinical_exams where patient_id = v_patient_a and status = 'completed') <> 11 then
    raise exception 'Os 11 tipos finais não foram preparados para o Portal.';
  end if;

  select type.id into v_type from public.exam_types type order by type.id limit 1;
  insert into public.clinical_exams (
    patient_id, exam_type_id, status, requested_by, responsible_professional_id,
    indication, technique, findings, conclusion, result_data, requested_at, started_at
  ) values (
    v_patient_a, v_type.id, 'in_progress', v_actor.user_id, v_actor.user_id,
    'Exame em andamento.', 'RASCUNHO PROIBIDO', 'RASCUNHO PROIBIDO', 'RASCUNHO PROIBIDO',
    jsonb_build_object('draft', 'RASCUNHO PROIBIDO'), clock_timestamp() + interval '1 minute', clock_timestamp() + interval '1 minute'
  ) returning id into v_incomplete;

  select type.id, type.code, type.name, type.category_id, type.result_config,
    category.code as category_code, category.name as category_name
  into v_type
  from public.exam_types type join public.exam_categories category on category.id = type.category_id
  order by type.id limit 1;
  v_snapshot := jsonb_set(v_snapshot, '{patient}', jsonb_build_object(
    'id', v_patient_b, 'name', 'Paciente Portal Exames B', 'passport', v_passport_b
  ));
  insert into public.clinical_exams (
    patient_id, exam_type_id, status, requested_by, responsible_professional_id, indication,
    requested_at, started_at, submitted_for_review_at, completed_at, reviewed_by,
    technique, findings, conclusion, result_data, final_report_snapshot
  ) values (
    v_patient_b, v_type.id, 'completed', v_actor.user_id, v_actor.user_id, 'Exame privado B.',
    clock_timestamp() - interval '3 hours', clock_timestamp() - interval '2 hours',
    clock_timestamp() - interval '1 hour', clock_timestamp(), v_actor.user_id,
    'Técnica B.', 'Achados B.', 'Conclusão B.', '{}'::jsonb, v_snapshot
  ) returning id into v_exam_b;

  insert into public.patient_portal_sessions (patient_id, token_hash, created_at, expires_at)
  values
    (v_patient_a, v_token_a, clock_timestamp(), clock_timestamp() + interval '1 hour'),
    (v_patient_b, v_token_b, clock_timestamp(), clock_timestamp() + interval '1 hour'),
    (v_patient_a, v_token_expired, clock_timestamp() - interval '2 hours', clock_timestamp() - interval '1 hour');

  insert into public.clinical_exam_documents (
    id, exam_id, storage_path, mime_type, file_size, pixel_width, pixel_height,
    render_version, created_by, created_by_patient_id
  ) values (
    v_document_id, v_exam_a,
    'clinical-exams/' || v_exam_a || '/documents/' || v_document_id || '.png',
    'image/png', 128, 1200, 800, 'exam-document-png-v2', null, v_patient_a
  );

  insert into phase64_context values
    ('exam_a', v_exam_a::text), ('exam_b', v_exam_b::text), ('incomplete', v_incomplete::text),
    ('patient_a', v_patient_a::text), ('token_a', v_token_a), ('token_b', v_token_b),
    ('token_expired', v_token_expired);
end;
$$;

grant select on phase64_context to service_role;
set local role service_role;

do $$
declare
  v_exam_a bigint := (select value::bigint from phase64_context where key = 'exam_a');
  v_exam_b bigint := (select value::bigint from phase64_context where key = 'exam_b');
  v_incomplete bigint := (select value::bigint from phase64_context where key = 'incomplete');
  v_patient_a bigint := (select value::bigint from phase64_context where key = 'patient_a');
  v_token_a text := (select value from phase64_context where key = 'token_a');
  v_token_b text := (select value from phase64_context where key = 'token_b');
  v_token_expired text := (select value from phase64_context where key = 'token_expired');
  v_all jsonb;
  v_completed jsonb;
  v_detail jsonb;
  v_incomplete_detail jsonb;
  v_share jsonb;
begin
  v_all := public.patient_portal_exam_page(v_token_a, null, null, 'all', 15);
  v_completed := public.patient_portal_exam_page(v_token_a, null, null, 'completed', 15);
  if jsonb_array_length(v_all -> 'items') <> 12 or jsonb_array_length(v_completed -> 'items') <> 11 then
    raise exception 'Listagem não preservou os 11 tipos e o exame em andamento: %, %', v_all, v_completed;
  end if;
  if v_all #>> '{items,0,status}' <> 'in_progress' then
    raise exception 'Listagem não está ordenada do mais recente para o mais antigo.';
  end if;

  v_detail := public.patient_portal_exam_detail(v_token_a, v_exam_a);
  if not coalesce((v_detail ->> 'found')::boolean, false)
     or v_detail #>> '{final_report_snapshot,schema}' <> 'hpsm.exam_report_snapshot.v1' then
    raise exception 'Detalhe concluído não entregou o snapshot final aprovado.';
  end if;

  v_incomplete_detail := public.patient_portal_exam_detail(v_token_a, v_incomplete);
  if v_incomplete_detail -> 'final_report_snapshot' <> 'null'::jsonb
     or jsonb_array_length(v_incomplete_detail -> 'images') <> 0
     or v_incomplete_detail::text like '%RASCUNHO PROIBIDO%' then
    raise exception 'Detalhe em andamento vazou rascunho clínico: %', v_incomplete_detail;
  end if;

  if coalesce((public.patient_portal_exam_detail(v_token_a, v_exam_b) ->> 'found')::boolean, true)
     or coalesce((public.patient_portal_exam_detail(v_token_b, v_exam_a) ->> 'found')::boolean, true)
     or coalesce((public.patient_portal_exam_document_state(v_token_b, v_exam_a) ->> 'found')::boolean, true)
     or coalesce((public.patient_portal_register_clinical_exam_document(
       v_token_b, v_exam_a, gen_random_uuid(), 'clinical-exams/' || v_exam_a || '/documents/' || gen_random_uuid() || '.png',
       128, 1200, 800, 'exam-document-png-v2'
     ) ->> 'found')::boolean, true)
     or coalesce((public.patient_portal_create_clinical_exam_document_share(v_token_b, v_exam_a) ->> 'found')::boolean, true) then
    raise exception 'Paciente B conseguiu localizar/preparar/compartilhar exame do Paciente A.';
  end if;

  v_share := public.patient_portal_create_clinical_exam_document_share(v_token_a, v_exam_a);
  if v_share #>> '{state,share,id}' is null then raise exception 'Paciente A não criou/reutilizou o share canônico.'; end if;
  if not exists (
    select 1 from public.clinical_exam_document_shares share
    where share.id = (v_share #>> '{state,share,id}')::uuid
      and share.created_by is null
      and share.created_by_patient_id = v_patient_a
  ) then raise exception 'Share do paciente perdeu sua atribuição explícita.'; end if;

  if coalesce((public.patient_portal_exam_page(v_token_expired) ->> 'authenticated')::boolean, true)
     or coalesce((public.patient_portal_exam_detail(v_token_expired, v_exam_a) ->> 'authenticated')::boolean, true)
     or coalesce((public.patient_portal_exam_page(repeat('0', 64)) ->> 'authenticated')::boolean, true) then
    raise exception 'Sessão expirada/inexistente permaneceu autorizada.';
  end if;
end;
$$;

reset role;

do $$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'public.patient_portal_exam_page(text,timestamp with time zone,bigint,text,integer)',
    'public.patient_portal_exam_detail(text,bigint)',
    'public.patient_portal_exam_image(text,bigint,uuid)',
    'public.patient_portal_exam_document_state(text,bigint)',
    'public.patient_portal_register_clinical_exam_document(text,bigint,uuid,text,bigint,integer,integer,text)',
    'public.patient_portal_create_clinical_exam_document_share(text,bigint)'
  ] loop
    if has_function_privilege('anon', v_signature, 'EXECUTE')
       or has_function_privilege('authenticated', v_signature, 'EXECUTE') then
      raise exception 'RPC % foi exposta ao cliente público.', v_signature;
    end if;
    if not has_function_privilege('service_role', v_signature, 'EXECUTE') then
      raise exception 'Backend perdeu execução da RPC %.', v_signature;
    end if;
  end loop;
end;
$$;

rollback;

select jsonb_build_object(
  'phase', '6.4', 'status', 'ok', 'exam_types', 11, 'draft_hidden', true,
  'patient_a_to_b_isolated', true, 'service_only', true, 'residue', false
) as result;
