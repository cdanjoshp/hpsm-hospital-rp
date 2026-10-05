-- HPSM · Fase 9 — Dashboard final do sistema profissional.
-- Consolida dados canônicos e autorizados sem criar tabela de snapshot ou regra paralela.

set lock_timeout = '5s';
set statement_timeout = '120s';

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
  v_today date := timezone('America/Sao_Paulo', now())::date;
  v_week_start date;
  v_week_end date;
  v_cycle_month date;
  v_role_code text;
  v_current_position jsonb;
  v_weekly_inputs jsonb := null;
  v_production jsonb := '{}'::jsonb;
  v_career jsonb := '{}'::jsonb;
  v_attention_items jsonb := '[]'::jsonb;
  v_attention_total integer := 0;
  v_management_pending integer := 0;
  v_announcements jsonb := '[]'::jsonb;
  v_hospital jsonb := null;
  v_count integer := 0;
  v_recruitment_count integer := 0;
begin
  v_week_start := v_today - (extract(isodow from v_today)::integer - 1);
  v_week_end := v_week_start + 6;
  v_cycle_month := date_trunc('month', v_week_end)::date;

  select
    profile.role_code,
    jsonb_build_object(
      'id', position.id,
      'name', coalesce(position.name, 'Cargo não definido'),
      'level', position.level,
      'advancement_mode', position.advancement_mode
    )
  into v_role_code, v_current_position
  from public.profiles profile
  left join public.staff_positions position on position.id = profile.position_id
  where profile.user_id = v_actor
    and profile.status = 'active';

  if v_role_code is null then
    raise exception 'Perfil ativo não localizado.' using errcode = '42501';
  end if;

  -- Mesmos insumos mínimos usados pelo widget global e por Meu RH. O cálculo
  -- final permanece no helper canônico buildWeeklyProgress da aplicação.
  if v_role_code <> 'diretor_geral' then
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

  -- Mesma definição financeira da Fase 8: somente atendimentos concluídos,
  -- total histórico do atendimento e quantidades preservadas nos itens.
  with week_attendances as materialized (
    select attendance.id, attendance.total
    from public.attendances attendance
    where attendance.performed_by = v_actor
      and attendance.status = 'completed'
      and attendance.created_at >= (v_week_start::timestamp at time zone 'America/Sao_Paulo')
      and attendance.created_at < ((v_week_end + 1)::timestamp at time zone 'America/Sao_Paulo')
  )
  select jsonb_build_object(
    'attendance_count', count(*)::integer,
    'item_count', coalesce((
      select sum(item.quantity)::integer
      from public.attendance_items item
      join week_attendances attendance on attendance.id = item.attendance_id
    ), 0),
    'total_amount', coalesce(sum(attendance.total), 0)
  )
  into v_production
  from week_attendances attendance;

  v_career := jsonb_build_object(
    'current_position', coalesce(v_current_position, 'null'::jsonb),
    'progression', coalesce(private.get_staff_progression_status(v_actor), '{}'::jsonb)
  );

  -- Pendências pessoais reais. Não criam estado paralelo e apenas apontam
  -- para Meu RH, onde a ação ou o acompanhamento continuam acontecendo.
  select count(*)::integer into v_count
  from public.rh_weekly_records record
  where record.employee_id = v_actor
    and record.week_start = v_week_start
    and record.closure_status in ('awaiting_justification', 'justification_pending');
  if v_count > 0 then
    v_attention_items := v_attention_items || jsonb_build_array(jsonb_build_object(
      'kind', 'personal_hours',
      'count', v_count,
      'href', '/meu-rh',
      'label', case
        when exists (
          select 1 from public.rh_weekly_records record
          where record.employee_id = v_actor
            and record.week_start = v_week_start
            and record.closure_status = 'awaiting_justification'
        ) then 'Justificativa de horas necessária'
        else 'Justificativa de horas em análise'
      end,
      'tone', 'important'
    ));
    v_attention_total := v_attention_total + v_count;
  end if;

  select count(*)::integer into v_count
  from public.rh_absence_requests absence
  where absence.employee_id = v_actor
    and absence.status = 'pending';
  if v_count > 0 then
    v_attention_items := v_attention_items || jsonb_build_array(jsonb_build_object(
      'kind', 'personal_absence',
      'count', v_count,
      'href', '/meu-rh',
      'label', 'Afastamento aguardando análise',
      'tone', 'normal'
    ));
    v_attention_total := v_attention_total + v_count;
  end if;

  -- As filas administrativas repetem exatamente a matriz da Central de
  -- Pendências. Cada tabela só é consultada quando a permissão efetiva existe.
  if 'recruitment.manage' = any(v_permissions) then
    select count(*)::integer into v_count
    from public.recruitment_applications application
    where application.status in ('submitted', 'under_review', 'interview');
    v_recruitment_count := v_count;
    if v_count > 0 then
      v_attention_items := v_attention_items || jsonb_build_array(jsonb_build_object(
        'kind', 'recruitment', 'count', v_count,
        'href', '/administrativo/pendencias#recrutamento',
        'label', 'Candidaturas aguardando análise', 'tone', 'normal'
      ));
    end if;
    v_management_pending := v_management_pending + v_count;
  end if;

  if 'hr.absences.review' = any(v_permissions) then
    select count(*)::integer into v_count
    from public.rh_absence_requests absence where absence.status = 'pending';
    if v_count > 0 then
      v_attention_items := v_attention_items || jsonb_build_array(jsonb_build_object(
        'kind', 'absence', 'count', v_count,
        'href', '/administrativo/pendencias#ausencias',
        'label', 'Afastamentos aguardando análise', 'tone', 'important'
      ));
    end if;
    v_management_pending := v_management_pending + v_count;
  end if;

  if 'hr.justifications.review' = any(v_permissions) then
    select count(*)::integer into v_count
    from public.rh_hour_justifications justification where justification.status = 'pending';
    if v_count > 0 then
      v_attention_items := v_attention_items || jsonb_build_array(jsonb_build_object(
        'kind', 'hour_justification', 'count', v_count,
        'href', '/administrativo/pendencias#ausencias',
        'label', 'Justificativas de horas aguardando análise', 'tone', 'important'
      ));
    end if;
    v_management_pending := v_management_pending + v_count;
  end if;

  if 'hr.discipline.manage' = any(v_permissions) or 'hr.discipline.review' = any(v_permissions) then
    select count(*)::integer into v_count
    from public.rh_disciplinary_reviews review where review.status = 'pending';
    if v_count > 0 then
      v_attention_items := v_attention_items || jsonb_build_array(jsonb_build_object(
        'kind', 'discipline', 'count', v_count,
        'href', '/administrativo/pendencias#disciplina',
        'label', 'Análises disciplinares pendentes', 'tone', 'urgent'
      ));
    end if;
    v_management_pending := v_management_pending + v_count;
  end if;

  if 'progression.review' = any(v_permissions) then
    select count(*)::integer into v_count
    from public.staff_promotion_reviews review where review.status = 'pending';
    if v_count > 0 then
      v_attention_items := v_attention_items || jsonb_build_array(jsonb_build_object(
        'kind', 'career', 'count', v_count,
        'href', '/administrativo/pendencias#carreira',
        'label', 'Promoções aguardando decisão', 'tone', 'important'
      ));
    end if;
    v_management_pending := v_management_pending + v_count;
  end if;

  if 'healthplans.review' = any(v_permissions) then
    select count(*)::integer into v_count
    from public.patient_health_plan_requests request where request.status = 'pending';
    if v_count > 0 then
      v_attention_items := v_attention_items || jsonb_build_array(jsonb_build_object(
        'kind', 'health_plan', 'count', v_count,
        'href', '/administrativo/pendencias#planos-saude',
        'label', 'Planos aguardando confirmação', 'tone', 'important'
      ));
    end if;
    v_management_pending := v_management_pending + v_count;
  end if;

  if 'casts.view' = any(v_permissions) and 'casts.manage' = any(v_permissions) then
    select count(*)::integer into v_count
    from public.clinical_casts cast_record
    where cast_record.status = 'in_use'
      and cast_record.expected_removal_at <= now();
    if v_count > 0 then
      v_attention_items := v_attention_items || jsonb_build_array(jsonb_build_object(
        'kind', 'cast', 'count', v_count,
        'href', '/administrativo/pendencias#gessos',
        'label', 'Gessos com retirada prevista ultrapassada', 'tone', 'urgent'
      ));
    end if;
    v_management_pending := v_management_pending + v_count;
  end if;

  v_attention_total := v_attention_total + v_management_pending;

  -- Três comunicados compactos. O corpo não integra o payload do Dashboard.
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', announcement.id,
    'title', announcement.title,
    'priority', announcement.priority,
    'action_url', announcement.action_url,
    'created_at', announcement.created_at,
    'author_name', announcement.author_name,
    'read_at', announcement.read_at
  ) order by announcement.unread desc, announcement.created_at desc, announcement.id desc), '[]'::jsonb)
  into v_announcements
  from (
    select
      notification.id,
      notification.title,
      notification.priority,
      notification.action_url,
      notification.created_at,
      coalesce(author.display_name, 'Sistema HPSM') as author_name,
      read.read_at,
      (read.read_at is null) as unread
    from public.notifications notification
    left join public.notification_reads read
      on read.notification_id = notification.id and read.user_id = v_actor
    left join public.profiles author on author.user_id = notification.created_by
    where notification.kind = 'announcement'
      and notification.archived_at is null
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
    order by (read.read_at is null) desc, notification.created_at desc, notification.id desc
    limit 3
  ) announcement;

  -- A visão gerencial só nasce para quem pode abrir Relatórios e reutiliza
  -- diretamente o agregador canônico da Fase 8, inclusive permissões parciais.
  if 'hr.reports.view' = any(v_permissions) then
    v_hospital := public.hpsm_report_overview(v_week_start, v_week_end)
      || jsonb_build_object('pending_count', v_management_pending)
      || case when 'recruitment.manage' = any(v_permissions)
        then jsonb_build_object('recruitment_pending', v_recruitment_count)
        else '{}'::jsonb
      end;
  end if;

  return jsonb_build_object(
    'period', jsonb_build_object('start', v_week_start, 'end', v_week_end),
    'weekly_inputs', v_weekly_inputs,
    'production', v_production,
    'career', v_career,
    'attention', jsonb_build_object('total', v_attention_total, 'items', v_attention_items),
    'announcements', v_announcements,
    'hospital', v_hospital
  );
end;
$$;

revoke all on function public.hpsm_dashboard_summary()
  from public, anon, authenticated, service_role;
grant execute on function public.hpsm_dashboard_summary()
  to authenticated;

comment on function public.hpsm_dashboard_summary() is
  'Dashboard profissional permission-aware da Fase 9; reutiliza Jornada, Progressão, Pendências, Comunicados e Relatórios sem criar fonte paralela.';
