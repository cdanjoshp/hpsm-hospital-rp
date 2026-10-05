do $$
declare
  v_actor uuid := '68808ed5-94e3-44e3-a8a1-483de268202f';
  v_authority uuid := '56d67f62-d37d-464c-9191-0d8a22134bf7';
  v_patient bigint;
  v_exam bigint;
  v_generic_exam bigint;
  v_image_exam bigint;
  v_generation uuid;
  v_image_generation uuid;
  v_report_generation uuid;
  v_image_id uuid;
  v_payload jsonb;
  v_parameters jsonb;
  v_status text;
  v_session uuid;
  v_rejected boolean := false;
begin
  select min(id) into v_patient from public.patients;
  if v_patient is null then raise exception 'Teste requer um paciente existente.'; end if;

  insert into public.clinical_exams (
    patient_id, exam_type_id, status, requested_by, responsible_professional_id,
    indication, result_data, started_at
  ) values (
    v_patient, 5, 'in_progress', v_actor, v_actor,
    'Hemograma com anemia leve para o RP.', private.build_lab_result(5), now()
  ) returning id into v_exam;

  select jsonb_agg(jsonb_build_object(
    'key', parameter->>'key',
    'value', case when parameter->>'field_type' = 'select' then parameter#>>'{options,0}' else '10' end,
    'flag', 'normal'
  ) order by (parameter->>'sort_order')::integer)
  into v_parameters
  from jsonb_array_elements((select result_data#>'{template_snapshot,parameters}' from public.clinical_exams where id = v_exam)) parameter
  where (parameter->>'active')::boolean;

  v_payload := jsonb_build_object(
    'schema', 'hpsm.ai.exam_bundle.v4',
    'parameters', v_parameters,
    'report', jsonb_build_object(
      'technique', 'Análise laboratorial automatizada.',
      'findings', jsonb_build_array('Anemia leve com demais parâmetros estáveis.'),
      'conclusion', 'Hemograma compatível com anemia leve.',
      'conduct', 'Correlação clínica e acompanhamento conforme evolução.'
    )
  );
  begin
    perform private.validate_exam_ai_suggestion(
      v_exam,
      'generate_exam',
      jsonb_set(v_payload, '{report,conduct}', to_jsonb('Acompanhamento clínico no RP.'::text))
    );
  exception when others then
    v_rejected := true;
  end;
  if not v_rejected then raise exception 'Validação aceitou metalinguagem no laudo.'; end if;
  v_rejected := false;
  begin
    perform private.validate_exam_ai_suggestion(
      v_exam,
      'generate_exam',
      jsonb_set(v_payload, '{parameters}', (v_payload->'parameters') || jsonb_build_array(jsonb_build_object('key', 'extra', 'value', '1', 'flag', 'normal')))
    );
  exception when others then
    v_rejected := true;
  end;
  if not v_rejected then raise exception 'Template laboratorial aceitou parâmetro extra.'; end if;
  insert into public.exam_ai_generations (
    exam_id, generation_type, status, requested_by, model, reasoning_effort, prompt_version,
    source_exam_updated_at, openai_response_id, input_tokens, output_tokens, total_tokens,
    suggestion_payload, idempotency_key, completed_at
  ) select id, 'generate_exam', 'completed', v_actor, 'gpt-5.6-luna', 'low', 'exam-rp-luna-v4',
    updated_at, 'resp_test_lab', 1, 1, 2, v_payload, gen_random_uuid(), now()
  from public.clinical_exams where id = v_exam returning id into v_generation;
  if (select prompt_version from public.exam_ai_generations where id = v_generation) <> 'exam-clinical-exam-v6' then raise exception 'Versão clínica do prompt completo não foi aplicada.'; end if;

  perform public.apply_and_submit_clinical_exam_ai_generation(v_generation, v_actor);
  select status into v_status from public.clinical_exams where id = v_exam;
  if v_status <> 'awaiting_review' then raise exception 'Exame laboratorial não foi enviado à revisão.'; end if;
  if not exists (select 1 from public.clinical_exam_report_versions where exam_id = v_exam and decision = 'pending') then raise exception 'Versão de revisão não foi criada.'; end if;
  if exists (select 1 from jsonb_array_elements((select result_data->'parameters' from public.clinical_exams where id = v_exam)) item where nullif(item->>'value', '') is null) then raise exception 'Parâmetro laboratorial ficou vazio.'; end if;

  select session.id into v_session from auth.sessions session where session.user_id = v_actor and (session.not_after is null or session.not_after > now()) order by session.created_at desc limit 1;
  if v_session is null then raise exception 'Teste requer sessão operacional ativa.'; end if;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_actor, 'session_id', v_session)::text, true);
  begin
    perform public.review_clinical_exam(v_exam, 'return', 'Teste de bloqueio');
    raise exception 'O responsável não autorizado conseguiu devolver o exame.';
  exception when insufficient_privilege then
    null;
  end;
  perform public.review_clinical_exam(v_exam, 'approve', null);
  if (select status from public.clinical_exams where id = v_exam) <> 'completed' then raise exception 'O responsável não conseguiu aprovar o próprio exame.'; end if;

  insert into public.clinical_exams (
    patient_id, exam_type_id, status, requested_by, responsible_professional_id,
    indication, result_data, started_at
  ) values (
    v_patient, 9, 'in_progress', v_actor, v_actor,
    'Biópsia com resultado inflamatório benigno para o RP.',
    jsonb_build_object('report_config_snapshot', private.clinical_exam_report_config(9), 'notes', ''), now()
  ) returning id into v_generic_exam;
  v_payload := jsonb_build_object(
    'schema', 'hpsm.ai.exam_bundle.v4',
    'parameters', jsonb_build_array(),
    'report', jsonb_build_object(
      'technique', 'Análise histológica da amostra.',
      'findings', jsonb_build_array('Alterações inflamatórias benignas.'),
      'conclusion', 'Processo inflamatório benigno.',
      'conduct', 'Acompanhamento conforme evolução clínica.'
    )
  );
  insert into public.exam_ai_generations (
    exam_id, generation_type, status, requested_by, model, reasoning_effort, prompt_version,
    source_exam_updated_at, openai_response_id, input_tokens, output_tokens, total_tokens,
    suggestion_payload, idempotency_key, completed_at
  ) select id, 'generate_exam', 'completed', v_actor, 'gpt-5.6-luna', 'low', 'exam-rp-luna-v4',
    updated_at, 'resp_test_generic', 1, 1, 2, v_payload, gen_random_uuid(), now()
  from public.clinical_exams where id = v_generic_exam returning id into v_generation;
  perform public.apply_and_submit_clinical_exam_ai_generation(v_generation, v_actor);
  if (select status from public.clinical_exams where id = v_generic_exam) <> 'awaiting_review' then raise exception 'Exame genérico não foi enviado à revisão.'; end if;

  select session.id into v_session from auth.sessions session where session.user_id = v_authority and (session.not_after is null or session.not_after > now()) order by session.created_at desc limit 1;
  if v_session is null then raise exception 'Teste requer sessão de autoridade ativa.'; end if;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_authority, 'session_id', v_session)::text, true);
  perform public.review_clinical_exam(v_generic_exam, 'approve', null);
  if (select status from public.clinical_exams where id = v_generic_exam) <> 'completed' then raise exception 'Cargo 11–14 não conseguiu aprovar o exame.'; end if;

  insert into public.clinical_exams (
    patient_id, exam_type_id, status, requested_by, responsible_professional_id,
    indication, result_data, started_at
  ) values (
    v_patient, 1, 'in_progress', v_actor, v_actor,
    'Raio-X do braço direito com fratura simples para o RP.',
    jsonb_set(jsonb_set(private.build_image_result(1), '{region}', to_jsonb('Braço'::text), true), '{laterality}', to_jsonb('right'::text), true), now()
  ) returning id into v_image_exam;
  v_image_generation := gen_random_uuid();
  insert into public.exam_ai_generations (
    id, exam_id, generation_type, status, requested_by, model, reasoning_effort, prompt_version,
    source_exam_updated_at, openai_response_id, input_tokens, output_tokens, total_tokens,
    suggestion_payload, idempotency_key, completed_at, image_quality, image_size, image_count,
    draft_storage_path, draft_mime_type, draft_file_size
  ) select v_image_generation, id, 'generate_image', 'completed', v_actor, 'gpt-image-2', 'low', 'exam-image-rp-v2',
    updated_at, 'resp_test_image', 1, 1, 2, '{}'::jsonb, gen_random_uuid(), now(), 'low', '1024x1024', 1,
    'clinical-exams/' || id || '/ai-drafts/' || gen_random_uuid() || '.png', 'image/png', 100
  from public.clinical_exams where id = v_image_exam;
  v_payload := jsonb_build_object(
    'schema', 'hpsm.ai.clinical_report.v3',
    'technique', 'Radiografia convencional do braço direito.',
    'findings', jsonb_build_array('Fratura simples do braço direito.'),
    'conclusion', 'Fratura simples do braço direito.',
    'conduct', 'Imobilização e acompanhamento clínico.'
  );
  insert into public.exam_ai_generations (
    exam_id, generation_type, status, requested_by, model, reasoning_effort, prompt_version,
    source_exam_updated_at, source_image_generation_id, openai_response_id, input_tokens,
    output_tokens, total_tokens, suggestion_payload, idempotency_key, completed_at
  ) select id, 'generate_report', 'completed', v_actor, 'gpt-5.6-luna', 'low', 'exam-rp-luna-v3',
    updated_at, v_image_generation, 'resp_test_image_report', 1, 1, 2, v_payload, gen_random_uuid(), now()
  from public.clinical_exams where id = v_image_exam returning id into v_report_generation;
  if (select prompt_version from public.exam_ai_generations where id = v_image_generation) <> 'exam-image-clinical-v3' then raise exception 'Versão clínica do prompt visual não foi aplicada.'; end if;
  if (select prompt_version from public.exam_ai_generations where id = v_report_generation) <> 'exam-clinical-report-v4' then raise exception 'Versão clínica do prompt de laudo não foi aplicada.'; end if;
  v_image_id := gen_random_uuid();
  perform public.apply_clinical_exam_ai_bundle(
    v_image_generation, v_report_generation, v_actor, v_image_id,
    'clinical-exams/' || v_image_exam || '/' || v_image_id || '.png', 100
  );
  if (select status from public.clinical_exams where id = v_image_exam) <> 'awaiting_review' then raise exception 'Exame de imagem não foi enviado automaticamente à revisão.'; end if;
  if not exists (select 1 from public.clinical_exam_images where id = v_image_id and source = 'ai_generated') then raise exception 'Imagem IA não foi anexada atomicamente.'; end if;

  if has_function_privilege('authenticated', 'public.register_clinical_exam_image(bigint,uuid,text,text,text,bigint,text)', 'execute') then raise exception 'Upload manual ainda está autorizado.'; end if;
  if exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'clinical_exam_images_storage_insert') then raise exception 'Policy de upload manual ainda existe.'; end if;
end;
$$;
