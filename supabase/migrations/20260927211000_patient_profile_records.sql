-- Perfil do paciente 2.0: histórico e documentos com paginação global e permissões por origem.
create or replace function public.hpsm_patient_record_page(
  p_patient_id bigint,
  p_mode text default 'timeline',
  p_filter text default 'all',
  p_limit integer default 10,
  p_offset integer default 0
) returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_exams boolean;
  v_casts boolean;
  v_hospitalizations boolean;
  v_certificates boolean;
  v_records boolean;
  v_result jsonb;
begin
  if not private.has_permission(v_actor, 'patients.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.patients where id = p_patient_id) then
    raise exception 'Paciente não localizado.';
  end if;
  if p_mode not in ('timeline', 'documents') or
     p_filter not in ('all', 'attendance', 'procedure', 'purchase', 'exam', 'cast', 'hospitalization', 'plan', 'certificate', 'prescription', 'record') or
     p_limit not between 1 and 50 or p_offset not between 0 and 100000 then
    raise exception 'Filtro ou paginação inválida.';
  end if;
  v_exams := private.has_permission(v_actor, 'exams.view');
  v_casts := private.has_permission(v_actor, 'casts.view');
  v_hospitalizations := private.has_permission(v_actor, 'hospitalizations.history');
  v_certificates := private.has_permission(v_actor, 'atestados.view');
  v_records := private.has_permission(v_actor, 'consultations.view');

  with records as materialized (
    select 'attendance-' || a.id as id, a.created_at as date, 'attendance'::text as category,
      case when a.status = 'cancelled' then 'Atendimento cancelado' else 'Atendimento realizado' end as title,
      'Atendimento #' || a.id as description, a.id::text as resource_id, 'attendance'::text as resource_kind,
      a.status::text as status, false as document
    from public.attendances a where a.patient_id = p_patient_id
    union all
    select 'procedure-' || ai.id, a.created_at, 'procedure', 'Procedimento: ' || ai.service_name,
      'Atendimento #' || a.id, a.id::text, 'attendance', a.status, false
    from public.attendance_items ai
    join public.attendances a on a.id = ai.attendance_id
    join public.service_catalog s on s.id = ai.service_id
    where a.patient_id = p_patient_id and lower(s.category) in ('atendimentos', 'exames')
    union all
    select 'purchase-' || ai.id, a.created_at, 'purchase', 'Compra: ' || ai.service_name,
      'Atendimento #' || a.id, a.id::text, 'attendance', a.status, false
    from public.attendance_items ai
    join public.attendances a on a.id = ai.attendance_id
    join public.service_catalog s on s.id = ai.service_id
    where a.patient_id = p_patient_id and lower(s.category) in ('insumos', 'medicamentos', 'produtos', 'convênios')
    union all
    select 'exam-' || e.id, e.requested_at, 'exam', 'Exame solicitado: ' || t.name,
      'Exame #' || e.id, e.id::text, 'exam', e.status, false
    from public.clinical_exams e join public.exam_types t on t.id = e.exam_type_id
    where e.patient_id = p_patient_id and v_exams
    union all
    select 'exam-result-' || e.id, e.completed_at, 'exam', 'Laudo: ' || t.name,
      'Exame #' || e.id, e.id::text, 'exam', e.status, true
    from public.clinical_exams e join public.exam_types t on t.id = e.exam_type_id
    where e.patient_id = p_patient_id and e.status = 'completed' and e.completed_at is not null and v_exams
    union all
    select 'cast-' || c.id, c.applied_at, 'cast', 'Gesso aplicado',
      private.clinical_cast_location_label(c.body_region, c.laterality), c.id::text, 'cast', c.status, false
    from public.clinical_casts c where c.patient_id = p_patient_id and v_casts
    union all
    select 'cast-removed-' || c.id, c.removed_at, 'cast', 'Gesso retirado',
      private.clinical_cast_location_label(c.body_region, c.laterality), c.id::text, 'cast', c.status, false
    from public.clinical_casts c where c.patient_id = p_patient_id and c.removed_at is not null and v_casts
    union all
    select 'hospitalization-' || h.id, h.admitted_at, 'hospitalization', 'Internação iniciada',
      coalesce(h.reason, 'Internação #' || h.id), h.id::text, 'hospitalization', h.status, false
    from public.hospitalizations h where h.patient_id = p_patient_id and v_hospitalizations
    union all
    select 'discharge-' || h.id, h.discharged_at, 'hospitalization', 'Alta hospitalar',
      'Internação #' || h.id, h.id::text, 'hospitalization', h.status, false
    from public.hospitalizations h where h.patient_id = p_patient_id and h.discharged_at is not null and v_hospitalizations
    union all
    select 'certificate-' || c.id, coalesce(c.finalized_at,c.created_at), 'certificate',
      'Atestado médico #' || c.id, case when c.status = 'finalized' then 'Documento finalizado' else 'Documento em elaboração' end,
      c.id::text, 'certificate', c.status, c.status = 'finalized'
    from public.medical_certificates c where c.patient_id = p_patient_id and v_certificates
    union all
    select 'record-' || d.id, coalesce(d.completed_at,d.created_at), 'record', 'Prontuário clínico',
      'Registro #' || c.id, c.id::text, 'record', d.status, d.status = 'completed'
    from public.consultation_documents d join public.clinical_consultations c on c.id = d.consultation_id
    where c.patient_id = p_patient_id and v_records and d.status = 'completed'
    union all
    select 'prescription-' || d.id, coalesce(d.completed_at,d.created_at), 'prescription', 'Receita médica',
      'Registro #' || c.id, c.id::text, 'prescription', d.status, d.status = 'completed'
    from public.prescription_documents d join public.clinical_consultations c on c.id = d.consultation_id
    where c.patient_id = p_patient_id and v_records and d.status = 'completed'
    union all
    select 'plan-request-' || p.id, p.requested_at, 'plan', 'Solicitação de plano de saúde',
      'Solicitação #' || p.id, p.id::text, 'plan', p.status, false
    from public.patient_health_plan_requests p where p.patient_id = p_patient_id
    union all
    select 'plan-review-' || p.id, p.reviewed_at, 'plan',
      case when p.status = 'rejected' then 'Plano recusado' when p.administrative_action = 'renew' then 'Plano renovado' else 'Plano ativado' end,
      case when p.status = 'rejected' then coalesce(p.rejection_reason,'Solicitação recusada') else 'Validade até ' || to_char(p.coverage_end at time zone 'America/Sao_Paulo','DD/MM/YYYY') end,
      p.id::text, 'plan', p.status, false
    from public.patient_health_plan_requests p where p.patient_id = p_patient_id and p.reviewed_at is not null
    union all
    select 'plan-expiry-' || p.id, p.coverage_end, 'plan', 'Plano vencido',
      'Validade encerrada', p.id::text, 'plan', 'expired'::text, false
    from public.patient_health_plan_requests p
    where p.patient_id = p_patient_id and p.status = 'approved' and p.coverage_end < now()
  ), filtered as materialized (
    select * from records r
    where r.date is not null and (p_mode = 'timeline' or r.document)
      and (p_filter = 'all' or r.category = p_filter)
  )
  select jsonb_build_object(
    'total', (select count(*) from filtered),
    'items', coalesce((select jsonb_agg(to_jsonb(item) order by item.date desc, item.id desc)
       from (select * from filtered order by date desc, id desc limit p_limit offset p_offset) item), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

revoke all on function public.hpsm_patient_record_page(bigint,text,text,integer,integer) from public, anon, authenticated, service_role;
grant execute on function public.hpsm_patient_record_page(bigint,text,text,integer,integer) to authenticated;

create index if not exists clinical_consultations_patient_profile_idx on public.clinical_consultations(patient_id,id);
create index if not exists hospitalizations_patient_profile_idx on public.hospitalizations(patient_id,admitted_at desc);

create or replace function public.hpsm_patient_active_hospitalization(p_patient_id bigint)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
begin
  if not private.has_permission(v_actor, 'patients.view') or not private.has_permission(v_actor, 'hospitalizations.history') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  return (select jsonb_build_object('id',h.id,'admitted_at',h.admitted_at,'reason',h.reason)
    from public.hospitalizations h where h.patient_id = p_patient_id and h.status = 'active'
    order by h.admitted_at desc limit 1);
end;
$$;
revoke all on function public.hpsm_patient_active_hospitalization(bigint) from public, anon, authenticated, service_role;
grant execute on function public.hpsm_patient_active_hospitalization(bigint) to authenticated;
