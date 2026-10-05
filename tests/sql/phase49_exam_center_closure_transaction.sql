begin;

do $$
declare
  v_actor uuid := '68808ed5-94e3-44e3-a8a1-483de268202f';
  v_authority uuid := '56d67f62-d37d-464c-9191-0d8a22134bf7';
  v_actor_session uuid;
  v_authority_session uuid;
  v_patient bigint;
  v_exam bigint;
  v_exam_ids bigint[] := array[]::bigint[];
  v_generation uuid;
  v_image_generation uuid;
  v_report_generation uuid;
  v_image_id uuid;
  v_result jsonb;
  v_payload jsonb;
  v_parameters jsonb;
  v_region text;
  v_row public.clinical_exams;
  v_snapshot jsonb;
  v_deleted bigint;
  v_unauthorized_exam bigint;
  v_blocked boolean;
  v_seen_codes text[] := array[]::text[];
  exam_type record;
begin
  select min(id) into v_patient from public.patients;
  if v_patient is null then raise exception 'A Fase 4.9 requer um paciente existente.'; end if;

  select session.id into v_actor_session
  from auth.sessions session
  where session.user_id = v_actor and (session.not_after is null or session.not_after > now())
  order by session.created_at desc limit 1;
  select session.id into v_authority_session
  from auth.sessions session
  where session.user_id = v_authority and (session.not_after is null or session.not_after > now())
  order by session.created_at desc limit 1;
  if v_actor_session is null or v_authority_session is null then
    raise exception 'A Fase 4.9 requer as duas sessões de teste ativas.';
  end if;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_actor, 'session_id', v_actor_session)::text, true);

  for exam_type in
    select type.id, type.code, type.name
    from public.exam_types type
    join public.exam_categories category on category.id = type.category_id
    where type.active and category.active
      and type.code in (
        'raio_x', 'tomografia', 'ressonancia_magnetica', 'ultrassom',
        'hemograma', 'bioquimica', 'tipagem_sanguinea', 'toxicologia',
        'biopsia', 'citologia', 'eletrocardiograma'
      )
    order by type.id
  loop
    v_result := private.build_clinical_exam_result(exam_type.id);
    if v_result->>'schema' = 'hpsm.image_result.v1' then
      select value#>>'{}' into v_region
      from jsonb_array_elements(v_result#>'{template_snapshot,region,options}') with ordinality option(value, position)
      order by position limit 1;
      v_result := jsonb_set(v_result, '{region}', to_jsonb(coalesce(v_region, 'Outra região')), true);
      if coalesce((v_result#>>'{template_snapshot,supports_laterality}')::boolean, false) then
        v_result := jsonb_set(v_result, '{laterality}', to_jsonb('right'::text), true);
      end if;
      if coalesce((v_result#>>'{template_snapshot,supports_contrast}')::boolean, false) then
        v_result := jsonb_set(v_result, '{contrast}', to_jsonb('without'::text), true);
      end if;
    else
      v_result := null;
    end if;

    v_exam := public.create_clinical_exam(
      v_patient,
      exam_type.id,
      v_actor,
      'Validação clínica completa da Fase 4.9 para ' || exam_type.name || '.',
      case when exam_type.id > 4 then 'Contexto clínico representativo e objetivo.' else null end,
      null,
      v_result
    );
    perform public.start_clinical_exam(v_exam);

    select * into v_row from public.clinical_exams where id = v_exam;
    if v_row.result_data->>'schema' = 'hpsm.image_result.v1' then
      v_image_generation := gen_random_uuid();
      insert into public.exam_ai_generations (
        id, exam_id, generation_type, status, requested_by, model, reasoning_effort,
        prompt_version, source_exam_updated_at, openai_response_id, input_tokens,
        output_tokens, total_tokens, suggestion_payload, idempotency_key, completed_at,
        image_quality, image_size, image_count, draft_storage_path, draft_mime_type,
        draft_file_size
      ) values (
        v_image_generation, v_exam, 'generate_image', 'completed', v_actor, 'gpt-image-2', 'low',
        'exam-image-rp-v2', v_row.updated_at, 'phase49_image_' || exam_type.code, 1, 1, 2,
        '{}'::jsonb, gen_random_uuid(), now(), 'low', '1024x1024', 1,
        'clinical-exams/' || v_exam || '/ai-drafts/' || gen_random_uuid() || '.png',
        'image/png', 256
      );

      v_payload := jsonb_build_object(
        'schema', 'hpsm.ai.clinical_report.v3',
        'technique', 'Aquisição técnica adequada para análise clínica.',
        'findings', jsonb_build_array('Achado localizado coerente com a indicação clínica informada.'),
        'conclusion', 'Alteração focal identificada no exame.',
        'conduct', 'Acompanhamento clínico conforme evolução.'
      );
      insert into public.exam_ai_generations (
        exam_id, generation_type, status, requested_by, model, reasoning_effort,
        prompt_version, source_exam_updated_at, source_image_generation_id,
        openai_response_id, input_tokens, output_tokens, total_tokens,
        suggestion_payload, idempotency_key, completed_at
      ) select
        v_exam, 'generate_report', 'completed', v_actor, 'gpt-5.6-luna', 'low',
        'exam-rp-luna-v3', updated_at, v_image_generation,
        'phase49_report_' || exam_type.code, 1, 1, 2, v_payload, gen_random_uuid(), now()
      from public.clinical_exams where id = v_exam
      returning id into v_report_generation;

      v_image_id := gen_random_uuid();
      perform public.apply_clinical_exam_ai_bundle(
        v_image_generation,
        v_report_generation,
        v_actor,
        v_image_id,
        'clinical-exams/' || v_exam || '/' || v_image_id || '.png',
        256
      );
    else
      if v_row.result_data->>'schema' = 'hpsm.lab_result.v1' then
        select jsonb_agg(
          jsonb_build_object(
            'key', parameter->>'key',
            'value', case
              when parameter->>'field_type' = 'select' then parameter#>>'{options,0}'
              when parameter->>'field_type' in ('number', 'percent') then '10'
              else 'Dentro da normalidade'
            end,
            'flag', case parameter#>>'{options,0}'
              when 'Positivo' then 'positive'
              when 'Negativo' then 'negative'
              when 'Inconclusivo' then 'inconclusive'
              else 'normal'
            end
          )
          order by (parameter->>'sort_order')::integer, parameter->>'label'
        ) into v_parameters
        from jsonb_array_elements(v_row.result_data#>'{template_snapshot,parameters}') parameter
        where coalesce((parameter->>'active')::boolean, false);
      else
        v_parameters := '[]'::jsonb;
      end if;

      v_payload := jsonb_build_object(
        'schema', 'hpsm.ai.exam_bundle.v4',
        'parameters', coalesce(v_parameters, '[]'::jsonb),
        'report', jsonb_build_object(
          'technique', 'Método técnico adequado ao tipo de exame.',
          'findings', jsonb_build_array('Resultado coerente com a indicação clínica informada.'),
          'conclusion', 'Exame concluído com resultado clínico objetivo.',
          'conduct', 'Acompanhamento clínico conforme evolução.'
        )
      );
      perform private.validate_exam_ai_suggestion(v_exam, 'generate_exam', v_payload);
      insert into public.exam_ai_generations (
        exam_id, generation_type, status, requested_by, model, reasoning_effort,
        prompt_version, source_exam_updated_at, openai_response_id, input_tokens,
        output_tokens, total_tokens, suggestion_payload, idempotency_key, completed_at
      ) select
        id, 'generate_exam', 'completed', v_actor, 'gpt-5.6-luna', 'low',
        'exam-rp-luna-v4', updated_at, 'phase49_exam_' || exam_type.code,
        1, 1, 2, v_payload, gen_random_uuid(), now()
      from public.clinical_exams where id = v_exam
      returning id into v_generation;
      perform public.apply_and_submit_clinical_exam_ai_generation(v_generation, v_actor);
    end if;

    if (select status from public.clinical_exams where id = v_exam) <> 'awaiting_review' then
      raise exception 'O tipo % não chegou à revisão.', exam_type.code;
    end if;
    if not exists (
      select 1 from public.clinical_exam_report_versions version
      where version.exam_id = v_exam and version.decision = 'pending'
    ) then raise exception 'O tipo % não criou a versão pendente.', exam_type.code; end if;

    v_exam_ids := array_append(v_exam_ids, v_exam);
    v_seen_codes := array_append(v_seen_codes, exam_type.code);
  end loop;

  if cardinality(v_exam_ids) <> 11 or cardinality(v_seen_codes) <> 11 then
    raise exception 'Nem todos os 11 tipos foram validados: %.', array_to_string(v_seen_codes, ', ');
  end if;

  -- Um ciclo completo de devolução, correção e reenvio preserva as duas versões.
  v_exam := v_exam_ids[1];
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_authority, 'session_id', v_authority_session)::text, true);
  perform public.review_clinical_exam(v_exam, 'return', 'Ajustar o texto conclusivo para a revisão final.');
  if (select status from public.clinical_exams where id = v_exam) <> 'in_progress' then
    raise exception 'A devolução não reabriu o exame.';
  end if;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_actor, 'session_id', v_actor_session)::text, true);
  select * into v_row from public.clinical_exams where id = v_exam;
  perform public.save_clinical_exam_draft(
    v_exam,
    v_row.technique,
    v_row.findings,
    v_row.conclusion || ' Conteúdo revisado.',
    v_row.result_data
  );
  perform public.submit_clinical_exam_review(v_exam);
  if (select count(*) from public.clinical_exam_report_versions where exam_id = v_exam) <> 2 then
    raise exception 'O reenvio não preservou duas versões do laudo.';
  end if;

  -- A autoridade aprova o ciclo devolvido; o responsável aprova os demais.
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_authority, 'session_id', v_authority_session)::text, true);
  perform public.review_clinical_exam(v_exam, 'approve', null);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_actor, 'session_id', v_actor_session)::text, true);
  for position in 2..cardinality(v_exam_ids) loop
    perform public.review_clinical_exam(v_exam_ids[position], 'approve', null);
  end loop;

  if exists (select 1 from public.clinical_exams where id = any(v_exam_ids) and status <> 'completed') then
    raise exception 'Um dos 11 tipos não foi concluído.';
  end if;
  if exists (
    select 1 from public.clinical_exams exam
    where exam.id = any(v_exam_ids)
      and (
        exam.final_report_snapshot is null
        or exam.final_report_snapshot->'patient' is null
        or exam.final_report_snapshot->'exam' is null
        or exam.final_report_snapshot->'content' is null
        or exam.final_report_snapshot->'executed_by' is null
        or exam.final_report_snapshot->'reviewed_by' is null
        or exam.final_report_snapshot#>>'{dates,completed_at}' is null
        or exam.final_report_snapshot::text ~* 'signed_url|base64'
      )
  ) then raise exception 'Um snapshot final ficou incompleto ou armazenou conteúdo efêmero.'; end if;
  if exists (
    select 1 from public.clinical_exams exam
    join public.exam_types type on type.id = exam.exam_type_id
    where exam.id = any(v_exam_ids) and type.id <= 4
      and jsonb_array_length(exam.final_report_snapshot->'images') <> 1
  ) then raise exception 'Uma imagem final não foi preservada no snapshot.'; end if;

  -- Mudança futura no catálogo não altera silenciosamente o snapshot já aprovado.
  select final_report_snapshot into v_snapshot from public.clinical_exams where id = v_exam_ids[5];
  update public.exam_types set name = name || ' TEMPORÁRIO 4.9' where id = 5;
  if (select final_report_snapshot from public.clinical_exams where id = v_exam_ids[5]) is distinct from v_snapshot then
    raise exception 'O catálogo alterou um snapshot final.';
  end if;

  -- O gatilho de imutabilidade também bloqueia alteração direta por proprietário.
  v_blocked := false;
  begin
    update public.clinical_exams set conclusion = 'Alteração silenciosa proibida' where id = v_exam_ids[5];
  exception when others then
    v_blocked := true;
  end;
  if not v_blocked then raise exception 'Um exame concluído aceitou alteração clínica direta.'; end if;

  -- Exclusão autorizada funciona antes da conclusão e gera auditoria independente.
  v_deleted := public.create_clinical_exam(
    v_patient, 9, v_actor, 'Solicitação temporária para validar exclusão.', null, null, null
  );
  perform public.delete_clinical_exam(v_deleted);
  if exists (select 1 from public.clinical_exams where id = v_deleted) then
    raise exception 'A exclusão autorizada não removeu o exame.';
  end if;
  if not exists (
    select 1 from public.audit_logs audit
    where audit.action = 'DELETE' and audit.entity_name = 'clinical_exams' and audit.entity_id = v_deleted::text
  ) then raise exception 'A exclusão não gerou auditoria.'; end if;

  -- Concluído nunca pode ser excluído pelo fluxo normal.
  v_blocked := false;
  begin
    perform public.delete_clinical_exam(v_exam_ids[5]);
  exception when others then
    v_blocked := true;
  end;
  if not v_blocked then raise exception 'Um exame concluído foi excluído.'; end if;

  -- Um ator inexistente/sem perfil válido é bloqueado no próprio banco.
  insert into public.clinical_exams (
    patient_id, exam_type_id, status, requested_by, responsible_professional_id,
    indication, result_data
  ) values (
    v_patient, 9, 'requested', v_actor, v_actor,
    'Validação de ator não autorizado.', private.attach_clinical_exam_report_context(9, private.build_clinical_exam_result(9))
  ) returning id into v_unauthorized_exam;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', gen_random_uuid(), 'session_id', gen_random_uuid())::text, true);
  v_blocked := false;
  begin
    perform public.start_clinical_exam(v_unauthorized_exam);
  exception when others then
    v_blocked := true;
  end;
  if not v_blocked then raise exception 'Um usuário sem perfil/permissão iniciou o exame.'; end if;
end;
$$;

rollback;
