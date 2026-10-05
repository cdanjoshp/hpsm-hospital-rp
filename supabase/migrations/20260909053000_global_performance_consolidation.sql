-- HPSM · consolidação transversal de performance.
-- Remove N+1 da progressão e pagina históricos sem alterar autorização ou regras clínicas.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function public.get_staff_progression_statuses(p_actor_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if not private.has_permission(p_actor_id, 'progression.review')
     and not private.has_permission(p_actor_id, 'hr.team.view') then
    raise exception using errcode = '42501', message = 'Você não possui permissão para consultar progressões.';
  end if;

  select coalesce(
    jsonb_object_agg(profile.user_id::text, private.get_staff_progression_status(profile.user_id)),
    '{}'::jsonb
  )
  into v_result
  from public.profiles profile
  join public.staff_positions position on position.id = profile.position_id
  where profile.status = 'active'
    and position.level between 1 and 10;

  return v_result;
end;
$$;

revoke all on function public.get_staff_progression_statuses(uuid)
  from public, anon, authenticated;
grant execute on function public.get_staff_progression_statuses(uuid)
  to service_role;

comment on function public.get_staff_progression_statuses(uuid) is
  'Retorna a progressão da equipe em uma única chamada server-side, preservando a autorização efetiva do ator.';

create or replace function public.hpsm_attendance_history_page(
  p_limit integer default 20,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_permissions text[] := public.effective_permission_codes(v_actor);
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_result jsonb;
begin
  if not (
    'attendances.create' = any(v_permissions)
    or 'attendances.manage' = any(v_permissions)
    or 'patients.view' = any(v_permissions)
  ) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  with visible as materialized (
    select source.*
    from public.attendances source
    where source.performed_by = v_actor
       or 'attendances.manage' = any(v_permissions)
       or 'patients.view' = any(v_permissions)
  ), page_rows as (
    select source.*
    from visible source
    order by source.created_at desc, source.id desc
    limit v_limit
    offset v_offset
  )
  select jsonb_build_object(
    'items', coalesce(jsonb_agg(
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
    ) filter (where attendance.id is not null), '[]'::jsonb),
    'total', (select count(*) from visible),
    'page', floor(v_offset::numeric / v_limit)::integer + 1,
    'pageSize', v_limit
  )
  into v_result
  from page_rows attendance
  left join public.profiles profile on profile.user_id = attendance.performed_by
  left join public.staff_positions position on position.id = profile.position_id;

  return v_result;
end;
$$;

revoke all on function public.hpsm_attendance_history_page(integer, integer)
  from public, anon;
grant execute on function public.hpsm_attendance_history_page(integer, integer)
  to authenticated;

comment on function public.hpsm_attendance_history_page(integer, integer) is
  'Histórico paginado de atendimentos com o mesmo escopo efetivo da navegação e da rota protegida.';

create or replace function public.hpsm_audit_page(
  p_limit integer default 25,
  p_offset integer default 0,
  p_action text default null,
  p_entity text default null,
  p_search text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_limit integer := least(greatest(coalesce(p_limit, 25), 1), 50);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_action text := nullif(btrim(coalesce(p_action, '')), '');
  v_entity text := nullif(lower(btrim(coalesce(p_entity, ''))), '');
  v_search text := nullif(btrim(coalesce(p_search, '')), '');
  v_result jsonb;
begin
  if not private.has_permission(v_actor, 'audit.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if char_length(coalesce(v_action, '')) > 80
     or char_length(coalesce(v_entity, '')) > 80
     or char_length(coalesce(v_search, '')) > 100 then
    raise exception 'Filtro inválido.' using errcode = '22023';
  end if;

  with filtered as materialized (
    select
      audit.id,
      audit.actor_passport,
      audit.action,
      audit.entity_name,
      audit.entity_id,
      audit.created_at,
      position.name as actor_position
    from public.audit_logs audit
    left join public.profiles profile on profile.user_id = audit.actor_user_id
    left join public.staff_positions position on position.id = profile.position_id
    where (v_action is null or audit.action = v_action)
      and (v_entity is null or audit.entity_name = v_entity)
      and (
        v_search is null
        or coalesce(audit.actor_passport, '') ilike '%' || v_search || '%'
        or coalesce(profile.display_name, '') ilike '%' || v_search || '%'
        or coalesce(audit.entity_id, '') ilike '%' || v_search || '%'
        or audit.entity_name ilike '%' || v_search || '%'
      )
  ), page_rows as (
    select source.*
    from filtered source
    order by source.created_at desc, source.id desc
    limit v_limit
    offset v_offset
  )
  select jsonb_build_object(
    'items', coalesce(jsonb_agg(
      jsonb_build_object(
        'id', entry.id,
        'actor_passport', entry.actor_passport,
        'actor_position', entry.actor_position,
        'action', entry.action,
        'entity_name', entry.entity_name,
        'entity_id', entry.entity_id,
        'created_at', entry.created_at
      ) order by entry.created_at desc, entry.id desc
    ) filter (where entry.id is not null), '[]'::jsonb),
    'total', (select count(*) from filtered),
    'page', floor(v_offset::numeric / v_limit)::integer + 1,
    'pageSize', v_limit
  )
  into v_result
  from page_rows entry;

  return v_result;
end;
$$;

revoke all on function public.hpsm_audit_page(integer, integer, text, text, text)
  from public, anon;
grant execute on function public.hpsm_audit_page(integer, integer, text, text, text)
  to authenticated;

comment on function public.hpsm_audit_page(integer, integer, text, text, text) is
  'Auditoria paginada e filtrada no servidor, protegida pela sessão canônica e por audit.view.';
