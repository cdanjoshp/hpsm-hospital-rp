-- Academia HPSM: preserva o cadastro legado de cursos e seus registros de carreira.
set lock_timeout = '5s';
set statement_timeout = '40s';

insert into public.system_permissions (code, module, label, description, sort_order) values
  ('courses.study', 'Formação', 'Estudar na Academia', 'Iniciar cursos publicados e concluir aulas.', 47),
  ('courses.takeexam', 'Formação', 'Realizar avaliações', 'Responder avaliações da própria matrícula.', 48),
  ('courses.results.viewown', 'Formação', 'Minhas notas', 'Consultar o próprio histórico acadêmico.', 49),
  ('courses.results.viewall', 'Formação', 'Resultados da Academia', 'Consultar resultados da equipe.', 50),
  ('courses.results.manage', 'Formação', 'Ajustar notas', 'Ajustar notas com motivo e histórico.', 51),
  ('courses.attempts.reopen', 'Formação', 'Liberar tentativas', 'Conceder tentativa adicional com justificativa.', 52)
on conflict (code) do nothing;

insert into public.staff_position_permissions (position_id, permission_code, granted_by)
select position.id, permission.code, coalesce(
  (select profile.user_id from public.profiles profile join public.staff_positions director on director.id = profile.position_id
    where profile.status = 'active' and director.official and director.level = 14 order by profile.created_at limit 1),
  position.updated_by, position.created_by)
from public.staff_positions position
cross join (values ('courses.study'), ('courses.takeexam'), ('courses.results.viewown'),
  ('courses.results.viewall'), ('courses.results.manage'), ('courses.attempts.reopen')) permission(code)
where position.official and position.active and
  (position.level between 7 and 14) and
  (position.level between 12 and 14 or permission.code in ('courses.study','courses.takeexam','courses.results.viewown'))
on conflict (position_id, permission_code) do nothing;

alter table public.courses
  add column if not exists slug text,
  add column if not exists short_description text not null default '',
  add column if not exists category text not null default 'Institucional',
  add column if not exists cover_url text,
  add column if not exists duration_minutes integer not null default 0,
  add column if not exists status text not null default 'draft',
  add column if not exists sort_order integer not null default 0,
  add column if not exists required boolean not null default false,
  add column if not exists published_at timestamptz;
alter table public.courses
  add constraint academy_courses_status_check check (status in ('draft','published','archived')),
  add constraint academy_courses_duration_check check (duration_minutes between 0 and 100000),
  add constraint academy_courses_short_check check (char_length(short_description) <= 250),
  add constraint academy_courses_category_check check (char_length(category) between 2 and 80),
  add constraint academy_courses_cover_check check (cover_url is null or (cover_url ~ '^https://[^[:space:]]+$' and char_length(cover_url) <= 1000));
create unique index academy_courses_slug_idx on public.courses (slug) where slug is not null;
create index academy_courses_published_idx on public.courses (sort_order, published_at desc) where status = 'published';

create table public.course_lessons (
  id bigint generated always as identity primary key,
  course_id bigint not null references public.courses(id) on delete restrict,
  title text not null check (char_length(btrim(title)) between 2 and 160),
  description text not null default '' check (char_length(description) <= 500),
  body text not null default '' check (char_length(body) <= 30000),
  content_type text not null default 'text' check (content_type in ('text','video','mixed')),
  video_url text check (video_url is null or (video_url ~ '^https://[^[:space:]]+$' and char_length(video_url) <= 1000)),
  image_url text check (image_url is null or (image_url ~ '^https://[^[:space:]]+$' and char_length(image_url) <= 1000)),
  material_url text check (material_url is null or (material_url ~ '^https://[^[:space:]]+$' and char_length(material_url) <= 1000)),
  duration_minutes integer not null default 0 check (duration_minutes between 0 and 10000),
  position integer not null default 0,
  required boolean not null default true,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index course_lessons_order_idx on public.course_lessons (course_id, position, id) where active;

create table public.course_assessments (
  id bigint generated always as identity primary key,
  course_id bigint not null unique references public.courses(id) on delete restrict,
  enabled boolean not null default false,
  question_count integer not null default 5 check (question_count between 1 and 100),
  passing_score numeric(5,2) not null default 70 check (passing_score between 0 and 100),
  max_attempts integer not null default 3 check (max_attempts between 1 and 20),
  shuffle_questions boolean not null default true,
  shuffle_options boolean not null default true,
  reveal_policy text not null default 'after_final' check (reveal_policy in ('immediate','after_final')),
  updated_at timestamptz not null default now()
);
create table public.course_questions (
  id bigint generated always as identity primary key,
  course_id bigint not null references public.courses(id) on delete restrict,
  body text not null check (char_length(btrim(body)) between 5 and 2000),
  kind text not null check (kind in ('multiple_choice','true_false')),
  explanation text not null default '' check (char_length(explanation) <= 2000),
  weight numeric(6,2) not null default 1 check (weight > 0 and weight <= 100),
  position integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index course_questions_bank_idx on public.course_questions (course_id, position, id) where active;
create table public.course_question_options (
  id bigint generated always as identity primary key,
  question_id bigint not null references public.course_questions(id) on delete restrict,
  label text not null check (char_length(btrim(label)) between 1 and 500),
  correct boolean not null default false,
  position integer not null default 0
);
create index course_question_options_idx on public.course_question_options (question_id, position, id);

create table public.course_enrollments (
  id bigint generated always as identity primary key,
  course_id bigint not null references public.courses(id) on delete restrict,
  professional_id uuid not null references public.profiles(user_id) on delete restrict,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  final_score numeric(5,2) check (final_score between 0 and 100),
  passed boolean not null default false,
  approved_attempt_id bigint,
  extra_attempts integer not null default 0 check (extra_attempts between 0 and 100),
  unique (course_id, professional_id)
);
create index course_enrollments_person_idx on public.course_enrollments (professional_id, started_at desc);
create index course_enrollments_course_idx on public.course_enrollments (course_id, started_at desc);

create table public.course_lesson_progress (
  id bigint generated always as identity primary key,
  enrollment_id bigint not null references public.course_enrollments(id) on delete restrict,
  lesson_id bigint not null references public.course_lessons(id) on delete restrict,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (enrollment_id, lesson_id)
);
create index course_lesson_progress_lesson_idx on public.course_lesson_progress (lesson_id);

create table public.course_attempts (
  id bigint generated always as identity primary key,
  enrollment_id bigint not null references public.course_enrollments(id) on delete restrict,
  assessment_id bigint not null references public.course_assessments(id) on delete restrict,
  attempt_number integer not null check (attempt_number > 0),
  status text not null default 'in_progress' check (status in ('in_progress','submitted')),
  started_at timestamptz not null default now(),
  submitted_at timestamptz,
  passing_score_snapshot numeric(5,2) not null check (passing_score_snapshot between 0 and 100),
  score numeric(5,2) check (score between 0 and 100),
  passed boolean,
  unique (enrollment_id, attempt_number),
  check ((status = 'in_progress' and submitted_at is null and score is null and passed is null)
    or (status = 'submitted' and submitted_at is not null and score is not null and passed is not null))
);
create unique index course_attempts_one_open_idx on public.course_attempts (enrollment_id) where status = 'in_progress';
create index course_attempts_enrollment_idx on public.course_attempts (enrollment_id, started_at desc);
alter table public.course_enrollments add constraint course_enrollments_approved_attempt_fk
  foreign key (approved_attempt_id) references public.course_attempts(id) on delete restrict;

-- Snapshot íntegro e privado: enunciado, alternativas e gabarito da versão sorteada.
create table public.course_attempt_items (
  id bigint generated always as identity primary key,
  attempt_id bigint not null references public.course_attempts(id) on delete restrict,
  question_id bigint not null references public.course_questions(id) on delete restrict,
  position integer not null,
  question_body text not null,
  kind text not null,
  explanation text not null default '',
  options jsonb not null check (jsonb_typeof(options) = 'array'),
  correct_option_id bigint not null,
  weight numeric(6,2) not null check (weight > 0),
  unique (attempt_id, question_id),
  unique (attempt_id, position)
);
create table public.course_attempt_answers (
  id bigint generated always as identity primary key,
  item_id bigint not null unique references public.course_attempt_items(id) on delete restrict,
  selected_option_id bigint not null,
  is_correct boolean,
  points numeric(6,2),
  updated_at timestamptz not null default now()
);

create table public.course_grade_adjustments (
  id bigint generated always as identity primary key,
  enrollment_id bigint not null references public.course_enrollments(id) on delete restrict,
  original_score numeric(5,2),
  previous_score numeric(5,2),
  adjusted_score numeric(5,2) not null check (adjusted_score between 0 and 100),
  reason text not null check (char_length(btrim(reason)) between 10 and 1000),
  adjusted_by uuid not null references public.profiles(user_id) on delete restrict,
  adjusted_at timestamptz not null default now()
);
create index course_grade_adjustments_enrollment_idx on public.course_grade_adjustments (enrollment_id, adjusted_at desc);
create table public.course_extra_attempt_grants (
  id bigint generated always as identity primary key,
  enrollment_id bigint not null references public.course_enrollments(id) on delete restrict,
  reason text not null check (char_length(btrim(reason)) between 10 and 1000),
  granted_by uuid not null references public.profiles(user_id) on delete restrict,
  granted_at timestamptz not null default now()
);
create index course_extra_attempt_grants_enrollment_idx on public.course_extra_attempt_grants (enrollment_id, granted_at desc);

do $$ declare t text; begin
  foreach t in array array['course_lessons','course_assessments','course_questions','course_question_options',
    'course_enrollments','course_lesson_progress','course_attempts','course_attempt_items','course_attempt_answers',
    'course_grade_adjustments','course_extra_attempt_grants'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('alter table public.%I force row level security',t);
    execute format('revoke all on public.%I from public, anon, authenticated',t);
    execute format('grant select on public.%I to service_role',t);
  end loop;
end $$;

-- O catálogo legado só é legível diretamente quando publicado; as outras
-- estruturas não são expostas ao Data API, e todas as operações passam por RPC.
drop policy if exists courses_read_active_or_manager on public.courses;
create policy courses_read_published_or_director on public.courses for select to authenticated
using ((status = 'published' and active and private.has_permission((select auth.uid()), 'courses.view'))
  or (private.has_permission((select auth.uid()), 'courses.manage')
    and private.current_position_level((select auth.uid())) between 12 and 14));

create or replace function private.academy_require(p_actor uuid, p_permission text, p_director boolean default false)
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if p_actor is null or not private.has_permission(p_actor,p_permission)
    or (p_director and not exists (
      select 1 from public.profiles profile join public.staff_positions position on position.id = profile.position_id
      where profile.user_id = p_actor and profile.status = 'active' and position.active and position.official
        and position.level between 12 and 14)) then
    raise exception 'Acesso não autorizado à Academia.' using errcode = '42501';
  end if;
end $$;
revoke all on function private.academy_require(uuid,text,boolean) from public,anon,authenticated;

create or replace function private.academy_audit(p_actor uuid,p_action text,p_entity text,p_id bigint,p_old jsonb default null,p_new jsonb default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into public.audit_logs (actor_user_id,actor_passport,action,entity_name,entity_id,old_values,new_values)
  select p_actor,profile.passport,p_action,p_entity,p_id::text,p_old,p_new
  from public.profiles profile where profile.user_id = p_actor;
end $$;
revoke all on function private.academy_audit(uuid,text,text,bigint,jsonb,jsonb) from public,anon,authenticated;

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
      and (coalesce(btrim(p_search),'')='' or profile.display_name ilike '%'||left(btrim(p_search),80)||'%'
        or profile.passport ilike '%'||left(btrim(p_search),80)||'%' or c.name ilike '%'||left(btrim(p_search),80)||'%')
      order by e.started_at desc,e.id desc limit 20 offset (v_page-1)*20) x;
    return jsonb_build_object('results',v_result,'page',v_page,'total',(
      select count(*) from public.course_enrollments e join public.profiles profile on profile.user_id=e.professional_id
      join public.courses c on c.id=e.course_id
      where (p_course_id is null or e.course_id=p_course_id)
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
      'courses',v_course.id,jsonb_build_object('status',case when p_action='publish' then 'draft' else 'published' end),jsonb_build_object('status',v_course.status));
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
begin
  perform private.academy_require(v_actor,'courses.study');
  select * into v_course from public.courses where id=(p_payload->>'course_id')::bigint
    and status='published' and active;
  if not found then raise exception 'Curso indisponível.'; end if;
  if p_action='enroll' then
    insert into public.course_enrollments(course_id,professional_id) values(v_course.id,v_actor)
      on conflict (course_id,professional_id) do nothing;
    select * into v_enrollment from public.course_enrollments where course_id=v_course.id and professional_id=v_actor;
    if v_enrollment.started_at > now()-interval '3 seconds' then
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
