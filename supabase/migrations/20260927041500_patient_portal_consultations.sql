-- Consultas e agendamentos do próprio paciente, pela sessão opaca existente.
-- Listagem compacta; prontuário congelado apenas no detalhe concluído.
set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function public.patient_portal_consultation_page(
  p_token_hash text,
  p_cursor_at timestamptz default null,
  p_cursor_key text default null,
  p_limit integer default 15
)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_session record;
  v_items jsonb;
  v_has_more boolean;
  v_next_at timestamptz;
  v_next_key text;
  v_limit integer := least(greatest(coalesce(p_limit, 15), 1), 30);
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('authenticated', false);
  end if;
  if (p_cursor_at is null) <> (p_cursor_key is null)
    or (p_cursor_key is not null and p_cursor_key !~ '^(appointment|consultation):[1-9][0-9]*$') then
    raise exception 'Cursor inválido.' using errcode = '22023';
  end if;
  select * into v_session from private.patient_portal_session_record(p_token_hash);
  if not found then return jsonb_build_object('authenticated', false); end if;

  with records as materialized (
    select 'appointment'::text as kind, appointment.id, appointment.scheduled_start as occurred_at,
      coalesce(consultation.status, appointment.status) as status,
      consultation.completed_at, consultation.id as consultation_id,
      appointment.reason, professional.display_name as professional_name,
      position.name as professional_position,
      'appointment:' || appointment.id::text as record_key
    from public.patient_appointments appointment
    left join public.clinical_consultations consultation
      on consultation.appointment_id = appointment.id and consultation.patient_id = v_session.patient_id
    left join public.profiles professional on professional.user_id = appointment.professional_id
    left join public.staff_positions position on position.id = professional.position_id
    where appointment.patient_id = v_session.patient_id
    union all
    select 'consultation'::text, consultation.id, consultation.started_at, consultation.status,
      consultation.completed_at, consultation.id, null::text,
      professional.display_name, position.name, 'consultation:' || consultation.id::text
    from public.clinical_consultations consultation
    left join public.profiles professional on professional.user_id = consultation.professional_id
    left join public.staff_positions position on position.id = professional.position_id
    where consultation.patient_id = v_session.patient_id and consultation.appointment_id is null
  ), page_rows as materialized (
    select * from records
    where p_cursor_at is null or (occurred_at, record_key) < (p_cursor_at, p_cursor_key)
    order by occurred_at desc, record_key desc limit v_limit + 1
  ), visible as materialized (
    select * from page_rows order by occurred_at desc, record_key desc limit v_limit
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'kind', visible.kind, 'id', visible.id, 'occurred_at', visible.occurred_at,
      'status', visible.status, 'completed_at', visible.completed_at,
      'consultation_id', visible.consultation_id, 'reason', visible.reason,
      'professional_name', visible.professional_name,
      'professional_position', visible.professional_position
    ) order by visible.occurred_at desc, visible.record_key desc), '[]'::jsonb),
    (select count(*) > v_limit from page_rows),
    (select occurred_at from visible order by occurred_at, record_key limit 1),
    (select record_key from visible order by occurred_at, record_key limit 1)
  into v_items, v_has_more, v_next_at, v_next_key from visible;

  return jsonb_build_object('authenticated', true,
    'patient', jsonb_build_object('name', v_session.patient_name, 'passport', v_session.patient_passport),
    'items', v_items,
    'next_cursor', case when v_has_more then jsonb_build_object('occurred_at', v_next_at, 'key', v_next_key) else null end);
end;
$$;

create or replace function public.patient_portal_consultation_detail(
  p_token_hash text, p_kind text, p_record_id bigint
)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_session record;
  v_item record;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('authenticated', false);
  end if;
  select * into v_session from private.patient_portal_session_record(p_token_hash);
  if not found then return jsonb_build_object('authenticated', false); end if;
  if p_record_id is null or p_record_id < 1 or p_kind not in ('appointment','consultation') then
    return jsonb_build_object('authenticated', true, 'found', false);
  end if;

  if p_kind = 'appointment' then
    select appointment.id, appointment.scheduled_start as occurred_at,
      coalesce(consultation.status, appointment.status) as status,
      consultation.completed_at, consultation.id as consultation_id,
      appointment.reason, professional.display_name as professional_name,
      position.name as professional_position,
      case when consultation.status = 'completed' then consultation.final_snapshot else null end as final_snapshot
    into v_item
    from public.patient_appointments appointment
    left join public.clinical_consultations consultation
      on consultation.appointment_id = appointment.id and consultation.patient_id = v_session.patient_id
    left join public.profiles professional on professional.user_id = appointment.professional_id
    left join public.staff_positions position on position.id = professional.position_id
    where appointment.id = p_record_id and appointment.patient_id = v_session.patient_id;
  else
    select consultation.id, consultation.started_at as occurred_at,
      consultation.status, consultation.completed_at, consultation.id as consultation_id,
      null::text as reason, professional.display_name as professional_name,
      position.name as professional_position,
      case when consultation.status = 'completed' then consultation.final_snapshot else null end as final_snapshot
    into v_item
    from public.clinical_consultations consultation
    left join public.profiles professional on professional.user_id = consultation.professional_id
    left join public.staff_positions position on position.id = professional.position_id
    where consultation.id = p_record_id and consultation.patient_id = v_session.patient_id
      and consultation.appointment_id is null;
  end if;
  if not found then return jsonb_build_object('authenticated', true, 'found', false); end if;
  return jsonb_build_object('authenticated', true, 'found', true,
    'patient', jsonb_build_object('name', v_session.patient_name, 'passport', v_session.patient_passport),
    'consultation', jsonb_build_object('kind', p_kind, 'id', v_item.id,
      'occurred_at', v_item.occurred_at, 'status', v_item.status,
      'completed_at', v_item.completed_at, 'consultation_id', v_item.consultation_id,
      'reason', v_item.reason, 'professional_name', v_item.professional_name,
      'professional_position', v_item.professional_position),
    'final_snapshot', v_item.final_snapshot);
end;
$$;

revoke all on function public.patient_portal_consultation_page(text,timestamptz,text,integer) from public, anon, authenticated;
revoke all on function public.patient_portal_consultation_detail(text,text,bigint) from public, anon, authenticated;
grant execute on function public.patient_portal_consultation_page(text,timestamptz,text,integer) to service_role;
grant execute on function public.patient_portal_consultation_detail(text,text,bigint) to service_role;
notify pgrst, 'reload schema';
