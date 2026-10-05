-- HPSM Assist: permissão e catálogos de leitura, sem persistência de casos.
insert into public.system_permissions (code, module, label, description, sort_order)
values ('hpsm.assist.use', 'HPSM Assist', 'Utilizar HPSM Assist', 'Analisa relatos avulsos de RP sem gravar conteúdo clínico.', 58)
on conflict (code) do update set module = excluded.module, label = excluded.label,
  description = excluded.description, sort_order = excluded.sort_order;

insert into public.staff_position_permissions (position_id, permission_code, granted_by)
select position.id, 'hpsm.assist.use',
  coalesce((select profile.user_id from public.profiles profile
    where profile.role_code = 'diretor_geral' and profile.status = 'active'
    order by profile.created_at limit 1), position.updated_by, position.created_by)
from public.staff_positions position
where position.official and position.active and position.level between 7 and 14
on conflict (position_id, permission_code) do nothing;

create or replace function public.hpsm_assist_reference_data()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
begin
  if not private.has_permission(v_actor, 'hpsm.assist.use') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'actor_id', v_actor,
    'exam_types', coalesce((
      select jsonb_agg(jsonb_build_object('id', exam.id, 'name', exam.name, 'category', category.name)
        order by category.sort_order, exam.sort_order, exam.name)
      from public.exam_types exam
      join public.exam_categories category on category.id = exam.category_id
      where exam.active and category.active
    ), '[]'::jsonb),
    'medications', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', medication.id, 'rp_name', medication.rp_name,
        'reference_name', medication.reference_name, 'category', medication.category,
        'controlled', medication.controlled, 'antibiotic', medication.antibiotic,
        'requires_justification', medication.requires_justification,
        'allowed_body_systems', medication.allowed_body_systems,
        'allowed_case_tags', medication.allowed_case_tags,
        'disallowed_case_tags', medication.disallowed_case_tags,
        'allergy_keywords', medication.allergy_keywords,
        'dose', medication.default_dose, 'frequency', medication.default_frequency,
        'duration', medication.default_duration, 'route', medication.default_route,
        'instructions', medication.default_instructions
      ) order by medication.rp_name)
      from public.rp_medications medication
      where medication.active
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.hpsm_assist_reference_data() from public, anon, authenticated, service_role;
grant execute on function public.hpsm_assist_reference_data() to authenticated;
comment on function public.hpsm_assist_reference_data() is
  'Catálogos ativos para análise descartável de RP, restritos a profissionais com hpsm.assist.use.';
