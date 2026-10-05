-- Corrige a desreferência do registro lateral usado na normalização do laudo.

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
      'value', coalesce(candidate_parameter.candidate->>'value', ''),
      'flag', case
        when candidate_parameter.candidate->'flag' is null or jsonb_typeof(candidate_parameter.candidate->'flag') = 'null' then null
        else to_jsonb(candidate_parameter.candidate->>'flag')
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

notify pgrst, 'reload schema';
