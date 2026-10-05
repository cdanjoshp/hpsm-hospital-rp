-- Beta HCG: resultado informado antes da idade gestacional; referência específica para negativo.
-- Exames existentes e seus snapshots permanecem inalterados.

alter table public.clinical_exams add constraint clinical_exams_negative_beta_hcg_range check (
  case when result_data#>>'{template_snapshot,exam_type_code}' = 'beta_hcg'
    and indication ~ E'\nResultado esperado do Beta HCG: Negativo[.]$'
    and coalesce(result_data#>>'{parameters,0,value}', '') <> ''
  then case when result_data#>>'{parameters,0,value}' ~ '^[0-9]+([.,][0-9]+)?$'
    then replace(result_data#>>'{parameters,0,value}', ',', '.')::numeric >= 0
      and replace(result_data#>>'{parameters,0,value}', ',', '.')::numeric < 5
      and result_data#>>'{parameters,0,flag}' = 'negative'
    else false end
  else true end
);

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
  v_gestational_weeks integer;
  v_beta_hcg_outcome text;
  v_indication text;
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
  v_indication := btrim(p_indication);
  if v_base_result#>>'{template_snapshot,exam_type_code}' = 'beta_hcg' then
    if p_initial_result_data is null
       or jsonb_typeof(p_initial_result_data) <> 'object'
       or coalesce(p_initial_result_data->>'beta_hcg_outcome', '') not in ('positive', 'negative') then
      raise exception 'Selecione Positivo ou Negativo para o Beta HCG.';
    end if;
    v_beta_hcg_outcome := p_initial_result_data->>'beta_hcg_outcome';
    v_indication := v_indication || E'\nResultado esperado do Beta HCG: ' || case when v_beta_hcg_outcome = 'positive' then 'Positivo.' else 'Negativo.' end;
    if v_beta_hcg_outcome = 'positive' then
      if jsonb_typeof(p_initial_result_data->'gestational_weeks') <> 'number'
         or coalesce(p_initial_result_data->>'gestational_weeks', '') !~ '^[0-9]{1,2}$'
         or (p_initial_result_data->>'gestational_weeks')::integer not between 3 and 40 then
        raise exception 'Informe entre 3 e 40 semanas de gestação para o Beta HCG positivo.';
      end if;
      v_gestational_weeks := (p_initial_result_data->>'gestational_weeks')::integer;
      v_indication := v_indication || E'\nIdade gestacional informada pelo médico: ' || v_gestational_weeks || ' semanas.';
    else
      if p_initial_result_data ? 'gestational_weeks' then
        raise exception 'Não informe semanas de gestação para o Beta HCG negativo.';
      end if;
      -- A referência deve viajar com o snapshot do pedido para aparecer no resultado final.
      v_base_result := jsonb_set(v_base_result, '{template_snapshot,parameters,0,reference}', to_jsonb('0–5 mIU/mL (não gestante)'::text));
      v_base_result := jsonb_set(v_base_result, '{parameters,0,reference}', to_jsonb('0–5 mIU/mL (não gestante)'::text));
    end if;
    if char_length(v_indication) > 4000 then raise exception 'A indicação clínica deve ter no máximo 4000 caracteres.'; end if;
  end if;
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
    v_indication,
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
  if p_generation_type not in ('generate_lab_results', 'generate_report', 'generate_exam') then raise exception 'Operação de IA inválida.'; end if;
  select * into v_exam from public.clinical_exams exam where exam.id = p_exam_id;
  if v_exam.id is null then raise exception 'Exame não localizado.'; end if;
  if v_exam.status <> 'in_progress' then raise exception 'A IA só pode auxiliar exames em execução.'; end if;
  if not private.can_access_clinical_exam_ai(v_actor, p_exam_id) then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;

  select category.code, category.name, exam_type.code, exam_type.name
  into v_category_code, v_category_name, v_type_code, v_type_name
  from public.exam_types exam_type
  join public.exam_categories category on category.id = exam_type.category_id
  where exam_type.id = v_exam.exam_type_id;

  if p_generation_type = 'generate_exam' and v_exam.result_data->>'schema' = 'hpsm.image_result.v1' then
    raise exception 'Exames de imagem usam a geração visual completa.';
  end if;
  v_report_config := coalesce(v_exam.result_data->'report_config_snapshot', private.clinical_exam_report_config(v_exam.exam_type_id));
  if p_generation_type in ('generate_lab_results', 'generate_exam') and v_exam.result_data->>'schema' = 'hpsm.lab_result.v1' then
    v_lab_template := jsonb_build_object(
      'schema', v_exam.result_data#>>'{template_snapshot,schema}',
      'version', v_exam.result_data->'template_version',
      'parameters', coalesce(v_exam.result_data#>'{template_snapshot,parameters}', '[]'::jsonb)
    );
  elsif p_generation_type = 'generate_lab_results' then
    raise exception 'A geração de resultados está disponível apenas para exames laboratoriais.';
  end if;

  if p_generation_type = 'generate_report' and v_exam.result_data->>'schema' = 'hpsm.lab_result.v1' then
    select jsonb_build_object(
      'kind', 'laboratory',
      'parameters', coalesce(jsonb_agg(jsonb_build_object(
        'key', parameter->>'key', 'label', parameter->>'label', 'value', parameter->>'value',
        'unit', parameter->>'unit', 'reference', parameter->>'reference', 'flag', parameter->'flag'
      ) order by (parameter->>'sort_order')::integer, parameter->>'label'), '[]'::jsonb),
      'notes', left(coalesce(v_exam.result_data->>'notes', ''), 4000)
    ) into v_result_context
    from jsonb_array_elements(v_exam.result_data->'parameters') parameter;
  elsif p_generation_type = 'generate_report' and v_exam.result_data->>'schema' = 'hpsm.image_result.v1' then
    v_result_context := jsonb_build_object(
      'kind', 'imaging',
      'region', case when v_exam.result_data->>'region' = 'Outra região' then v_exam.result_data->>'other_region' else v_exam.result_data->>'region' end,
      'laterality', v_exam.result_data->>'laterality',
      'contrast', v_exam.result_data->>'contrast',
      'current_findings', left(coalesce(v_exam.findings, ''), 4000)
    );
  elsif p_generation_type = 'generate_report' then
    v_result_context := jsonb_build_object('kind', 'generic', 'observation', left(coalesce(v_exam.result_data->>'notes', ''), 4000));
  end if;

  return jsonb_build_object(
    'actor_id', v_actor,
    'exam_id', v_exam.id,
    'generation_type', p_generation_type,
    'patient_context', 'Paciente fictício do RP',
    'exam', jsonb_build_object('category_code', v_category_code, 'category_name', v_category_name, 'type_code', v_type_code, 'type_name', v_type_name),
    'case_context', jsonb_build_object('summary', private.clinical_exam_case_summary(v_exam.indication, v_exam.clinical_context)),
    'gestational_weeks', case when v_type_code = 'beta_hcg' then substring(v_exam.indication from E'\nIdade gestacional informada pelo médico: ([0-9]{1,2}) semanas[.]$')::integer else null end,
    'beta_hcg_outcome', case when v_type_code = 'beta_hcg' then
      case when v_exam.indication ~ E'\nResultado esperado do Beta HCG: Negativo[.]$' then 'negative'
           when v_exam.indication ~ E'\nResultado esperado do Beta HCG: Positivo[.]\nIdade gestacional informada pelo médico: [0-9]{1,2} semanas[.]$'
             or v_exam.indication ~ E'\nIdade gestacional informada pelo médico: [0-9]{1,2} semanas[.]$' then 'positive'
           else null end
      else null end,
    'report_config', v_report_config,
    'lab_template', v_lab_template,
    'result_context', v_result_context
  );
end;
$$;


notify pgrst, 'reload schema';
