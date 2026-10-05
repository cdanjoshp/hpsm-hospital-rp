-- HPSM · descomissionamento total e definitivo do TCC.
-- Carreira, cursos, progressão normal e auditoria genérica permanecem intactos.

set lock_timeout = '5s';
set statement_timeout = '120s';

-- A progressão dos níveis 1–10 passa a depender exclusivamente dos critérios
-- normais: tempo, horas, atendimentos, advertências e situação ativa.
create or replace function private.get_staff_progression_status(p_employee_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles;
  v_position public.staff_positions;
  v_next public.staff_positions;
  v_rule public.staff_position_transition_rules;
  v_since timestamptz;
  v_elapsed integer := 0;
  v_worked integer := 0;
  v_attendances integer := 0;
  v_warnings integer := 0;
  v_required_days integer := 15;
  v_eligible boolean := false;
begin
  select * into v_profile from public.profiles where user_id = p_employee_id;
  if not found or v_profile.position_id is null then
    return jsonb_build_object('employee_id', p_employee_id, 'eligible', false, 'reason', 'Cargo não definido');
  end if;
  select * into v_position from public.staff_positions where id = v_profile.position_id;
  if v_position.level >= 10 then
    return jsonb_build_object(
      'employee_id', p_employee_id, 'position_id', v_position.id,
      'level', v_position.level, 'eligible', false,
      'reason', case when v_position.level = 10 then 'Próximo cargo depende de nomeação' else 'Cargo de gestão' end
    );
  end if;
  select * into v_next from public.staff_positions where level = v_position.level + 1 and active;
  select * into v_rule from public.staff_position_transition_rules
  where from_position_id = v_position.id and to_position_id = v_next.id and active;
  select coalesce(max(history.effective_at), v_profile.created_at) into v_since
  from public.staff_position_history history
  where history.employee_id = p_employee_id and history.to_position_id = v_position.id;
  v_elapsed := greatest(0, floor(extract(epoch from (now() - v_since)) / 86400)::integer);
  v_worked := private.staff_worked_minutes_since(p_employee_id, v_since);
  select count(*)::integer into v_attendances
  from public.attendances attendance
  where attendance.performed_by = p_employee_id
    and attendance.status = 'completed'
    and attendance.created_at >= v_since;
  select count(*)::integer into v_warnings
  from public.rh_warnings warning
  where warning.employee_id = p_employee_id
    and warning.status = 'active'
    and warning.impacts_progression
    and warning.issued_at >= v_since;
  v_required_days := case when v_warnings = 0 then v_rule.min_days when v_warnings = 1 then 30 else 60 end;
  v_eligible := v_profile.status = 'active'
    and v_warnings < 3
    and v_elapsed >= v_required_days
    and v_worked >= v_rule.min_worked_minutes
    and v_attendances >= v_rule.min_attendances;
  return jsonb_build_object(
    'employee_id', p_employee_id,
    'position_id', v_position.id,
    'position_name', v_position.name,
    'level', v_position.level,
    'next_position_id', v_next.id,
    'next_position_name', v_next.name,
    'since', v_since,
    'elapsed_days', v_elapsed,
    'required_days', v_required_days,
    'worked_minutes', v_worked,
    'required_worked_minutes', v_rule.min_worked_minutes,
    'attendance_count', v_attendances,
    'required_attendances', v_rule.min_attendances,
    'flagged_warning_count', v_warnings,
    'eligible', v_eligible,
    'blocked', v_warnings >= 3 or v_profile.status <> 'active'
  );
end;
$$;

create or replace function private.ensure_staff_promotion_review(p_employee_id uuid)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status jsonb;
  v_id bigint;
begin
  v_status := private.get_staff_progression_status(p_employee_id);
  if coalesce((v_status ->> 'eligible')::boolean, false) is not true then return null; end if;
  select id into v_id from public.staff_promotion_reviews
  where employee_id = p_employee_id and status in ('pending', 'deferred')
  order by created_at desc limit 1;
  if v_id is not null then return v_id; end if;
  insert into public.staff_promotion_reviews (
    employee_id, from_position_id, to_position_id, required_days,
    elapsed_days, worked_minutes, attendance_count, flagged_warning_count
  ) values (
    p_employee_id, (v_status ->> 'position_id')::bigint,
    (v_status ->> 'next_position_id')::bigint,
    (v_status ->> 'required_days')::smallint,
    (v_status ->> 'elapsed_days')::integer,
    (v_status ->> 'worked_minutes')::integer,
    (v_status ->> 'attendance_count')::integer,
    (v_status ->> 'flagged_warning_count')::integer
  ) returning id into v_id;
  return v_id;
end;
$$;

-- O snapshot de Meu RH preserva progressão, cursos e todos os fluxos de RH.
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

-- O contador global preserva todas as filas correntes, sem a fila removida.
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
    + (case when 'healthplans.review' = any(v_permissions)
      then (select count(*) from public.patient_health_plan_requests where status = 'pending') else 0 end)
    + (case when 'casts.view' = any(v_permissions) and 'casts.manage' = any(v_permissions)
      then (select count(*) from public.clinical_casts where status = 'in_use' and expected_removal_at <= now()) else 0 end)
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

-- A configuração de pacotes continua canônica e mantém todas as proteções
-- críticas, sem a exceção específica da funcionalidade removida.
create or replace function public.set_staff_position_permissions(
  p_position_id bigint,
  p_permission_codes jsonb,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text;
  v_codes text[] := array[]::text[];
  v_level smallint;
begin
  if not private.has_permission(p_actor_id, 'access.manage')
     or private.current_position_level(p_actor_id) <> 14 then
    raise exception using errcode = '42501', message = 'Somente o Diretor Geral pode configurar os pacotes de acesso.';
  end if;
  select level into v_level from public.staff_positions where id = p_position_id;
  if v_level is null or p_permission_codes is null or jsonb_typeof(p_permission_codes) <> 'array' then
    raise exception using errcode = '22023', message = 'Cargo ou permissões inválidas.';
  end if;
  for v_code in select jsonb_array_elements_text(p_permission_codes)
  loop
    if not exists (select 1 from public.system_permissions where code = v_code)
       or v_code = any(v_codes) then
      raise exception using errcode = '22023', message = 'A lista contém permissão inválida ou repetida.';
    end if;
    v_codes := array_append(v_codes, v_code);
  end loop;
  if v_level = 14 and exists (
    select 1 from public.system_permissions permission where not (permission.code = any(v_codes))
  ) then
    raise exception using errcode = '23514', message = 'O Diretor Geral deve manter acesso total.';
  end if;
  if v_level <> 14 and v_codes && array['access.manage', 'access.grants.manage', 'succession.manage', 'settings.critical']::text[] then
    raise exception using errcode = '42501', message = 'Permissões críticas são exclusivas do Diretor Geral.';
  end if;
  delete from public.staff_position_permissions where position_id = p_position_id;
  insert into public.staff_position_permissions (position_id, permission_code, granted_by)
  select p_position_id, code, p_actor_id from unnest(v_codes) code;
  update public.staff_positions set updated_by = p_actor_id, updated_at = now() where id = p_position_id;
  return jsonb_build_object('position_id', p_position_id, 'permission_codes', to_jsonb(v_codes));
end;
$$;

-- Remove notificações operacionais da funcionalidade, preservando audit_logs.
delete from public.notification_reads
where notification_id in (
  select notification.id
  from public.notifications notification
  where notification.source_type = 'tcc_submission'
     or notification.required_permission in ('tcc.submit', 'tcc.vote')
     or lower(coalesce(notification.action_url, '')) like '%/career/tcc%'
     or lower(coalesce(notification.title, '')) like '%tcc%'
     or lower(coalesce(notification.body, '')) like '%tcc%'
);

delete from public.notifications notification
where notification.source_type = 'tcc_submission'
   or notification.required_permission in ('tcc.submit', 'tcc.vote')
   or lower(coalesce(notification.action_url, '')) like '%/career/tcc%'
   or lower(coalesce(notification.title, '')) like '%tcc%'
   or lower(coalesce(notification.body, '')) like '%tcc%';

-- Remove as capacidades do catálogo e todas as concessões associadas.
delete from public.user_permission_grants
where permission_code in ('tcc.submit', 'tcc.vote');

delete from public.staff_position_permissions
where permission_code in ('tcc.submit', 'tcc.vote');

delete from public.system_permissions
where code in ('tcc.submit', 'tcc.vote');

-- Desliga dependências externas antes de excluir as estruturas exclusivas.
drop policy if exists tcc_documents_insert_own on storage.objects;
drop policy if exists tcc_documents_read_own_or_voter on storage.objects;

drop trigger if exists tcc_submissions_notify on public.tcc_submissions;
drop function if exists private.notify_tcc_submission();
drop function if exists public.register_tcc_submission(uuid, text, text, text, text, bigint, uuid);
drop function if exists public.cast_tcc_vote(uuid, text, uuid);

drop table if exists public.tcc_votes;
drop table if exists public.tcc_submissions;

alter table public.staff_promotion_reviews
  drop column if exists tcc_approved;

alter table public.staff_position_transition_rules
  drop column if exists requires_tcc;

-- O bucket foi verificado vazio. O bloqueio evita órfãos caso a migração seja
-- reaplicada em outro ambiente que ainda contenha objetos.
do $$
begin
  if exists (select 1 from storage.objects where bucket_id = 'tcc-documents') then
    raise exception 'O bucket tcc-documents ainda possui objetos e deve ser esvaziado pela Storage API antes desta migração.';
  end if;
  perform set_config('storage.allow_delete_query', 'true', true);
  delete from storage.buckets where id = 'tcc-documents';
  perform set_config('storage.allow_delete_query', 'false', true);
end;
$$;

reset lock_timeout;
reset statement_timeout;
