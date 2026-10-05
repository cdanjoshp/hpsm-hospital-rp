-- HPSM · Ajustes da Central de Exames
-- Dados de imagem passam a nascer na solicitação, o laudo simples deixa de criar
-- observação RP e exames não concluídos ganham exclusão permanente controlada.

insert into public.system_permissions (code, module, label, description, sort_order)
values ('exams.delete', 'Exames', 'Excluir exames', 'Exclui permanentemente exames ainda não concluídos.', 25)
on conflict (code) do update set
  module = excluded.module,
  label = excluded.label,
  description = excluded.description,
  sort_order = excluded.sort_order;

insert into public.staff_position_permissions (position_id, permission_code, granted_by)
select
  position.id,
  'exams.delete',
  coalesce(
    (select profile.user_id from public.profiles profile where profile.role_code = 'diretor_geral' limit 1),
    position.updated_by,
    position.created_by
  )
from public.staff_positions position
where position.official and position.level between 11 and 14
on conflict (position_id, permission_code) do nothing;

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
      ) order by position.level, profile.display_name)
      from public.profiles profile
      left join public.staff_positions position on position.id = profile.position_id
      where profile.status = 'active'
        and (private.has_permission(profile.user_id, 'exams.perform') or private.has_permission(profile.user_id, 'exams.review'))
    ), '[]'::jsonb)
  );
end;
$$;

drop function if exists public.create_clinical_exam(bigint, bigint, uuid, text, text, bigint);

create function public.create_clinical_exam(
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
  v_responsible uuid := coalesce(p_responsible_professional_id, v_actor);
  v_exam public.clinical_exams;
  v_base_result jsonb;
  v_candidate jsonb;
  v_result_data jsonb;
begin
  if v_actor is null or not private.has_permission(v_actor, 'exams.create') or not private.has_permission(v_actor, 'patients.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
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
  if not exists (select 1 from public.profiles profile where profile.user_id = v_responsible and profile.status = 'active')
     or not (private.has_permission(v_responsible, 'exams.perform') or private.has_permission(v_responsible, 'exams.review')) then
    raise exception 'Profissional responsável inválido.';
  end if;

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
      'notes', coalesce(p_initial_result_data->>'notes', '')
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
    btrim(p_indication), nullif(btrim(p_clinical_context), ''), v_result_data
  ) returning * into v_exam;

  insert into public.clinical_exam_status_history (exam_id, from_status, to_status, changed_by, note)
  values (v_exam.id, null, 'requested', v_actor, 'Exame solicitado.');
  perform private.audit_exam_action(v_actor, 'clinical_exam.created', 'clinical_exams', v_exam.id::text, null, to_jsonb(v_exam));
  return v_exam.id;
end;
$$;

revoke all on function public.create_clinical_exam(bigint, bigint, uuid, text, text, bigint, jsonb) from public, anon, authenticated, service_role;
grant execute on function public.create_clinical_exam(bigint, bigint, uuid, text, text, bigint, jsonb) to authenticated;

create or replace function private.validate_exam_ai_suggestion(p_exam_id bigint, p_generation_type text, p_payload jsonb)
returns void language plpgsql stable security definer set search_path = '' as $$
declare
  v_exam public.clinical_exams;
  v_candidate jsonb;
  v_config jsonb;
begin
  select * into v_exam from public.clinical_exams where id = p_exam_id;
  if v_exam.id is null or v_exam.status <> 'in_progress' then raise exception 'O exame não aceita mais sugestões de IA.'; end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then raise exception 'Sugestão de IA inválida.'; end if;

  if p_generation_type = 'generate_lab_results' then
    if p_payload->>'schema' <> 'hpsm.ai.lab_suggestion.v1'
       or coalesce(jsonb_typeof(p_payload->'parameters'), '') <> 'array'
       or coalesce(jsonb_typeof(p_payload->'notes'), '') <> 'string'
       or exists (select 1 from jsonb_object_keys(p_payload) key where key not in ('schema', 'parameters', 'notes'))
       or jsonb_array_length(p_payload->'parameters') <> (
         select count(*) from jsonb_array_elements(v_exam.result_data#>'{template_snapshot,parameters}') parameter
         where coalesce((parameter->>'active')::boolean, false)
       )
       or (select count(*) <> count(distinct parameter->>'key') from jsonb_array_elements(p_payload->'parameters') parameter)
       or exists (
         select 1 from jsonb_array_elements(v_exam.result_data#>'{template_snapshot,parameters}') snapshot
         where coalesce((snapshot->>'active')::boolean, false)
           and not exists (select 1 from jsonb_array_elements(p_payload->'parameters') suggestion where suggestion->>'key' = snapshot->>'key')
       ) then raise exception 'Sugestão laboratorial incompatível com o template.'; end if;
    v_candidate := v_exam.result_data || jsonb_build_object('parameters', p_payload->'parameters', 'notes', left(p_payload->>'notes', 12000));
    perform private.normalize_lab_result(v_exam.result_data, v_candidate);
  elsif p_generation_type = 'generate_report' and p_payload->>'schema' in ('hpsm.ai.simple_report.v1', 'hpsm.ai.simple_report.v2') then
    if exists (
         select 1 from jsonb_object_keys(p_payload) key
         where key not in ('schema', 'summary', 'findings', 'conclusion', 'rp_note')
       )
       or coalesce(jsonb_typeof(p_payload->'summary'), '') <> 'string'
       or coalesce(jsonb_typeof(p_payload->'findings'), '') <> 'array'
       or coalesce(jsonb_typeof(p_payload->'conclusion'), '') <> 'string'
       or (p_payload->>'schema' = 'hpsm.ai.simple_report.v1' and coalesce(jsonb_typeof(p_payload->'rp_note'), '') <> 'string')
       or (p_payload->>'schema' = 'hpsm.ai.simple_report.v2' and p_payload ? 'rp_note')
       or jsonb_array_length(p_payload->'findings') not between 1 and 4
       or char_length(p_payload->>'summary') > 1200
       or char_length(p_payload->>'conclusion') > 1200
       or char_length(coalesce(p_payload->>'rp_note', '')) > 600
       or exists (select 1 from jsonb_array_elements(p_payload->'findings') item where jsonb_typeof(item) <> 'string' or char_length(item#>>'{}') > 1200)
    then raise exception 'Sugestão de laudo simplificado inválida.'; end if;
  elsif p_generation_type = 'generate_report' then
    v_config := coalesce(v_exam.result_data->'report_config_snapshot', private.clinical_exam_report_config(v_exam.exam_type_id));
    if p_payload->>'schema' <> 'hpsm.ai.report_suggestion.v1'
       or coalesce(jsonb_typeof(p_payload->'fields'), '') <> 'object'
       or exists (select 1 from jsonb_object_keys(p_payload) key where key not in ('schema', 'fields'))
       or exists (
         select 1 from jsonb_object_keys(p_payload->'fields') key
         where key not in ('technique', 'findings', 'conclusion', 'observations')
            or coalesce((v_config#>>array['fields', key, 'visible'])::boolean, false) is false
            or jsonb_typeof(p_payload->'fields'->key) <> 'string'
            or char_length(p_payload->'fields'->>key) > case key when 'findings' then 8000 when 'observations' then 12000 else 4000 end
       )
       or exists (
         select 1 from jsonb_object_keys(v_config->'fields') key
         where coalesce((v_config#>>array['fields', key, 'visible'])::boolean, false) and not (p_payload->'fields' ? key)
       ) then raise exception 'Sugestão de laudo incompatível com a configuração do exame.'; end if;
  else
    raise exception 'Operação de IA inválida.';
  end if;
end;
$$;

create or replace function public.apply_clinical_exam_ai_generation(p_generation_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_generation public.exam_ai_generations;
  v_exam public.clinical_exams;
  v_parameters jsonb;
  v_candidate jsonb;
  v_result_data jsonb;
  v_config jsonb;
  v_fields jsonb;
  v_technique text;
  v_findings text;
  v_conclusion text;
  v_observations text;
begin
  select * into v_generation from public.exam_ai_generations where id = p_generation_id;
  if v_generation.id is null then raise exception 'Sugestão de IA não localizada.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_generation.exam_id::text || ':' || v_generation.generation_type, 0));
  select * into v_exam from public.clinical_exams where id = v_generation.exam_id for update;
  select * into v_generation from public.exam_ai_generations where id = p_generation_id for update;
  if v_exam.status <> 'in_progress' then raise exception 'O exame não aceita mais alterações.'; end if;
  if not private.can_access_clinical_exam_ai(v_actor, v_exam.id) then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if v_generation.status <> 'completed' then raise exception 'A sugestão de IA não está disponível para aplicação.'; end if;
  if v_exam.updated_at is distinct from v_generation.source_exam_updated_at then raise exception 'O exame foi atualizado após a geração. Gere uma nova sugestão para comparar com o rascunho atual.'; end if;
  perform private.validate_exam_ai_suggestion(v_exam.id, v_generation.generation_type, v_generation.suggestion_payload);

  if v_generation.generation_type = 'generate_lab_results' then
    select jsonb_agg(parameter || jsonb_build_object('value', suggestion.item->>'value', 'flag', suggestion.item->'flag')
      order by (parameter->>'sort_order')::integer, parameter->>'label') into v_parameters
    from jsonb_array_elements(v_exam.result_data->'parameters') parameter
    join lateral (select item from jsonb_array_elements(v_generation.suggestion_payload->'parameters') item where item->>'key' = parameter->>'key' limit 1) suggestion on true;
    v_candidate := v_exam.result_data || jsonb_build_object('parameters', v_parameters, 'notes', v_generation.suggestion_payload->>'notes');
    v_result_data := private.normalize_lab_result(v_exam.result_data, v_candidate)
      || jsonb_build_object('report_config_snapshot', v_exam.result_data->'report_config_snapshot', 'exam_type_snapshot', v_exam.result_data->'exam_type_snapshot');
    update public.clinical_exams set result_data = v_result_data where id = v_exam.id;
  else
    v_config := coalesce(v_exam.result_data->'report_config_snapshot', private.clinical_exam_report_config(v_exam.exam_type_id));
    if v_generation.suggestion_payload->>'schema' in ('hpsm.ai.simple_report.v1', 'hpsm.ai.simple_report.v2') then
      select string_agg('- ' || item, E'\n') into v_findings from jsonb_array_elements_text(v_generation.suggestion_payload->'findings') item;
      v_technique := nullif(btrim(v_generation.suggestion_payload->>'summary'), '');
      v_conclusion := nullif(btrim(v_generation.suggestion_payload->>'conclusion'), '');
      v_observations := case when v_generation.suggestion_payload->>'schema' = 'hpsm.ai.simple_report.v1'
        then btrim(v_generation.suggestion_payload->>'rp_note') else null end;
    else
      v_fields := v_generation.suggestion_payload->'fields';
      v_technique := nullif(btrim(v_fields->>'technique'), '');
      v_findings := nullif(btrim(v_fields->>'findings'), '');
      v_conclusion := nullif(btrim(v_fields->>'conclusion'), '');
      v_observations := coalesce(v_fields->>'observations', '');
    end if;
    v_result_data := case
      when v_exam.result_data->>'schema' = 'hpsm.image_result.v1' then v_exam.result_data
      when v_observations is not null and coalesce((v_config#>>'{fields,observations,visible}')::boolean, false)
        then jsonb_set(v_exam.result_data, '{notes}', to_jsonb(v_observations), true)
      else v_exam.result_data
    end;
    update public.clinical_exams set
      technique = case when coalesce((v_config#>>'{fields,technique,visible}')::boolean, false) then v_technique else technique end,
      findings = case when coalesce((v_config#>>'{fields,findings,visible}')::boolean, false) then v_findings else findings end,
      conclusion = case when coalesce((v_config#>>'{fields,conclusion,visible}')::boolean, false) then v_conclusion else conclusion end,
      result_data = v_result_data
    where id = v_exam.id;
  end if;

  update public.exam_ai_generations set status = 'applied', applied_at = now() where id = p_generation_id;
  perform private.audit_exam_action(v_actor, 'clinical_exam.ai_applied', 'exam_ai_generations', p_generation_id::text,
    jsonb_build_object('status', 'completed'),
    jsonb_build_object('status', 'applied', 'exam_id', v_exam.id, 'generation_type', v_generation.generation_type,
      'model', v_generation.model, 'prompt_version', v_generation.prompt_version,
      'source_image_generation_id', v_generation.source_image_generation_id, 'source_image_id', v_generation.source_image_id));
end;
$$;

create or replace function public.apply_clinical_exam_ai_bundle(
  p_image_generation_id uuid,
  p_report_generation_id uuid,
  p_actor uuid,
  p_image_id uuid,
  p_storage_path text,
  p_file_size bigint
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_image_generation public.exam_ai_generations;
  v_report_generation public.exam_ai_generations;
  v_exam public.clinical_exams;
  v_count integer;
  v_config jsonb;
  v_fields jsonb;
  v_findings text;
  v_technique text;
  v_conclusion text;
  v_observations text;
  v_result_data jsonb;
begin
  select * into v_image_generation from public.exam_ai_generations where id = p_image_generation_id;
  select * into v_report_generation from public.exam_ai_generations where id = p_report_generation_id;
  if v_image_generation.id is null or v_report_generation.id is null or v_image_generation.exam_id <> v_report_generation.exam_id then raise exception 'Prévia de IA incompleta.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_image_generation.exam_id::text || ':ai_bundle', 0));
  select * into v_exam from public.clinical_exams where id = v_image_generation.exam_id for update;
  select * into v_image_generation from public.exam_ai_generations where id = p_image_generation_id for update;
  select * into v_report_generation from public.exam_ai_generations where id = p_report_generation_id for update;

  if v_exam.status <> 'in_progress' or v_exam.responsible_professional_id is distinct from p_actor or not private.has_permission(p_actor, 'exams.perform') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if v_image_generation.generation_type <> 'generate_image' or v_image_generation.status <> 'completed' or v_image_generation.requested_by is distinct from p_actor then raise exception 'Rascunho de imagem indisponível.'; end if;
  if v_report_generation.generation_type <> 'generate_report' or v_report_generation.status <> 'completed' then raise exception 'Sugestão de laudo indisponível.'; end if;
  if v_exam.updated_at is distinct from v_report_generation.source_exam_updated_at then raise exception 'O exame foi atualizado após a geração. Gere uma nova prévia.'; end if;
  if p_storage_path <> 'clinical-exams/' || v_exam.id::text || '/' || p_image_id::text || '.png'
     or p_file_size <> v_image_generation.draft_file_size then raise exception 'Imagem final inválida.'; end if;
  perform private.validate_exam_ai_suggestion(v_exam.id, 'generate_report', v_report_generation.suggestion_payload);

  select count(*) into v_count from public.clinical_exam_images where exam_id = v_exam.id and removed_at is null;
  if not (v_exam.result_data#>>'{template_snapshot,allows_multiple_images}')::boolean and v_count > 0 then raise exception 'Este tipo de exame aceita somente uma imagem.'; end if;
  insert into public.clinical_exam_images(id, exam_id, storage_path, original_filename, mime_type, file_size, sort_order, caption, source, uploaded_by)
  values(p_image_id, v_exam.id, p_storage_path, 'imagem-ficticia-ia.png', 'image/png', p_file_size, (v_count + 1) * 10,
    'Imagem fictícia gerada por IA para fins de RP.', 'ai_generated', p_actor);

  v_config := coalesce(v_exam.result_data->'report_config_snapshot', private.clinical_exam_report_config(v_exam.exam_type_id));
  if v_report_generation.suggestion_payload->>'schema' in ('hpsm.ai.simple_report.v1', 'hpsm.ai.simple_report.v2') then
    select string_agg('- ' || item, E'\n') into v_findings from jsonb_array_elements_text(v_report_generation.suggestion_payload->'findings') item;
    v_technique := nullif(btrim(v_report_generation.suggestion_payload->>'summary'), '');
    v_conclusion := nullif(btrim(v_report_generation.suggestion_payload->>'conclusion'), '');
    v_observations := case when v_report_generation.suggestion_payload->>'schema' = 'hpsm.ai.simple_report.v1'
      then btrim(v_report_generation.suggestion_payload->>'rp_note') else null end;
  else
    v_fields := v_report_generation.suggestion_payload->'fields';
    v_technique := nullif(btrim(v_fields->>'technique'), '');
    v_findings := nullif(btrim(v_fields->>'findings'), '');
    v_conclusion := nullif(btrim(v_fields->>'conclusion'), '');
    v_observations := coalesce(v_fields->>'observations', '');
  end if;
  v_result_data := case
    when v_exam.result_data->>'schema' = 'hpsm.image_result.v1' then v_exam.result_data
    when v_observations is not null and coalesce((v_config#>>'{fields,observations,visible}')::boolean, false)
      then jsonb_set(v_exam.result_data, '{notes}', to_jsonb(v_observations), true)
    else v_exam.result_data
  end;
  update public.clinical_exams set
    technique = case when coalesce((v_config#>>'{fields,technique,visible}')::boolean, false) then v_technique else technique end,
    findings = case when coalesce((v_config#>>'{fields,findings,visible}')::boolean, false) then v_findings else findings end,
    conclusion = case when coalesce((v_config#>>'{fields,conclusion,visible}')::boolean, false) then v_conclusion else conclusion end,
    result_data = v_result_data
  where id = v_exam.id;

  update public.exam_ai_generations set status = 'applied', applied_at = now(), official_image_id = p_image_id where id = p_image_generation_id;
  update public.exam_ai_generations set status = 'applied', applied_at = now() where id = p_report_generation_id;
  perform private.audit_exam_action(p_actor, 'clinical_exam.ai_bundle_applied', 'clinical_exams', v_exam.id::text, null,
    jsonb_build_object('image_generation_id', p_image_generation_id, 'report_generation_id', p_report_generation_id,
      'image_id', p_image_id, 'image_model', v_image_generation.model, 'report_model', v_report_generation.model));
  return jsonb_build_object('exam_id', v_exam.id, 'image_id', p_image_id, 'draft_path', v_image_generation.draft_storage_path);
end;
$$;

create or replace function public.delete_clinical_exam(p_exam_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_exam public.clinical_exams;
  v_storage_paths jsonb;
  v_image_ids text[];
  v_generation_ids text[];
  v_image_count integer;
  v_generation_count integer;
  v_report_version_count integer;
  v_history_count integer;
begin
  if v_actor is null then raise exception 'Sessão inválida.' using errcode = '42501'; end if;
  select * into v_exam from public.clinical_exams where id = p_exam_id for update;
  if v_exam.id is null then raise exception 'Exame não localizado.'; end if;
  if v_exam.status = 'completed' then raise exception 'Exames concluídos não podem ser excluídos.'; end if;
  if v_exam.responsible_professional_id is distinct from v_actor and not private.has_permission(v_actor, 'exams.delete') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(path order by path), '[]'::jsonb) into v_storage_paths
  from (
    select image.storage_path as path from public.clinical_exam_images image where image.exam_id = p_exam_id
    union
    select generation.draft_storage_path as path from public.exam_ai_generations generation
    where generation.exam_id = p_exam_id and generation.draft_storage_path is not null
  ) paths;
  select coalesce(array_agg(image.id::text), array[]::text[]), count(*)::integer
  into v_image_ids, v_image_count
  from public.clinical_exam_images image where image.exam_id = p_exam_id;
  select coalesce(array_agg(generation.id::text), array[]::text[]), count(*)::integer
  into v_generation_ids, v_generation_count
  from public.exam_ai_generations generation where generation.exam_id = p_exam_id;
  select count(*)::integer into v_report_version_count from public.clinical_exam_report_versions version where version.exam_id = p_exam_id;
  select count(*)::integer into v_history_count from public.clinical_exam_status_history history where history.exam_id = p_exam_id;

  delete from public.audit_logs audit
  where (audit.entity_name = 'clinical_exams' and audit.entity_id = p_exam_id::text)
     or (audit.entity_name = 'clinical_exam_images' and audit.entity_id = any(v_image_ids))
     or (audit.entity_name = 'exam_ai_generations' and audit.entity_id = any(v_generation_ids));
  delete from public.exam_ai_generations where exam_id = p_exam_id;
  delete from public.clinical_exam_images where exam_id = p_exam_id;
  delete from public.clinical_exam_report_versions where exam_id = p_exam_id;
  delete from public.clinical_exam_status_history where exam_id = p_exam_id;
  delete from public.clinical_exams where id = p_exam_id;

  perform private.audit_exam_action(
    v_actor,
    'DELETE',
    'clinical_exams',
    p_exam_id::text,
    jsonb_build_object(
      'status', v_exam.status,
      'exam_type_id', v_exam.exam_type_id,
      'patient_id', v_exam.patient_id,
      'responsible_professional_id', v_exam.responsible_professional_id
    ),
    jsonb_build_object(
      'deleted', true,
      'images', v_image_count,
      'ai_generations', v_generation_count,
      'report_versions', v_report_version_count,
      'status_events', v_history_count
    )
  );
  return jsonb_build_object('exam_id', p_exam_id, 'storage_paths', v_storage_paths);
end;
$$;

revoke all on function public.delete_clinical_exam(bigint) from public, anon, authenticated, service_role;
grant execute on function public.delete_clinical_exam(bigint) to authenticated;

comment on function public.delete_clinical_exam(bigint) is
  'Exclui um exame não concluído pelo responsável ou por usuário com exams.delete; retorna paths privados para limpeza via Storage API.';
