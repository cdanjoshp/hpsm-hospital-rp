-- HPSM · Solicitação simplificada de exames
-- Unifica o contexto dos exames de imagem, fixa o profissional pela sessão e
-- limita o vínculo financeiro às vendas elegíveis do paciente.

create or replace function private.clinical_exam_case_summary(p_indication text, p_context text)
returns text
language sql
immutable
set search_path = ''
as $$
  select left(
    case
      when nullif(btrim(coalesce(p_indication, '')), '') is null then btrim(coalesce(p_context, ''))
      when nullif(btrim(coalesce(p_context, '')), '') is null
        or btrim(p_context) = btrim(p_indication) then btrim(p_indication)
      else btrim(p_indication) || E'\n' || btrim(p_context)
    end,
    4000
  );
$$;

revoke all on function private.clinical_exam_case_summary(text, text) from public, anon, authenticated, service_role;

create or replace function public.clinical_exam_reference_data()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null or not (
    private.has_permission(v_actor, 'exams.view')
    or private.has_permission(v_actor, 'exams.create')
    or private.has_permission(v_actor, 'exams.perform')
    or private.has_permission(v_actor, 'exams.review')
    or private.has_permission(v_actor, 'exams.catalog.manage')
  ) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'categories', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', category.id,
        'code', category.code,
        'name', category.name,
        'active', category.active,
        'sort_order', category.sort_order
      ) order by category.sort_order, category.name)
      from public.exam_categories category
    ), '[]'::jsonb),
    'types', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', exam_type.id,
        'category_id', exam_type.category_id,
        'code', exam_type.code,
        'name', exam_type.name,
        'description', exam_type.description,
        'active', exam_type.active,
        'sort_order', exam_type.sort_order,
        'result_config', exam_type.result_config
      ) order by exam_type.category_id, exam_type.sort_order, exam_type.name)
      from public.exam_types exam_type
    ), '[]'::jsonb),
    'professionals', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', profile.user_id,
        'name', profile.display_name,
        'position', position.name
      ))
      from public.profiles profile
      left join public.staff_positions position on position.id = profile.position_id
      where profile.user_id = v_actor
        and profile.status = 'active'
        and (private.has_permission(v_actor, 'exams.perform') or private.has_permission(v_actor, 'exams.review'))
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.clinical_exam_attendance_options(p_patient_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null
     or not private.has_permission(v_actor, 'exams.create')
     or not private.has_permission(v_actor, 'patients.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.patients patient where patient.id = p_patient_id) then
    raise exception 'Paciente não localizado.';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', attendance.id,
      'created_at', attendance.created_at,
      'total', attendance.total,
      'summary', coalesce((
        select string_agg(item.service_name || case when item.quantity > 1 then ' ×' || item.quantity::text else '' end, ', ' order by item.id)
        from public.attendance_items item
        where item.attendance_id = attendance.id
      ), 'Atendimento sem itens')
    ) order by attendance.created_at desc)
    from (
      select sale.id, sale.created_at, sale.total
      from public.attendances sale
      where sale.patient_id = p_patient_id
        and sale.status = 'completed'
        and exists (
          select 1
          from public.attendance_items item
          left join public.service_catalog catalog on catalog.id = item.service_id
          where item.attendance_id = sale.id
            and (
              upper(btrim(item.service_name)) in ('EXAMES / RAIO-X', 'RESSON. TOMO.')
              or upper(btrim(catalog.name)) in ('EXAMES / RAIO-X', 'RESSON. TOMO.')
            )
        )
      order by sale.created_at desc
      limit 30
    ) attendance
  ), '[]'::jsonb);
end;
$$;

create or replace function public.create_clinical_exam(
  p_patient_id bigint,
  p_exam_type_id bigint,
  p_responsible_professional_id uuid,
  p_indication text,
  p_clinical_context text default null,
  p_attendance_id bigint default null,
  p_initial_result_data jsonb default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_responsible uuid := auth.uid();
  v_exam public.clinical_exams;
  v_base_result jsonb;
  v_candidate jsonb;
  v_result_data jsonb;
begin
  if v_actor is null or not private.has_permission(v_actor, 'exams.create') or not private.has_permission(v_actor, 'patients.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if nullif(btrim(coalesce(p_indication, '')), '') is null then
    raise exception 'Informe a indicação clínica.';
  end if;
  if char_length(btrim(p_indication)) > 4000 then
    raise exception 'A indicação clínica deve ter no máximo 4000 caracteres.';
  end if;
  if not exists (select 1 from public.patients patient where patient.id = p_patient_id) then
    raise exception 'Paciente não localizado.';
  end if;
  if not exists (
    select 1
    from public.exam_types exam_type
    join public.exam_categories category on category.id = exam_type.category_id
    where exam_type.id = p_exam_type_id and exam_type.active and category.active
  ) then
    raise exception 'Tipo de exame indisponível.';
  end if;
  if not exists (
    select 1
    from public.profiles profile
    where profile.user_id = v_responsible and profile.status = 'active'
  ) or not (
    private.has_permission(v_responsible, 'exams.perform')
    or private.has_permission(v_responsible, 'exams.review')
  ) then
    raise exception 'Seu perfil não está habilitado como profissional responsável.';
  end if;
  if p_attendance_id is not null and not exists (
    select 1
    from public.attendances sale
    where sale.id = p_attendance_id
      and sale.patient_id = p_patient_id
      and sale.status = 'completed'
      and exists (
        select 1
        from public.attendance_items item
        left join public.service_catalog catalog on catalog.id = item.service_id
        where item.attendance_id = sale.id
          and (
            upper(btrim(item.service_name)) in ('EXAMES / RAIO-X', 'RESSON. TOMO.')
            or upper(btrim(catalog.name)) in ('EXAMES / RAIO-X', 'RESSON. TOMO.')
          )
      )
  ) then
    raise exception 'O atendimento relacionado deve ser uma venda concluída deste paciente com EXAMES / RAIO-X ou RESSON. TOMO.';
  end if;

  -- O parâmetro legado permanece na assinatura durante a transição, mas a
  -- responsabilidade é sempre definida pela sessão autenticada.
  v_base_result := private.build_clinical_exam_result(p_exam_type_id);
  if v_base_result->>'schema' = 'hpsm.image_result.v1' then
    if p_initial_result_data is null or jsonb_typeof(p_initial_result_data) <> 'object' then
      raise exception 'Preencha as informações básicas do exame de imagem na solicitação.';
    end if;
    v_candidate := v_base_result || jsonb_build_object(
      'region', coalesce(p_initial_result_data->>'region', ''),
      'other_region', coalesce(p_initial_result_data->>'other_region', ''),
      'laterality', coalesce(p_initial_result_data->>'laterality', ''),
      'contrast', coalesce(p_initial_result_data->>'contrast', ''),
      'notes', ''
    );
    v_result_data := private.normalize_image_result(v_base_result, v_candidate);
    if coalesce((v_result_data#>>'{template_snapshot,region,required}')::boolean, false)
       and btrim(v_result_data->>'region') = '' then
      raise exception 'Informe a região examinada na solicitação.';
    end if;
    if coalesce((v_result_data#>>'{template_snapshot,supports_laterality}')::boolean, false)
       and btrim(v_result_data->>'laterality') = '' then
      raise exception 'Informe a lateralidade na solicitação.';
    end if;
    if coalesce((v_result_data#>>'{template_snapshot,supports_contrast}')::boolean, false)
       and btrim(v_result_data->>'contrast') = '' then
      raise exception 'Informe o uso de contraste na solicitação.';
    end if;
  else
    v_result_data := v_base_result;
  end if;

  v_result_data := private.attach_clinical_exam_report_context(p_exam_type_id, v_result_data);
  insert into public.clinical_exams (
    patient_id, exam_type_id, attendance_id, requested_by, responsible_professional_id,
    indication, clinical_context, result_data
  ) values (
    p_patient_id, p_exam_type_id, p_attendance_id, v_actor, v_responsible,
    btrim(p_indication),
    case when v_base_result->>'schema' = 'hpsm.image_result.v1' then null else nullif(btrim(p_clinical_context), '') end,
    v_result_data
  ) returning * into v_exam;

  insert into public.clinical_exam_status_history (exam_id, from_status, to_status, changed_by, note)
  values (v_exam.id, null, 'requested', v_actor, 'Exame solicitado.');
  perform private.audit_exam_action(v_actor, 'clinical_exam.created', 'clinical_exams', v_exam.id::text, null, to_jsonb(v_exam));
  return v_exam.id;
end;
$$;

create or replace function public.clinical_exam_ai_context(p_exam_id bigint, p_generation_type text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_exam public.clinical_exams;
  v_category_code text;
  v_category_name text;
  v_type_code text;
  v_type_name text;
  v_report_config jsonb;
  v_lab_template jsonb;
  v_result_context jsonb := '{}'::jsonb;
begin
  if p_generation_type not in ('generate_lab_results', 'generate_report') then raise exception 'Operação de IA inválida.'; end if;
  select * into v_exam from public.clinical_exams exam where exam.id = p_exam_id;
  if v_exam.id is null then raise exception 'Exame não localizado.'; end if;
  if v_exam.status <> 'in_progress' then raise exception 'A IA só pode auxiliar exames em execução.'; end if;
  if not private.can_access_clinical_exam_ai(v_actor, p_exam_id) then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;

  select category.code, category.name, exam_type.code, exam_type.name
  into v_category_code, v_category_name, v_type_code, v_type_name
  from public.exam_types exam_type
  join public.exam_categories category on category.id = exam_type.category_id
  where exam_type.id = v_exam.exam_type_id;

  v_report_config := coalesce(v_exam.result_data->'report_config_snapshot', private.clinical_exam_report_config(v_exam.exam_type_id));
  if p_generation_type = 'generate_lab_results' then
    if v_exam.result_data->>'schema' <> 'hpsm.lab_result.v1' then raise exception 'A geração de resultados está disponível apenas para exames laboratoriais.'; end if;
    v_lab_template := jsonb_build_object(
      'schema', v_exam.result_data#>>'{template_snapshot,schema}',
      'version', v_exam.result_data->'template_version',
      'parameters', coalesce(v_exam.result_data#>'{template_snapshot,parameters}', '[]'::jsonb)
    );
  elsif v_exam.result_data->>'schema' = 'hpsm.lab_result.v1' then
    select jsonb_build_object(
      'kind', 'laboratory',
      'parameters', coalesce(jsonb_agg(jsonb_build_object(
        'key', parameter->>'key', 'label', parameter->>'label', 'value', parameter->>'value',
        'unit', parameter->>'unit', 'reference', parameter->>'reference', 'flag', parameter->'flag'
      ) order by (parameter->>'sort_order')::integer, parameter->>'label'), '[]'::jsonb),
      'notes', left(coalesce(v_exam.result_data->>'notes', ''), 4000)
    ) into v_result_context
    from jsonb_array_elements(v_exam.result_data->'parameters') parameter;
  elsif v_exam.result_data->>'schema' = 'hpsm.image_result.v1' then
    v_result_context := jsonb_build_object(
      'kind', 'imaging',
      'region', case when v_exam.result_data->>'region' = 'Outra região' then v_exam.result_data->>'other_region' else v_exam.result_data->>'region' end,
      'laterality', v_exam.result_data->>'laterality',
      'contrast', v_exam.result_data->>'contrast',
      'current_findings', left(coalesce(v_exam.findings, ''), 4000)
    );
  else
    v_result_context := jsonb_build_object('kind', 'generic', 'observation', left(coalesce(v_exam.result_data->>'notes', ''), 4000));
  end if;

  return jsonb_build_object(
    'actor_id', v_actor,
    'exam_id', v_exam.id,
    'generation_type', p_generation_type,
    'patient_context', 'Paciente fictício do RP',
    'exam', jsonb_build_object('category_code', v_category_code, 'category_name', v_category_name, 'type_code', v_type_code, 'type_name', v_type_name),
    'case_context', jsonb_build_object('summary', private.clinical_exam_case_summary(v_exam.indication, v_exam.clinical_context)),
    'report_config', v_report_config,
    'lab_template', v_lab_template,
    'result_context', v_result_context
  );
end;
$$;

create or replace function public.clinical_exam_ai_image_context(p_exam_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_exam public.clinical_exams;
  v_type_code text;
  v_type_name text;
begin
  select exam.* into v_exam from public.clinical_exams exam where exam.id = p_exam_id;
  if v_exam.id is null then raise exception 'Exame não localizado.'; end if;
  select exam_type.code, exam_type.name into v_type_code, v_type_name from public.exam_types exam_type where exam_type.id = v_exam.exam_type_id;
  if v_exam.status <> 'in_progress' then raise exception 'A imagem por IA só pode ser gerada em exame em andamento.'; end if;
  if v_exam.responsible_professional_id is distinct from v_actor or not private.has_permission(v_actor, 'exams.perform') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if v_exam.result_data->>'schema' <> 'hpsm.image_result.v1' or v_type_code not in ('raio_x', 'tomografia', 'ressonancia_magnetica', 'ultrassom') then raise exception 'Este tipo de exame não aceita geração de imagem por IA.'; end if;
  if nullif(btrim(case when v_exam.result_data->>'region' = 'Outra região' then v_exam.result_data->>'other_region' else v_exam.result_data->>'region' end), '') is null
     or nullif(btrim(v_exam.indication), '') is null then
    raise exception 'Preencha e salve a região e a suspeita/contexto do caso antes de gerar.';
  end if;
  if coalesce((v_exam.result_data#>>'{template_snapshot,supports_laterality}')::boolean, false)
     and nullif(v_exam.result_data->>'laterality', '') is null then raise exception 'Selecione e salve a lateralidade antes de gerar.'; end if;

  return jsonb_build_object(
    'actor_id', v_actor,
    'exam_id', v_exam.id,
    'type_code', v_type_code,
    'type_name', v_type_name,
    'region', case when v_exam.result_data->>'region' = 'Outra região' then v_exam.result_data->>'other_region' else v_exam.result_data->>'region' end,
    'laterality', v_exam.result_data->>'laterality',
    'contrast', v_exam.result_data->>'contrast',
    'findings', left(coalesce(v_exam.findings, ''), 4000),
    'case_summary', private.clinical_exam_case_summary(v_exam.indication, v_exam.clinical_context)
  );
end;
$$;

revoke all on function public.clinical_exam_reference_data() from public, anon, authenticated, service_role;
revoke all on function public.clinical_exam_attendance_options(bigint) from public, anon, authenticated, service_role;
revoke all on function public.create_clinical_exam(bigint, bigint, uuid, text, text, bigint, jsonb) from public, anon, authenticated, service_role;
revoke all on function public.clinical_exam_ai_context(bigint, text) from public, anon, authenticated, service_role;
revoke all on function public.clinical_exam_ai_image_context(bigint) from public, anon, authenticated, service_role;

grant execute on function public.clinical_exam_reference_data() to authenticated;
grant execute on function public.clinical_exam_attendance_options(bigint) to authenticated;
grant execute on function public.create_clinical_exam(bigint, bigint, uuid, text, text, bigint, jsonb) to authenticated;
grant execute on function public.clinical_exam_ai_context(bigint, text) to authenticated;
grant execute on function public.clinical_exam_ai_image_context(bigint) to authenticated;

comment on function public.clinical_exam_attendance_options(bigint) is
  'Lista até 30 vendas concluídas do paciente que contenham EXAMES / RAIO-X ou RESSON. TOMO. para vínculo clínico opcional.';
comment on function public.create_clinical_exam(bigint, bigint, uuid, text, text, bigint, jsonb) is
  'Cria exame com responsável igual ao ator autenticado; imagem usa contexto unificado e só aceita vendas elegíveis do paciente.';

notify pgrst, 'reload schema';
