-- Um responsável adicional cadastrado tem a mesma gestão da composição no Portal.
set lock_timeout = '5s';
set statement_timeout = '120s';

alter table public.partnerships
  add column secondary_responsible_patient_id bigint references public.patients(id) on delete restrict,
  add column secondary_responsible_assigned_at timestamptz,
  add column secondary_responsible_assigned_by uuid references public.profiles(user_id) on delete restrict,
  add constraint partnerships_secondary_assignment_check check (
    (secondary_responsible_patient_id is null and secondary_responsible_assigned_at is null and secondary_responsible_assigned_by is null)
    or (secondary_responsible_patient_id is not null and secondary_responsible_assigned_at is not null and secondary_responsible_assigned_by is not null)
  ),
  add constraint partnerships_distinct_responsibles_check check (
    secondary_responsible_patient_id is null or
    (responsible_patient_id is not null and responsible_patient_id <> secondary_responsible_patient_id)
  );
create index partnerships_secondary_responsible_idx on public.partnerships (secondary_responsible_patient_id, status, id)
  where secondary_responsible_patient_id is not null;
create index partnerships_secondary_assigned_by_idx on public.partnerships (secondary_responsible_assigned_by)
  where secondary_responsible_assigned_by is not null;

alter table public.partnership_responsible_history
  add column responsibility_role text not null default 'primary',
  add constraint partnership_responsible_history_role_check check (responsibility_role in ('primary', 'secondary'));


create or replace function public.hpsm_partnership_page(
  p_status text default 'active',
  p_search text default null,
  p_limit integer default 24,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.partnership_assert_professional('partnerships.view');
  v_status text := lower(btrim(coalesce(p_status, 'active')));
  v_search text := lower(btrim(coalesce(p_search, '')));
  v_limit integer := least(greatest(coalesce(p_limit, 24), 1), 50);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_result jsonb;
begin
  if v_status not in ('active', 'inactive') then raise exception 'Status de parceria inválido.' using errcode = '22023'; end if;

  with filtered as materialized (
    select partnership.*
    from public.partnerships partnership
    where partnership.status = v_status
      and (v_search = '' or lower(partnership.name) like '%' || v_search || '%')
  ), member_counts as materialized (
    select membership.partnership_id, count(*)::integer as linked
    from public.patient_partnerships membership
    join filtered partnership on partnership.id = membership.partnership_id
    where membership.status = 'active'
    group by membership.partnership_id
  ), pending_counts as materialized (
    select pending.partnership_id,
      count(*) filter (where pending.status = 'pending_registration')::integer as pending_registration,
      count(*) filter (where pending.status = 'name_review')::integer as name_review
    from public.partnership_pending_beneficiaries pending
    join filtered partnership on partnership.id = pending.partnership_id
    where pending.status in ('pending_registration', 'name_review')
    group by pending.partnership_id
  ), page_rows as (
    select partnership.*, patient.name as responsible_name, patient.passport as responsible_passport,
      secondary.name as secondary_responsible_name, secondary.passport as secondary_responsible_passport,
      coalesce(member_counts.linked, 0) as linked,
      coalesce(pending_counts.pending_registration, 0) as pending_registration,
      coalesce(pending_counts.name_review, 0) as name_review
    from filtered partnership
    left join public.patients patient on patient.id = partnership.responsible_patient_id
    left join public.patients secondary on secondary.id = partnership.secondary_responsible_patient_id
    left join member_counts on member_counts.partnership_id = partnership.id
    left join pending_counts on pending_counts.partnership_id = partnership.id
    order by lower(partnership.name), partnership.id
    limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'id', row.id,
      'name', row.name,
      'status', row.status,
      'responsible', case when row.responsible_patient_id is null then null else jsonb_build_object(
        'id', row.responsible_patient_id, 'name', row.responsible_name, 'passport', row.responsible_passport
      ) end,
      'secondary_responsible', case when row.secondary_responsible_patient_id is null then null else jsonb_build_object(
        'id', row.secondary_responsible_patient_id, 'name', row.secondary_responsible_name, 'passport', row.secondary_responsible_passport
      ) end,
      'linked', row.linked,
      'pending_registration', row.pending_registration,
      'name_review', row.name_review,
      'total_informed', row.linked + row.pending_registration + row.name_review,
      'created_at', row.created_at,
      'updated_at', row.updated_at
    ) order by lower(row.name), row.id), '[]'::jsonb),
    'total', (select count(*)::integer from filtered),
    'limit', v_limit,
    'offset', v_offset
  ) into v_result
  from page_rows row;
  return v_result;
end;
$$;

create or replace function public.hpsm_partnership_detail(p_partnership_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.partnership_assert_professional('partnerships.view');
  v_result jsonb;
begin
  select jsonb_build_object(
    'found', true,
    'partnership', jsonb_build_object(
      'id', partnership.id,
      'name', partnership.name,
      'status', partnership.status,
      'notes', partnership.notes,
      'responsible', case when patient.id is null then null else jsonb_build_object(
        'id', patient.id, 'name', patient.name, 'passport', patient.passport,
        'portal_ready', patient.birth_date is not null
      ) end,
      'secondary_responsible', case when secondary.id is null then null else jsonb_build_object(
        'id', secondary.id, 'name', secondary.name, 'passport', secondary.passport,
        'portal_ready', secondary.birth_date is not null
      ) end,
      'created_at', partnership.created_at,
      'updated_at', partnership.updated_at,
      'deactivated_at', partnership.deactivated_at,
      'deactivation_reason', partnership.deactivation_reason
    ),
    'metrics', jsonb_build_object(
      'linked', (select count(*) from public.patient_partnerships membership where membership.partnership_id = partnership.id and membership.status = 'active'),
      'pending_registration', (select count(*) from public.partnership_pending_beneficiaries pending where pending.partnership_id = partnership.id and pending.status = 'pending_registration'),
      'name_review', (select count(*) from public.partnership_pending_beneficiaries pending where pending.partnership_id = partnership.id and pending.status = 'name_review')
    )
  ) into v_result
  from public.partnerships partnership
  left join public.patients patient on patient.id = partnership.responsible_patient_id
  left join public.patients secondary on secondary.id = partnership.secondary_responsible_patient_id
  where partnership.id = p_partnership_id;

  return coalesce(v_result, jsonb_build_object('found', false));
end;
$$;

create or replace function public.update_partnership_v2(
  p_partnership_id bigint,
  p_name text,
  p_notes text default null,
  p_responsible_patient_id bigint default null,
  p_secondary_responsible_patient_id bigint default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.partnership_assert_professional('partnerships.manage');
  v_current public.partnerships%rowtype;
  v_name text := btrim(coalesce(p_name, ''));
  v_notes text := nullif(btrim(coalesce(p_notes, '')), '');
begin
  select * into v_current from public.partnerships where id = p_partnership_id for update;
  if not found then raise exception 'Parceria não localizada.' using errcode = '22023'; end if;
  if char_length(v_name) not between 2 and 120 then raise exception 'Informe o nome da parceria.' using errcode = '22023'; end if;
  if v_notes is not null and char_length(v_notes) > 2000 then raise exception 'A observação pode ter até 2.000 caracteres.' using errcode = '22023'; end if;
  if p_responsible_patient_id is not null and not private.partnership_patient_can_use_portal(p_responsible_patient_id) then
    raise exception 'O responsável precisa ser um paciente cadastrado com passaporte válido para acessar o Portal.' using errcode = '22023';
  end if;

  if p_secondary_responsible_patient_id is not null and not private.partnership_patient_can_use_portal(p_secondary_responsible_patient_id) then
    raise exception 'O responsável adicional precisa ser um paciente cadastrado com passaporte válido.' using errcode = '22023';
  end if;
  if p_secondary_responsible_patient_id is not null and (p_responsible_patient_id is null or p_secondary_responsible_patient_id = p_responsible_patient_id) then
    raise exception 'Selecione um responsável principal e outro paciente para a responsabilidade adicional.' using errcode = '22023';
  end if;

  update public.partnerships set
    name = v_name,
    notes = v_notes,
    responsible_patient_id = p_responsible_patient_id,
    responsible_assigned_at = case
      when responsible_patient_id is distinct from p_responsible_patient_id and p_responsible_patient_id is not null then now()
      when p_responsible_patient_id is null then null
      else responsible_assigned_at end,
    responsible_assigned_by = case
      when responsible_patient_id is distinct from p_responsible_patient_id and p_responsible_patient_id is not null then v_actor
      when p_responsible_patient_id is null then null
      else responsible_assigned_by end,
    secondary_responsible_patient_id = p_secondary_responsible_patient_id,
    secondary_responsible_assigned_at = case
      when secondary_responsible_patient_id is distinct from p_secondary_responsible_patient_id and p_secondary_responsible_patient_id is not null then now()
      when p_secondary_responsible_patient_id is null then null
      else secondary_responsible_assigned_at end,
    secondary_responsible_assigned_by = case
      when secondary_responsible_patient_id is distinct from p_secondary_responsible_patient_id and p_secondary_responsible_patient_id is not null then v_actor
      when p_secondary_responsible_patient_id is null then null
      else secondary_responsible_assigned_by end,
    updated_at = now(),
    updated_by = v_actor
  where id = p_partnership_id;

  if v_current.responsible_patient_id is distinct from p_responsible_patient_id then
    insert into public.partnership_responsible_history (partnership_id, previous_patient_id, responsible_patient_id, changed_by)
    values (p_partnership_id, v_current.responsible_patient_id, p_responsible_patient_id, v_actor);
  end if;
  if v_current.secondary_responsible_patient_id is distinct from p_secondary_responsible_patient_id then
    insert into public.partnership_responsible_history (partnership_id, previous_patient_id, responsible_patient_id, changed_by, responsibility_role)
    values (p_partnership_id, v_current.secondary_responsible_patient_id, p_secondary_responsible_patient_id, v_actor, 'secondary');
  end if;
  perform private.partnership_audit('PARTNERSHIP_UPDATED', 'partnerships', p_partnership_id::text, 'professional', v_actor, null,
    jsonb_build_object('name', v_current.name, 'responsible_patient_id', v_current.responsible_patient_id, 'secondary_responsible_patient_id', v_current.secondary_responsible_patient_id),
    jsonb_build_object('name', v_name, 'responsible_patient_id', p_responsible_patient_id, 'secondary_responsible_patient_id', p_secondary_responsible_patient_id));
  return true;
exception when unique_violation then
  raise exception 'Já existe uma parceria com este nome.' using errcode = '23505';
end;
$$;

create or replace function private.partnership_portal_actor(
  p_token_hash text,
  p_partnership_id bigint,
  p_require_active boolean default false
)
returns bigint
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_patient_id bigint;
  v_status text;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'Sessão do Portal inválida.' using errcode = '42501';
  end if;

  select session.patient_id, partnership.status
  into v_patient_id, v_status
  from private.patient_portal_session_record(p_token_hash) session
  join private.patient_portal_credentials credential on credential.patient_id = session.patient_id
  join public.partnerships partnership
    on partnership.id = p_partnership_id
   and (partnership.responsible_patient_id = session.patient_id
     or partnership.secondary_responsible_patient_id = session.patient_id);

  if not found then
    raise exception 'Parceria não localizada para esta sessão.' using errcode = '42501';
  end if;
  if p_require_active and v_status <> 'active' then
    raise exception 'Esta parceria está inativa e não permite alterações.' using errcode = '22023';
  end if;
  return v_patient_id;
end;
$$;

create or replace function public.patient_portal_partnership_page(p_token_hash text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_session record;
  v_result jsonb;
begin
  select * into v_session from private.patient_portal_session_record(p_token_hash);
  if not found then return jsonb_build_object('authenticated', false); end if;

  with responsible as materialized (
    select partnership.*
    from public.partnerships partnership
    where partnership.responsible_patient_id = v_session.patient_id
       or partnership.secondary_responsible_patient_id = v_session.patient_id
  ), member_counts as materialized (
    select membership.partnership_id, count(*)::integer as linked
    from public.patient_partnerships membership
    join responsible partnership on partnership.id = membership.partnership_id
    where membership.status = 'active'
    group by membership.partnership_id
  ), pending_counts as materialized (
    select pending.partnership_id,
      count(*) filter (where pending.status = 'pending_registration')::integer as pending_registration,
      count(*) filter (where pending.status = 'name_review')::integer as name_review
    from public.partnership_pending_beneficiaries pending
    join responsible partnership on partnership.id = pending.partnership_id
    where pending.status in ('pending_registration', 'name_review')
    group by pending.partnership_id
  )
  select jsonb_build_object(
    'authenticated', true,
    'patient', jsonb_build_object('name', v_session.patient_name, 'passport', v_session.patient_passport),
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'id', partnership.id,
      'name', partnership.name,
      'role', case when partnership.responsible_patient_id = v_session.patient_id then 'primary' else 'secondary' end,
      'status', partnership.status,
      'linked', coalesce(member_counts.linked, 0),
      'pending_registration', coalesce(pending_counts.pending_registration, 0),
      'name_review', coalesce(pending_counts.name_review, 0),
      'total_informed', coalesce(member_counts.linked, 0) + coalesce(pending_counts.pending_registration, 0) + coalesce(pending_counts.name_review, 0)
    ) order by (partnership.status = 'active') desc, lower(partnership.name)), '[]'::jsonb)
  ) into v_result
  from responsible partnership
  left join member_counts on member_counts.partnership_id = partnership.id
  left join pending_counts on pending_counts.partnership_id = partnership.id;
  return v_result;
end;
$$;

create or replace function public.patient_portal_session_me(p_token_hash text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_session record;
begin
  select * into v_session from private.patient_portal_session_record(p_token_hash);
  if not found then return jsonb_build_object('authenticated', false); end if;
  return jsonb_build_object(
    'authenticated', true,
    'name', v_session.patient_name,
    'passport', v_session.patient_passport,
    'expires_at', v_session.expires_at,
    'manages_partnerships', exists (
      select 1 from public.partnerships partnership
      where partnership.responsible_patient_id = v_session.patient_id
         or partnership.secondary_responsible_patient_id = v_session.patient_id
    )
  );
end;
$$;

revoke all on function public.update_partnership_v2(bigint,text,text,bigint,bigint)
  from public, anon, authenticated, service_role;
grant execute on function public.update_partnership_v2(bigint,text,text,bigint,bigint) to authenticated;
notify pgrst, 'reload schema';
