-- Fase 3: estabilidade de carreira e leitura segura do Perfil do Paciente.

alter table public.staff_position_history
  drop constraint if exists staff_position_history_event_check;

alter table public.staff_position_history
  add constraint staff_position_history_event_check check (
    event_type in ('initial_assignment', 'promotion', 'appointment', 'succession', 'override')
  );

create or replace function private.staff_worked_minutes_since(
  p_employee_id uuid,
  p_since timestamptz
)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  with bounds as (
    select
      p_since::date as since_date,
      (now() at time zone 'America/Sao_Paulo')::date as through_date
  ), months as (
    select month_start::date
    from bounds,
      lateral generate_series(
        date_trunc('month', bounds.since_date)::date,
        date_trunc('month', bounds.through_date)::date,
        interval '1 month'
      ) as month_start
  ), periods as (
    select
      months.month_start,
      greatest(months.month_start, bounds.since_date) as period_start,
      least((months.month_start + interval '1 month - 1 day')::date, bounds.through_date) as period_end
    from months cross join bounds
  ), readings as (
    select
      periods.month_start,
      periods.period_start,
      end_reading.total_minutes as end_total,
      case
        when periods.period_start = periods.month_start then 0
        else baseline.total_minutes
      end as baseline_total
    from periods
    left join lateral (
      select snapshot.total_minutes
      from public.rh_hour_snapshots snapshot
      where snapshot.employee_id = p_employee_id
        and snapshot.reference_month = periods.month_start
        and snapshot.reading_date <= periods.period_end
      order by snapshot.reading_date desc, snapshot.updated_at desc
      limit 1
    ) end_reading on true
    left join lateral (
      select snapshot.total_minutes
      from public.rh_hour_snapshots snapshot
      where snapshot.employee_id = p_employee_id
        and snapshot.reference_month = periods.month_start
        and snapshot.reading_date < periods.period_start
      order by snapshot.reading_date desc, snapshot.updated_at desc
      limit 1
    ) baseline on periods.period_start <> periods.month_start
  )
  select coalesce(sum(
    case
      when end_total is null or baseline_total is null then 0
      else greatest(0, end_total - baseline_total)
    end
  ), 0)::integer
  from readings;
$$;

revoke all on function private.staff_worked_minutes_since(uuid, timestamptz) from public, anon, authenticated;
grant execute on function private.staff_worked_minutes_since(uuid, timestamptz) to service_role;

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
  v_tcc boolean := false;
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
  select exists (
    select 1 from public.tcc_submissions submission
    where submission.employee_id = p_employee_id and submission.status = 'approved'
  ) into v_tcc;
  v_eligible := v_profile.status = 'active'
    and v_warnings < 3
    and v_elapsed >= v_required_days
    and v_worked >= v_rule.min_worked_minutes
    and v_attendances >= v_rule.min_attendances
    and (not v_rule.requires_tcc or v_tcc);
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
    'requires_tcc', v_rule.requires_tcc,
    'tcc_approved', v_tcc,
    'eligible', v_eligible,
    'blocked', v_warnings >= 3 or v_profile.status <> 'active'
  );
end;
$$;

create or replace function public.override_staff_position(
  p_employee_id uuid,
  p_to_position_id bigint,
  p_note text,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor public.profiles;
  v_actor_position public.staff_positions;
  v_employee public.profiles;
  v_from public.staff_positions;
  v_to public.staff_positions;
  v_history public.staff_position_history;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  select * into v_actor from public.profiles where user_id = p_actor_id;
  select * into v_actor_position from public.staff_positions where id = v_actor.position_id;
  if not found
     or v_actor.role_code <> 'diretor_geral'
     or v_actor.status <> 'active'
     or v_actor_position.level <> 14 then
    raise exception using errcode = '42501', message = 'Somente o Diretor Geral pode alterar cargos diretamente.';
  end if;
  if p_employee_id = p_actor_id then
    raise exception using errcode = '42501', message = 'O cargo de Diretor Geral só pode ser alterado pelo fluxo de sucessão.';
  end if;
  if v_note is not null and char_length(v_note) not between 2 and 2000 then
    raise exception using errcode = '22023', message = 'A observação deve possuir entre 2 e 2000 caracteres.';
  end if;

  select * into v_employee from public.profiles where user_id = p_employee_id for update;
  if not found or v_employee.status = 'inactive' or v_employee.role_code = 'diretor_geral' then
    raise exception using errcode = '22023', message = 'Colaborador indisponível para alteração direta de cargo.';
  end if;
  select * into v_from from public.staff_positions where id = v_employee.position_id;
  select * into v_to from public.staff_positions where id = p_to_position_id and active;
  if not found or v_to.level = 14 then
    raise exception using errcode = '22023', message = 'O cargo de Diretor Geral exige o fluxo de sucessão.';
  end if;
  if v_employee.position_id = v_to.id then
    raise exception using errcode = '22023', message = 'Selecione um cargo diferente do atual.';
  end if;

  perform set_config('hpsm.position_change_authorized', 'true', true);
  update public.profiles
  set position_id = v_to.id, updated_by = p_actor_id, updated_at = now()
  where user_id = p_employee_id and position_id is not distinct from v_employee.position_id;
  if not found then
    raise exception using errcode = '40001', message = 'O cargo foi alterado durante a operação. Atualize a página.';
  end if;

  update public.staff_promotion_reviews
  set status = 'cancelled', decided_by = p_actor_id, decided_at = now(),
      decision_note = 'Encerrada por alteração direta de cargo pelo Diretor Geral.', updated_at = now()
  where employee_id = p_employee_id and status in ('pending', 'deferred');

  insert into public.staff_position_history (
    employee_id, from_position_id, to_position_id, event_type, decided_by, note
  ) values (
    p_employee_id, v_employee.position_id, v_to.id, 'override', p_actor_id, v_note
  ) returning * into v_history;

  insert into public.notifications (
    kind, recipient_id, priority, title, body, action_url, created_by
  ) values (
    'personal', p_employee_id, 'important', 'Cargo alterado pela Direção Geral',
    format('Seu cargo foi alterado para %s. Consulte o histórico no Meu RH.', v_to.name),
    '/meu-rh', p_actor_id
  );

  return to_jsonb(v_history);
end;
$$;

revoke all on function public.override_staff_position(uuid, bigint, text, uuid) from public, anon, authenticated;
grant execute on function public.override_staff_position(uuid, bigint, text, uuid) to service_role;

drop function if exists public.patient_activity_page(bigint, text, integer, integer);

create function public.patient_activity_page(
  p_patient_id bigint,
  p_kind text default 'all',
  p_month date default null,
  p_limit integer default 10,
  p_offset integer default 0
)
returns table (
  total_count bigint,
  records jsonb,
  selected_month text,
  available_months jsonb,
  monthly_total numeric,
  monthly_count bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_selected_month date;
  v_months jsonb;
begin
  if not private.has_permission((select auth.uid()), 'patients.view') then
    raise exception using errcode = '42501', message = 'Você não possui permissão para consultar pacientes.';
  end if;
  if p_kind not in ('all', 'purchases', 'procedures') then
    raise exception using errcode = '22023', message = 'Tipo de histórico inválido.';
  end if;
  if p_limit < 1 or p_limit > 50 or p_offset < 0 then
    raise exception using errcode = '22023', message = 'Paginação inválida.';
  end if;
  if p_month is not null and p_month <> date_trunc('month', p_month)::date then
    raise exception using errcode = '22023', message = 'Competência mensal inválida.';
  end if;

  select coalesce(
    p_month,
    max(date_trunc('month', attendance.created_at at time zone 'America/Sao_Paulo')::date),
    date_trunc('month', now() at time zone 'America/Sao_Paulo')::date
  ) into v_selected_month
  from public.attendances attendance
  where attendance.patient_id = p_patient_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'month', month_row.month_code,
    'count', month_row.record_count,
    'total', month_row.total_value
  ) order by month_row.month_code desc), '[]'::jsonb)
  into v_months
  from (
    select
      to_char(date_trunc('month', attendance.created_at at time zone 'America/Sao_Paulo'), 'YYYY-MM') as month_code,
      count(*) filter (where attendance.status = 'completed')::bigint as record_count,
      coalesce(sum(attendance.total) filter (where attendance.status = 'completed'), 0)::numeric as total_value
    from public.attendances attendance
    where attendance.patient_id = p_patient_id
    group by date_trunc('month', attendance.created_at at time zone 'America/Sao_Paulo')
  ) month_row;

  return query
  with matching as materialized (
    select attendance.*
    from public.attendances attendance
    where attendance.patient_id = p_patient_id
      and attendance.created_at >= (v_selected_month::timestamp at time zone 'America/Sao_Paulo')
      and attendance.created_at < ((v_selected_month + interval '1 month')::timestamp at time zone 'America/Sao_Paulo')
      and (
        p_kind = 'all'
        or exists (
          select 1
          from public.attendance_items item
          join public.service_catalog service on service.id = item.service_id
          where item.attendance_id = attendance.id
            and (
              (p_kind = 'purchases' and lower(service.category) in ('insumos', 'medicamentos', 'produtos', 'convênios'))
              or (p_kind = 'procedures' and lower(service.category) in ('atendimentos', 'exames'))
            )
        )
      )
  ), page as (
    select matching.*
    from matching
    order by matching.created_at desc, matching.id desc
    limit p_limit offset p_offset
  ), rendered as (
    select
      page.created_at,
      page.id,
      jsonb_build_object(
        'id', page.id,
        'created_at', page.created_at,
        'status', page.status,
        'patient_name', page.patient_name,
        'patient_passport', page.patient_passport,
        'plan_code', page.plan_code,
        'plan_name', page.plan_name,
        'subtotal', page.subtotal,
        'discount', page.discount,
        'total', page.total,
        'notes', page.notes,
        'professional_name', coalesce(professional.display_name, 'Profissional'),
        'professional_passport', coalesce(professional.passport, '—'),
        'professional_position', coalesce(position.name, 'Cargo não definido'),
        'items', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', item.id,
            'service_id', item.service_id,
            'service_name', item.service_name,
            'category', service.category,
            'code', service.code,
            'unit_price', item.unit_price,
            'quantity', item.quantity,
            'discount_percent', item.discount_percent,
            'discount_amount', item.discount_amount,
            'line_total', item.line_total
          ) order by item.id)
          from public.attendance_items item
          join public.service_catalog service on service.id = item.service_id
          where item.attendance_id = page.id
            and (
              p_kind = 'all'
              or (p_kind = 'purchases' and lower(service.category) in ('insumos', 'medicamentos', 'produtos', 'convênios'))
              or (p_kind = 'procedures' and lower(service.category) in ('atendimentos', 'exames'))
            )
        ), '[]'::jsonb)
      ) as record
    from page
    left join public.profiles professional on professional.user_id = page.performed_by
    left join public.staff_positions position on position.id = professional.position_id
  )
  select
    (select count(*) from matching)::bigint,
    coalesce(jsonb_agg(rendered.record order by rendered.created_at desc, rendered.id desc), '[]'::jsonb),
    to_char(v_selected_month, 'YYYY-MM'),
    v_months,
    coalesce((select sum(matching.total) from matching where matching.status = 'completed'), 0)::numeric,
    (select count(*) from matching where matching.status = 'completed')::bigint
  from rendered;
end;
$$;

revoke all on function public.patient_activity_page(bigint, text, date, integer, integer) from public, anon, authenticated;
grant execute on function public.patient_activity_page(bigint, text, date, integer, integer) to authenticated;

alter function public.patient_timeline(bigint, integer) security definer;
alter function public.patient_plan_history_page(bigint, integer, integer) security definer;

revoke all on function public.patient_timeline(bigint, integer) from public, anon, authenticated;
revoke all on function public.patient_plan_history_page(bigint, integer, integer) from public, anon, authenticated;
grant execute on function public.patient_timeline(bigint, integer) to authenticated;
grant execute on function public.patient_plan_history_page(bigint, integer, integer) to authenticated;

notify pgrst, 'reload schema';
