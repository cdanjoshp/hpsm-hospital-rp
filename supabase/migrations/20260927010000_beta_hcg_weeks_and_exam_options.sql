-- Beta HCG quantitativo com semanas obrigatórias e catálogo sem opções genéricas.
-- Snapshots históricos permanecem intocados.

insert into public.exam_types (category_id, code, name, description, active, sort_order, result_config)
select category.id, 'beta_hcg', 'Beta HCG', 'Dosagem quantitativa de beta-hCG por idade gestacional informada.', true, 50,
  jsonb_build_object(
    'schema', 'hpsm.lab_template.v1', 'kind', 'laboratory', 'version', 1,
    'parameters', jsonb_build_array(jsonb_build_object(
      'key', 'beta_hcg', 'label', 'Beta HCG quantitativo', 'field_type', 'number',
      'unit', 'mIU/mL', 'reference', 'Faixa variável conforme semanas de gestação informadas',
      'required', true, 'sort_order', 10, 'active', true, 'options', jsonb_build_array()
    ))
  )
from public.exam_categories category
where category.code = 'laboratorial'
on conflict (code) do nothing;

update public.exam_types exam_type
set result_config = jsonb_set(
  jsonb_set(exam_type.result_config, '{region,options}', (
    select jsonb_agg(to_jsonb(option_value) order by ordinal)
    from jsonb_array_elements_text(exam_type.result_config#>'{region,options}') with ordinality as regions(option_value, ordinal)
    where lower(btrim(option_value)) !~ '^outr[oa]s?($|[[:space:]])'
  )),
  '{version}', to_jsonb((exam_type.result_config->>'version')::integer + 1)
)
where exam_type.result_config->>'schema' = 'hpsm.image_template.v1'
  and exists (select 1 from jsonb_array_elements_text(exam_type.result_config#>'{region,options}') option_value where lower(btrim(option_value)) ~ '^outr[oa]s?($|[[:space:]])');

create or replace function private.default_image_template(p_exam_type_code text)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'schema', 'hpsm.image_template.v1',
    'kind', 'imaging',
    'version', 1,
    'region', jsonb_build_object(
      'required', true,
      'options', case p_exam_type_code
        when 'raio_x' then jsonb_build_array('Tórax','Abdome','Coluna cervical','Coluna torácica','Coluna lombar','Pelve','Ombro','Braço','Cotovelo','Antebraço','Punho','Mão','Quadril','Coxa','Joelho','Perna','Tornozelo','Pé','Crânio','Face')
        when 'tomografia' then jsonb_build_array('Crânio','Seios da face','Pescoço','Tórax','Abdome','Pelve','Coluna','Membro superior','Membro inferior','Angiotomografia')
        when 'ressonancia_magnetica' then jsonb_build_array('Crânio','Coluna cervical','Coluna torácica','Coluna lombar','Ombro','Cotovelo','Punho','Mão','Quadril','Joelho','Tornozelo','Pé','Abdome','Pelve')
        when 'ultrassom' then jsonb_build_array('Abdome total','Abdome superior','Pelve','Obstétrico','Rins e vias urinárias','Tireoide','Mama','Partes moles','Musculoesquelético','Doppler vascular')
        else jsonb_build_array('Região a configurar')
      end
    ),
    'supports_laterality', true,
    'supports_contrast', p_exam_type_code in ('tomografia', 'ressonancia_magnetica'),
    'requires_image', true,
    'allows_multiple_images', true
  );
$$;

create or replace function private.assert_valid_image_template(p_config jsonb)
returns void
language plpgsql
set search_path = ''
as $$
begin
  if p_config is null
     or jsonb_typeof(p_config) <> 'object'
     or p_config->>'schema' <> 'hpsm.image_template.v1'
     or p_config->>'kind' <> 'imaging'
     or coalesce((p_config->>'version') ~ '^[1-9][0-9]*$', false) is not true
     or jsonb_typeof(p_config->'region') <> 'object'
     or jsonb_typeof(p_config#>'{region,required}') <> 'boolean'
     or jsonb_typeof(p_config#>'{region,options}') <> 'array'
     or jsonb_array_length(p_config#>'{region,options}') not between 1 and 60
     or jsonb_typeof(p_config->'supports_laterality') <> 'boolean'
     or jsonb_typeof(p_config->'supports_contrast') <> 'boolean'
     or jsonb_typeof(p_config->'requires_image') <> 'boolean'
     or jsonb_typeof(p_config->'allows_multiple_images') <> 'boolean' then
    raise exception 'Template de imagem inválido.';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_config#>'{region,options}') option_value
    where jsonb_typeof(option_value) <> 'string'
       or char_length(btrim(option_value #>> '{}')) not between 2 and 120
  ) or (
    select count(*) <> count(distinct lower(btrim(option_value #>> '{}')))
    from jsonb_array_elements(p_config#>'{region,options}') option_value
  ) or exists (
    select 1 from jsonb_array_elements_text(p_config#>'{region,options}') option_value
    where lower(btrim(option_value)) ~ '^outr[oa]s?($|[[:space:]])'
  ) then
    raise exception 'Revise as regiões disponíveis no template: opções genéricas não são permitidas.';
  end if;
end;
$$;

create or replace function private.assert_valid_lab_template(p_config jsonb)
returns void
language plpgsql
set search_path = ''
as $$
begin
  if p_config is null
     or jsonb_typeof(p_config) <> 'object'
     or p_config->>'schema' <> 'hpsm.lab_template.v1'
     or p_config->>'kind' <> 'laboratory'
     or coalesce((p_config->>'version') ~ '^[1-9][0-9]*$', false) is not true
     or jsonb_typeof(p_config->'parameters') <> 'array' then
    raise exception 'Template laboratorial inválido.';
  end if;

  if jsonb_array_length(p_config->'parameters') > 100 then
    raise exception 'O template pode conter no máximo 100 parâmetros.';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_config->'parameters') parameter
    where jsonb_typeof(parameter) <> 'object'
       or coalesce(parameter->>'key', '') !~ '^[a-z0-9_]{2,64}$'
       or char_length(btrim(coalesce(parameter->>'label', ''))) not between 2 and 100
       or coalesce(parameter->>'field_type', '') not in ('number', 'text', 'select', 'observation', 'percent')
       or char_length(coalesce(parameter->>'unit', '')) > 40
       or char_length(coalesce(parameter->>'reference', '')) > 240
       or jsonb_typeof(parameter->'required') <> 'boolean'
       or jsonb_typeof(parameter->'active') <> 'boolean'
       or coalesce((parameter->>'sort_order') ~ '^-?[0-9]+$', false) is not true
       or (parameter->>'field_type' = 'select' and (
         jsonb_typeof(parameter->'options') <> 'array'
         or jsonb_array_length(parameter->'options') not between 2 and 50
         or exists (
           select 1 from jsonb_array_elements(parameter->'options') option_value
           where jsonb_typeof(option_value) <> 'string'
              or char_length(btrim(option_value #>> '{}')) not between 1 and 80
         )
       ))
  ) then
    raise exception 'Revise os campos, tipos e opções dos parâmetros do template.';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_config->'parameters') parameter
    cross join lateral jsonb_array_elements_text(case when jsonb_typeof(parameter->'options') = 'array' then parameter->'options' else '[]'::jsonb end) option_value
    where lower(btrim(option_value)) ~ '^outr[oa]s?($|[[:space:]])'
  ) then raise exception 'Opções genéricas não são permitidas nos parâmetros laboratoriais.'; end if;

  if (
    select count(*) <> count(distinct parameter->>'key')
    from jsonb_array_elements(p_config->'parameters') parameter
  ) then
    raise exception 'Cada parâmetro deve possuir um identificador único.';
  end if;
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
  v_gestational_weeks integer;
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
       or jsonb_typeof(p_initial_result_data->'gestational_weeks') <> 'number'
       or coalesce(p_initial_result_data->>'gestational_weeks', '') !~ '^[0-9]{1,2}$'
       or (p_initial_result_data->>'gestational_weeks')::integer not between 3 and 40 then
      raise exception 'Informe entre 3 e 40 semanas de gestação antes de solicitar o Beta HCG.';
    end if;
    v_gestational_weeks := (p_initial_result_data->>'gestational_weeks')::integer;
    v_indication := v_indication || E'\nIdade gestacional informada pelo médico: ' || v_gestational_weeks || ' semanas.';
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
    'report_config', v_report_config,
    'lab_template', v_lab_template,
    'result_context', v_result_context
  );
end;
$$;

alter table public.exam_ai_generations drop constraint exam_ai_generations_prompt_check;
alter table public.exam_ai_generations add constraint exam_ai_generations_prompt_check check (
  (generation_type = 'generate_image' and prompt_version in ('exam-image-rp-v1', 'exam-image-rp-v2', 'exam-image-clinical-v3'))
  or (generation_type = 'generate_exam' and prompt_version in ('exam-rp-luna-v4', 'exam-clinical-exam-v5', 'exam-clinical-exam-v6', 'exam-clinical-exam-v7', 'exam-clinical-exam-v8'))
  or (generation_type = 'generate_report' and prompt_version in ('exam-rp-luna-v1', 'exam-rp-luna-v2', 'exam-rp-luna-v3', 'exam-clinical-report-v4'))
  or (generation_type = 'generate_lab_results' and prompt_version in ('exam-rp-luna-v1', 'exam-rp-luna-v2', 'exam-rp-luna-v3', 'exam-clinical-lab-v3', 'exam-clinical-lab-v4', 'exam-clinical-lab-v5'))
);

create or replace function private.assign_current_exam_ai_prompt_version()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  new.prompt_version := case new.generation_type
    when 'generate_image' then 'exam-image-clinical-v3'
    when 'generate_lab_results' then 'exam-clinical-lab-v5'
    when 'generate_report' then 'exam-clinical-report-v4'
    when 'generate_exam' then 'exam-clinical-exam-v8'
    else new.prompt_version
  end;
  return new;
end;
$$;

notify pgrst, 'reload schema';
