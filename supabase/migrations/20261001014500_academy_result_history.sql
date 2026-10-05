-- Histórico detalhado da matrícula, disponível apenas à Diretoria autorizada.
set lock_timeout = '5s';
set statement_timeout = '40s';
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
  if p_view in ('admin','admin_content','admin_results','admin_result') then
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
  if p_view='admin_result' then
    perform private.academy_require(v_actor,'courses.results.viewall',true);
    select * into v_enrollment from public.course_enrollments where id=p_ref_id;
    if not found then raise exception 'Matrícula não encontrada.'; end if;
    return jsonb_build_object('enrollment',to_jsonb(v_enrollment),
      'attempts',coalesce((select jsonb_agg(to_jsonb(t) order by t.attempt_number)
        from public.course_attempts t where t.enrollment_id=v_enrollment.id),'[]'::jsonb),
      'grade_history',coalesce((select jsonb_agg(to_jsonb(g) order by g.adjusted_at)
        from public.course_grade_adjustments g where g.enrollment_id=v_enrollment.id),'[]'::jsonb),
      'extra_attempts',coalesce((select jsonb_agg(to_jsonb(g) order by g.granted_at)
        from public.course_extra_attempt_grants g where g.enrollment_id=v_enrollment.id),'[]'::jsonb));
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

