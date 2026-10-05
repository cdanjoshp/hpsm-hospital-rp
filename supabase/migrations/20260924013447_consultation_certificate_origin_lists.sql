-- Expõe a origem clínica dos atestados nas listagens existentes sem quebrar
-- consumidores antigos que continuam usando attendance_id.

create or replace function public.medical_certificate_page(
  p_search text default null,
  p_status text default null,
  p_date_from date default null,
  p_date_to date default null,
  p_created_by uuid default null,
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
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
begin
  if not private.has_permission(v_actor, 'atestados.view') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if p_status is not null and p_status not in ('draft', 'finalized', 'cancelled') then raise exception 'Status de atestado inválido.'; end if;
  if p_date_from is not null and p_date_to is not null and p_date_from > p_date_to then raise exception 'Período inválido.'; end if;
  return (
    with filtered as (
      select certificate.id, certificate.patient_id, patient.name patient_name, patient.passport patient_passport,
        certificate.attendance_id, certificate.consultation_id, certificate.leave_days, certificate.status, certificate.created_by,
        creator.display_name professional_name, position.name professional_position,
        certificate.created_at, certificate.finalized_at, certificate.cancelled_at,
        (certificate.final_png_path is not null) document_ready
      from public.medical_certificates certificate
      join public.patients patient on patient.id = certificate.patient_id
      join public.profiles creator on creator.user_id = certificate.created_by
      left join public.staff_positions position on position.id = creator.position_id
      where (p_status is null or certificate.status = p_status)
        and (p_created_by is null or certificate.created_by = p_created_by)
        and (p_date_from is null or certificate.created_at >= p_date_from::timestamptz)
        and (p_date_to is null or certificate.created_at < (p_date_to + 1)::timestamptz)
        and (
          nullif(btrim(p_search), '') is null
          or patient.name ilike '%' || btrim(p_search) || '%'
          or patient.passport ilike btrim(p_search) || '%'
          or certificate.id::text = btrim(p_search)
        )
    ), page_rows as (
      select * from filtered order by created_at desc, id desc limit v_limit offset v_offset
    )
    select jsonb_build_object(
      'items', coalesce((select jsonb_agg(to_jsonb(page_rows) order by created_at desc, id desc) from page_rows), '[]'::jsonb),
      'total', (select count(*)::integer from filtered)
    )
  );
end;
$$;
create or replace function public.patient_medical_certificate_page(
  p_patient_id bigint,
  p_limit integer default 10,
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
  v_limit integer := least(greatest(coalesce(p_limit, 10), 1), 25);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
begin
  if not private.has_permission(v_actor, 'patients.view') or not private.has_permission(v_actor, 'atestados.view') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if not exists (select 1 from public.patients where id = p_patient_id) then raise exception 'Paciente não localizado.'; end if;
  return (
    with filtered as (
      select certificate.id, certificate.attendance_id, certificate.consultation_id, certificate.leave_days, certificate.status,
        certificate.created_at, certificate.finalized_at, certificate.cancelled_at,
        creator.display_name professional_name, position.name professional_position,
        certificate.final_png_path is not null document_ready
      from public.medical_certificates certificate
      join public.profiles creator on creator.user_id = certificate.created_by
      left join public.staff_positions position on position.id = creator.position_id
      where certificate.patient_id = p_patient_id
    ), page_rows as (
      select * from filtered order by created_at desc, id desc limit v_limit offset v_offset
    )
    select jsonb_build_object(
      'items', coalesce((select jsonb_agg(to_jsonb(page_rows) order by created_at desc, id desc) from page_rows), '[]'::jsonb),
      'total', (select count(*)::integer from filtered)
    )
  );
end;
$$;
