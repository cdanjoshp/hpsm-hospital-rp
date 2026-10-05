-- HPSM · otimização global de navegação e leitura
-- Consolida os caminhos quentes sem criar fontes de verdade paralelas.

create or replace function private.hpsm_current_actor()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
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
$$;

revoke all on function private.hpsm_current_actor()
  from public, anon, authenticated, service_role;

create or replace function public.hpsm_session_bootstrap()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
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
    'positionDisplayName', position.name
  )
  into v_result
  from public.profiles profile
  left join public.staff_positions position on position.id = profile.position_id
  where profile.user_id = v_actor
    and profile.status = 'active';

  if v_result is null then
    raise exception 'Perfil ativo não localizado.' using errcode = '42501';
  end if;

  return v_result;
end;
$$;

create or replace function public.hpsm_dashboard_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_permissions text[] := public.effective_permission_codes(v_actor);
  v_result jsonb;
begin
  with visible_attendances as (
    select attendance.status, attendance.total
    from public.attendances attendance
    where attendance.performed_by = v_actor
       or 'attendances.manage' = any(v_permissions)
       or 'patients.view' = any(v_permissions)
    order by attendance.created_at desc
    limit 100
  )
  select jsonb_build_object(
    'activeServices', (select count(*) from public.service_catalog service where service.active),
    'completedTotal', coalesce(sum(attendance.total) filter (where attendance.status = 'completed'), 0),
    'visibleAttendances', count(*)
  )
  into v_result
  from visible_attendances attendance;

  return v_result;
end;
$$;

create or replace function public.hpsm_attendance_history(p_limit integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_permissions text[] := public.effective_permission_codes(v_actor);
  v_limit integer := least(greatest(coalesce(p_limit, 100), 1), 100);
  v_result jsonb;
begin
  if not (
    'attendances.create' = any(v_permissions)
    or 'attendances.manage' = any(v_permissions)
    or 'patients.view' = any(v_permissions)
  ) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', attendance.id,
      'patient_id', attendance.patient_id,
      'patient_name', attendance.patient_name,
      'patient_passport', attendance.patient_passport,
      'plan_code', attendance.plan_code,
      'plan_name', attendance.plan_name,
      'status', attendance.status,
      'subtotal', attendance.subtotal,
      'discount', attendance.discount,
      'total', attendance.total,
      'notes', attendance.notes,
      'performed_by', attendance.performed_by,
      'created_at', attendance.created_at,
      'professional_name', coalesce(profile.display_name, 'Profissional'),
      'professional_passport', coalesce(profile.passport, '—'),
      'professional_position', coalesce(position.name, 'Cargo não definido'),
      'attendance_items', (
        select coalesce(jsonb_agg(
          jsonb_build_object(
            'id', item.id,
            'service_id', item.service_id,
            'service_name', item.service_name,
            'unit_price', item.unit_price,
            'quantity', item.quantity,
            'discount_percent', item.discount_percent,
            'discount_amount', item.discount_amount,
            'line_total', item.line_total
          ) order by item.id
        ), '[]'::jsonb)
        from public.attendance_items item
        where item.attendance_id = attendance.id
      )
    ) order by attendance.created_at desc, attendance.id desc
  ), '[]'::jsonb)
  into v_result
  from (
    select source.*
    from public.attendances source
    where source.performed_by = v_actor
       or 'attendances.manage' = any(v_permissions)
       or 'patients.view' = any(v_permissions)
    order by source.created_at desc, source.id desc
    limit v_limit
  ) attendance
  left join public.profiles profile on profile.user_id = attendance.performed_by
  left join public.staff_positions position on position.id = profile.position_id;

  return v_result;
end;
$$;

create or replace function public.hpsm_my_hr_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_result jsonb;
begin
  select jsonb_build_object(
    'positions', (
      select coalesce(jsonb_agg(to_jsonb(position) order by position.level), '[]'::jsonb)
      from public.staff_positions position
    ),
    'history', (
      select coalesce(jsonb_agg(to_jsonb(history) order by history.effective_at desc), '[]'::jsonb)
      from (
        select source.*
        from public.staff_position_history source
        where source.employee_id = v_actor
        order by source.effective_at desc
        limit 100
      ) history
    ),
    'progression', coalesce(private.get_staff_progression_status(v_actor), '{}'::jsonb),
    'submissions', (
      select coalesce(jsonb_agg(to_jsonb(submission) order by submission.submitted_at desc), '[]'::jsonb)
      from (
        select source.*
        from public.tcc_submissions source
        where source.employee_id = v_actor
        order by source.submitted_at desc
        limit 20
      ) submission
    ),
    'votes', (
      select coalesce(jsonb_agg(to_jsonb(vote) order by vote.voted_at desc), '[]'::jsonb)
      from (
        select vote.*
        from public.tcc_votes vote
        join public.tcc_submissions submission on submission.id = vote.submission_id
        where submission.employee_id = v_actor
        order by vote.voted_at desc
        limit 1000
      ) vote
    ),
    'courses', (
      select coalesce(jsonb_agg(to_jsonb(course) order by course.active desc, course.name), '[]'::jsonb)
      from public.courses course
    ),
    'courseRecords', (
      select coalesce(jsonb_agg(to_jsonb(record) order by record.assigned_at desc), '[]'::jsonb)
      from (
        select source.*
        from public.staff_course_records source
        where source.employee_id = v_actor
        order by source.assigned_at desc
        limit 200
      ) record
    ),
    'snapshots', (
      select coalesce(jsonb_agg(to_jsonb(snapshot) order by snapshot.reading_date), '[]'::jsonb)
      from public.rh_hour_snapshots snapshot
      where snapshot.employee_id = v_actor
    ),
    'absences', (
      select coalesce(jsonb_agg(to_jsonb(absence) order by absence.requested_at desc), '[]'::jsonb)
      from (
        select source.*
        from public.rh_absence_requests source
        where source.employee_id = v_actor
        order by source.requested_at desc
        limit 100
      ) absence
    ),
    'leaveAdjustments', (
      select coalesce(jsonb_agg(to_jsonb(adjustment) order by adjustment.week_start desc), '[]'::jsonb)
      from (
        select source.*
        from public.rh_leave_week_adjustments source
        where source.employee_id = v_actor
        order by source.week_start desc
        limit 250
      ) adjustment
    ),
    'weeklyRecords', (
      select coalesce(jsonb_agg(to_jsonb(record) order by record.week_start desc), '[]'::jsonb)
      from (
        select source.*
        from public.rh_weekly_records source
        where source.employee_id = v_actor
        order by source.week_start desc
        limit 100
      ) record
    ),
    'hourJustifications', (
      select coalesce(jsonb_agg(to_jsonb(justification) order by justification.submitted_at desc), '[]'::jsonb)
      from (
        select source.*
        from public.rh_hour_justifications source
        where source.employee_id = v_actor
        order by source.submitted_at desc
        limit 100
      ) justification
    ),
    'warnings', (
      select coalesce(jsonb_agg(to_jsonb(warning) order by warning.issued_at desc), '[]'::jsonb)
      from (
        select source.*
        from public.rh_warnings source
        where source.employee_id = v_actor
        order by source.issued_at desc
        limit 100
      ) warning
    )
  ) into v_result;

  return v_result;
end;
$$;

create or replace function public.hpsm_shell_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_permissions text[] := public.effective_permission_codes(v_actor);
  v_role_code text;
  v_notifications jsonb := '[]'::jsonb;
  v_unread_count integer := 0;
  v_pending_count integer := 0;
  v_weekly_inputs jsonb := null;
  v_today date := timezone('America/Sao_Paulo', now())::date;
  v_week_start date;
  v_cycle_month date;
begin
  select profile.role_code into v_role_code
  from public.profiles profile
  where profile.user_id = v_actor;

  with visible as materialized (
    select
      notification.id,
      notification.kind,
      notification.recipient_id,
      notification.audience,
      notification.priority,
      notification.title,
      notification.body,
      notification.action_url,
      notification.created_by,
      notification.created_at,
      notification.expires_at,
      notification.archived_at,
      notification.source_type,
      notification.source_id,
      notification.required_permission,
      notification.resolved_at,
      notification.resolved_by,
      read.read_at,
      coalesce(author.display_name, 'Sistema HPSM') as author_name,
      author.passport as author_passport
    from public.notifications notification
    left join public.notification_reads read
      on read.notification_id = notification.id and read.user_id = v_actor
    left join public.profiles author on author.user_id = notification.created_by
    where notification.archived_at is null
      and (notification.expires_at is null or notification.expires_at > now())
      and (
        notification.recipient_id = v_actor
        or notification.audience = 'all'
        or (
          notification.audience = 'directors'
          and case
            when notification.required_permission is not null
              then notification.required_permission = any(v_permissions)
            else 'hr.team.view' = any(v_permissions)
          end
        )
        or (
          notification.audience = 'employees'
          and not ('hr.team.view' = any(v_permissions))
        )
      )
  ), picked_ids as (
    (
      select visible.id
      from visible
      where visible.read_at is null and visible.resolved_at is null
      order by visible.created_at desc, visible.id desc
      limit 8
    )
    union
    (
      select visible.id
      from visible
      where visible.kind = 'announcement'
      order by (visible.read_at is null) desc, visible.created_at desc, visible.id desc
      limit 3
    )
  )
  select
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', visible.id,
        'kind', visible.kind,
        'recipient_id', visible.recipient_id,
        'audience', visible.audience,
        'priority', visible.priority,
        'title', visible.title,
        'body', visible.body,
        'action_url', visible.action_url,
        'created_by', visible.created_by,
        'created_at', visible.created_at,
        'expires_at', visible.expires_at,
        'archived_at', visible.archived_at,
        'source_type', visible.source_type,
        'source_id', visible.source_id,
        'required_permission', visible.required_permission,
        'resolved_at', visible.resolved_at,
        'resolved_by', visible.resolved_by,
        'read_at', visible.read_at,
        'author_name', visible.author_name,
        'author_passport', visible.author_passport
      ) order by visible.created_at desc, visible.id desc)
      from visible
      join picked_ids on picked_ids.id = visible.id
    ), '[]'::jsonb),
    (select count(*)::integer from visible where visible.read_at is null and visible.resolved_at is null)
  into v_notifications, v_unread_count;

  select
    (case when 'recruitment.manage' = any(v_permissions)
      then (select count(*) from public.recruitment_applications where status in ('submitted', 'under_review', 'interview')) else 0 end)
    + (case when 'hr.absences.review' = any(v_permissions)
      then (select count(*) from public.rh_absence_requests where status = 'pending') else 0 end)
    + (case when 'hr.justifications.review' = any(v_permissions)
      then (select count(*) from public.rh_hour_justifications where status = 'pending') else 0 end)
    + (case when 'hr.discipline.manage' = any(v_permissions) or 'hr.discipline.review' = any(v_permissions)
      then (select count(*) from public.rh_disciplinary_reviews where status = 'pending') else 0 end)
    + (case when 'progression.review' = any(v_permissions)
      then (select count(*) from public.staff_promotion_reviews where status = 'pending') else 0 end)
    + (case when 'tcc.vote' = any(v_permissions)
      then (select count(*) from public.tcc_submissions where status = 'submitted') else 0 end)
    + (case when 'healthplans.review' = any(v_permissions)
      then (select count(*) from public.patient_health_plan_requests where status = 'pending') else 0 end)
  into v_pending_count;

  if v_role_code <> 'diretor_geral' then
    v_week_start := v_today - (extract(isodow from v_today)::integer - 1);
    v_cycle_month := date_trunc('month', v_week_start + 6)::date;
    select jsonb_build_object(
      'snapshots', (
        select coalesce(jsonb_agg(to_jsonb(snapshot) order by snapshot.reading_date), '[]'::jsonb)
        from public.rh_hour_snapshots snapshot
        where snapshot.employee_id = v_actor
          and snapshot.reading_date >= date_trunc('month', v_week_start - 1)::date
          and snapshot.reading_date <= v_today
      ),
      'leaveAdjustments', (
        select coalesce(jsonb_agg(to_jsonb(adjustment) order by adjustment.week_start desc), '[]'::jsonb)
        from public.rh_leave_week_adjustments adjustment
        where adjustment.employee_id = v_actor
          and adjustment.week_start = v_week_start
      ),
      'weeklyRecords', (
        select coalesce(jsonb_agg(to_jsonb(record) order by record.week_start desc), '[]'::jsonb)
        from public.rh_weekly_records record
        where record.employee_id = v_actor
          and record.week_start = v_week_start
      ),
      'warnings', (
        select coalesce(jsonb_agg(to_jsonb(warning) order by warning.issued_at desc), '[]'::jsonb)
        from public.rh_warnings warning
        where warning.employee_id = v_actor
          and warning.cycle_month = v_cycle_month
      )
    ) into v_weekly_inputs;
  end if;

  return jsonb_build_object(
    'notifications', v_notifications,
    'unread_count', v_unread_count,
    'pending_count', v_pending_count,
    'weekly_inputs', v_weekly_inputs
  );
end;
$$;

revoke all on function public.hpsm_session_bootstrap()
  from public, anon, authenticated, service_role;
revoke all on function public.hpsm_dashboard_summary()
  from public, anon, authenticated, service_role;
revoke all on function public.hpsm_attendance_history(integer)
  from public, anon, authenticated, service_role;
revoke all on function public.hpsm_my_hr_snapshot()
  from public, anon, authenticated, service_role;
revoke all on function public.hpsm_shell_snapshot()
  from public, anon, authenticated, service_role;

grant execute on function public.hpsm_session_bootstrap() to authenticated;
grant execute on function public.hpsm_dashboard_summary() to authenticated;
grant execute on function public.hpsm_attendance_history(integer) to authenticated;
grant execute on function public.hpsm_my_hr_snapshot() to authenticated;
grant execute on function public.hpsm_shell_snapshot() to authenticated;

comment on function public.hpsm_session_bootstrap() is
  'Contexto mínimo da sessão atual: perfil, cargo e permissões em uma única ida ao banco, com validação da sessão Auth.';
comment on function public.hpsm_dashboard_summary() is
  'Resumo operacional compacto e autorizado da Dashboard.';
comment on function public.hpsm_attendance_history(integer) is
  'Histórico autorizado de atendimentos com itens e identidade profissional resolvidos em lote.';
comment on function public.hpsm_my_hr_snapshot() is
  'Snapshot pessoal canônico de RH e carreira, limitado ao usuário autenticado.';
comment on function public.hpsm_shell_snapshot() is
  'Dados secundários compactos do App Shell: notificações, pendências e meta semanal.';

notify pgrst, 'reload schema';
