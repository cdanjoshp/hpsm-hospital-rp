-- Fase 10: sessão canônica, primeiro acesso, RLS granular e escrita financeira protegida.
-- Migração incremental: não remove dados nem altera snapshots existentes.

CREATE OR REPLACE FUNCTION private.hpsm_auth_actor()
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_session_id uuid;
begin
  begin
    v_session_id := nullif(auth.jwt() ->> 'session_id', '')::uuid;
  exception when invalid_text_representation then
    v_session_id := null;
  end;

  if v_actor is null
     or v_session_id is null
     or not exists (
       select 1
       from auth.sessions session
       join auth.users auth_user on auth_user.id = session.user_id
       join public.profiles profile on profile.user_id = session.user_id
       where session.id = v_session_id
         and session.user_id = v_actor
         and (session.not_after is null or session.not_after > now())
         and auth_user.deleted_at is null
         and (auth_user.banned_until is null or auth_user.banned_until <= now())
         and profile.status = 'active'
     ) then
    raise exception 'Sessão inválida ou expirada.' using errcode = '42501';
  end if;

  return v_actor;
end;
$function$;


revoke all on function private.hpsm_auth_actor() from public, anon, authenticated;
CREATE OR REPLACE FUNCTION private.hpsm_current_actor() RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
declare v_actor uuid := private.hpsm_auth_actor();
begin
  if exists (select 1 from public.profiles where user_id = v_actor and must_change_password) then
    raise exception 'Altere sua senha antes de acessar o sistema.' using errcode = '42501';
  end if;
  return v_actor;
end; $$;
CREATE OR REPLACE FUNCTION private.hpsm_session_valid(p_require_ready boolean DEFAULT true) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
begin
  if p_require_ready then perform private.hpsm_current_actor(); else perform private.hpsm_auth_actor(); end if;
  return true;
exception when insufficient_privilege then return false;
end; $$;
revoke all on function private.hpsm_session_valid(boolean) from public, anon;
grant execute on function private.hpsm_session_valid(boolean) to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.hpsm_session_bootstrap()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_auth_actor();
  v_permissions text[];
  v_result jsonb;
begin
  v_permissions := public.effective_permission_codes(v_actor);
  select jsonb_build_object(
    'profile', jsonb_build_object(
      'user_id', profile.user_id,
      'passport', profile.passport,
      'display_name', profile.display_name,
      'role_code', profile.role_code,
      'status', profile.status,
      'must_change_password', profile.must_change_password,
      'position_id', profile.position_id
    ),
    'permissionCodes', to_jsonb(coalesce(v_permissions, array[]::text[])),
    'positionDisplayName', position.name,
    'positionLevel', position.level
  ) into v_result
  from public.profiles profile
  left join public.staff_positions position on position.id = profile.position_id
  where profile.user_id = v_actor and profile.status = 'active';
  if v_result is null then raise exception 'Perfil ativo não localizado.' using errcode = '42501'; end if;
  return v_result;
end;
$function$;


CREATE OR REPLACE FUNCTION private.has_permission(p_user_id uuid, p_permission_code text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1
    from public.profiles profile
    join public.staff_positions current_position
      on current_position.id = profile.position_id
     and current_position.active
    where profile.user_id = p_user_id
      and profile.status = 'active'
      and not profile.must_change_password
      and ((select auth.uid()) is null or private.hpsm_session_valid())
      and (
        p_permission_code <> 'recruitment.manage'
        or current_position.level between 11 and 14
      )
      and (
        exists (
          select 1
          from public.staff_position_permissions position_permission
          join public.staff_positions position on position.id = position_permission.position_id
          where position_permission.position_id = profile.position_id
            and position_permission.permission_code = p_permission_code
            and position.active
        )
        or exists (
          select 1
          from public.user_permission_grants permission_grant
          where permission_grant.user_id = profile.user_id
            and permission_grant.permission_code = p_permission_code
            and permission_grant.revoked_at is null
            and permission_grant.valid_from <= now()
            and (permission_grant.expires_at is null or permission_grant.expires_at > now())
        )
      )
  );
$function$;


CREATE OR REPLACE FUNCTION public.effective_permission_codes(p_user_id uuid)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(array_agg(distinct effective.permission_code order by effective.permission_code), array[]::text[])
  from (
    select position_permission.permission_code
    from public.profiles profile
    join public.staff_positions position on position.id = profile.position_id and position.active
    join public.staff_position_permissions position_permission on position_permission.position_id = position.id
    where profile.user_id = p_user_id
      and profile.status = 'active'
      and not profile.must_change_password
      and (
        position_permission.permission_code <> 'recruitment.manage'
        or position.level between 11 and 14
      )
    union all
    select permission_grant.permission_code
    from public.profiles profile
    join public.staff_positions position on position.id = profile.position_id and position.active
    join public.user_permission_grants permission_grant on permission_grant.user_id = profile.user_id
    where profile.user_id = p_user_id
      and profile.status = 'active'
      and not profile.must_change_password
      and permission_grant.revoked_at is null
      and permission_grant.valid_from <= now()
      and (permission_grant.expires_at is null or permission_grant.expires_at > now())
      and (
        permission_grant.permission_code <> 'recruitment.manage'
        or position.level between 11 and 14
      )
  ) effective;
$function$;


CREATE OR REPLACE FUNCTION private.is_active_user() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  select private.hpsm_session_valid();
$$;

create policy phase10_valid_session on public.clinical_exam_images as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.system_settings as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.profiles as restrictive for all to authenticated
using ((select private.hpsm_session_valid(false)))
with check ((select private.hpsm_session_valid(false)));

create policy phase10_valid_session on public.audit_logs as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.system_permissions as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.attendance_items as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.patients as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.attendances as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.staff_position_permissions as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.benefit_plans as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.staff_positions as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.plan_discounts as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.recruitment_decisions as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.recruitment_applications as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.service_catalog as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.rh_hour_snapshots as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.rh_disciplinary_reviews as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.rh_absence_requests as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.notification_reads as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.notifications as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.clinical_exam_report_versions as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.user_permission_grants as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.clinical_exam_document_shares as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.clinical_exam_documents as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.rh_weekly_records as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.rh_warnings as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.rh_leave_week_adjustments as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.rh_week_closures as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.rh_week_reopen_events as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.rh_hour_justifications as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.clinical_casts as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.staff_position_history as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.exam_ai_generations as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.staff_position_transition_rules as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.staff_promotion_reviews as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.courses as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.staff_course_records as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.patient_health_plan_requests as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.clinical_exams as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.exam_categories as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.exam_types as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.clinical_exam_status_history as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.patient_portal_sessions as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_valid_session on public.patient_portal_login_attempts as restrictive for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));

create policy phase10_hpsm_storage_session on storage.objects as restrictive for all to authenticated
using (bucket_id not in ('catalog-images','clinical-exam-images','clinical-exam-documents') or (select private.hpsm_session_valid()))
with check (bucket_id not in ('catalog-images','clinical-exam-images','clinical-exam-documents') or (select private.hpsm_session_valid()));

alter policy settings_read_directors on public.system_settings using (( SELECT (private.has_permission((select auth.uid()), 'settings.critical')) AS is_director));

alter policy profiles_read_own_or_director on public.profiles using (((user_id = ( SELECT auth.uid() AS uid)) OR ( SELECT (private.has_permission((select auth.uid()), 'team.manage') or private.has_permission((select auth.uid()), 'access.manage') or private.has_permission((select auth.uid()), 'hr.team.view')) AS is_director)));

alter policy audit_read_directors on public.audit_logs using (( SELECT (private.has_permission((select auth.uid()), 'audit.view')) AS is_director));

alter policy rh_hour_snapshots_read_own_or_director on public.rh_hour_snapshots using ((((employee_id = ( SELECT auth.uid() AS uid)) AND ( SELECT private.is_active_user() AS is_active_user)) OR ( SELECT (private.has_permission((select auth.uid()), 'hr.team.view') or private.has_permission((select auth.uid()), 'hr.hours.manage') or private.has_permission((select auth.uid()), 'hr.hours.import') or private.has_permission((select auth.uid()), 'hr.weeks.close') or private.has_permission((select auth.uid()), 'hr.reports.view')) AS is_director)));

alter policy rh_disciplinary_reviews_read_own_or_director on public.rh_disciplinary_reviews using ((((employee_id = ( SELECT auth.uid() AS uid)) AND ( SELECT private.is_active_user() AS is_active_user)) OR ( SELECT (private.has_permission((select auth.uid()), 'hr.team.view') or private.has_permission((select auth.uid()), 'hr.discipline.review') or private.has_permission((select auth.uid()), 'hr.discipline.manage')) AS is_director)));

alter policy rh_absence_requests_read_own_or_director on public.rh_absence_requests using ((((employee_id = ( SELECT auth.uid() AS uid)) AND ( SELECT private.is_active_user() AS is_active_user)) OR ( SELECT (private.has_permission((select auth.uid()), 'hr.team.view') or private.has_permission((select auth.uid()), 'hr.absences.review')) AS is_director)));

alter policy rh_weekly_records_read_own_or_director on public.rh_weekly_records using ((((employee_id = ( SELECT auth.uid() AS uid)) AND ( SELECT private.is_active_user() AS is_active_user)) OR ( SELECT (private.has_permission((select auth.uid()), 'hr.team.view') or private.has_permission((select auth.uid()), 'hr.weeks.close') or private.has_permission((select auth.uid()), 'hr.weeks.reopen') or private.has_permission((select auth.uid()), 'hr.reports.view')) AS is_director)));

alter policy rh_warnings_read_own_or_director on public.rh_warnings using ((((employee_id = ( SELECT auth.uid() AS uid)) AND ( SELECT private.is_active_user() AS is_active_user)) OR ( SELECT (private.has_permission((select auth.uid()), 'hr.team.view') or private.has_permission((select auth.uid()), 'hr.warnings.issue') or private.has_permission((select auth.uid()), 'hr.warnings.annul') or private.has_permission((select auth.uid()), 'hr.discipline.review') or private.has_permission((select auth.uid()), 'hr.reports.view')) AS is_director)));

alter policy rh_leave_week_adjustments_read_own_or_director on public.rh_leave_week_adjustments using ((((employee_id = ( SELECT auth.uid() AS uid)) AND ( SELECT private.is_active_user() AS is_active_user)) OR ( SELECT (private.has_permission((select auth.uid()), 'hr.team.view') or private.has_permission((select auth.uid()), 'hr.absences.review') or private.has_permission((select auth.uid()), 'hr.reports.view')) AS is_director)));

alter policy rh_week_closures_read_director on public.rh_week_closures using (( SELECT (private.has_permission((select auth.uid()), 'hr.team.view') or private.has_permission((select auth.uid()), 'hr.weeks.close') or private.has_permission((select auth.uid()), 'hr.weeks.reopen') or private.has_permission((select auth.uid()), 'hr.reports.view')) AS is_director));

alter policy rh_week_reopen_events_read_director on public.rh_week_reopen_events using (( SELECT (private.has_permission((select auth.uid()), 'hr.team.view') or private.has_permission((select auth.uid()), 'hr.weeks.reopen') or private.has_permission((select auth.uid()), 'hr.reports.view')) AS is_director));

alter policy rh_hour_justifications_read_own_or_director on public.rh_hour_justifications using ((((employee_id = ( SELECT auth.uid() AS uid)) AND ( SELECT private.is_active_user() AS is_active_user)) OR ( SELECT (private.has_permission((select auth.uid()), 'hr.team.view') or private.has_permission((select auth.uid()), 'hr.justifications.review') or private.has_permission((select auth.uid()), 'hr.reports.view')) AS is_director)));

CREATE OR REPLACE FUNCTION public.restore_clinical_exam_image(p_image_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_image public.clinical_exam_images;
begin
  select * into v_image from public.clinical_exam_images where id = p_image_id for update;
  if v_image.id is null
     or v_image.removed_by is distinct from v_actor
     or v_image.removed_at is null
     or v_image.removed_at < now() - interval '5 minutes' then
    raise exception 'Não foi possível restaurar o metadado da imagem.';
  end if;
  perform 1 from public.clinical_exams where id = v_image.exam_id and status = 'in_progress' for update;
  if not found then raise exception 'O exame não permite alterações de imagem.'; end if;
  update public.clinical_exam_images set removed_at = null, removed_by = null where id = p_image_id;
  update public.clinical_exams set updated_at = now() where id = v_image.exam_id;
  perform private.audit_exam_action(v_actor, 'clinical_exam.image_removal_compensated', 'clinical_exam_images', p_image_id::text, jsonb_build_object('removed', true), jsonb_build_object('removed', false));
end;
$function$;


CREATE OR REPLACE FUNCTION public.delete_clinical_exam(p_exam_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_exam public.clinical_exams;
  v_storage_paths jsonb;
  v_image_ids text[];
  v_generation_ids text[];
  v_image_count integer;
  v_generation_count integer;
  v_report_version_count integer;
  v_history_count integer;
begin
  if v_actor is null then raise exception 'Sessão inválida.' using errcode = '42501'; end if;
  select * into v_exam from public.clinical_exams where id = p_exam_id for update;
  if v_exam.id is null then raise exception 'Exame não localizado.'; end if;
  if v_exam.status = 'completed' then raise exception 'Exames concluídos não podem ser excluídos.'; end if;
  if v_exam.responsible_professional_id is distinct from v_actor and not private.has_permission(v_actor, 'exams.delete') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(path order by path), '[]'::jsonb) into v_storage_paths
  from (
    select image.storage_path as path from public.clinical_exam_images image where image.exam_id = p_exam_id
    union
    select generation.draft_storage_path as path from public.exam_ai_generations generation
    where generation.exam_id = p_exam_id and generation.draft_storage_path is not null
  ) paths;
  select coalesce(array_agg(image.id::text), array[]::text[]), count(*)::integer
  into v_image_ids, v_image_count
  from public.clinical_exam_images image where image.exam_id = p_exam_id;
  select coalesce(array_agg(generation.id::text), array[]::text[]), count(*)::integer
  into v_generation_ids, v_generation_count
  from public.exam_ai_generations generation where generation.exam_id = p_exam_id;
  select count(*)::integer into v_report_version_count from public.clinical_exam_report_versions version where version.exam_id = p_exam_id;
  select count(*)::integer into v_history_count from public.clinical_exam_status_history history where history.exam_id = p_exam_id;

  delete from public.audit_logs audit
  where (audit.entity_name = 'clinical_exams' and audit.entity_id = p_exam_id::text)
     or (audit.entity_name = 'clinical_exam_images' and audit.entity_id = any(v_image_ids))
     or (audit.entity_name = 'exam_ai_generations' and audit.entity_id = any(v_generation_ids));
  delete from public.exam_ai_generations where exam_id = p_exam_id;
  delete from public.clinical_exam_images where exam_id = p_exam_id;
  delete from public.clinical_exam_report_versions where exam_id = p_exam_id;
  delete from public.clinical_exam_status_history where exam_id = p_exam_id;
  delete from public.clinical_exams where id = p_exam_id;

  perform private.audit_exam_action(
    v_actor,
    'DELETE',
    'clinical_exams',
    p_exam_id::text,
    jsonb_build_object(
      'status', v_exam.status,
      'exam_type_id', v_exam.exam_type_id,
      'patient_id', v_exam.patient_id,
      'responsible_professional_id', v_exam.responsible_professional_id
    ),
    jsonb_build_object(
      'deleted', true,
      'images', v_image_count,
      'ai_generations', v_generation_count,
      'report_versions', v_report_version_count,
      'status_events', v_history_count
    )
  );
  return jsonb_build_object('exam_id', p_exam_id, 'storage_paths', v_storage_paths);
end;
$function$;


CREATE OR REPLACE FUNCTION private.create_attendance(p_patient_id bigint, p_items jsonb, p_notes text DEFAULT NULL::text, p_benefit_code text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_attendance_id bigint;
  v_discount numeric(18, 2);
  v_input_count integer;
  v_patient_name text;
  v_patient_passport text;
  v_plan_code text;
  v_plan_name text;
  v_subtotal numeric(18, 2);
  v_valid_count integer;
begin
  perform private.hpsm_current_actor();
  if not private.has_permission((select auth.uid()), 'attendances.create') then
    raise exception 'Você não possui permissão para registrar atendimentos.';
  end if;

  if p_patient_id is null then
    v_patient_name := 'Venda avulsa';
    v_patient_passport := '—';
  else
    select patient.name, patient.passport
    into v_patient_name, v_patient_passport
    from public.patients as patient
    where patient.id = p_patient_id;

    if not found then
      raise exception 'Paciente não localizado.';
    end if;
  end if;

  v_plan_code := nullif(btrim(coalesce(p_benefit_code, '')), '');
  if v_plan_code is not null then
    select plan.name
    into v_plan_name
    from public.benefit_plans as plan
    where plan.code = v_plan_code;
    if not found then
      raise exception 'Benefício inválido ou indisponível.';
    end if;
  end if;

  if p_notes is not null and char_length(p_notes) > 1000 then
    raise exception 'Observação muito longa.';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'Inclua ao menos um item.';
  end if;

  v_input_count := jsonb_array_length(p_items);
  if v_input_count < 1 or v_input_count > 50 then
    raise exception 'Quantidade de itens inválida.';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_items) as item(service_id bigint, quantity integer)
    group by service_id
    having count(*) <> 1
  ) then
    raise exception 'Cada item deve aparecer apenas uma vez.';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_items) as item(service_id bigint, quantity integer)
    join public.service_catalog as catalog on catalog.id = item.service_id
    where catalog.code = 'plano_saude_convenio'
      and item.quantity <> 1
  ) then
    raise exception 'O plano de saúde pode aparecer somente uma vez no atendimento.';
  end if;

  if p_patient_id is null and exists (
    select 1
    from jsonb_to_recordset(p_items) as item(service_id bigint, quantity integer)
    join public.service_catalog as catalog on catalog.id = item.service_id
    where lower(btrim(catalog.category)) not in ('insumos', 'medicamentos')
  ) then
    raise exception 'Venda avulsa aceita somente insumos e medicamentos.';
  end if;

  if not private.has_permission((select auth.uid()), 'catalog.view')
     or (p_patient_id is not null and not private.has_permission((select auth.uid()), 'patients.view')) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  perform 1 from public.service_catalog where id in (
    select service_id from jsonb_to_recordset(p_items) as item(service_id bigint, quantity integer)
  ) for share;
  perform 1 from public.plan_discounts where plan_code = v_plan_code and service_id in (
    select service_id from jsonb_to_recordset(p_items) as item(service_id bigint, quantity integer)
  ) for share;
  with input_items as (
    select service_id, quantity
    from jsonb_to_recordset(p_items) as item(service_id bigint, quantity integer)
  )
  select
    count(*),
    coalesce(sum(catalog.unit_price * input_items.quantity), 0),
    coalesce(sum(round(catalog.unit_price * input_items.quantity * coalesce(discount.discount_percent, 0) / 100, 2)), 0)
  into v_valid_count, v_subtotal, v_discount
  from input_items
  join public.service_catalog as catalog
    on catalog.id = input_items.service_id
   and catalog.active = true
  left join public.plan_discounts as discount
    on discount.service_id = catalog.id
   and discount.plan_code = v_plan_code
  where input_items.quantity between 1 and 99;

  if v_valid_count <> v_input_count then
    raise exception 'Um dos itens não está disponível.';
  end if;

  insert into public.attendances (
    patient_id, patient_name, patient_passport, plan_code, plan_name,
    subtotal, discount, notes, performed_by
  ) values (
    p_patient_id, v_patient_name, v_patient_passport, v_plan_code, v_plan_name,
    v_subtotal, v_discount, nullif(btrim(coalesce(p_notes, '')), ''), (select auth.uid())
  )
  returning id into v_attendance_id;

  insert into public.attendance_items (
    attendance_id, service_id, service_name, unit_price, quantity, discount_percent
  )
  select
    v_attendance_id, catalog.id, catalog.name, catalog.unit_price,
    input_items.quantity::smallint, coalesce(discount.discount_percent, 0)
  from jsonb_to_recordset(p_items) as input_items(service_id bigint, quantity integer)
  join public.service_catalog as catalog
    on catalog.id = input_items.service_id
   and catalog.active = true
  left join public.plan_discounts as discount
    on discount.service_id = catalog.id
   and discount.plan_code = v_plan_code;

  return v_attendance_id;
end;
$function$;


revoke all on function private.create_attendance(bigint,jsonb,text,text) from public, anon;
grant execute on function private.create_attendance(bigint,jsonb,text,text) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.create_attendance(p_patient_id bigint, p_items jsonb, p_notes text DEFAULT NULL, p_benefit_code text DEFAULT NULL) RETURNS bigint
LANGUAGE sql SECURITY INVOKER SET search_path = '' AS $$
  select private.create_attendance(p_patient_id,p_items,p_notes,p_benefit_code);
$$;
revoke all on function public.create_attendance(bigint,jsonb,text,text) from public, anon;
grant execute on function public.create_attendance(bigint,jsonb,text,text) to authenticated, service_role;

CREATE OR REPLACE FUNCTION private.cancel_attendance(p_attendance_id bigint)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform private.hpsm_current_actor();
  if not private.has_permission((select auth.uid()), 'attendances.manage') then
    raise exception 'Você não possui permissão para cancelar atendimentos.';
  end if;
  update public.attendances
  set status = 'cancelled', cancelled_by = (select auth.uid()), cancelled_at = now()
  where id = p_attendance_id and status = 'completed';
  return found;
end;
$function$;


revoke all on function private.cancel_attendance(bigint) from public, anon;
grant execute on function private.cancel_attendance(bigint) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.cancel_attendance(p_attendance_id bigint) RETURNS boolean
LANGUAGE sql SECURITY INVOKER SET search_path = '' AS $$
  select private.cancel_attendance(p_attendance_id);
$$;
revoke all on function public.cancel_attendance(bigint) from public, anon;
grant execute on function public.cancel_attendance(bigint) to authenticated, service_role;

revoke insert, update, delete on public.attendances, public.attendance_items from authenticated;
