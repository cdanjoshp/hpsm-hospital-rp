-- Todas as leituras partem da sessão opaca. Nenhuma função aceita patient_id do cliente.
set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function public.patient_portal_hospitalization_page(
  p_token_hash text, p_limit integer default 15, p_offset integer default 0
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_session record;
  v_limit integer := least(greatest(coalesce(p_limit, 15), 1), 30);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then return jsonb_build_object('authenticated', false); end if;
  select * into v_session from private.patient_portal_session_record(p_token_hash);
  if v_session.patient_id is null then return jsonb_build_object('authenticated', false); end if;
  return jsonb_build_object(
    'authenticated', true,
    'patient', jsonb_build_object('name', v_session.patient_name, 'passport', v_session.patient_passport),
    'items', coalesce((
      select jsonb_agg(to_jsonb(item) order by item.admitted_at desc, item.id desc)
      from (
        select h.id, h.admitted_at, h.discharged_at, h.reason, h.status,
          bed.label as bed_label, admitted.display_name as admitted_by_name,
          discharged.display_name as discharged_by_name
        from public.hospitalizations h
        join public.hospital_beds bed on bed.id = h.bed_id
        left join public.profiles admitted on admitted.user_id = h.admitted_by
        left join public.profiles discharged on discharged.user_id = h.discharged_by
        where h.patient_id = v_session.patient_id and h.source = 'hpsm'
          and h.status in ('active', 'discharged')
        order by h.admitted_at desc, h.id desc limit v_limit offset v_offset
      ) item
    ), '[]'::jsonb),
    'total', (select count(*)::integer from public.hospitalizations h
      where h.patient_id = v_session.patient_id and h.source = 'hpsm' and h.status in ('active', 'discharged'))
  );
end;
$$;
revoke all on function public.patient_portal_hospitalization_page(text,integer,integer) from public, anon, authenticated, service_role;
grant execute on function public.patient_portal_hospitalization_page(text,integer,integer) to service_role;

create or replace function public.patient_portal_legacy_history_page(
  p_token_hash text, p_record_type text default null, p_limit integer default 20, p_offset integer default 0
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_session record;
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then return jsonb_build_object('authenticated', false); end if;
  if p_record_type is not null and p_record_type not in ('registration','attendance','exam','vaccine','appointment','health_plan') then
    raise exception 'Tipo de histórico inválido.' using errcode = '22023';
  end if;
  select * into v_session from private.patient_portal_session_record(p_token_hash);
  if v_session.patient_id is null then return jsonb_build_object('authenticated', false); end if;
  return jsonb_build_object(
    'authenticated', true,
    'patient', jsonb_build_object('name', v_session.patient_name, 'passport', v_session.patient_passport),
    'total', (select count(*)::integer from public.legacy_patient_records r where r.patient_id = v_session.patient_id
      and (p_record_type is null or r.record_type = p_record_type)),
    'summary', coalesce((select jsonb_object_agg(record_type, total) from
      (select r.record_type, count(*)::integer total from public.legacy_patient_records r
       where r.patient_id = v_session.patient_id group by r.record_type) totals), '{}'::jsonb),
    'items', coalesce((select jsonb_agg(to_jsonb(item) order by item.occurred_at desc nulls last, item.id desc)
      from (select r.id, r.record_type, r.occurred_at, r.occurred_precision, r.title, r.status,
        r.professional_name, r.professional_registration, r.summary, r.details, r.reference_links
        from public.legacy_patient_records r
        where r.patient_id = v_session.patient_id and (p_record_type is null or r.record_type = p_record_type)
        order by r.occurred_at desc nulls last, r.id desc limit v_limit offset v_offset) item), '[]'::jsonb)
  );
end;
$$;
revoke all on function public.patient_portal_legacy_history_page(text,text,integer,integer) from public, anon, authenticated, service_role;
grant execute on function public.patient_portal_legacy_history_page(text,text,integer,integer) to service_role;

create or replace function public.patient_portal_prescription_snapshot(
  p_token_hash text, p_consultation_id bigint
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_session record;
  v_snapshot jsonb;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then return jsonb_build_object('authenticated', false); end if;
  select * into v_session from private.patient_portal_session_record(p_token_hash);
  if v_session.patient_id is null then return jsonb_build_object('authenticated', false); end if;
  select prescription.final_snapshot into v_snapshot
  from public.clinical_consultations consultation
  join public.consultation_prescriptions prescription on prescription.consultation_id = consultation.id
  where consultation.id = p_consultation_id and consultation.patient_id = v_session.patient_id
    and consultation.status = 'completed' and prescription.status = 'finalized'
    and prescription.final_snapshot is not null;
  return jsonb_build_object('authenticated', true, 'found', v_snapshot is not null,
    'snapshot', v_snapshot);
end;
$$;
revoke all on function public.patient_portal_prescription_snapshot(text,bigint) from public, anon, authenticated, service_role;
grant execute on function public.patient_portal_prescription_snapshot(text,bigint) to service_role;

-- A linha do tempo conserva as regras de visibilidade de cada domínio e inclui
-- consultas, atestados, internações e registros importados datados.
create or replace function public.patient_portal_history_page_v2(
  p_token_hash text, p_cursor_at timestamptz default null,
  p_cursor_key text default null, p_limit integer default 20
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_session record;
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_items jsonb;
  v_has_more boolean;
  v_next_at timestamptz;
  v_next_key text;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then return jsonb_build_object('authenticated', false); end if;
  if (p_cursor_at is null) <> (p_cursor_key is null)
     or (p_cursor_key is not null and char_length(p_cursor_key) > 128) then
    raise exception 'Cursor inválido.' using errcode = '22023';
  end if;
  select * into v_session from private.patient_portal_session_record(p_token_hash);
  if v_session.patient_id is null then return jsonb_build_object('authenticated', false); end if;

  with events as (
    select a.created_at event_at, 'attendance:' || a.id event_key, 'attendance'::text event_type,
      'Atendimento realizado'::text title, coalesce(p.display_name,'Profissional')::text description,
      p.display_name professional_name, sp.name professional_position, a.total amount, a.id attendance_id
    from public.attendances a left join public.profiles p on p.user_id=a.performed_by
      left join public.staff_positions sp on sp.id=p.position_id
    where a.patient_id=v_session.patient_id and a.status='completed'
    union all
    select e.completed_at, 'exam:' || e.id, 'exam', et.name || ' concluído',
      coalesce(p.display_name,'Profissional responsável'), p.display_name, sp.name, null::numeric, null::bigint
    from public.clinical_exams e join public.exam_types et on et.id=e.exam_type_id
      left join public.profiles p on p.user_id=e.responsible_professional_id
      left join public.staff_positions sp on sp.id=p.position_id
    where e.patient_id=v_session.patient_id and e.status='completed' and e.completed_at is not null
    union all
    select c.applied_at, 'cast-applied:' || c.id, 'cast',
      'Gesso aplicado — ' || private.clinical_cast_location_label(c.body_region,c.laterality),
      coalesce(p.display_name,'Profissional responsável'), p.display_name, sp.name, null::numeric, null::bigint
    from public.clinical_casts c left join public.profiles p on p.user_id=c.applied_by
      left join public.staff_positions sp on sp.id=p.position_id
    where c.patient_id=v_session.patient_id and c.status in ('in_use','removed')
    union all
    select c.removed_at, 'cast-removed:' || c.id, 'cast',
      'Gesso retirado — ' || private.clinical_cast_location_label(c.body_region,c.laterality),
      coalesce(p.display_name,'Profissional responsável'), p.display_name, sp.name, null::numeric, null::bigint
    from public.clinical_casts c left join public.profiles p on p.user_id=c.removed_by
      left join public.staff_positions sp on sp.id=p.position_id
    where c.patient_id=v_session.patient_id and c.status='removed' and c.removed_at is not null
    union all
    select hp.reviewed_at, 'health-plan:' || hp.id, 'health_plan',
      case when hp.coverage_start > hp.reviewed_at + interval '1 minute' then 'Plano de Saúde renovado' else 'Plano de Saúde ativado' end,
      'Cobertura até ' || to_char(hp.coverage_end at time zone 'America/Sao_Paulo','DD/MM/YYYY'),
      null::text, null::text, null::numeric, null::bigint
    from public.patient_health_plan_requests hp
    where hp.patient_id=v_session.patient_id and hp.status='approved' and hp.reviewed_at is not null
    union all
    select c.completed_at,
      'consultation:' || case when c.appointment_id is null then 'consultation:' || c.id else 'appointment:' || c.appointment_id end,
      'consultation', 'Consulta concluída', coalesce(p.display_name,'Profissional responsável'),
      p.display_name, sp.name, null::numeric, null::bigint
    from public.clinical_consultations c left join public.profiles p on p.user_id=c.professional_id
      left join public.staff_positions sp on sp.id=p.position_id
    where c.patient_id=v_session.patient_id and c.status='completed' and c.completed_at is not null
    union all
    select m.finalized_at, 'certificate:' || m.id, 'certificate', 'Atestado emitido',
      'Afastamento de ' || m.leave_days || case when m.leave_days=1 then ' dia' else ' dias' end,
      p.display_name, sp.name, null::numeric, null::bigint
    from public.medical_certificates m left join public.profiles p on p.user_id=m.created_by
      left join public.staff_positions sp on sp.id=p.position_id
    where m.patient_id=v_session.patient_id and m.status='finalized' and m.finalized_at is not null
    union all
    select h.admitted_at, 'hospitalization-admitted:' || h.id, 'hospitalization',
      'Internação iniciada', h.reason, p.display_name, sp.name, null::numeric, null::bigint
    from public.hospitalizations h left join public.profiles p on p.user_id=h.admitted_by
      left join public.staff_positions sp on sp.id=p.position_id
    where h.patient_id=v_session.patient_id and h.source='hpsm' and h.status in ('active','discharged')
    union all
    select h.discharged_at, 'hospitalization-discharged:' || h.id, 'hospitalization',
      'Alta da internação', null::text, p.display_name, sp.name, null::numeric, null::bigint
    from public.hospitalizations h left join public.profiles p on p.user_id=h.discharged_by
      left join public.staff_positions sp on sp.id=p.position_id
    where h.patient_id=v_session.patient_id and h.source='hpsm' and h.status='discharged' and h.discharged_at is not null
    union all
    select r.occurred_at, 'legacy:' || r.id, 'legacy', r.title,
      r.summary, r.professional_name, null::text, null::numeric, null::bigint
    from public.legacy_patient_records r
    where r.patient_id=v_session.patient_id and r.occurred_at is not null
  ), page_rows as materialized (
    select * from events
    where event_at is not null and (p_cursor_at is null or (event_at,event_key) < (p_cursor_at,p_cursor_key))
    order by event_at desc,event_key desc limit v_limit+1
  ), visible as materialized (
    select * from page_rows order by event_at desc,event_key desc limit v_limit
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'key', v.event_key, 'occurred_at', v.event_at, 'type', v.event_type,
      'title', v.title, 'description', v.description,
      'professional_name', v.professional_name, 'professional_position', v.professional_position,
      'amount', v.amount, 'attendance_id', v.attendance_id
    ) order by v.event_at desc,v.event_key desc),'[]'::jsonb),
    (select count(*) > v_limit from page_rows),
    (select event_at from visible order by event_at,event_key limit 1),
    (select event_key from visible order by event_at,event_key limit 1)
  into v_items,v_has_more,v_next_at,v_next_key from visible v;
  return jsonb_build_object('authenticated',true,
    'patient',jsonb_build_object('name',v_session.patient_name,'passport',v_session.patient_passport),
    'items',v_items,
    'next_cursor',case when v_has_more then jsonb_build_object('occurred_at',v_next_at,'key',v_next_key) else null end);
end;
$$;
revoke all on function public.patient_portal_history_page_v2(text,timestamptz,text,integer) from public, anon, authenticated, service_role;
grant execute on function public.patient_portal_history_page_v2(text,timestamptz,text,integer) to service_role;

notify pgrst, 'reload schema';
