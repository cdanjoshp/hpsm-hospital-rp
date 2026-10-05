-- HPSM · Fase 7 · Busca Global profissional.
-- Consulta somente fontes canônicas e aplica as permissões efetivas do ator.
-- Central de Exames e clinical_exams não fazem parte da Busca Global.

create or replace function public.hpsm_global_search(
  p_query text,
  p_limit integer default 5
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
  v_query text := btrim(coalesce(p_query, ''));
  v_limit integer := least(greatest(coalesce(p_limit, 5), 1), 5);
  v_escaped text;
  v_contains text;
  v_prefix text;
  v_result jsonb;
begin
  if char_length(v_query) < 2 then
    return jsonb_build_object('items', '[]'::jsonb);
  end if;
  if char_length(v_query) > 100 then
    raise exception 'A busca deve ter no máximo 100 caracteres.' using errcode = '22023';
  end if;

  -- Escapa curingas fornecidos pelo usuário antes de montar os padrões ILIKE.
  v_escaped := replace(replace(replace(v_query, '\', '\\'), '%', '\%'), '_', '\_');
  v_contains := '%' || v_escaped || '%';
  v_prefix := v_escaped || '%';

  with
  patient_results as (
    select
      1 as category_order,
      case
        when upper(patient.passport) = upper(v_query) then 1
        when patient.passport ilike v_prefix escape '\' then 2
        when lower(patient.name) = lower(v_query) then 3
        when patient.name ilike v_prefix escape '\' then 4
        else 5
      end as score,
      patient.updated_at as sort_at,
      'patients'::text as category,
      patient.id::text as id,
      patient.name as title,
      'Passaporte ' || patient.passport as subtitle,
      '/pacientes/' || patient.id::text as href,
      null::numeric as amount
    from public.patients patient
    where 'patients.view' = any(v_permissions)
      and (
        patient.passport ilike v_contains escape '\'
        or patient.name ilike v_contains escape '\'
      )
    order by score, patient.updated_at desc, patient.name
    limit v_limit
  ),
  professional_results as (
    select
      2 as category_order,
      case
        when upper(profile.passport) = upper(v_query) then 1
        when profile.passport ilike v_prefix escape '\' then 2
        when lower(profile.display_name) = lower(v_query) then 3
        when profile.display_name ilike v_prefix escape '\' then 4
        when lower(coalesce(position.name, '')) = lower(v_query) then 5
        when coalesce(position.name, '') ilike v_prefix escape '\' then 6
        else 7
      end as score,
      profile.updated_at as sort_at,
      'professionals'::text as category,
      profile.user_id::text as id,
      profile.display_name as title,
      profile.passport || ' · ' || coalesce(position.name, 'Sem cargo atual') as subtitle,
      '/administrativo/perfis?selecionar=' || profile.user_id::text as href,
      null::numeric as amount
    from public.profiles profile
    left join public.staff_positions position on position.id = profile.position_id
    where v_permissions && array['hr.team.view', 'hr.reports.view', 'team.manage', 'access.manage']::text[]
      and (
        profile.passport ilike v_contains escape '\'
        or profile.display_name ilike v_contains escape '\'
        or coalesce(position.name, '') ilike v_contains escape '\'
      )
    order by score, profile.updated_at desc, profile.display_name
    limit v_limit
  ),
  attendance_results as (
    select
      3 as category_order,
      case
        when v_query ~ '^[0-9]+$' and attendance.id::text = v_query then 1
        when v_query ~ '^[0-9]+$' and attendance.id::text like v_query || '%' then 2
        when upper(patient.passport) = upper(v_query) then 3
        when patient.passport ilike v_prefix escape '\' then 4
        when lower(patient.name) = lower(v_query) then 5
        when patient.name ilike v_prefix escape '\' then 6
        else 7
      end as score,
      attendance.created_at as sort_at,
      'attendances'::text as category,
      attendance.id::text as id,
      coalesce(nullif(btrim(attendance.patient_name), ''), 'Venda avulsa') as title,
      'Atendimento #' || attendance.id::text || ' · ' || attendance.patient_passport
        || ' · ' || to_char(attendance.created_at at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI') as subtitle,
      '/atendimentos#atendimento-' || attendance.id::text as href,
      attendance.total as amount
    from public.attendances attendance
    join public.patients patient on patient.id = attendance.patient_id
    where (
        'attendances.create' = any(v_permissions)
        or 'attendances.manage' = any(v_permissions)
        or 'patients.view' = any(v_permissions)
      )
      and (
        attendance.performed_by = v_actor
        or 'attendances.manage' = any(v_permissions)
        or 'patients.view' = any(v_permissions)
      )
      and (
        (v_query ~ '^[0-9]+$' and attendance.id::text like v_query || '%')
        or patient.passport ilike v_contains escape '\'
        or patient.name ilike v_contains escape '\'
      )
    order by score, attendance.created_at desc, attendance.id desc
    limit v_limit
  ),
  catalog_results as (
    select
      4 as category_order,
      case
        when lower(service.name) = lower(v_query) then 1
        when service.name ilike v_prefix escape '\' then 2
        when lower(service.category) = lower(v_query) then 3
        when service.category ilike v_prefix escape '\' then 4
        else 5
      end as score,
      service.updated_at as sort_at,
      'catalog'::text as category,
      service.id::text as id,
      service.name as title,
      service.category || ' · ' || case when service.active then 'Ativo' else 'Inativo' end as subtitle,
      '/catalogo?item=' || service.id::text as href,
      service.unit_price as amount
    from public.service_catalog service
    where 'catalog.manage' = any(v_permissions)
      and (
        service.name ilike v_contains escape '\'
        or service.category ilike v_contains escape '\'
      )
    order by score, service.updated_at desc, service.name
    limit v_limit
  ),
  application_results as (
    select
      5 as category_order,
      case
        when upper(application.passport) = upper(v_query) then 1
        when application.passport ilike v_prefix escape '\' then 2
        when lower(application.full_name) = lower(v_query) then 3
        when application.full_name ilike v_prefix escape '\' then 4
        else 5
      end as score,
      application.created_at as sort_at,
      'applications'::text as category,
      application.id::text as id,
      application.full_name as title,
      application.passport || ' · ' || case application.status
        when 'submitted' then 'Recebida'
        when 'under_review' then 'Em análise'
        when 'interview' then 'Entrevista'
        when 'approved' then 'Aprovada'
        when 'rejected' then 'Recusada'
        when 'withdrawn' then 'Retirada'
        else 'Situação não informada'
      end as subtitle,
      '/administrativo/recrutamento?selecionar=' || application.id::text as href,
      null::numeric as amount
    from public.recruitment_applications application
    where 'recruitment.manage' = any(v_permissions)
      and (
        application.passport ilike v_contains escape '\'
        or application.full_name ilike v_contains escape '\'
      )
    order by score, application.created_at desc, application.full_name
    limit v_limit
  ),
  combined as (
    select * from patient_results
    union all select * from professional_results
    union all select * from attendance_results
    union all select * from catalog_results
    union all select * from application_results
  )
  select jsonb_build_object(
    'items', coalesce(
      jsonb_agg(
        jsonb_build_object(
          'amount', combined.amount,
          'category', combined.category,
          'href', combined.href,
          'id', combined.id,
          'subtitle', combined.subtitle,
          'title', combined.title
        )
        order by combined.category_order, combined.score, combined.sort_at desc, combined.title
      ),
      '[]'::jsonb
    )
  ) into v_result
  from combined;

  return v_result;
end;
$$;

revoke all on function public.hpsm_global_search(text, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.hpsm_global_search(text, integer)
  to authenticated;

comment on function public.hpsm_global_search(text, integer) is
  'Busca profissional por fontes canônicas e permissões efetivas. Não consulta a Central de Exames nem clinical_exams.';

notify pgrst, 'reload schema';
