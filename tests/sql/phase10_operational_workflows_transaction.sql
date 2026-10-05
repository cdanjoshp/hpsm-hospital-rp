begin;
-- Rollback-only fixtures. No external messaging or Auth account creation.
create temporary table phase10_workflows (key text primary key, value text) on commit drop;
do $$
declare actor uuid; sid uuid; employee uuid; patient bigint; pass text;
begin
  select p.user_id,s.id into actor,sid from public.profiles p join auth.sessions s on s.user_id=p.user_id
  where p.status='active' and not p.must_change_password
    and private.has_permission(p.user_id,'healthplans.review') and private.has_permission(p.user_id,'recruitment.manage')
    and private.has_permission(p.user_id,'hr.weeks.close') and private.has_permission(p.user_id,'courses.manage')
    and private.has_permission(p.user_id,'partnerships.manage')
    and (s.not_after is null or s.not_after>now()) order by s.created_at desc limit 1;
  select user_id into employee from public.profiles where user_id<>actor and status='active' and role_code<>'diretor_geral' order by created_at limit 1;
  if actor is null or employee is null then raise exception 'Profissionais necessários indisponíveis.'; end if;
  select lpad(n::text,4,'0') into pass from generate_series(1,9999) n where not exists(select 1 from public.patients where passport=lpad(n::text,4,'0')) order by n desc limit 1;
  insert into public.patients(passport,name,phone,birth_date) values(pass,'Regressão Fase 10','(055) 610-001',date '1990-01-01') returning id into patient;
  insert into phase10_workflows values('actor',actor::text),('session',sid::text),('employee',employee::text),('patient',patient::text);
end $$;
grant select on phase10_workflows to authenticated, service_role;
set local role service_role;
do $$
declare actor uuid:=(select value::uuid from phase10_workflows where key='actor'); employee uuid:=(select value::uuid from phase10_workflows where key='employee');
  pass text; app uuid; decision text; r jsonb; leave_id bigint; v_course bigint; announcement bigint;
begin
  foreach decision in array array['approved','rejected'] loop
    select lpad(n::text,4,'0') into pass from generate_series(1,9999) n
    where not exists(select 1 from public.recruitment_applications where passport=lpad(n::text,4,'0')) order by n desc limit 1;
    insert into public.recruitment_applications(full_name,passport,birth_day,birth_month,city_phone,discord_id,availability,prior_experience,interest_area,motivation,external_calls)
    values('Regressão Fase 10',pass,1,1,'(055) 610-002',(10000000000000000+txid_current()*10+case when decision='approved' then 1 else 2 end)::text,array['morning'],false,'clinical_care','Candidatura fictícia para validar a regressão do sistema.','full') returning id into app;
    r:=public.decide_recruitment_application(app,decision,'Recusa fictícia para regressão controlada.',actor);
    if r->>'decision'<>decision or (select count(*) from public.recruitment_decisions where application_id=app)<>1 then raise exception 'Decisão de recrutamento divergente.'; end if;
    begin perform public.decide_recruitment_application(app,decision,'Recusa fictícia para regressão controlada.',actor); raise exception 'Decisão duplicada aceita.';
    exception when no_data_found then null;
    end;
  end loop;
  insert into public.rh_absence_requests(employee_id,start_date,end_date,reason)
  values(employee,date '2026-06-08',date '2026-06-14','Afastamento fictício para validar cálculo semanal.') returning id into leave_id;
  r:=public.review_hr_leave_request(leave_id,'approved','[{"week_start":"2026-06-08","deducted_minutes":240}]'::jsonb,'Revisão transacional.',actor);
  if (r->>'deducted_minutes')::int<>240 then raise exception 'Afastamento não concedeu quatro horas.'; end if;
  r:=public.close_hr_week(employee,date '2026-06-08',360,'{}'::jsonb,'Regressão transacional.',actor);
  if r->>'status'<>'met' or (r->>'required_minutes')::int<>360 or (r->>'remaining_deficit_minutes')::int<>0 then raise exception 'Meta de 10h menos 4h não foi cumprida com 6h.'; end if;
  v_course:=(public.create_course('Curso Fase 10 '||txid_current(),'Curso temporário de regressão.',actor)->>'id')::bigint;
  r:=public.record_staff_course_status(v_course,employee,'completed',actor);
  if r->>'status'<>'completed' then raise exception 'Conclusão de curso falhou.'; end if;
  perform public.record_staff_course_status(v_course,employee,'completed',actor);
  if (select count(*) from public.staff_course_records record where record.course_id=v_course and record.employee_id=employee)>1 then raise exception 'Curso duplicado.'; end if;
  announcement:=(public.publish_notification_announcement('Regressão Fase 10','Aviso temporário que será revertido na mesma transação.','all','normal',null,actor)->>'id')::bigint;
  perform public.mark_notification_read(announcement,employee);
  r:=public.archive_notification_announcement(announcement,actor);
  if r->>'archived_at' is null then raise exception 'Arquivamento de comunicado falhou.'; end if;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select value from phase10_workflows where key='actor'),'session_id',(select value from phase10_workflows where key='session'),'role','authenticated')::text,true);
set local role authenticated;
do $$
declare patient bigint:=(select value::bigint from phase10_workflows where key='patient'); service bigint; sale bigint; request_id bigint; r jsonb; finish timestamptz; benefit text; partnership bigint;
begin
  select id into service from public.service_catalog where code='plano_saude_convenio' and active;
  sale:=public.create_attendance(patient,jsonb_build_array(jsonb_build_object('service_id',service,'quantity',1)),null,null);
  select id into request_id from public.patient_health_plan_requests where attendance_id=sale;
  if request_id is null then raise exception 'Venda do plano não gerou pendência.'; end if;
  r:=public.review_patient_health_plan_request(request_id,'approved',null);
  finish:=(r->>'valid_until')::timestamptz;
  if r->>'status'<>'approved' or (r->>'already_reviewed')::boolean then raise exception 'Plano não ativado.'; end if;
  r:=public.review_patient_health_plan_request(request_id,'approved',null);
  if not (r->>'already_reviewed')::boolean or (r->>'valid_until')::timestamptz<>finish then raise exception 'Repetição de aprovação renovou indevidamente.'; end if;
  select catalog.id into service from public.service_catalog catalog join public.plan_discounts discount on discount.service_id=catalog.id
  where catalog.active and discount.discount_percent>0 order by catalog.id limit 1;
  if service is null then raise exception 'Item com desconto necessário para a regressão.'; end if;
  partnership:=public.create_partnership('Parceria Regressão Fase 10','Fixture temporária revertida ao final.',patient);
  r:=public.import_partnership_people(partnership,jsonb_build_array(jsonb_build_object(
    'passport',(select passport from public.patients where id=patient),
    'name',(select name from public.patients where id=patient)
  )),'individual');
  if (r #>> '{summary,linked}')::integer<>1 then raise exception 'Vínculo temporário da parceria não foi criado.'; end if;
  foreach benefit in array array[null::text,'plano_saude','parceiros_hp','policiais_arcanjos'] loop
    sale:=public.create_attendance(patient,jsonb_build_array(jsonb_build_object('service_id',service,'quantity',2)),null,benefit,
      case when benefit='parceiros_hp' then partnership else null end);
    if (select total from public.attendances where id=sale) is distinct from (select sum(line_total) from public.attendance_items where attendance_id=sale)
       or (select discount from public.attendances where id=sale) is distinct from (select sum(round(unit_price*quantity*discount_percent/100,2)) from public.attendance_items where attendance_id=sale) then
      raise exception 'Total e itens divergem para benefício %.',benefit;
    end if;
  end loop;
  if exists(select 1 from public.clinical_exams where patient_id=patient) or exists(select 1 from public.clinical_casts where patient_id=patient) then raise exception 'Venda fabricou registro clínico.'; end if;
end $$;
reset role;
rollback;
select jsonb_build_object('phase','10','status','ok','recruitment_decisions',true,'adjusted_hr_goal',true,'course_completion',true,'announcement_lifecycle',true,'plan_sale_review_idempotency',true,'residue',false) as result;
