-- Corrige a busca operacional de pacientes após a remoção deliberada do helper
-- público get_patient_health_plan_states durante o hardening do plano de saúde.

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
      patient.birth_date,
      patient.emergency_contact_name,
      patient.emergency_contact_phone,
      patient.created_at,
      patient.updated_at
    from public.patients patient
    where patient.passport like v_passport || '%'
    order by (patient.passport = v_passport) desc, patient.passport asc
    limit v_limit
  ), plan_states as materialized (
    select
      matching.id as patient_id,
      case
        when approved.coverage_end > now() then 'active'
        when approved.id is not null then 'expired'
        when pending.id is not null then 'awaiting_confirmation'
        else 'none'
      end as status,
      approved.coverage_start as activated_at,
      approved.coverage_end as valid_until,
      approved.reviewed_by as authorized_by,
      reviewer.display_name as authorized_by_name,
      pending.id as pending_request_id,
      pending.requested_at as pending_requested_at
    from matching
    left join lateral (
      select
        request.id,
        request.coverage_start,
        request.coverage_end,
        request.reviewed_by
      from public.patient_health_plan_requests request
      where request.patient_id = matching.id
        and request.status = 'approved'
      order by request.coverage_end desc, request.id desc
      limit 1
    ) approved on true
    left join public.profiles reviewer on reviewer.user_id = approved.reviewed_by
    left join lateral (
      select request.id, request.requested_at
      from public.patient_health_plan_requests request
      where request.patient_id = matching.id
        and request.status = 'pending'
      order by request.requested_at, request.id
      limit 1
    ) pending on true
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', matching.id,
        'passport', matching.passport,
        'name', matching.name,
        'phone', matching.phone,
        'birth_date', matching.birth_date,
        'emergency_contact_name', matching.emergency_contact_name,
        'emergency_contact_phone', matching.emergency_contact_phone,
        'created_at', matching.created_at,
        'updated_at', matching.updated_at,
        'health_plan', jsonb_build_object(
          'status', plan_states.status,
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
  join plan_states on plan_states.patient_id = matching.id;

  return v_result;
end;
$$;

revoke all on function public.hpsm_patient_quick_lookup(text, integer)
from public, anon, authenticated, service_role;
grant execute on function public.hpsm_patient_quick_lookup(text, integer)
to authenticated;

comment on function public.hpsm_patient_quick_lookup(text, integer) is
  'Busca operacional por prefixo de passaporte com plano resolvido internamente, sessão ativa e patients.view validados em uma única RPC.';
