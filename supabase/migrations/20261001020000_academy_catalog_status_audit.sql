-- Exibe arquivados no histórico próprio e audita a transição real de estado.
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
      'id',c.id,'slug',c.slug,'name',c.name,'status',c.status,'short_description',c.short_description,
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


create or replace function public.academy_manage(p_action text,p_payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_course public.courses;
  v_lesson public.course_lessons;
  v_question public.course_questions;
  v_assessment public.course_assessments;
  v_enrollment public.course_enrollments;
  v_option jsonb;
  v_correct integer := 0;
  v_total integer := 0;
  v_score numeric;
  v_original numeric;
  v_reason text;
  v_old_status text;
  v_id bigint;
begin
  if p_action in ('override_grade','grant_attempt') then
    perform private.academy_require(v_actor,case when p_action='override_grade' then 'courses.results.manage' else 'courses.attempts.reopen' end,true);
    select * into v_enrollment from public.course_enrollments where id=(p_payload->>'enrollment_id')::bigint for update;
    if not found then raise exception 'Matrícula não encontrada.'; end if;
    v_reason := btrim(coalesce(p_payload->>'reason',''));
    if char_length(v_reason) not between 10 and 1000 then raise exception 'Informe um motivo com pelo menos dez caracteres.'; end if;
    select * into v_course from public.courses where id=v_enrollment.course_id;
    if p_action='grant_attempt' then
      if v_enrollment.passed then raise exception 'O curso já foi aprovado.'; end if;
      insert into public.course_extra_attempt_grants(enrollment_id,reason,granted_by) values(v_enrollment.id,v_reason,v_actor) returning id into v_id;
      update public.course_enrollments set extra_attempts=extra_attempts+1 where id=v_enrollment.id;
      perform private.academy_audit(v_actor,'EXTRA_ATTEMPT_GRANTED','course_enrollments',v_enrollment.id,null,
        jsonb_build_object('grant_id',v_id,'reason',v_reason));
      return jsonb_build_object('id',v_enrollment.id,'extra_attempts',v_enrollment.extra_attempts+1);
    end if;
    v_score := (p_payload->>'score')::numeric;
    if v_score is null or v_score < 0 or v_score > 100 then raise exception 'Nota deve estar entre 0 e 100.'; end if;
    if not exists(select 1 from public.course_attempts where enrollment_id=v_enrollment.id and status='submitted') then
      raise exception 'Ainda não existe uma prova corrigida para ajustar.';
    end if;
    select t.score into v_original from public.course_attempts t where t.enrollment_id=v_enrollment.id and t.status='submitted'
      order by t.submitted_at desc limit 1;
    select * into v_assessment from public.course_assessments where course_id=v_enrollment.course_id;
    insert into public.course_grade_adjustments(enrollment_id,original_score,previous_score,adjusted_score,reason,adjusted_by)
      values(v_enrollment.id,v_original,v_enrollment.final_score,v_score,v_reason,v_actor) returning id into v_id;
    update public.course_enrollments set final_score=v_score,
      passed=v_score>=v_assessment.passing_score,
      completed_at=case when v_score>=v_assessment.passing_score then coalesce(completed_at,now()) else null end,
      approved_attempt_id=case when v_score>=v_assessment.passing_score then
        (select id from public.course_attempts where enrollment_id=v_enrollment.id and status='submitted' order by submitted_at desc limit 1)
        else null end
      where id=v_enrollment.id;
    perform private.academy_audit(v_actor,'GRADE_OVERRIDDEN','course_enrollments',v_enrollment.id,
      jsonb_build_object('score',v_enrollment.final_score,'passed',v_enrollment.passed),
      jsonb_build_object('original_score',v_original,'adjusted_score',v_score,'reason',v_reason,'adjustment_id',v_id));
    return jsonb_build_object('id',v_enrollment.id,'final_score',v_score,'passed',v_score>=v_assessment.passing_score);
  end if;
  perform private.academy_require(v_actor,'courses.manage',true);
  if p_action='create_course' then
    insert into public.courses(name,description,short_description,category,cover_url,duration_minutes,sort_order,
      required,created_by,updated_by,status,active)
    values(btrim(p_payload->>'name'),coalesce(p_payload->>'description',''),coalesce(p_payload->>'short_description',''),
      coalesce(nullif(btrim(p_payload->>'category'),''),'Institucional'),nullif(btrim(p_payload->>'cover_url'),''),
      coalesce((p_payload->>'duration_minutes')::integer,0),coalesce((p_payload->>'sort_order')::integer,0),
      coalesce((p_payload->>'required')::boolean,false),v_actor,v_actor,'draft',true)
    returning * into v_course;
    update public.courses set slug=left(trim(both '-' from regexp_replace(lower(v_course.name),'[^a-z0-9]+','-','g')),100)||'-'||v_course.id
      where id=v_course.id returning * into v_course;
    insert into public.course_assessments(course_id) values(v_course.id);
    perform private.academy_audit(v_actor,'COURSE_CREATED','courses',v_course.id,null,jsonb_build_object('name',v_course.name));
    return to_jsonb(v_course);
  end if;
  select * into v_course from public.courses where id=(p_payload->>'course_id')::bigint for update;
  if not found then raise exception 'Curso não encontrado.'; end if;
  if p_action='update_course' then
    update public.courses set name=btrim(p_payload->>'name'),description=coalesce(p_payload->>'description',''),
      short_description=coalesce(p_payload->>'short_description',''),
      category=coalesce(nullif(btrim(p_payload->>'category'),''),'Institucional'),
      cover_url=nullif(btrim(p_payload->>'cover_url'),''),duration_minutes=coalesce((p_payload->>'duration_minutes')::integer,0),
      sort_order=coalesce((p_payload->>'sort_order')::integer,0),required=coalesce((p_payload->>'required')::boolean,false),
      updated_by=v_actor,updated_at=now() where id=v_course.id returning * into v_course;
    perform private.academy_audit(v_actor,'COURSE_UPDATED','courses',v_course.id,null,jsonb_build_object('name',v_course.name));
    return to_jsonb(v_course);
  end if;
  if p_action in ('publish','unpublish','archive') then
    v_old_status := v_course.status;
    if p_action='publish' then
      if not exists(select 1 from public.course_lessons where course_id=v_course.id and active and required) then
        raise exception 'Inclua ao menos uma aula obrigatória antes de publicar.'; end if;
      select * into v_assessment from public.course_assessments where course_id=v_course.id;
      if coalesce(v_assessment.enabled,false) and
        (select count(*) from public.course_questions where course_id=v_course.id and active) < v_assessment.question_count then
        raise exception 'O banco de questões não cobre a prova configurada.'; end if;
    end if;
    update public.courses set status=case p_action when 'publish' then 'published' when 'archive' then 'archived' else 'draft' end,
      active=p_action='publish',published_at=case when p_action='publish' then coalesce(published_at,now()) else published_at end,
      updated_by=v_actor,updated_at=now() where id=v_course.id returning * into v_course;
    perform private.academy_audit(v_actor,case p_action when 'publish' then 'COURSE_PUBLISHED' when 'archive' then 'COURSE_ARCHIVED' else 'COURSE_UNPUBLISHED' end,
      'courses',v_course.id,jsonb_build_object('status',v_old_status),jsonb_build_object('status',v_course.status));
    return to_jsonb(v_course);
  end if;
  if p_action='save_lesson' then
    if nullif(p_payload->>'lesson_id','') is not null then
      select * into v_lesson from public.course_lessons where id=(p_payload->>'lesson_id')::bigint and course_id=v_course.id;
      if not found then raise exception 'Aula não encontrada.'; end if;
      update public.course_lessons set title=btrim(p_payload->>'title'),description=coalesce(p_payload->>'description',''),
        body=coalesce(p_payload->>'body',''),content_type=coalesce(p_payload->>'content_type','text'),
        video_url=nullif(btrim(p_payload->>'video_url'),''),image_url=nullif(btrim(p_payload->>'image_url'),''),
        material_url=nullif(btrim(p_payload->>'material_url'),''),duration_minutes=coalesce((p_payload->>'duration_minutes')::integer,0),
        position=coalesce((p_payload->>'position')::integer,0),required=coalesce((p_payload->>'required')::boolean,true),
        active=coalesce((p_payload->>'active')::boolean,true),updated_at=now()
      where id=v_lesson.id returning * into v_lesson;
      perform private.academy_audit(v_actor,'LESSON_UPDATED','course_lessons',v_lesson.id,null,jsonb_build_object('course_id',v_course.id));
    else
      insert into public.course_lessons(course_id,title,description,body,content_type,video_url,image_url,material_url,duration_minutes,position,required)
      values(v_course.id,btrim(p_payload->>'title'),coalesce(p_payload->>'description',''),coalesce(p_payload->>'body',''),
        coalesce(p_payload->>'content_type','text'),nullif(btrim(p_payload->>'video_url'),''),nullif(btrim(p_payload->>'image_url'),''),
        nullif(btrim(p_payload->>'material_url'),''),coalesce((p_payload->>'duration_minutes')::integer,0),
        coalesce((p_payload->>'position')::integer,0),coalesce((p_payload->>'required')::boolean,true)) returning * into v_lesson;
      perform private.academy_audit(v_actor,'LESSON_CREATED','course_lessons',v_lesson.id,null,jsonb_build_object('course_id',v_course.id));
    end if;
    return to_jsonb(v_lesson);
  end if;
  if p_action='remove_lesson' then
    update public.course_lessons set active=false,updated_at=now() where id=(p_payload->>'lesson_id')::bigint and course_id=v_course.id returning * into v_lesson;
    if not found then raise exception 'Aula não encontrada.'; end if;
    perform private.academy_audit(v_actor,'LESSON_REMOVED','course_lessons',v_lesson.id,null,jsonb_build_object('course_id',v_course.id));
    return to_jsonb(v_lesson);
  end if;
  if p_action='save_assessment' then
    insert into public.course_assessments(course_id,enabled,question_count,passing_score,max_attempts,shuffle_questions,shuffle_options,reveal_policy)
      values(v_course.id,coalesce((p_payload->>'enabled')::boolean,false),coalesce((p_payload->>'question_count')::integer,5),
        coalesce((p_payload->>'passing_score')::numeric,70),coalesce((p_payload->>'max_attempts')::integer,3),
        coalesce((p_payload->>'shuffle_questions')::boolean,true),coalesce((p_payload->>'shuffle_options')::boolean,true),
        coalesce(p_payload->>'reveal_policy','after_final'))
    on conflict (course_id) do update set enabled=excluded.enabled,question_count=excluded.question_count,
      passing_score=excluded.passing_score,max_attempts=excluded.max_attempts,shuffle_questions=excluded.shuffle_questions,
      shuffle_options=excluded.shuffle_options,reveal_policy=excluded.reveal_policy,updated_at=now()
    returning * into v_assessment;
    perform private.academy_audit(v_actor,'ASSESSMENT_UPDATED','course_assessments',v_assessment.id,null,
      jsonb_build_object('course_id',v_course.id,'enabled',v_assessment.enabled,'passing_score',v_assessment.passing_score));
    return to_jsonb(v_assessment);
  end if;
  if p_action='save_question' then
    if jsonb_typeof(p_payload->'options') <> 'array' then raise exception 'Informe as alternativas.'; end if;
    v_total := jsonb_array_length(p_payload->'options');
    if v_total < 2 or v_total > 8 or (p_payload->>'kind'='true_false' and v_total<>2) then
      raise exception 'Informe de duas a oito alternativas (duas para verdadeiro/falso).'; end if;
    for v_option in select value from jsonb_array_elements(p_payload->'options') loop
      if char_length(btrim(coalesce(v_option->>'label',''))) not between 1 and 500 then raise exception 'Alternativa inválida.'; end if;
      if coalesce((v_option->>'correct')::boolean,false) then v_correct:=v_correct+1; end if;
    end loop;
    if v_correct<>1 then raise exception 'Marque exatamente uma resposta correta.'; end if;
    if nullif(p_payload->>'question_id','') is not null then
      select * into v_question from public.course_questions where id=(p_payload->>'question_id')::bigint and course_id=v_course.id;
      if not found then raise exception 'Questão não encontrada.'; end if;
      update public.course_questions set body=btrim(p_payload->>'body'),kind=p_payload->>'kind',
        explanation=coalesce(p_payload->>'explanation',''),weight=coalesce((p_payload->>'weight')::numeric,1),
        position=coalesce((p_payload->>'position')::integer,0),active=true,updated_at=now()
      where id=v_question.id returning * into v_question;
      delete from public.course_question_options where question_id=v_question.id;
      perform private.academy_audit(v_actor,'QUESTION_UPDATED','course_questions',v_question.id,null,jsonb_build_object('course_id',v_course.id));
    else
      insert into public.course_questions(course_id,body,kind,explanation,weight,position)
      values(v_course.id,btrim(p_payload->>'body'),p_payload->>'kind',coalesce(p_payload->>'explanation',''),
        coalesce((p_payload->>'weight')::numeric,1),coalesce((p_payload->>'position')::integer,0)) returning * into v_question;
      perform private.academy_audit(v_actor,'QUESTION_CREATED','course_questions',v_question.id,null,jsonb_build_object('course_id',v_course.id));
    end if;
    v_total:=0;
    for v_option in select value from jsonb_array_elements(p_payload->'options') loop
      v_total:=v_total+1;
      insert into public.course_question_options(question_id,label,correct,position)
      values(v_question.id,btrim(v_option->>'label'),coalesce((v_option->>'correct')::boolean,false),v_total);
    end loop;
    return to_jsonb(v_question);
  end if;
  if p_action='remove_question' then
    update public.course_questions set active=false,updated_at=now()
      where id=(p_payload->>'question_id')::bigint and course_id=v_course.id returning * into v_question;
    if not found then raise exception 'Questão não encontrada.'; end if;
    perform private.academy_audit(v_actor,'QUESTION_REMOVED','course_questions',v_question.id,null,jsonb_build_object('course_id',v_course.id));
    return to_jsonb(v_question);
  end if;
  raise exception 'Ação administrativa inválida.';
end $$;
revoke all on function public.academy_manage(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.academy_manage(text,jsonb) to authenticated;

