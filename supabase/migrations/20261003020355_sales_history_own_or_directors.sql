-- O histórico de vendas segue o autor do registro; apenas a diretoria vê a equipe inteira.
-- Restringe também a leitura direta das tabelas, além da RPC paginada.
set lock_timeout = '5s';
set statement_timeout = '30s';

drop policy if exists attendances_read_own_manage_or_patient_center on public.attendances;
create policy attendances_read_own_or_directors on public.attendances
for select to authenticated
using (
  private.is_active_user()
  and (
    performed_by = (select auth.uid())
    or exists (
      select 1 from public.profiles profile
      join public.staff_positions position on position.id = profile.position_id
      where profile.user_id = (select auth.uid()) and profile.status = 'active' and position.active
        and ((position.official and position.level between 12 and 14) or position.code = 'diretores_sr')
    )
  )
);

drop policy if exists attendance_items_read_visible_attendance on public.attendance_items;
create policy attendance_items_read_visible_attendance on public.attendance_items
for select to authenticated
using (
  private.is_active_user()
  and exists (
    select 1 from public.attendances attendance
    where attendance.id = attendance_items.attendance_id
  )
);

create or replace function public.hpsm_attendance_history_page(
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
  v_can_view_all boolean;
begin
  select exists (
    select 1 from public.profiles profile
    join public.staff_positions position on position.id = profile.position_id
    where profile.user_id = v_actor and profile.status = 'active' and position.active
      and ((position.official and position.level between 12 and 14) or position.code = 'diretores_sr')
  ) into v_can_view_all;
  if not ('attendances.create' = any(v_permissions) or 'attendances.manage' = any(v_permissions) or 'patients.view' = any(v_permissions) or v_can_view_all) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if p_focus_id is not null then
    select target.created_at into v_focus_created_at from public.attendances target
    where target.id = p_focus_id and (target.performed_by = v_actor or v_can_view_all);
    if found then
      select count(*)::integer into v_rows_before from public.attendances source
      where (source.performed_by = v_actor or v_can_view_all)
        and (source.created_at, source.id) > (v_focus_created_at, p_focus_id);
      v_offset := (v_rows_before / v_limit) * v_limit;
    end if;
  end if;
  with visible as materialized (
    select source.* from public.attendances source
    where source.performed_by = v_actor or v_can_view_all
  ), page_rows as (
    select source.* from visible source order by source.created_at desc, source.id desc limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'id', attendance.id, 'patient_id', attendance.patient_id, 'patient_name', attendance.patient_name,
      'patient_passport', attendance.patient_passport, 'plan_code', attendance.plan_code,
      'plan_name', attendance.plan_name, 'partnership_id', attendance.partnership_id,
      'partnership_name', attendance.partnership_name, 'status', attendance.status,
      'subtotal', attendance.subtotal, 'discount', attendance.discount, 'total', attendance.total,
      'notes', attendance.notes, 'performed_by', attendance.performed_by, 'created_at', attendance.created_at,
      'professional_name', coalesce(profile.display_name, 'Profissional'),
      'professional_passport', coalesce(profile.passport, '—'),
      'professional_position', coalesce(position.name, 'Cargo não definido'),
      'attendance_items', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', item.id, 'service_id', item.service_id, 'service_name', item.service_name,
        'unit_price', item.unit_price, 'quantity', item.quantity, 'discount_percent', item.discount_percent,
        'discount_amount', item.discount_amount, 'line_total', item.line_total
      ) order by item.id), '[]'::jsonb) from public.attendance_items item where item.attendance_id = attendance.id)
    ) order by attendance.created_at desc, attendance.id desc) filter (where attendance.id is not null), '[]'::jsonb),
    'total', (select count(*) from visible), 'page', floor(v_offset::numeric / v_limit)::integer + 1, 'pageSize', v_limit
  ) into v_result
  from page_rows attendance
  left join public.profiles profile on profile.user_id = attendance.performed_by
  left join public.staff_positions position on position.id = profile.position_id;
  return v_result;
end;
$$;

revoke all on function public.hpsm_attendance_history_page(integer, integer, bigint)
from public, anon, authenticated, service_role;
grant execute on function public.hpsm_attendance_history_page(integer, integer, bigint) to authenticated;

-- O diretório e o resumo do paciente continuam agregando os atendimentos
-- de toda a equipe, por funções com autorização clínica explícita.
create or replace function public.hpsm_patient_last_attendance(p_patient_id bigint)
returns timestamptz
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not private.has_permission(private.hpsm_current_actor(), 'patients.view') then
    return null;
  end if;
  return (
    select attendance.created_at from public.attendances attendance
    where attendance.patient_id = p_patient_id and attendance.status = 'completed'
    order by attendance.created_at desc, attendance.id desc limit 1
  );
end;
$$;
revoke all on function public.hpsm_patient_last_attendance(bigint) from public, anon, authenticated, service_role;
grant execute on function public.hpsm_patient_last_attendance(bigint) to authenticated;

create or replace view public.patient_directory with (security_invoker = true) as
select patient.id, patient.passport, patient.name, patient.phone,
  patient.emergency_contact_name, patient.emergency_contact_phone,
  patient.created_at, patient.updated_at,
  public.hpsm_patient_last_attendance(patient.id) as last_attendance_at,
  case when approved.coverage_end > now() then 'active'
       when approved.id is not null then 'expired'
       when pending.id is not null then 'awaiting_confirmation'
       else 'none' end as plan_status,
  approved.coverage_start as plan_activated_at,
  approved.coverage_end as plan_valid_until,
  approved.reviewed_by as plan_authorized_by,
  reviewer.display_name as plan_authorized_by_name,
  pending.id as pending_request_id,
  pending.requested_at as pending_requested_at,
  patient.birth_date, patient.allergies
from public.patients patient
left join lateral (
  select request.id, request.coverage_start, request.coverage_end, request.reviewed_by
  from public.patient_health_plan_requests request
  where request.patient_id = patient.id and request.status = 'approved'
  order by request.reviewed_at desc nulls last, request.id desc limit 1
) approved on true
left join public.profiles reviewer on reviewer.user_id = approved.reviewed_by
left join lateral (
  select request.id, request.requested_at
  from public.patient_health_plan_requests request
  where request.patient_id = patient.id and request.status = 'pending'
  order by request.requested_at, request.id limit 1
) pending on true;

create or replace function public.patient_profile_summary(p_patient_id bigint)
returns table (
  total_attendances bigint,
  last_attendance_at timestamptz,
  total_purchases bigint,
  recent_procedures jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.has_permission(private.hpsm_current_actor(), 'patients.view') then
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

revoke all on function public.patient_profile_summary(bigint) from public, anon, authenticated, service_role;
grant execute on function public.patient_profile_summary(bigint) to authenticated;

-- Vínculos clínicos validam o paciente e o atendimento dentro de triggers
-- já protegidos pelas permissões de escrita dos respectivos módulos.
alter function private.validate_clinical_cast_link() security definer;
alter function private.validate_clinical_exam_link() security definer;
alter function private.validate_medical_certificate_link() security definer;

notify pgrst, 'reload schema';
