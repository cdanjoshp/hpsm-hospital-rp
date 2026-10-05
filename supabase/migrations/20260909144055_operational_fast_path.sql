-- HPSM · caminho rápido da operação.
-- Consolida catálogo e busca de pacientes em uma chamada autenticada por fluxo.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function public.hpsm_patient_quick_lookup(
  p_passport text,
  p_limit integer default 8
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
  v_passport text := btrim(coalesce(p_passport, ''));
  v_limit integer := least(greatest(coalesce(p_limit, 8), 1), 8);
  v_result jsonb;
begin
  if not ('patients.view' = any(v_permissions)) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  if v_passport !~ '^[0-9]{1,4}$' then
    raise exception 'Informe um passaporte válido.' using errcode = '22023';
  end if;

  with matching as materialized (
    select
      patient.id,
      patient.passport,
      patient.name,
      patient.phone,
      patient.emergency_contact_name,
      patient.emergency_contact_phone,
      patient.created_at,
      patient.updated_at
    from public.patients patient
    where patient.passport like v_passport || '%'
    order by (patient.passport = v_passport) desc, patient.passport asc
    limit v_limit
  ), plan_states as materialized (
    select state.*
    from public.get_patient_health_plan_states(
      coalesce((select array_agg(matching.id) from matching), array[]::bigint[])
    ) state
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', matching.id,
        'passport', matching.passport,
        'name', matching.name,
        'phone', matching.phone,
        'emergency_contact_name', matching.emergency_contact_name,
        'emergency_contact_phone', matching.emergency_contact_phone,
        'created_at', matching.created_at,
        'updated_at', matching.updated_at,
        'health_plan', jsonb_build_object(
          'status', coalesce(plan_states.status, 'none'),
          'activated_at', plan_states.activated_at,
          'valid_until', plan_states.valid_until,
          'authorized_by', plan_states.authorized_by,
          'authorized_by_name', plan_states.authorized_by_name,
          'pending_request_id', plan_states.pending_request_id,
          'pending_requested_at', plan_states.pending_requested_at
        )
      )
      order by (matching.passport = v_passport) desc, matching.passport asc
    ),
    '[]'::jsonb
  )
  into v_result
  from matching
  left join plan_states on plan_states.patient_id = matching.id;

  return v_result;
end;
$$;

revoke all on function public.hpsm_patient_quick_lookup(text, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.hpsm_patient_quick_lookup(text, integer)
  to authenticated;

comment on function public.hpsm_patient_quick_lookup(text, integer) is
  'Busca operacional por prefixo de passaporte com plano resolvido, sessão ativa e patients.view validados em uma única RPC.';

create or replace function public.hpsm_operational_catalog()
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
  if not (
    'catalog.view' = any(v_permissions)
    or 'catalog.manage' = any(v_permissions)
    or 'attendances.create' = any(v_permissions)
    or 'attendances.manage' = any(v_permissions)
  ) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', service.id,
        'code', service.code,
        'icon', service.icon,
        'image_path', service.image_path,
        'name', service.name,
        'category', service.category,
        'unit_price', service.unit_price,
        'active', service.active,
        'sort_order', service.sort_order,
        'created_at', service.created_at,
        'updated_at', service.updated_at,
        'plan_discounts', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'plan_code', discount.plan_code,
              'discount_percent', discount.discount_percent
            )
            order by discount.plan_code
          )
          from public.plan_discounts discount
          where discount.service_id = service.id
        ), '[]'::jsonb)
      )
      order by service.sort_order asc, service.name asc
    ),
    '[]'::jsonb
  )
  into v_result
  from public.service_catalog service;

  return v_result;
end;
$$;

revoke all on function public.hpsm_operational_catalog()
  from public, anon, authenticated, service_role;
grant execute on function public.hpsm_operational_catalog()
  to authenticated;

comment on function public.hpsm_operational_catalog() is
  'Entrega o catálogo operacional e seus descontos em uma única RPC após validar sessão e permissão efetiva.';
