-- HPSM · Fase 4.2 · Templates e resultados laboratoriais estruturados
-- O catálogo permanece em exam_types.result_config e cada exame preserva um snapshot imutável.

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

  if (
    select count(*) <> count(distinct parameter->>'key')
    from jsonb_array_elements(p_config->'parameters') parameter
  ) then
    raise exception 'Cada parâmetro deve possuir um identificador único.';
  end if;
end;
$$;

revoke all on function private.assert_valid_lab_template(jsonb) from public, anon, authenticated, service_role;

create or replace function private.build_lab_result(p_exam_type_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_code text;
  v_name text;
  v_config jsonb;
  v_snapshot jsonb;
  v_parameters jsonb;
begin
  select exam_type.code, exam_type.name, exam_type.result_config
  into v_code, v_name, v_config
  from public.exam_types exam_type
  join public.exam_categories category on category.id = exam_type.category_id
  where exam_type.id = p_exam_type_id
    and category.code = 'laboratorial'
    and exam_type.result_config->>'kind' = 'laboratory';

  if v_config is null then
    return '{}'::jsonb;
  end if;

  perform private.assert_valid_lab_template(v_config);
  v_snapshot := v_config || jsonb_build_object('exam_type_code', v_code, 'exam_type_name', v_name);

  select coalesce(jsonb_agg(
    parameter || jsonb_build_object('value', '', 'flag', null)
    order by (parameter->>'sort_order')::integer, parameter->>'label'
  ), '[]'::jsonb)
  into v_parameters
  from jsonb_array_elements(v_config->'parameters') parameter
  where (parameter->>'active')::boolean;

  return jsonb_build_object(
    'schema', 'hpsm.lab_result.v1',
    'template_version', (v_config->>'version')::integer,
    'template_snapshot', v_snapshot,
    'parameters', v_parameters,
    'notes', ''
  );
end;
$$;

revoke all on function private.build_lab_result(bigint) from public, anon, authenticated, service_role;

create or replace function private.normalize_lab_result(p_existing jsonb, p_candidate jsonb)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_snapshot jsonb;
  v_parameters jsonb;
  v_notes text;
begin
  if p_existing->>'schema' <> 'hpsm.lab_result.v1'
     or jsonb_typeof(p_existing->'template_snapshot') <> 'object'
     or jsonb_typeof(p_existing->'parameters') <> 'array' then
    raise exception 'O resultado laboratorial não possui um snapshot válido.';
  end if;
  if p_candidate is null
     or jsonb_typeof(p_candidate) <> 'object'
     or p_candidate->>'schema' <> 'hpsm.lab_result.v1'
     or jsonb_typeof(p_candidate->'parameters') <> 'array'
     or p_candidate->'template_snapshot' is distinct from p_existing->'template_snapshot'
     or p_candidate->'template_version' is distinct from p_existing->'template_version' then
    raise exception 'O snapshot do template não pode ser alterado.';
  end if;

  if jsonb_array_length(p_candidate->'parameters') > 100
     or (select count(*) <> count(distinct parameter->>'key') from jsonb_array_elements(p_candidate->'parameters') parameter)
     or exists (
       select 1
       from jsonb_array_elements(p_candidate->'parameters') parameter
       where coalesce(parameter->>'key', '') = ''
          or char_length(coalesce(parameter->>'value', '')) > 2000
          or (parameter->'flag' is not null and jsonb_typeof(parameter->'flag') <> 'null'
              and coalesce(parameter->>'flag', '') not in ('normal', 'low', 'high', 'positive', 'negative', 'inconclusive'))
          or not exists (
            select 1
            from jsonb_array_elements(p_existing#>'{template_snapshot,parameters}') snapshot_parameter
            where snapshot_parameter->>'key' = parameter->>'key'
          )
     ) then
    raise exception 'Os parâmetros do resultado são inválidos.';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_candidate->'parameters') candidate
    join jsonb_array_elements(p_existing#>'{template_snapshot,parameters}') snapshot
      on snapshot->>'key' = candidate->>'key'
    where nullif(btrim(candidate->>'value'), '') is not null
      and (
        (snapshot->>'field_type' in ('number', 'percent') and candidate->>'value' !~ '^-?[0-9]+([.,][0-9]+)?$')
        or (snapshot->>'field_type' = 'select' and not exists (
          select 1 from jsonb_array_elements_text(snapshot->'options') option_value
          where option_value = candidate->>'value'
        ))
      )
  ) then
    raise exception 'Há valores incompatíveis com o tipo configurado.';
  end if;

  v_snapshot := p_existing->'template_snapshot';
  v_notes := left(coalesce(p_candidate->>'notes', ''), 12000);

  select coalesce(jsonb_agg(
    snapshot_parameter || jsonb_build_object(
      'value', coalesce(candidate_parameter->>'value', ''),
      'flag', case
        when candidate_parameter->'flag' is null or jsonb_typeof(candidate_parameter->'flag') = 'null' then null
        else to_jsonb(candidate_parameter->>'flag')
      end
    ) order by (snapshot_parameter->>'sort_order')::integer, snapshot_parameter->>'label'
  ), '[]'::jsonb)
  into v_parameters
  from jsonb_array_elements(v_snapshot->'parameters') snapshot_parameter
  left join lateral (
    select candidate
    from jsonb_array_elements(p_candidate->'parameters') candidate
    where candidate->>'key' = snapshot_parameter->>'key'
    limit 1
  ) candidate_parameter on true
  where (snapshot_parameter->>'active')::boolean;

  return jsonb_build_object(
    'schema', 'hpsm.lab_result.v1',
    'template_version', p_existing->'template_version',
    'template_snapshot', v_snapshot,
    'parameters', v_parameters,
    'notes', v_notes
  );
end;
$$;

revoke all on function private.normalize_lab_result(jsonb, jsonb) from public, anon, authenticated, service_role;

-- Templates iniciais enxutos para RP. A atualização só ocupa configurações ainda vazias.
update public.exam_types exam_type
set result_config = seed.config
from (
  values
    ('hemograma', jsonb_build_object(
      'schema', 'hpsm.lab_template.v1', 'kind', 'laboratory', 'version', 1,
      'parameters', jsonb_build_array(
        jsonb_build_object('key','hemacias','label','Hemácias','field_type','number','unit','milhões/µL','reference','Faixa configurada para RP','required',true,'sort_order',10,'active',true,'options',jsonb_build_array()),
        jsonb_build_object('key','hemoglobina','label','Hemoglobina','field_type','number','unit','g/dL','reference','Faixa configurada para RP','required',true,'sort_order',20,'active',true,'options',jsonb_build_array()),
        jsonb_build_object('key','hematocrito','label','Hematócrito','field_type','percent','unit','%','reference','Faixa configurada para RP','required',true,'sort_order',30,'active',true,'options',jsonb_build_array()),
        jsonb_build_object('key','leucocitos','label','Leucócitos','field_type','number','unit','/µL','reference','Faixa configurada para RP','required',true,'sort_order',40,'active',true,'options',jsonb_build_array()),
        jsonb_build_object('key','plaquetas','label','Plaquetas','field_type','number','unit','/µL','reference','Faixa configurada para RP','required',true,'sort_order',50,'active',true,'options',jsonb_build_array())
      )
    )),
    ('bioquimica', jsonb_build_object(
      'schema', 'hpsm.lab_template.v1', 'kind', 'laboratory', 'version', 1,
      'parameters', jsonb_build_array(
        jsonb_build_object('key','glicose','label','Glicose','field_type','number','unit','mg/dL','reference','Faixa configurada para RP','required',true,'sort_order',10,'active',true,'options',jsonb_build_array()),
        jsonb_build_object('key','ureia','label','Ureia','field_type','number','unit','mg/dL','reference','Faixa configurada para RP','required',true,'sort_order',20,'active',true,'options',jsonb_build_array()),
        jsonb_build_object('key','creatinina','label','Creatinina','field_type','number','unit','mg/dL','reference','Faixa configurada para RP','required',true,'sort_order',30,'active',true,'options',jsonb_build_array()),
        jsonb_build_object('key','sodio','label','Sódio','field_type','number','unit','mEq/L','reference','Faixa configurada para RP','required',true,'sort_order',40,'active',true,'options',jsonb_build_array()),
        jsonb_build_object('key','potassio','label','Potássio','field_type','number','unit','mEq/L','reference','Faixa configurada para RP','required',true,'sort_order',50,'active',true,'options',jsonb_build_array())
      )
    )),
    ('tipagem_sanguinea', jsonb_build_object(
      'schema', 'hpsm.lab_template.v1', 'kind', 'laboratory', 'version', 1,
      'parameters', jsonb_build_array(
        jsonb_build_object('key','grupo_abo','label','Grupo ABO','field_type','select','unit','','reference','','required',true,'sort_order',10,'active',true,'options',jsonb_build_array('A','B','AB','O')),
        jsonb_build_object('key','fator_rh','label','Fator Rh','field_type','select','unit','','reference','','required',true,'sort_order',20,'active',true,'options',jsonb_build_array('Positivo','Negativo'))
      )
    )),
    ('toxicologia', jsonb_build_object(
      'schema', 'hpsm.lab_template.v1', 'kind', 'laboratory', 'version', 1,
      'parameters', jsonb_build_array(
        jsonb_build_object('key','alcool','label','Álcool','field_type','select','unit','','reference','','required',true,'sort_order',10,'active',true,'options',jsonb_build_array('Negativo','Positivo','Inconclusivo')),
        jsonb_build_object('key','estimulantes','label','Estimulantes','field_type','select','unit','','reference','','required',true,'sort_order',20,'active',true,'options',jsonb_build_array('Negativo','Positivo','Inconclusivo')),
        jsonb_build_object('key','opiaceos','label','Opiáceos','field_type','select','unit','','reference','','required',true,'sort_order',30,'active',true,'options',jsonb_build_array('Negativo','Positivo','Inconclusivo'))
      )
    ))
) as seed(code, config)
where exam_type.code = seed.code
  and exam_type.result_config = '{}'::jsonb;

do $$
declare
  v_config jsonb;
begin
  for v_config in
    select exam_type.result_config
    from public.exam_types exam_type
    join public.exam_categories category on category.id = exam_type.category_id
    where category.code = 'laboratorial' and exam_type.result_config->>'kind' = 'laboratory'
  loop
    perform private.assert_valid_lab_template(v_config);
  end loop;
end;
$$;

create or replace function public.clinical_exam_template_catalog()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null or not private.has_permission(v_actor, 'exams.catalog.manage') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', exam_type.id,
      'code', exam_type.code,
      'name', exam_type.name,
      'active', exam_type.active,
      'result_config', exam_type.result_config
    ) order by exam_type.sort_order, exam_type.name)
    from public.exam_types exam_type
    join public.exam_categories category on category.id = exam_type.category_id
    where category.code = 'laboratorial'
      and exam_type.result_config->>'kind' = 'laboratory'
  ), '[]'::jsonb);
end;
$$;

create or replace function public.manage_exam_template(
  p_exam_type_id bigint,
  p_expected_version integer,
  p_parameters jsonb
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_type public.exam_types;
  v_old_config jsonb;
  v_new_config jsonb;
  v_new_version integer;
begin
  if v_actor is null or not private.has_permission(v_actor, 'exams.catalog.manage') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  select exam_type.* into v_type
  from public.exam_types exam_type
  join public.exam_categories category on category.id = exam_type.category_id
  where exam_type.id = p_exam_type_id and category.code = 'laboratorial'
  for update of exam_type;
  if v_type.id is null or v_type.result_config->>'kind' <> 'laboratory' then
    raise exception 'Template laboratorial não localizado.';
  end if;
  if p_expected_version is distinct from (v_type.result_config->>'version')::integer then
    raise exception 'O template foi atualizado por outra pessoa. Reabra-o antes de salvar.';
  end if;
  if jsonb_typeof(p_parameters) <> 'array' then
    raise exception 'A lista de parâmetros é inválida.';
  end if;

  v_old_config := v_type.result_config;
  v_new_version := p_expected_version + 1;
  v_new_config := jsonb_build_object(
    'schema', 'hpsm.lab_template.v1',
    'kind', 'laboratory',
    'version', v_new_version,
    'parameters', p_parameters
  );
  perform private.assert_valid_lab_template(v_new_config);

  if exists (
    select 1
    from jsonb_array_elements(v_old_config->'parameters') old_parameter
    where not exists (
      select 1 from jsonb_array_elements(p_parameters) new_parameter
      where new_parameter->>'key' = old_parameter->>'key'
    )
    and exists (
      select 1
      from public.clinical_exams exam
      cross join lateral jsonb_array_elements(coalesce(exam.result_data#>'{template_snapshot,parameters}', '[]'::jsonb)) historical_parameter
      where exam.exam_type_id = p_exam_type_id
        and historical_parameter->>'key' = old_parameter->>'key'
    )
  ) then
    raise exception 'Parâmetros já usados em exames devem ser inativados, não removidos.';
  end if;

  update public.exam_types
  set result_config = v_new_config, updated_by = v_actor
  where id = p_exam_type_id;

  perform private.audit_exam_action(
    v_actor,
    'exam_template.updated',
    'exam_types',
    p_exam_type_id::text,
    jsonb_build_object('result_config', v_old_config),
    jsonb_build_object('result_config', v_new_config)
  );
  return v_new_version;
end;
$$;

create or replace function public.create_clinical_exam(
  p_patient_id bigint,
  p_exam_type_id bigint,
  p_responsible_professional_id uuid,
  p_indication text,
  p_clinical_context text default null,
  p_attendance_id bigint default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_responsible uuid := coalesce(p_responsible_professional_id, v_actor);
  v_exam public.clinical_exams;
  v_result_data jsonb;
begin
  if v_actor is null
     or not private.has_permission(v_actor, 'exams.create')
     or not private.has_permission(v_actor, 'patients.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.patients patient where patient.id = p_patient_id) then
    raise exception 'Paciente não localizado.';
  end if;
  if not exists (
    select 1 from public.exam_types exam_type
    join public.exam_categories category on category.id = exam_type.category_id
    where exam_type.id = p_exam_type_id and exam_type.active and category.active
  ) then
    raise exception 'Tipo de exame indisponível.';
  end if;
  if not exists (select 1 from public.profiles profile where profile.user_id = v_responsible and profile.status = 'active')
     or not (private.has_permission(v_responsible, 'exams.perform') or private.has_permission(v_responsible, 'exams.review')) then
    raise exception 'Profissional responsável inválido.';
  end if;
  v_result_data := private.build_lab_result(p_exam_type_id);
  insert into public.clinical_exams (
    patient_id, exam_type_id, attendance_id, requested_by, responsible_professional_id,
    indication, clinical_context, result_data
  ) values (
    p_patient_id, p_exam_type_id, p_attendance_id, v_actor, v_responsible,
    btrim(p_indication), nullif(btrim(p_clinical_context), ''), v_result_data
  ) returning * into v_exam;
  insert into public.clinical_exam_status_history (exam_id, from_status, to_status, changed_by, note)
  values (v_exam.id, null, 'requested', v_actor, 'Exame solicitado.');
  perform private.audit_exam_action(v_actor, 'clinical_exam.created', 'clinical_exams', v_exam.id::text, null, to_jsonb(v_exam));
  return v_exam.id;
end;
$$;

create or replace function public.start_clinical_exam(p_exam_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_old public.clinical_exams;
  v_new public.clinical_exams;
  v_result_data jsonb;
begin
  select * into v_old from public.clinical_exams where id = p_exam_id for update;
  if v_old.id is null then raise exception 'Exame não localizado.'; end if;
  if not private.can_perform_clinical_exam(v_actor, v_old.responsible_professional_id) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if v_old.status <> 'requested' then raise exception 'O exame não está disponível para início.'; end if;
  v_result_data := case
    when v_old.result_data->>'schema' = 'hpsm.lab_result.v1' then v_old.result_data
    else private.build_lab_result(v_old.exam_type_id)
  end;
  update public.clinical_exams set status = 'in_progress', started_at = now(), result_data = v_result_data
  where id = p_exam_id returning * into v_new;
  insert into public.clinical_exam_status_history (exam_id, from_status, to_status, changed_by, note)
  values (p_exam_id, 'requested', 'in_progress', v_actor, 'Execução iniciada.');
  perform private.audit_exam_action(v_actor, 'clinical_exam.started', 'clinical_exams', p_exam_id::text, to_jsonb(v_old), to_jsonb(v_new));
end;
$$;

create or replace function public.save_clinical_exam_draft(
  p_exam_id bigint,
  p_technique text,
  p_findings text,
  p_conclusion text,
  p_result_data jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_old public.clinical_exams;
  v_new public.clinical_exams;
  v_result_data jsonb;
begin
  select * into v_old from public.clinical_exams where id = p_exam_id for update;
  if v_old.id is null then raise exception 'Exame não localizado.'; end if;
  if not private.can_perform_clinical_exam(v_actor, v_old.responsible_professional_id) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if v_old.status <> 'in_progress' then raise exception 'O exame não está em andamento.'; end if;
  if p_result_data is null or jsonb_typeof(p_result_data) <> 'object' then raise exception 'Dados adicionais inválidos.'; end if;
  v_result_data := case
    when v_old.result_data->>'schema' = 'hpsm.lab_result.v1'
      then private.normalize_lab_result(v_old.result_data, p_result_data)
    else p_result_data
  end;
  update public.clinical_exams set
    technique = nullif(btrim(p_technique), ''),
    findings = nullif(btrim(p_findings), ''),
    conclusion = nullif(btrim(p_conclusion), ''),
    result_data = v_result_data
  where id = p_exam_id returning * into v_new;
  if (to_jsonb(v_old) - 'updated_at') is distinct from (to_jsonb(v_new) - 'updated_at') then
    perform private.audit_exam_action(
      v_actor, 'clinical_exam.result_saved', 'clinical_exams', p_exam_id::text,
      jsonb_build_object('technique', v_old.technique, 'findings', v_old.findings, 'conclusion', v_old.conclusion, 'result_data', v_old.result_data),
      jsonb_build_object('technique', v_new.technique, 'findings', v_new.findings, 'conclusion', v_new.conclusion, 'result_data', v_new.result_data)
    );
  end if;
end;
$$;

create or replace function public.submit_clinical_exam_review(p_exam_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_old public.clinical_exams;
  v_new public.clinical_exams;
  v_missing text;
begin
  select * into v_old from public.clinical_exams where id = p_exam_id for update;
  if v_old.id is null then raise exception 'Exame não localizado.'; end if;
  if not private.can_perform_clinical_exam(v_actor, v_old.responsible_professional_id) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if v_old.status <> 'in_progress' then raise exception 'O exame não está em andamento.'; end if;
  if v_old.technique is null or v_old.findings is null or v_old.conclusion is null then
    raise exception 'Preencha técnica, achados e conclusão antes do envio.';
  end if;
  if v_old.result_data->>'schema' = 'hpsm.lab_result.v1' then
    select string_agg(snapshot->>'label', ', ' order by (snapshot->>'sort_order')::integer)
    into v_missing
    from jsonb_array_elements(v_old.result_data#>'{template_snapshot,parameters}') snapshot
    where (snapshot->>'active')::boolean
      and (snapshot->>'required')::boolean
      and not exists (
        select 1 from jsonb_array_elements(v_old.result_data->'parameters') result_parameter
        where result_parameter->>'key' = snapshot->>'key'
          and nullif(btrim(result_parameter->>'value'), '') is not null
      );
    if v_missing is not null then
      raise exception 'Preencha os parâmetros obrigatórios: %.', v_missing;
    end if;
  end if;
  update public.clinical_exams set status = 'awaiting_review', submitted_for_review_at = now()
  where id = p_exam_id returning * into v_new;
  insert into public.clinical_exam_status_history (exam_id, from_status, to_status, changed_by, note)
  values (p_exam_id, 'in_progress', 'awaiting_review', v_actor, 'Exame enviado para revisão.');
  perform private.audit_exam_action(v_actor, 'clinical_exam.submitted_for_review', 'clinical_exams', p_exam_id::text, to_jsonb(v_old), to_jsonb(v_new));
end;
$$;

-- Inicializa solicitações/em andamento anteriores à Fase 4.2 sem tocar resultados concluídos.
update public.clinical_exams exam
set result_data = private.build_lab_result(exam.exam_type_id)
from public.exam_types exam_type
join public.exam_categories category on category.id = exam_type.category_id
where exam.exam_type_id = exam_type.id
  and category.code = 'laboratorial'
  and exam_type.result_config->>'kind' = 'laboratory'
  and exam.status in ('requested', 'in_progress')
  and exam.result_data = '{}'::jsonb;

revoke all on function public.clinical_exam_template_catalog() from public, anon, authenticated;
revoke all on function public.manage_exam_template(bigint, integer, jsonb) from public, anon, authenticated;
grant execute on function public.clinical_exam_template_catalog() to authenticated;
grant execute on function public.manage_exam_template(bigint, integer, jsonb) to authenticated;

comment on column public.exam_types.result_config is 'Template configurável; laboratórios usam hpsm.lab_template.v1 com versão e parâmetros.';
comment on column public.clinical_exams.result_data is 'Resultado clínico; laboratórios usam hpsm.lab_result.v1 com snapshot imutável do template.';

notify pgrst, 'reload schema';
