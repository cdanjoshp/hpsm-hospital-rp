-- Permissão explícita da gestão, atalhos da Home e refinamentos das RPCs.
set lock_timeout = '5s';
set statement_timeout = '40s';

insert into public.system_permissions(code,module,label,description,sort_order)
values('courses.academy.manage','Formação','Gestão da Academia','Acessa a gestão acadêmica com permissão de cursos e cargo de Diretoria.',53)
on conflict (code) do nothing;
insert into public.staff_position_permissions(position_id,permission_code,granted_by)
select position.id,'courses.academy.manage',coalesce(
  (select profile.user_id from public.profiles profile join public.staff_positions director on director.id=profile.position_id
    where profile.status='active' and director.official and director.level=14 order by profile.created_at limit 1),
  position.updated_by,position.created_by)
from public.staff_positions position where position.official and position.active and position.level between 12 and 14
on conflict(position_id,permission_code) do nothing;

create or replace function private.academy_require(p_actor uuid,p_permission text,p_director boolean default false)
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if p_actor is null or not private.has_permission(p_actor,p_permission)
    or (p_director and (not private.has_permission(p_actor,'courses.academy.manage') or not exists (
      select 1 from public.profiles profile join public.staff_positions position on position.id=profile.position_id
      where profile.user_id=p_actor and profile.status='active' and position.active and position.official
        and position.level between 12 and 14))) then
    raise exception 'Acesso não autorizado à Academia.' using errcode='42501';
  end if;
end $$;
revoke all on function private.academy_require(uuid,text,boolean) from public,anon,authenticated;

drop policy if exists courses_read_published_or_director on public.courses;
create policy courses_read_published_or_director on public.courses for select to authenticated
using ((status='published' and active and private.has_permission((select auth.uid()),'courses.study'))
  or (private.has_permission((select auth.uid()),'courses.manage')
    and private.has_permission((select auth.uid()),'courses.academy.manage')
    and private.current_position_level((select auth.uid())) between 12 and 14));

create or replace function private.hpsm_dashboard_config_valid(p_config jsonb)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_allowed_widgets constant text[] := array[
    'my_week', 'my_production', 'career', 'attention',
    'communications', 'shortcuts', 'hospital_overview'
  ];
  v_allowed_shortcuts constant text[] := array[
    'overview', 'new_attendance', 'attendances', 'patients', 'catalog',
    'exams', 'casts', 'academy', 'academy_management', 'consultations', 'hospitalizations', 'certificates', 'my_hr', 'administrative', 'pending', 'rh',
    'career', 'recruitment', 'partnerships', 'team', 'profiles', 'reports', 'records', 'audit',
    'communications'
  ];
  v_breakpoint text;
  v_cols integer;
  v_layout jsonb;
  v_count integer;
  v_unique_count integer;
  v_valid boolean;
begin
  if p_config is null
     or jsonb_typeof(p_config) <> 'object'
     or pg_column_size(p_config) > 32768
     or p_config - array['configVersion', 'layouts', 'hiddenWidgets', 'shortcuts'] <> '{}'::jsonb
     or not (p_config ?& array['configVersion', 'layouts', 'hiddenWidgets', 'shortcuts'])
     or p_config ->> 'configVersion' <> '1'
     or jsonb_typeof(p_config -> 'layouts') <> 'object'
     or jsonb_typeof(p_config -> 'hiddenWidgets') <> 'array'
     or jsonb_typeof(p_config -> 'shortcuts') <> 'array'
  then
    return false;
  end if;

  select count(*) into v_count from jsonb_object_keys(p_config -> 'layouts');
  if v_count <> 3
     or not (p_config -> 'layouts' ?& array['lg', 'md', 'sm'])
  then
    return false;
  end if;

  foreach v_breakpoint in array array['lg', 'md', 'sm'] loop
    v_cols := case v_breakpoint when 'lg' then 12 when 'md' then 8 else 1 end;
    v_layout := p_config -> 'layouts' -> v_breakpoint;
    if jsonb_typeof(v_layout) <> 'array' or jsonb_array_length(v_layout) <> 7 then
      return false;
    end if;

    select
      count(*),
      count(distinct item ->> 'i'),
      coalesce(bool_and(
        jsonb_typeof(item) = 'object'
        and item - array['i', 'x', 'y', 'w', 'h'] = '{}'::jsonb
        and item ?& array['i', 'x', 'y', 'w', 'h']
        and item ->> 'i' = any(v_allowed_widgets)
        and (item ->> 'x') ~ '^[0-9]+$'
        and (item ->> 'y') ~ '^[0-9]+$'
        and (item ->> 'w') ~ '^[0-9]+$'
        and (item ->> 'h') ~ '^[0-9]+$'
        and (item ->> 'x')::integer between 0 and v_cols - 1
        and (item ->> 'y')::integer between 0 and 240
        and (item ->> 'w')::integer between 1 and v_cols
        and (item ->> 'h')::integer between 4 and 40
        and (item ->> 'x')::integer + (item ->> 'w')::integer <= v_cols
      ), false)
    into v_count, v_unique_count, v_valid
    from jsonb_array_elements(v_layout) item;

    if v_count <> 7 or v_unique_count <> 7 or not v_valid then
      return false;
    end if;

    if exists (
      select 1
      from jsonb_array_elements(v_layout) with ordinality left_item(item, position)
      join jsonb_array_elements(v_layout) with ordinality right_item(item, position)
        on left_item.position < right_item.position
      where left_item.item ->> 'i' <> 'shortcuts'
        and right_item.item ->> 'i' <> 'shortcuts'
        and not (p_config -> 'hiddenWidgets' ? (left_item.item ->> 'i'))
        and not (p_config -> 'hiddenWidgets' ? (right_item.item ->> 'i'))
        and (left_item.item ->> 'x')::integer < (right_item.item ->> 'x')::integer + (right_item.item ->> 'w')::integer
        and (left_item.item ->> 'x')::integer + (left_item.item ->> 'w')::integer > (right_item.item ->> 'x')::integer
        and (left_item.item ->> 'y')::integer < (right_item.item ->> 'y')::integer + (right_item.item ->> 'h')::integer
        and (left_item.item ->> 'y')::integer + (left_item.item ->> 'h')::integer > (right_item.item ->> 'y')::integer
    ) then
      return false;
    end if;
  end loop;

  select count(*), count(distinct value), coalesce(bool_and(value = any(v_allowed_widgets)), false)
  into v_count, v_unique_count, v_valid
  from jsonb_array_elements_text(p_config -> 'hiddenWidgets') value;
  if v_count > 7 or v_count <> v_unique_count or (v_count > 0 and not v_valid) then
    return false;
  end if;

  select count(*), count(distinct value), coalesce(bool_and(value = any(v_allowed_shortcuts)), false)
  into v_count, v_unique_count, v_valid
  from jsonb_array_elements_text(p_config -> 'shortcuts') value;
  if v_count > 32 or v_count <> v_unique_count or (v_count > 0 and not v_valid) then
    return false;
  end if;

  return true;
exception
  when others then
    return false;
end;
$$;

revoke all on function private.hpsm_dashboard_config_valid(jsonb) from public, anon, authenticated;

comment on function private.hpsm_dashboard_config_valid(jsonb) is
  'Valida preferências v1 para a ordem de todos os módulos, preservando IDs legados e permissões na interface.';


create or replace function public.academy_read(
  p_view text, p_course_id bigint default null, p_ref_id bigint default null,
  p_page integer default 1, p_search text default ''
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_course public.courses;
  v_enrollment public.course_enrollments;
  v_attempt public.course_attempts;
  v_assessment public.course_assessments;
  v_page integer := greatest(1,least(coalesce(p_page,1),100000));
  v_reveal boolean;
  v_result jsonb;
begin
  if p_view in ('admin','admin_content','admin_results') then
    perform private.academy_require(v_actor,'courses.manage',true);
  else
    perform private.academy_require(v_actor,'courses.study');
  end if;
  if p_view = 'catalog' then
    select coalesce(jsonb_agg(x.payload order by x.sort_order,x.id),'[]'::jsonb) into v_result
    from (select c.id,c.sort_order,jsonb_build_object(
      'id',c.id,'slug',c.slug,'name',c.name,'short_description',c.short_description,
      'category',c.category,'cover_url',c.cover_url,'duration_minutes',c.duration_minutes,
      'required',c.required,'started_at',e.started_at,'completed_at',e.completed_at,
      'final_score',e.final_score,'passed',coalesce(e.passed,false),
      'lesson_count',(select count(*) from public.course_lessons l where l.course_id=c.id and l.active and l.required),
      'completed_lessons',(select count(*) from public.course_lesson_progress lp
        join public.course_lessons l on l.id=lp.lesson_id
        where lp.enrollment_id=e.id and l.active and l.required and lp.completed_at is not null),
      'assessment_enabled',coalesce(a.enabled,false)) as payload
    from public.courses c left join public.course_enrollments e on e.course_id=c.id and e.professional_id=v_actor
    left join public.course_assessments a on a.course_id=c.id
    where (c.status='published' and c.active) or (c.status='archived' and e.id is not null)
    order by c.sort_order,c.id limit 100) x;
    return jsonb_build_object('courses',v_result);
  end if;
  if p_view in ('admin','admin_results') then
    if p_view='admin' then
      select coalesce(jsonb_agg(x.payload order by x.sort_order,x.id),'[]'::jsonb) into v_result
      from (select c.id,c.sort_order,to_jsonb(c) || jsonb_build_object(
        'students',(select count(*) from public.course_enrollments e where e.course_id=c.id),
        'approved',(select count(*) from public.course_enrollments e where e.course_id=c.id and e.passed),
        'average_score',(select round(avg(e.final_score),1) from public.course_enrollments e where e.course_id=c.id and e.final_score is not null)) as payload
        from public.courses c order by c.sort_order,c.id limit 100 offset (v_page-1)*100) x;
      return jsonb_build_object('courses',v_result,'page',v_page,
        'total',(select count(*) from public.courses));
    end if;
    perform private.academy_require(v_actor,'courses.results.viewall',true);
    select coalesce(jsonb_agg(x.payload order by x.started_at desc,x.id desc),'[]'::jsonb) into v_result
    from (select e.id,e.started_at,to_jsonb(e) || jsonb_build_object(
      'professional_name',profile.display_name,'passport',profile.passport,'course_name',c.name,
      'attempt_count',(select count(*) from public.course_attempts t where t.enrollment_id=e.id),
      'original_score',(select t.score from public.course_attempts t where t.enrollment_id=e.id and t.status='submitted' order by t.submitted_at desc limit 1),
      'adjustments',(select count(*) from public.course_grade_adjustments g where g.enrollment_id=e.id)) as payload
      from public.course_enrollments e join public.profiles profile on profile.user_id=e.professional_id
      join public.courses c on c.id=e.course_id
      where (p_course_id is null or e.course_id=p_course_id)
      and (p_ref_id is null or (p_ref_id=1 and e.final_score is null)
        or (p_ref_id=2 and e.passed) or (p_ref_id=3 and e.final_score is not null and not e.passed))
      and (coalesce(btrim(p_search),'')='' or profile.display_name ilike '%'||left(btrim(p_search),80)||'%'
        or profile.passport ilike '%'||left(btrim(p_search),80)||'%' or c.name ilike '%'||left(btrim(p_search),80)||'%')
      order by e.started_at desc,e.id desc limit 20 offset (v_page-1)*20) x;
    return jsonb_build_object('results',v_result,'page',v_page,'total',(
      select count(*) from public.course_enrollments e join public.profiles profile on profile.user_id=e.professional_id
      join public.courses c on c.id=e.course_id
      where (p_course_id is null or e.course_id=p_course_id)
      and (p_ref_id is null or (p_ref_id=1 and e.final_score is null)
        or (p_ref_id=2 and e.passed) or (p_ref_id=3 and e.final_score is not null and not e.passed))
      and (coalesce(btrim(p_search),'')='' or profile.display_name ilike '%'||left(btrim(p_search),80)||'%'
        or profile.passport ilike '%'||left(btrim(p_search),80)||'%' or c.name ilike '%'||left(btrim(p_search),80)||'%')));
  end if;
  select * into v_course from public.courses where id=p_course_id;
  if not found then raise exception 'Curso não encontrado.'; end if;
  if p_view in ('admin_content') then
    select coalesce(jsonb_agg(to_jsonb(l) order by l.position,l.id),'[]'::jsonb) into v_result
    from public.course_lessons l where l.course_id=p_course_id;
    return jsonb_build_object('course',to_jsonb(v_course),'lessons',v_result,
      'assessment',(select to_jsonb(a) from public.course_assessments a where a.course_id=p_course_id),
      'questions',coalesce((select jsonb_agg(to_jsonb(q) || jsonb_build_object(
        'options',(select coalesce(jsonb_agg(to_jsonb(o) order by o.position,o.id),'[]'::jsonb)
          from public.course_question_options o where o.question_id=q.id)) order by q.position,q.id)
        from (select * from public.course_questions where course_id=p_course_id order by position,id limit 25 offset (v_page-1)*25) q),'[]'::jsonb),
      'question_total',(select count(*) from public.course_questions q where q.course_id=p_course_id),
      'page',v_page);
  end if;
  select * into v_enrollment from public.course_enrollments
  where course_id=p_course_id and professional_id=v_actor;
  if (v_course.status <> 'published' or not v_course.active)
    and not (v_course.status='archived' and v_enrollment.id is not null) then
    perform private.academy_require(v_actor,'courses.manage',true);
  end if;
  select * into v_assessment from public.course_assessments where course_id=p_course_id;
  if p_view='course' then
    select coalesce(jsonb_agg(to_jsonb(l)-'body'-'video_url'-'image_url'-'material_url' order by l.position,l.id),'[]'::jsonb) into v_result
    from public.course_lessons l where l.course_id=p_course_id and l.active;
    return jsonb_build_object('course',to_jsonb(v_course),'lessons',v_result,
      'enrollment',case when v_enrollment.id is null then null else to_jsonb(v_enrollment) end,
      'progress',coalesce((select jsonb_agg(jsonb_build_object('lesson_id',lp.lesson_id,'started_at',lp.started_at,'completed_at',lp.completed_at))
        from public.course_lesson_progress lp where lp.enrollment_id=v_enrollment.id),'[]'::jsonb),
      'assessment',case when v_assessment.id is null then null else to_jsonb(v_assessment) end,
      'attempts',coalesce((select jsonb_agg(to_jsonb(t) order by t.attempt_number desc)
        from public.course_attempts t where t.enrollment_id=v_enrollment.id),'[]'::jsonb));
  end if;
  if p_view='lesson' then
    if v_enrollment.id is null then raise exception 'Inicie o curso antes de estudar.' using errcode='42501'; end if;
    select to_jsonb(l) into v_result from public.course_lessons l
    where l.id=p_ref_id and l.course_id=p_course_id and l.active;
    if v_result is null then raise exception 'Aula não encontrada.'; end if;
    return jsonb_build_object('lesson',v_result);
  end if;
  if p_view='attempt' then
    perform private.academy_require(v_actor,'courses.takeexam');
    if v_enrollment.id is null then raise exception 'Tentativa não encontrada.' using errcode='42501'; end if;
    select * into v_attempt from public.course_attempts where id=p_ref_id and enrollment_id=v_enrollment.id;
    if not found then raise exception 'Tentativa não encontrada.'; end if;
    v_reveal := v_attempt.status='submitted' and (
      v_assessment.reveal_policy='immediate' or v_attempt.passed or
      (select count(*) from public.course_attempts t where t.enrollment_id=v_enrollment.id) >= v_assessment.max_attempts+v_enrollment.extra_attempts);
    select coalesce(jsonb_agg(jsonb_build_object(
      'id',item.id,'position',item.position,'body',item.question_body,'kind',item.kind,
      'options',item.options,'selected_option_id',answer.selected_option_id,
      'is_correct',case when v_attempt.status='submitted' then answer.is_correct else null end,
      'correct_option_id',case when v_reveal then item.correct_option_id else null end,
      'explanation',case when v_reveal then item.explanation else null end
      ) order by item.position),'[]'::jsonb) into v_result
    from public.course_attempt_items item left join public.course_attempt_answers answer on answer.item_id=item.id
    where item.attempt_id=v_attempt.id;
    return jsonb_build_object('attempt',to_jsonb(v_attempt),'items',v_result,'answers_revealed',v_reveal);
  end if;
  raise exception 'Consulta da Academia inválida.';
end $$;
revoke all on function public.academy_read(text,bigint,bigint,integer,text) from public,anon,authenticated,service_role;
grant execute on function public.academy_read(text,bigint,bigint,integer,text) to authenticated;


create or replace function public.academy_study(p_action text,p_payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_course public.courses;
  v_enrollment public.course_enrollments;
  v_lesson public.course_lessons;
  v_assessment public.course_assessments;
  v_attempt public.course_attempts;
  v_item public.course_attempt_items;
  v_question public.course_questions;
  v_options jsonb;
  v_correct bigint;
  v_position integer := 0;
  v_selected bigint;
  v_weight numeric;
  v_earned numeric;
  v_score numeric;
  v_passed boolean;
  v_remaining integer;
  v_new_enrollment boolean := false;
begin
  perform private.academy_require(v_actor,'courses.study');
  select * into v_course from public.courses where id=(p_payload->>'course_id')::bigint
    and status='published' and active;
  if not found then raise exception 'Curso indisponível.'; end if;
  if p_action='enroll' then
    insert into public.course_enrollments(course_id,professional_id) values(v_course.id,v_actor)
      on conflict (course_id,professional_id) do nothing returning * into v_enrollment;
    v_new_enrollment := found;
    select * into v_enrollment from public.course_enrollments where course_id=v_course.id and professional_id=v_actor;
    if v_new_enrollment then
      perform private.academy_audit(v_actor,'COURSE_STARTED','course_enrollments',v_enrollment.id,null,jsonb_build_object('course_id',v_course.id));
    end if;
    return to_jsonb(v_enrollment);
  end if;
  select * into v_enrollment from public.course_enrollments
    where course_id=v_course.id and professional_id=v_actor for update;
  if not found then raise exception 'Inicie o curso antes de continuar.' using errcode='42501'; end if;
  if p_action in ('lesson_start','lesson_complete') then
    select * into v_lesson from public.course_lessons where id=(p_payload->>'lesson_id')::bigint
      and course_id=v_course.id and active;
    if not found then raise exception 'Aula não encontrada.'; end if;
    insert into public.course_lesson_progress(enrollment_id,lesson_id,completed_at)
      values(v_enrollment.id,v_lesson.id,case when p_action='lesson_complete' then now() else null end)
    on conflict (enrollment_id,lesson_id) do update set
      completed_at=case when p_action='lesson_complete' then coalesce(public.course_lesson_progress.completed_at,now())
        else public.course_lesson_progress.completed_at end;
    if p_action='lesson_complete' then
      perform private.academy_audit(v_actor,'LESSON_COMPLETED','course_lesson_progress',v_lesson.id,null,
        jsonb_build_object('course_id',v_course.id,'enrollment_id',v_enrollment.id));
      select * into v_assessment from public.course_assessments where course_id=v_course.id;
      if not coalesce(v_assessment.enabled,false) and not v_enrollment.passed and not exists (
        select 1 from public.course_lessons l where l.course_id=v_course.id and l.active and l.required
        and not exists(select 1 from public.course_lesson_progress lp where lp.enrollment_id=v_enrollment.id
          and lp.lesson_id=l.id and lp.completed_at is not null)) then
        update public.course_enrollments set passed=true,completed_at=now() where id=v_enrollment.id;
        perform private.academy_audit(v_actor,'COURSE_COMPLETED','course_enrollments',v_enrollment.id,null,
          jsonb_build_object('course_id',v_course.id,'without_assessment',true));
      end if;
    end if;
    return jsonb_build_object('lesson_id',v_lesson.id,'completed',p_action='lesson_complete');
  end if;
  perform private.academy_require(v_actor,'courses.takeexam');
  select * into v_assessment from public.course_assessments where course_id=v_course.id and enabled;
  if not found then raise exception 'Este curso não possui avaliação disponível.'; end if;
  if p_action='attempt_start' then
    if v_enrollment.passed then raise exception 'Você já concluiu este curso.'; end if;
    if exists(select 1 from public.course_lessons l where l.course_id=v_course.id and l.active and l.required
      and not exists(select 1 from public.course_lesson_progress lp where lp.enrollment_id=v_enrollment.id
        and lp.lesson_id=l.id and lp.completed_at is not null)) then
      raise exception 'Conclua as aulas obrigatórias para liberar a avaliação.';
    end if;
    select * into v_attempt from public.course_attempts where enrollment_id=v_enrollment.id and status='in_progress';
    if found then return jsonb_build_object('attempt_id',v_attempt.id,'existing',true); end if;
    select count(*) into v_remaining from public.course_attempts where enrollment_id=v_enrollment.id;
    if v_remaining >= v_assessment.max_attempts+v_enrollment.extra_attempts then raise exception 'Limite de tentativas atingido.'; end if;
    if (select count(*) from public.course_questions where course_id=v_course.id and active) < v_assessment.question_count then
      raise exception 'Banco de questões insuficiente. A Diretoria deve revisar a prova.'; end if;
    insert into public.course_attempts(enrollment_id,assessment_id,attempt_number,passing_score_snapshot)
      values(v_enrollment.id,v_assessment.id,v_remaining+1,v_assessment.passing_score) returning * into v_attempt;
    for v_question in select * from public.course_questions q where q.course_id=v_course.id and q.active
      order by case when v_assessment.shuffle_questions then random() else q.position::double precision end,q.id
      limit v_assessment.question_count loop
      select jsonb_agg(jsonb_build_object('id',o.id,'label',o.label)
        order by case when v_assessment.shuffle_options then random() else o.position::double precision end,o.id),
        max(o.id) filter (where o.correct) into v_options,v_correct
      from public.course_question_options o where o.question_id=v_question.id;
      if v_options is null or jsonb_array_length(v_options)<2 or v_correct is null then
        raise exception 'Questão incompleta. A Diretoria deve revisar o banco.'; end if;
      v_position:=v_position+1;
      insert into public.course_attempt_items(attempt_id,question_id,position,question_body,kind,explanation,options,correct_option_id,weight)
        values(v_attempt.id,v_question.id,v_position,v_question.body,v_question.kind,v_question.explanation,v_options,v_correct,v_question.weight);
    end loop;
    perform private.academy_audit(v_actor,'ASSESSMENT_STARTED','course_attempts',v_attempt.id,null,
      jsonb_build_object('course_id',v_course.id,'attempt_number',v_attempt.attempt_number));
    return jsonb_build_object('attempt_id',v_attempt.id,'existing',false);
  end if;
  select * into v_attempt from public.course_attempts where id=(p_payload->>'attempt_id')::bigint
    and enrollment_id=v_enrollment.id for update;
  if not found then raise exception 'Tentativa não encontrada.'; end if;
  if v_attempt.status<>'in_progress' then raise exception 'Esta tentativa já foi enviada.'; end if;
  if p_action='attempt_save' then
    select * into v_item from public.course_attempt_items where id=(p_payload->>'item_id')::bigint
      and attempt_id=v_attempt.id;
    if not found then raise exception 'Questão não pertence à prova.'; end if;
    v_selected:=(p_payload->>'option_id')::bigint;
    if not exists(select 1 from jsonb_array_elements(v_item.options) option where (option->>'id')::bigint=v_selected) then
      raise exception 'Alternativa inválida.'; end if;
    insert into public.course_attempt_answers(item_id,selected_option_id) values(v_item.id,v_selected)
      on conflict (item_id) do update set selected_option_id=excluded.selected_option_id,
        is_correct=null,points=null,updated_at=now();
    return jsonb_build_object('saved',true,'item_id',v_item.id);
  end if;
  if p_action='attempt_submit' then
    update public.course_attempt_answers answer set is_correct=answer.selected_option_id=item.correct_option_id,
      points=case when answer.selected_option_id=item.correct_option_id then item.weight else 0 end
    from public.course_attempt_items item where item.id=answer.item_id and item.attempt_id=v_attempt.id;
    select sum(item.weight),coalesce(sum(case when answer.is_correct then item.weight else 0 end),0)
      into v_weight,v_earned from public.course_attempt_items item
      left join public.course_attempt_answers answer on answer.item_id=item.id where item.attempt_id=v_attempt.id;
    v_score:=round(100*v_earned/nullif(v_weight,0),2);
    if v_score is null then raise exception 'A prova não possui questões válidas.'; end if;
    v_passed:=v_score>=v_attempt.passing_score_snapshot;
    update public.course_attempts set status='submitted',submitted_at=now(),score=v_score,passed=v_passed where id=v_attempt.id;
    update public.course_enrollments set final_score=v_score,passed=v_passed,
      completed_at=case when v_passed then now() else null end,
      approved_attempt_id=case when v_passed then v_attempt.id else null end
      where id=v_enrollment.id;
    perform private.academy_audit(v_actor,'ASSESSMENT_SUBMITTED','course_attempts',v_attempt.id,null,
      jsonb_build_object('course_id',v_course.id,'score',v_score,'passed',v_passed));
    perform private.academy_audit(v_actor,case when v_passed then 'COURSE_COMPLETED' else 'COURSE_FAILED' end,
      'course_enrollments',v_enrollment.id,null,jsonb_build_object('course_id',v_course.id,'attempt_id',v_attempt.id));
    return jsonb_build_object('attempt_id',v_attempt.id,'score',v_score,'passed',v_passed);
  end if;
  raise exception 'Ação de estudo inválida.';
end $$;
revoke all on function public.academy_study(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.academy_study(text,jsonb) to authenticated;
