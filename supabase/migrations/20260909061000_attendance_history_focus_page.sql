-- HPSM · preserva deep links ao paginar o histórico de atendimentos.
-- O banco seleciona diretamente a página que contém o atendimento focalizado.

set lock_timeout = '5s';
set statement_timeout = '120s';

drop function if exists public.hpsm_attendance_history_page(integer, integer);

create function public.hpsm_attendance_history_page(
  p_limit integer default 20,
  p_offset integer default 0,
  p_focus_id bigint default null
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
  v_focus_created_at timestamptz;
  v_rows_before integer;
  v_result jsonb;
begin
  if not (
    'attendances.create' = any(v_permissions)
    or 'attendances.manage' = any(v_permissions)
    or 'patients.view' = any(v_permissions)
  ) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  if p_focus_id is not null then
    select target.created_at
    into v_focus_created_at
    from public.attendances target
    where target.id = p_focus_id
      and (
        target.performed_by = v_actor
        or 'attendances.manage' = any(v_permissions)
        or 'patients.view' = any(v_permissions)
      );

    if found then
      select count(*)::integer
      into v_rows_before
      from public.attendances source
      where (
          source.performed_by = v_actor
          or 'attendances.manage' = any(v_permissions)
          or 'patients.view' = any(v_permissions)
        )
        and (source.created_at, source.id) > (v_focus_created_at, p_focus_id);
      v_offset := (v_rows_before / v_limit) * v_limit;
    end if;
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

revoke all on function public.hpsm_attendance_history_page(integer, integer, bigint)
  from public, anon;
grant execute on function public.hpsm_attendance_history_page(integer, integer, bigint)
  to authenticated;

comment on function public.hpsm_attendance_history_page(integer, integer, bigint) is
  'Histórico paginado que preserva deep links visíveis sem consultas sequenciais no navegador.';
