-- A ordem das aulas passa a ser definida na lista, por arrastar ou pelas setas do teclado.
set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function public.academy_reorder_lessons(
  p_course_id bigint,
  p_lesson_ids bigint[]
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_course_id bigint;
  v_count bigint;
  v_before jsonb;
begin
  perform private.academy_require(v_actor, 'courses.manage', true);
  perform private.academy_require(v_actor, 'courses.academy.manage', true);

  select id into v_course_id from public.courses where id = p_course_id for update;
  if not found then raise exception 'Curso não encontrado.' using errcode = '22023'; end if;

  select count(*), coalesce(jsonb_agg(id order by position, id), '[]'::jsonb)
  into v_count, v_before
  from public.course_lessons where course_id = p_course_id;

  if p_lesson_ids is null or cardinality(p_lesson_ids) <> v_count
    or exists (
      select 1 from unnest(p_lesson_ids) as item(id)
      group by item.id having item.id is null or count(*) > 1
    )
    or exists (
      select 1 from unnest(p_lesson_ids) as item(id)
      where not exists (select 1 from public.course_lessons lesson
        where lesson.course_id = p_course_id and lesson.id = item.id)
    ) then
    raise exception 'A lista de aulas mudou. Atualize a página e tente novamente.' using errcode = '22023';
  end if;

  update public.course_lessons lesson
  set position = item.position::integer, updated_at = now()
  from unnest(p_lesson_ids) with ordinality as item(id, position)
  where lesson.course_id = p_course_id and lesson.id = item.id
    and lesson.position is distinct from item.position::integer;

  if v_before is distinct from to_jsonb(p_lesson_ids) then
    perform private.academy_audit(v_actor, 'LESSONS_REORDERED', 'courses', p_course_id,
      jsonb_build_object('lesson_ids', v_before),
      jsonb_build_object('lesson_ids', to_jsonb(p_lesson_ids)));
  end if;
  return jsonb_build_object('lesson_ids', to_jsonb(p_lesson_ids));
end;
$$;

revoke all on function public.academy_reorder_lessons(bigint,bigint[])
  from public, anon, authenticated, service_role;
grant execute on function public.academy_reorder_lessons(bigint,bigint[]) to authenticated;
notify pgrst, 'reload schema';
