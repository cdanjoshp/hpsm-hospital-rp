-- HPSM · Fase 3.1 — Central de Pacientes.
-- Camada de consulta derivada: não duplica atendimentos, itens ou histórico de planos.

create extension if not exists pg_trgm with schema extensions;

insert into public.system_permissions (code, module, label, description, sort_order)
values (
  'patients.manage',
  'Pacientes',
  'Alterar cadastro de pacientes',
  'Permite corrigir os dados cadastrais dos pacientes, com registro em auditoria.',
  104
)
on conflict (code) do update
set module = excluded.module,
    label = excluded.label,
    description = excluded.description,
    sort_order = excluded.sort_order;

with actor as (
  select user_id
  from public.profiles
  where role_code = 'diretor_geral'
  order by created_at
  limit 1
)
insert into public.staff_position_permissions (position_id, permission_code, granted_by)
select position.id, 'patients.manage', actor.user_id
from public.staff_positions as position
cross join actor
where position.level between 11 and 14
on conflict (position_id, permission_code) do nothing;

drop policy if exists patients_read_active on public.patients;
drop policy if exists patients_insert_active on public.patients;
drop policy if exists patients_update_active on public.patients;
drop policy if exists patients_update_director on public.patients;

create policy patients_read_authorized
on public.patients for select
to authenticated
using (private.has_permission((select auth.uid()), 'patients.view'));

create policy patients_insert_authorized
on public.patients for insert
to authenticated
with check (
  private.has_permission((select auth.uid()), 'patients.view')
  and created_by = (select auth.uid())
  and updated_by = (select auth.uid())
);

create policy patients_update_authorized
on public.patients for update
to authenticated
using (private.has_permission((select auth.uid()), 'patients.manage'))
with check (
  private.has_permission((select auth.uid()), 'patients.manage')
  and updated_by = (select auth.uid())
);

drop policy if exists attendances_read_own_or_authorized on public.attendances;
drop policy if exists attendances_read_own_manage_or_patient_center on public.attendances;
create policy attendances_read_own_manage_or_patient_center
on public.attendances for select
to authenticated
using (
  private.is_active_user()
  and (
    performed_by = (select auth.uid())
    or private.has_permission((select auth.uid()), 'attendances.manage')
    or private.has_permission((select auth.uid()), 'patients.view')
  )
);

drop policy if exists attendance_items_read_visible_attendance on public.attendance_items;
create policy attendance_items_read_visible_attendance
on public.attendance_items for select
to authenticated
using (
  private.is_active_user()
  and exists (
    select 1
    from public.attendances
    where attendances.id = attendance_items.attendance_id
      and (
        attendances.performed_by = (select auth.uid())
        or private.has_permission((select auth.uid()), 'attendances.manage')
        or private.has_permission((select auth.uid()), 'patients.view')
      )
  )
);

drop policy if exists patient_health_plan_requests_read_reviewers on public.patient_health_plan_requests;
drop policy if exists patient_health_plan_requests_read_patient_center on public.patient_health_plan_requests;
create policy patient_health_plan_requests_read_patient_center
on public.patient_health_plan_requests for select
to authenticated
using (
  private.has_permission((select auth.uid()), 'healthplans.review')
  or private.has_permission((select auth.uid()), 'patients.view')
);

create index if not exists patients_name_trgm_idx
  on public.patients using gin (name extensions.gin_trgm_ops);

create index if not exists patient_health_plan_requests_patient_requested_idx
  on public.patient_health_plan_requests (patient_id, requested_at desc, id desc);

create or replace view public.patient_directory
with (security_invoker = true)
as
select
  patient.id,
  patient.passport,
  patient.name,
  patient.phone,
  patient.emergency_contact_name,
  patient.emergency_contact_phone,
  patient.created_at,
  patient.updated_at,
  last_attendance.created_at as last_attendance_at,
  case
    when approved.coverage_end > now() then 'active'
    when approved.id is not null then 'expired'
    when pending.id is not null then 'awaiting_confirmation'
    else 'none'
  end as plan_status,
  approved.coverage_start as plan_activated_at,
  approved.coverage_end as plan_valid_until,
  approved.reviewed_by as plan_authorized_by,
  reviewer.display_name as plan_authorized_by_name,
  pending.id as pending_request_id,
  pending.requested_at as pending_requested_at
from public.patients as patient
left join lateral (
  select attendance.created_at
  from public.attendances as attendance
  where attendance.patient_id = patient.id
    and attendance.status = 'completed'
  order by attendance.created_at desc, attendance.id desc
  limit 1
) as last_attendance on true
left join lateral (
  select request.id, request.coverage_start, request.coverage_end, request.reviewed_by
  from public.patient_health_plan_requests as request
  where request.patient_id = patient.id
    and request.status = 'approved'
  order by request.coverage_end desc, request.id desc
  limit 1
) as approved on true
left join public.profiles as reviewer on reviewer.user_id = approved.reviewed_by
left join lateral (
  select request.id, request.requested_at
  from public.patient_health_plan_requests as request
  where request.patient_id = patient.id
    and request.status = 'pending'
  order by request.requested_at, request.id
  limit 1
) as pending on true;

revoke all on public.patient_directory from public, anon, authenticated;
grant select on public.patient_directory to authenticated;

create or replace function public.patient_profile_summary(p_patient_id bigint)
returns table (
  total_attendances bigint,
  last_attendance_at timestamptz,
  total_purchases bigint,
  recent_procedures jsonb
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if not private.has_permission((select auth.uid()), 'patients.view') then
    raise exception 'Você não possui permissão para consultar pacientes.';
  end if;

  return query
  select
    count(*) filter (where attendance.status = 'completed')::bigint,
    max(attendance.created_at) filter (where attendance.status = 'completed'),
    count(*) filter (
      where attendance.status = 'completed'
        and exists (
          select 1
          from public.attendance_items as item
          join public.service_catalog as service on service.id = item.service_id
          where item.attendance_id = attendance.id
            and lower(service.category) in ('insumos', 'medicamentos', 'produtos', 'convênios')
        )
    )::bigint,
    coalesce((
      select jsonb_agg(recent.item order by recent.created_at desc, recent.id desc)
      from (
        select
          item.id,
          attendance_item.created_at,
          jsonb_build_object(
            'id', item.id,
            'attendance_id', attendance_item.id,
            'name', item.service_name,
            'category', service.category,
            'date', attendance_item.created_at
          ) as item
        from public.attendance_items as item
        join public.attendances as attendance_item on attendance_item.id = item.attendance_id
        join public.service_catalog as service on service.id = item.service_id
        where attendance_item.patient_id = p_patient_id
          and attendance_item.status = 'completed'
          and lower(service.category) in ('atendimentos', 'exames')
        order by attendance_item.created_at desc, item.id desc
        limit 5
      ) as recent
    ), '[]'::jsonb)
  from public.attendances as attendance
  where attendance.patient_id = p_patient_id;
end;
$$;

create or replace function public.patient_activity_page(
  p_patient_id bigint,
  p_kind text default 'all',
  p_limit integer default 10,
  p_offset integer default 0
)
returns table (total_count bigint, records jsonb)
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if not private.has_permission((select auth.uid()), 'patients.view') then
    raise exception 'Você não possui permissão para consultar pacientes.';
  end if;
  if p_kind not in ('all', 'purchases', 'procedures') then
    raise exception 'Tipo de histórico inválido.';
  end if;
  if p_limit < 1 or p_limit > 50 or p_offset < 0 then
    raise exception 'Paginação inválida.';
  end if;

  return query
  with matching as materialized (
    select attendance.*
    from public.attendances as attendance
    where attendance.patient_id = p_patient_id
      and (
        p_kind = 'all'
        or exists (
          select 1
          from public.attendance_items as item
          join public.service_catalog as service on service.id = item.service_id
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
          select jsonb_agg(
            jsonb_build_object(
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
            ) order by item.id
          )
          from public.attendance_items as item
          join public.service_catalog as service on service.id = item.service_id
          where item.attendance_id = page.id
            and (
              p_kind = 'all'
              or (p_kind = 'purchases' and lower(service.category) in ('insumos', 'medicamentos', 'produtos', 'convênios'))
              or (p_kind = 'procedures' and lower(service.category) in ('atendimentos', 'exames'))
            )
        ), '[]'::jsonb)
      ) as record
    from page
    left join public.profiles as professional on professional.user_id = page.performed_by
    left join public.staff_positions as position on position.id = professional.position_id
  )
  select
    (select count(*) from matching)::bigint,
    coalesce(jsonb_agg(rendered.record order by rendered.created_at desc, rendered.id desc), '[]'::jsonb)
  from rendered;
end;
$$;

create or replace function public.patient_plan_history_page(
  p_patient_id bigint,
  p_limit integer default 10,
  p_offset integer default 0
)
returns table (total_count bigint, records jsonb)
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if not private.has_permission((select auth.uid()), 'patients.view') then
    raise exception 'Você não possui permissão para consultar pacientes.';
  end if;
  if p_limit < 1 or p_limit > 50 or p_offset < 0 then
    raise exception 'Paginação inválida.';
  end if;

  return query
  with matching as materialized (
    select request.*
    from public.patient_health_plan_requests as request
    where request.patient_id = p_patient_id
  ), page as (
    select matching.*
    from matching
    order by matching.requested_at desc, matching.id desc
    limit p_limit offset p_offset
  ), rendered as (
    select
      page.requested_at,
      page.id,
      jsonb_build_object(
        'id', page.id,
        'attendance_id', page.attendance_id,
        'status', page.status,
        'requested_at', page.requested_at,
        'reviewed_at', page.reviewed_at,
        'rejection_reason', page.rejection_reason,
        'coverage_start', page.coverage_start,
        'coverage_end', page.coverage_end,
        'authorized_by_name', reviewer.display_name,
        'seller_name', seller.display_name,
        'seller_passport', seller.passport,
        'attendance_total', attendance.total,
        'plan_value', coalesce((
          select sum(item.line_total)
          from public.attendance_items as item
          join public.service_catalog as service on service.id = item.service_id
          where item.attendance_id = page.attendance_id
            and service.code = 'plano_saude_convenio'
        ), 0)
      ) as record
    from page
    left join public.attendances as attendance on attendance.id = page.attendance_id
    left join public.profiles as seller on seller.user_id = attendance.performed_by
    left join public.profiles as reviewer on reviewer.user_id = page.reviewed_by
  )
  select
    (select count(*) from matching)::bigint,
    coalesce(jsonb_agg(rendered.record order by rendered.requested_at desc, rendered.id desc), '[]'::jsonb)
  from rendered;
end;
$$;

create or replace function public.patient_timeline(p_patient_id bigint, p_limit integer default 50)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if not private.has_permission((select auth.uid()), 'patients.view') then
    raise exception 'Você não possui permissão para consultar pacientes.';
  end if;
  if p_limit < 1 or p_limit > 100 then
    raise exception 'Limite inválido.';
  end if;

  with events as (
    select
      'patient-created-' || patient.id::text as id,
      patient.created_at as event_at,
      'cadastro'::text as event_type,
      'Paciente cadastrado no HPSM'::text as title,
      'Passaporte ' || patient.passport as description
    from public.patients as patient
    where patient.id = p_patient_id

    union all

    select
      'attendance-' || attendance.id::text,
      attendance.created_at,
      'attendance',
      case when attendance.status = 'cancelled' then 'Atendimento cancelado' else 'Atendimento realizado' end,
      coalesce(professional.display_name, 'Profissional') || ' · atendimento #' || attendance.id::text
    from public.attendances as attendance
    left join public.profiles as professional on professional.user_id = attendance.performed_by
    where attendance.patient_id = p_patient_id

    union all

    select
      'plan-request-' || request.id::text,
      request.requested_at,
      'health-plan-request',
      'Solicitação de Plano de Saúde registrada',
      'Atendimento #' || request.attendance_id::text || ' · aguardando conferência'
    from public.patient_health_plan_requests as request
    where request.patient_id = p_patient_id

    union all

    select
      'plan-review-' || request.id::text,
      request.reviewed_at,
      'health-plan-review',
      case
        when request.status = 'rejected' then 'Ativação do plano recusada'
        when request.coverage_start > request.reviewed_at + interval '1 minute' then 'Plano de Saúde renovado'
        else 'Plano de Saúde ativado'
      end,
      case
        when request.status = 'rejected' then coalesce(request.rejection_reason, 'Solicitação recusada')
        else 'Validade até ' || to_char(request.coverage_end at time zone 'UTC', 'DD/MM/YYYY')
      end
    from public.patient_health_plan_requests as request
    where request.patient_id = p_patient_id
      and request.status in ('approved', 'rejected')
      and request.reviewed_at is not null
  ), limited as (
    select *
    from events
    order by event_at desc, id desc
    limit p_limit
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', limited.id,
      'date', limited.event_at,
      'type', limited.event_type,
      'title', limited.title,
      'description', limited.description
    ) order by limited.event_at desc, limited.id desc
  ), '[]'::jsonb)
  into v_result
  from limited;

  return v_result;
end;
$$;

revoke all on function public.patient_profile_summary(bigint) from public, anon, authenticated;
revoke all on function public.patient_activity_page(bigint, text, integer, integer) from public, anon, authenticated;
revoke all on function public.patient_plan_history_page(bigint, integer, integer) from public, anon, authenticated;
revoke all on function public.patient_timeline(bigint, integer) from public, anon, authenticated;

grant execute on function public.patient_profile_summary(bigint) to authenticated;
grant execute on function public.patient_activity_page(bigint, text, integer, integer) to authenticated;
grant execute on function public.patient_plan_history_page(bigint, integer, integer) to authenticated;
grant execute on function public.patient_timeline(bigint, integer) to authenticated;

notify pgrst, 'reload schema';
