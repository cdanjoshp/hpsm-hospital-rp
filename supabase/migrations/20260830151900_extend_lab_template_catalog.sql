-- Tipos futuros criados na categoria Laboratorial já nascem com template versionável vazio.

update public.exam_types exam_type
set result_config = jsonb_build_object(
  'schema', 'hpsm.lab_template.v1',
  'kind', 'laboratory',
  'version', 1,
  'parameters', jsonb_build_array()
)
from public.exam_categories category
where category.id = exam_type.category_id
  and category.code = 'laboratorial'
  and exam_type.result_config = '{}'::jsonb;

create or replace function public.manage_exam_type(
  p_id bigint,
  p_category_id bigint,
  p_name text,
  p_code text,
  p_description text,
  p_active boolean,
  p_sort_order integer
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_old public.exam_types;
  v_new public.exam_types;
  v_category_active boolean;
  v_category_code text;
  v_result_config jsonb := '{}'::jsonb;
  v_action text;
begin
  if v_actor is null or not private.has_permission(v_actor, 'exams.catalog.manage') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  select category.active, category.code into v_category_active, v_category_code
  from public.exam_categories category where category.id = p_category_id;
  if v_category_active is null then raise exception 'Categoria não localizada.'; end if;
  if p_active and not v_category_active then raise exception 'Ative a categoria antes de ativar o tipo de exame.'; end if;

  if v_category_code = 'laboratorial' then
    v_result_config := jsonb_build_object(
      'schema', 'hpsm.lab_template.v1',
      'kind', 'laboratory',
      'version', 1,
      'parameters', jsonb_build_array()
    );
  end if;

  if p_id is null then
    insert into public.exam_types (
      category_id, code, name, description, active, sort_order,
      result_config, created_by, updated_by
    ) values (
      p_category_id, btrim(p_code), btrim(p_name), nullif(btrim(p_description), ''),
      coalesce(p_active, true), p_sort_order, v_result_config, v_actor, v_actor
    ) returning * into v_new;
    v_action := 'exam_type.created';
  else
    select * into v_old from public.exam_types where id = p_id for update;
    if v_old.id is null then raise exception 'Tipo de exame não localizado.'; end if;
    update public.exam_types set
      category_id = p_category_id,
      name = btrim(p_name),
      description = nullif(btrim(p_description), ''),
      active = p_active,
      sort_order = p_sort_order,
      result_config = case
        when v_category_code = 'laboratorial' and result_config = '{}'::jsonb then v_result_config
        else result_config
      end,
      updated_by = v_actor
    where id = p_id returning * into v_new;
    v_action := case when v_old.active is distinct from v_new.active then 'exam_type.status_changed' else 'exam_type.updated' end;
  end if;
  perform private.audit_exam_action(v_actor, v_action, 'exam_types', v_new.id::text, case when v_old.id is null then null else to_jsonb(v_old) end, to_jsonb(v_new));
  return v_new.id;
end;
$$;

revoke all on function public.manage_exam_type(bigint, bigint, text, text, text, boolean, integer) from public, anon, authenticated;
grant execute on function public.manage_exam_type(bigint, bigint, text, text, text, boolean, integer) to authenticated;

notify pgrst, 'reload schema';
