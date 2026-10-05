-- Execute through Supabase SQL, then roll back every fixture.
begin;
do $$
declare
  v_director uuid; v_director_session uuid; v_doctor uuid; v_doctor_session uuid;
  v_course bigint; v_lesson bigint; v_attempt bigint; v_second bigint; v_item bigint;
  v_wrong bigint; v_correct bigint; v_enrollment bigint; v_result jsonb;
begin
  select p.user_id,s.id into v_director,v_director_session from public.profiles p
    join public.staff_positions sp on sp.id=p.position_id join auth.sessions s on s.user_id=p.user_id
    where p.status='active' and not p.must_change_password and sp.official and sp.level between 12 and 14
      and (s.not_after is null or s.not_after>now()) order by s.created_at desc limit 1;
  select p.user_id,s.id into v_doctor,v_doctor_session from public.profiles p
    join public.staff_positions sp on sp.id=p.position_id join auth.sessions s on s.user_id=p.user_id
    where p.status='active' and not p.must_change_password and sp.official and sp.level between 7 and 10
      and (s.not_after is null or s.not_after>now()) order by s.created_at desc limit 1;
  if v_director is null or v_doctor is null then raise exception 'Academy test needs active director and doctor sessions'; end if;
  perform set_config('request.jwt.claim.sub',v_director::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_director,'session_id',v_director_session,'role','authenticated')::text,true);
  v_result:=public.academy_manage('create_course',jsonb_build_object('name','QA Academia '||left(gen_random_uuid()::text,8),'category','Medicina'));
  v_course:=(v_result->>'id')::bigint;
  v_result:=public.academy_manage('save_lesson',jsonb_build_object('course_id',v_course,'title','Aula de teste','body','# Introdução','required',true));
  v_lesson:=(v_result->>'id')::bigint;
  perform public.academy_manage('save_question',jsonb_build_object('course_id',v_course,'body','Qual alternativa está correta?',
    'kind','multiple_choice','options',jsonb_build_array(jsonb_build_object('label','Correta','correct',true),jsonb_build_object('label','Errada','correct',false))));
  perform public.academy_manage('save_assessment',jsonb_build_object('course_id',v_course,'enabled',true,'question_count',1,'max_attempts',1,'passing_score',70));
  perform set_config('request.jwt.claim.sub',v_doctor::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_doctor,'session_id',v_doctor_session,'role','authenticated')::text,true);
  if public.academy_read('catalog')->'courses' @> jsonb_build_array(jsonb_build_object('id',v_course)) then raise exception 'Draft visible'; end if;
  begin
    perform public.academy_read('course',v_course);
    raise exception 'Draft opened by doctor';
  exception when insufficient_privilege then null; end;
  begin
    perform public.academy_manage('publish',jsonb_build_object('course_id',v_course));
    raise exception 'Doctor managed course';
  exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claim.sub',v_director::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_director,'session_id',v_director_session,'role','authenticated')::text,true);
  perform public.academy_manage('publish',jsonb_build_object('course_id',v_course));
  perform set_config('request.jwt.claim.sub',v_doctor::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_doctor,'session_id',v_doctor_session,'role','authenticated')::text,true);
  if not (public.academy_read('catalog')->'courses' @> jsonb_build_array(jsonb_build_object('id',v_course))) then raise exception 'Published course missing'; end if;
  v_result:=public.academy_study('enroll',jsonb_build_object('course_id',v_course)); v_enrollment:=(v_result->>'id')::bigint;
  perform public.academy_study('enroll',jsonb_build_object('course_id',v_course));
  if (select count(*) from public.course_enrollments where course_id=v_course)<>1 then raise exception 'Duplicate enrollment'; end if;
  perform public.academy_study('lesson_complete',jsonb_build_object('course_id',v_course,'lesson_id',v_lesson));
  v_result:=public.academy_study('attempt_start',jsonb_build_object('course_id',v_course)); v_attempt:=(v_result->>'attempt_id')::bigint;
  if (public.academy_study('attempt_start',jsonb_build_object('course_id',v_course))->>'attempt_id')::bigint<>v_attempt then raise exception 'Start not idempotent'; end if;
  v_result:=public.academy_read('attempt',v_course,v_attempt);
  if (v_result->'items'->0->>'correct_option_id') is not null then raise exception 'Gabarito vazou'; end if;
  select item.id,item.correct_option_id,(select (option->>'id')::bigint from jsonb_array_elements(item.options) option
    where (option->>'id')::bigint<>item.correct_option_id limit 1) into v_item,v_correct,v_wrong
  from public.course_attempt_items item where item.attempt_id=v_attempt;
  perform public.academy_study('attempt_save',jsonb_build_object('course_id',v_course,'attempt_id',v_attempt,'item_id',v_item,'option_id',v_wrong));
  v_result:=public.academy_study('attempt_submit',jsonb_build_object('course_id',v_course,'attempt_id',v_attempt));
  if (v_result->>'score')::numeric<>0 or (v_result->>'passed')::boolean then raise exception 'Falha não corrigida'; end if;
  begin
    perform public.academy_study('attempt_submit',jsonb_build_object('course_id',v_course,'attempt_id',v_attempt));
    raise exception 'Double submission accepted';
  exception when others then if sqlerrm='Double submission accepted' then raise; end if; end;
  begin
    perform public.academy_study('attempt_start',jsonb_build_object('course_id',v_course));
    raise exception 'Attempt limit bypassed';
  exception when others then if sqlerrm='Attempt limit bypassed' then raise; end if; end;
  begin
    perform public.academy_read('admin_results');
    raise exception 'Doctor read team grades';
  exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claim.sub',v_director::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_director,'session_id',v_director_session,'role','authenticated')::text,true);
  perform public.academy_manage('grant_attempt',jsonb_build_object('enrollment_id',v_enrollment,'reason','Problema técnico durante a primeira prova.'));
  perform set_config('request.jwt.claim.sub',v_doctor::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_doctor,'session_id',v_doctor_session,'role','authenticated')::text,true);
  v_result:=public.academy_study('attempt_start',jsonb_build_object('course_id',v_course)); v_second:=(v_result->>'attempt_id')::bigint;
  select id,correct_option_id into v_item,v_correct from public.course_attempt_items where attempt_id=v_second;
  perform public.academy_study('attempt_save',jsonb_build_object('course_id',v_course,'attempt_id',v_second,'item_id',v_item,'option_id',v_correct));
  v_result:=public.academy_study('attempt_submit',jsonb_build_object('course_id',v_course,'attempt_id',v_second));
  if (v_result->>'score')::numeric<>100 or not (v_result->>'passed')::boolean then raise exception 'Approval incorrect'; end if;
  perform set_config('request.jwt.claim.sub',v_director::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_director,'session_id',v_director_session,'role','authenticated')::text,true);
  perform public.academy_manage('override_grade',jsonb_build_object('enrollment_id',v_enrollment,'score',50,'reason','Revisão administrativa da nota original.'));
  perform public.academy_manage('override_grade',jsonb_build_object('enrollment_id',v_enrollment,'score',80,'reason','Retificação autorizada pela diretoria.'));
  v_result:=public.academy_read('admin_result',null,v_enrollment);
  if jsonb_array_length(v_result->'grade_history')<>2 or jsonb_array_length(v_result->'extra_attempts')<>1
    or (select score from public.course_attempts where id=v_second)<>100 then raise exception 'Original grade/history lost'; end if;
end $$;
rollback;
