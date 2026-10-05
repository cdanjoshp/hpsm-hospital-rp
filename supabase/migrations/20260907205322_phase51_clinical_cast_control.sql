-- HPSM · Fase 5.1 · Controle clínico de aplicação e retirada de gesso
-- O registro clínico apenas referencia o atendimento financeiro; nenhuma venda o cria automaticamente.

insert into public.system_permissions (code, module, label, description, sort_order) values
  ('casts.view', 'Controle de Gesso', 'Visualizar registros de gesso', 'Consulta aplicações, retiradas e cancelamentos clínicos de gesso.', 30),
  ('casts.create', 'Controle de Gesso', 'Registrar aplicação de gesso', 'Cria um registro clínico manual de aplicação de gesso.', 31),
  ('casts.remove', 'Controle de Gesso', 'Registrar retirada de gesso', 'Registra a retirada clínica de um gesso em uso.', 32),
  ('casts.manage', 'Controle de Gesso', 'Gerenciar registros de gesso', 'Altera previsões e cancela registros clínicos criados indevidamente.', 33)
on conflict (code) do update set
  module = excluded.module,
  label = excluded.label,
  description = excluded.description,
  sort_order = excluded.sort_order;

with grants(permission_code, min_level) as (
  values
    ('casts.view', 1),
    ('casts.create', 1),
    ('casts.remove', 1),
    ('casts.manage', 11)
)
insert into public.staff_position_permissions (position_id, permission_code, granted_by)
select
  position.id,
  grant_row.permission_code,
  coalesce(
    (select profile.user_id from public.profiles profile where profile.role_code = 'diretor_geral' limit 1),
    position.updated_by,
    position.created_by
  )
from public.staff_positions position
join grants grant_row on position.level >= grant_row.min_level
where position.official and position.active
on conflict (position_id, permission_code) do nothing;

create table public.clinical_casts (
  id bigint generated always as identity primary key,
  patient_id bigint not null references public.patients(id) on delete restrict,
  attendance_id bigint references public.attendances(id) on delete restrict,
  body_region text not null,
  laterality text not null,
  status text not null default 'in_use',
  applied_at timestamptz not null,
  applied_by uuid not null references public.profiles(user_id) on delete restrict,
  expected_removal_at timestamptz not null,
  application_notes text,
  removed_at timestamptz,
  removed_by uuid references public.profiles(user_id) on delete restrict,
  removal_notes text,
  cancelled_at timestamptz,
  cancelled_by uuid references public.profiles(user_id) on delete restrict,
  cancellation_reason text,
  created_by uuid not null references public.profiles(user_id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint clinical_casts_body_region_check check (
    body_region in ('hand', 'wrist', 'forearm', 'elbow', 'arm', 'foot', 'ankle', 'leg', 'knee', 'other')
  ),
  constraint clinical_casts_laterality_check check (
    laterality in ('right', 'left', 'bilateral', 'not_applicable')
  ),
  constraint clinical_casts_status_check check (status in ('in_use', 'removed', 'cancelled')),
  constraint clinical_casts_expected_after_application_check check (expected_removal_at > applied_at),
  constraint clinical_casts_application_notes_check check (
    application_notes is null or char_length(btrim(application_notes)) between 2 and 1000
  ),
  constraint clinical_casts_removal_notes_check check (
    removal_notes is null or char_length(btrim(removal_notes)) between 2 and 1000
  ),
  constraint clinical_casts_cancellation_reason_check check (
    cancellation_reason is null or char_length(btrim(cancellation_reason)) between 2 and 500
  ),
  constraint clinical_casts_application_actor_check check (applied_by = created_by),
  constraint clinical_casts_state_check check (
    (
      status = 'in_use'
      and removed_at is null and removed_by is null and removal_notes is null
      and cancelled_at is null and cancelled_by is null and cancellation_reason is null
    )
    or (
      status = 'removed'
      and removed_at is not null and removed_by is not null and removed_at >= applied_at
      and cancelled_at is null and cancelled_by is null and cancellation_reason is null
    )
    or (
      status = 'cancelled'
      and removed_at is null and removed_by is null and removal_notes is null
      and cancelled_at is not null and cancelled_by is not null and cancellation_reason is not null
    )
  )
);

create index clinical_casts_patient_updated_idx
  on public.clinical_casts (patient_id, updated_at desc, id desc);
create index clinical_casts_status_updated_idx
  on public.clinical_casts (status, updated_at desc, id desc);
create index clinical_casts_in_use_due_idx
  on public.clinical_casts (expected_removal_at, id)
  where status = 'in_use';
create index clinical_casts_active_duplicate_idx
  on public.clinical_casts (patient_id, body_region, laterality)
  where status = 'in_use';
create index clinical_casts_attendance_idx
  on public.clinical_casts (attendance_id)
  where attendance_id is not null;
create index clinical_casts_applied_by_idx on public.clinical_casts (applied_by, applied_at desc);
create index clinical_casts_removed_by_idx on public.clinical_casts (removed_by, removed_at desc) where removed_by is not null;
create index clinical_casts_cancelled_by_idx on public.clinical_casts (cancelled_by, cancelled_at desc) where cancelled_by is not null;
create index clinical_casts_created_by_idx on public.clinical_casts (created_by, created_at desc);

create trigger clinical_casts_touch_updated_at
before update on public.clinical_casts
for each row execute function private.touch_updated_at();

create or replace function private.validate_clinical_cast_link()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.attendance_id is not null and not exists (
    select 1
    from public.attendances attendance
    where attendance.id = new.attendance_id
      and attendance.patient_id = new.patient_id
      and attendance.status = 'completed'
  ) then
    raise exception 'O atendimento informado não pertence ao paciente ou não está concluído.';
  end if;
  return new;
end;
$$;

create trigger clinical_casts_validate_link
before insert or update of patient_id, attendance_id on public.clinical_casts
for each row execute function private.validate_clinical_cast_link();

create or replace function private.guard_clinical_cast_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status in ('removed', 'cancelled') then
    raise exception 'Este registro clínico já foi encerrado e não pode ser alterado.';
  end if;
  if new.patient_id is distinct from old.patient_id
     or new.attendance_id is distinct from old.attendance_id
     or new.body_region is distinct from old.body_region
     or new.laterality is distinct from old.laterality
     or new.applied_at is distinct from old.applied_at
     or new.applied_by is distinct from old.applied_by
     or new.application_notes is distinct from old.application_notes
     or new.created_by is distinct from old.created_by
     or new.created_at is distinct from old.created_at then
    raise exception 'Os dados da aplicação de gesso são históricos e não podem ser substituídos.';
  end if;
  if new.status not in ('in_use', 'removed', 'cancelled') then
    raise exception 'Transição de status inválida.';
  end if;
  return new;
end;
$$;

create trigger clinical_casts_guard_update
before update on public.clinical_casts
for each row execute function private.guard_clinical_cast_update();

alter table public.clinical_casts enable row level security;
alter table public.clinical_casts force row level security;

create policy clinical_casts_read_authorized
on public.clinical_casts for select to authenticated
using ((select private.has_permission((select auth.uid()), 'casts.view')));

revoke all on public.clinical_casts from public, anon, authenticated, service_role;
grant select on public.clinical_casts to authenticated;
grant select, insert, update on public.clinical_casts to service_role;
grant usage, select on sequence public.clinical_casts_id_seq to service_role;
revoke all on function private.validate_clinical_cast_link() from public, anon, authenticated, service_role;
revoke all on function private.guard_clinical_cast_update() from public, anon, authenticated, service_role;

create or replace function private.audit_cast_action(
  p_actor_id uuid,
  p_action text,
  p_cast_id bigint,
  p_old_values jsonb,
  p_new_values jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_passport text;
begin
  if p_actor_id is null then
    raise exception 'Ação sem profissional autenticado.';
  end if;
  select profile.passport into v_passport
  from public.profiles profile
  where profile.user_id = p_actor_id and profile.status = 'active';
  if v_passport is null then
    raise exception 'Profissional não autorizado.';
  end if;
  insert into public.audit_logs (
    actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values
  ) values (
    p_actor_id, v_passport, p_action, 'clinical_casts', p_cast_id::text, p_old_values, p_new_values
  );
end;
$$;

revoke all on function private.audit_cast_action(uuid, text, bigint, jsonb, jsonb)
from public, anon, authenticated, service_role;

create or replace function public.clinical_cast_page(
  p_search text default null,
  p_status text default 'in_use',
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
  v_actor uuid := auth.uid();
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_result jsonb;
begin
  if v_actor is null or not private.has_permission(v_actor, 'casts.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if p_status is not null and p_status not in ('in_use', 'removed', 'cancelled') then
    raise exception 'Status de gesso inválido.';
  end if;

  with filtered as (
    select
      cast_record.id,
      cast_record.patient_id,
      patient.name as patient_name,
      patient.passport as patient_passport,
      cast_record.attendance_id,
      cast_record.body_region,
      cast_record.laterality,
      cast_record.status,
      cast_record.applied_at,
      cast_record.expected_removal_at,
      cast_record.removed_at,
      cast_record.applied_by,
      applied.display_name as applied_by_name,
      applied_position.name as applied_by_position,
      cast_record.updated_at
    from public.clinical_casts cast_record
    join public.patients patient on patient.id = cast_record.patient_id
    join public.profiles applied on applied.user_id = cast_record.applied_by
    left join public.staff_positions applied_position on applied_position.id = applied.position_id
    where (p_status is null or cast_record.status = p_status)
      and (
        nullif(btrim(p_search), '') is null
        or patient.name ilike '%' || btrim(p_search) || '%'
        or patient.passport ilike btrim(p_search) || '%'
      )
  ), counted as (
    select count(*)::integer as total from filtered
  ), page_rows as (
    select *
    from filtered
    order by
      case when status = 'in_use' then 0 else 1 end,
      case when status = 'in_use' then expected_removal_at end asc,
      case when status <> 'in_use' then updated_at end desc,
      id desc
    limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'items', coalesce((select jsonb_agg(to_jsonb(page_rows) order by
      case when status = 'in_use' then 0 else 1 end,
      case when status = 'in_use' then expected_removal_at end asc,
      case when status <> 'in_use' then updated_at end desc,
      id desc
    ) from page_rows), '[]'::jsonb),
    'total', (select total from counted)
  ) into v_result;

  return v_result;
end;
$$;

create or replace function public.clinical_cast_detail(p_cast_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_result jsonb;
begin
  if v_actor is null or not private.has_permission(v_actor, 'casts.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'id', cast_record.id,
    'patient_id', cast_record.patient_id,
    'patient_name', patient.name,
    'patient_passport', patient.passport,
    'attendance_id', cast_record.attendance_id,
    'attendance_created_at', attendance.created_at,
    'attendance_total', attendance.total,
    'attendance_summary', case when attendance.id is null then null else coalesce((
      select string_agg(item.service_name || case when item.quantity > 1 then ' ×' || item.quantity::text else '' end, ', ' order by item.id)
      from public.attendance_items item where item.attendance_id = attendance.id
    ), 'Atendimento sem itens') end,
    'body_region', cast_record.body_region,
    'laterality', cast_record.laterality,
    'status', cast_record.status,
    'applied_at', cast_record.applied_at,
    'applied_by', cast_record.applied_by,
    'applied_by_name', applied.display_name,
    'applied_by_position', applied_position.name,
    'expected_removal_at', cast_record.expected_removal_at,
    'application_notes', cast_record.application_notes,
    'removed_at', cast_record.removed_at,
    'removed_by', cast_record.removed_by,
    'removed_by_name', removed.display_name,
    'removed_by_position', removed_position.name,
    'removal_notes', cast_record.removal_notes,
    'cancelled_at', cast_record.cancelled_at,
    'cancelled_by', cast_record.cancelled_by,
    'cancelled_by_name', cancelled.display_name,
    'cancelled_by_position', cancelled_position.name,
    'cancellation_reason', cast_record.cancellation_reason,
    'created_at', cast_record.created_at,
    'updated_at', cast_record.updated_at
  ) into v_result
  from public.clinical_casts cast_record
  join public.patients patient on patient.id = cast_record.patient_id
  left join public.attendances attendance on attendance.id = cast_record.attendance_id
  join public.profiles applied on applied.user_id = cast_record.applied_by
  left join public.staff_positions applied_position on applied_position.id = applied.position_id
  left join public.profiles removed on removed.user_id = cast_record.removed_by
  left join public.staff_positions removed_position on removed_position.id = removed.position_id
  left join public.profiles cancelled on cancelled.user_id = cast_record.cancelled_by
  left join public.staff_positions cancelled_position on cancelled_position.id = cancelled.position_id
  where cast_record.id = p_cast_id;

  if v_result is null then raise exception 'Registro de gesso não localizado.'; end if;
  return v_result;
end;
$$;

create or replace function public.clinical_cast_attendance_options(p_patient_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null
     or not private.has_permission(v_actor, 'casts.create')
     or not private.has_permission(v_actor, 'patients.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.patients patient where patient.id = p_patient_id) then
    raise exception 'Paciente não localizado.';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', option.id,
      'created_at', option.created_at,
      'total', option.total,
      'has_cast_item', option.has_cast_item,
      'summary', coalesce((
        select string_agg(item.service_name || case when item.quantity > 1 then ' ×' || item.quantity::text else '' end, ', ' order by item.id)
        from public.attendance_items item where item.attendance_id = option.id
      ), 'Atendimento sem itens')
    ) order by option.has_cast_item desc, option.created_at desc)
    from (
      select
        attendance.id,
        attendance.created_at,
        attendance.total,
        exists (
          select 1
          from public.attendance_items item
          join public.service_catalog catalog on catalog.id = item.service_id
          where item.attendance_id = attendance.id
            and regexp_replace(upper(btrim(catalog.name)), '\s+', ' ', 'g')
              in ('GESSO', 'APLICAÇÃO DE GESSO', 'APLICACAO DE GESSO')
        ) as has_cast_item
      from public.attendances attendance
      where attendance.patient_id = p_patient_id and attendance.status = 'completed'
      order by has_cast_item desc, attendance.created_at desc
      limit 30
    ) option
  ), '[]'::jsonb);
end;
$$;

create or replace function public.create_clinical_cast(
  p_patient_id bigint,
  p_attendance_id bigint,
  p_body_region text,
  p_laterality text,
  p_applied_at timestamptz,
  p_expected_removal_at timestamptz,
  p_application_notes text default null,
  p_confirm_duplicate boolean default false
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_cast public.clinical_casts;
  v_notes text := nullif(btrim(coalesce(p_application_notes, '')), '');
begin
  if v_actor is null
     or not private.has_permission(v_actor, 'casts.create')
     or not private.has_permission(v_actor, 'patients.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles profile where profile.user_id = v_actor and profile.status = 'active') then
    raise exception 'Profissional responsável não localizado.';
  end if;
  if not exists (select 1 from public.patients patient where patient.id = p_patient_id) then
    raise exception 'Paciente não localizado.';
  end if;
  if p_body_region not in ('hand', 'wrist', 'forearm', 'elbow', 'arm', 'foot', 'ankle', 'leg', 'knee', 'other') then
    raise exception 'Região inválida.';
  end if;
  if p_laterality not in ('right', 'left', 'bilateral', 'not_applicable') then
    raise exception 'Lateralidade inválida.';
  end if;
  if p_applied_at is null then raise exception 'Informe a data e hora da aplicação.'; end if;
  if p_expected_removal_at is null or p_expected_removal_at <= p_applied_at then
    raise exception 'A previsão de retirada deve ser posterior à aplicação.';
  end if;
  if v_notes is not null and char_length(v_notes) > 1000 then
    raise exception 'A observação deve ter no máximo 1000 caracteres.';
  end if;
  if p_attendance_id is not null and not exists (
    select 1 from public.attendances attendance
    where attendance.id = p_attendance_id
      and attendance.patient_id = p_patient_id
      and attendance.status = 'completed'
  ) then
    raise exception 'O atendimento informado não pertence ao paciente ou não está concluído.';
  end if;
  if not coalesce(p_confirm_duplicate, false) and exists (
    select 1 from public.clinical_casts active_cast
    where active_cast.patient_id = p_patient_id
      and active_cast.body_region = p_body_region
      and active_cast.laterality = p_laterality
      and active_cast.status = 'in_use'
  ) then
    raise exception 'O paciente já possui um gesso em uso na mesma região e lateralidade.'
      using errcode = '23505', detail = 'HPSM_ACTIVE_CAST_DUPLICATE';
  end if;

  insert into public.clinical_casts (
    patient_id, attendance_id, body_region, laterality, status,
    applied_at, applied_by, expected_removal_at, application_notes, created_by
  ) values (
    p_patient_id, p_attendance_id, p_body_region, p_laterality, 'in_use',
    p_applied_at, v_actor, p_expected_removal_at, v_notes, v_actor
  ) returning * into v_cast;

  perform private.audit_cast_action(
    v_actor, 'CAST_APPLIED', v_cast.id, null,
    jsonb_build_object(
      'patient_id', v_cast.patient_id,
      'attendance_id', v_cast.attendance_id,
      'body_region', v_cast.body_region,
      'laterality', v_cast.laterality,
      'applied_at', v_cast.applied_at,
      'expected_removal_at', v_cast.expected_removal_at,
      'status', v_cast.status
    )
  );
  return v_cast.id;
end;
$$;

create or replace function public.update_clinical_cast_expected_removal(
  p_cast_id bigint,
  p_expected_removal_at timestamptz,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_old public.clinical_casts;
  v_new public.clinical_casts;
  v_reason text := btrim(coalesce(p_reason, ''));
begin
  select * into v_old from public.clinical_casts where id = p_cast_id for update;
  if v_old.id is null then raise exception 'Registro de gesso não localizado.'; end if;
  if v_actor is null or not (
    private.has_permission(v_actor, 'casts.manage')
    or (v_old.applied_by = v_actor and private.has_permission(v_actor, 'casts.create'))
  ) then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if v_old.status <> 'in_use' then raise exception 'Somente gessos em uso permitem alterar a previsão.'; end if;
  if p_expected_removal_at is null or p_expected_removal_at <= v_old.applied_at then
    raise exception 'A previsão de retirada deve ser posterior à aplicação.';
  end if;
  if p_expected_removal_at = v_old.expected_removal_at then raise exception 'Informe uma nova previsão de retirada.'; end if;
  if char_length(v_reason) not between 2 and 500 then raise exception 'Informe o motivo da alteração.'; end if;

  update public.clinical_casts
  set expected_removal_at = p_expected_removal_at
  where id = p_cast_id
  returning * into v_new;

  perform private.audit_cast_action(
    v_actor, 'CAST_EXPECTED_REMOVAL_CHANGED', v_new.id,
    jsonb_build_object('expected_removal_at', v_old.expected_removal_at),
    jsonb_build_object('expected_removal_at', v_new.expected_removal_at, 'reason', v_reason)
  );
end;
$$;

create or replace function public.remove_clinical_cast(
  p_cast_id bigint,
  p_removed_at timestamptz,
  p_removal_notes text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_old public.clinical_casts;
  v_new public.clinical_casts;
  v_notes text := nullif(btrim(coalesce(p_removal_notes, '')), '');
begin
  if v_actor is null or not private.has_permission(v_actor, 'casts.remove') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  select * into v_old from public.clinical_casts where id = p_cast_id for update;
  if v_old.id is null then raise exception 'Registro de gesso não localizado.'; end if;
  if v_old.status <> 'in_use' then raise exception 'Este gesso já foi retirado ou cancelado.'; end if;
  if p_removed_at is null then raise exception 'Informe a data e hora da retirada.'; end if;
  if p_removed_at < v_old.applied_at then raise exception 'A retirada não pode ocorrer antes da aplicação.'; end if;
  if v_notes is not null and char_length(v_notes) > 1000 then
    raise exception 'A observação da retirada deve ter no máximo 1000 caracteres.';
  end if;

  update public.clinical_casts
  set status = 'removed', removed_at = p_removed_at, removed_by = v_actor, removal_notes = v_notes
  where id = p_cast_id
  returning * into v_new;

  perform private.audit_cast_action(
    v_actor, 'CAST_REMOVED', v_new.id,
    jsonb_build_object('status', v_old.status, 'expected_removal_at', v_old.expected_removal_at),
    jsonb_build_object(
      'status', v_new.status,
      'removed_at', v_new.removed_at,
      'removed_by', v_new.removed_by,
      'early_removal', v_new.removed_at < v_new.expected_removal_at,
      'removal_notes', v_new.removal_notes
    )
  );
end;
$$;

create or replace function public.cancel_clinical_cast(p_cast_id bigint, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_old public.clinical_casts;
  v_new public.clinical_casts;
  v_reason text := btrim(coalesce(p_reason, ''));
begin
  if v_actor is null or not private.has_permission(v_actor, 'casts.manage') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if char_length(v_reason) not between 2 and 500 then raise exception 'Informe o motivo do cancelamento.'; end if;
  select * into v_old from public.clinical_casts where id = p_cast_id for update;
  if v_old.id is null then raise exception 'Registro de gesso não localizado.'; end if;
  if v_old.status <> 'in_use' then raise exception 'Somente um gesso em uso pode ser cancelado.'; end if;

  update public.clinical_casts
  set status = 'cancelled', cancelled_at = now(), cancelled_by = v_actor, cancellation_reason = v_reason
  where id = p_cast_id
  returning * into v_new;

  perform private.audit_cast_action(
    v_actor, 'CAST_CANCELLED', v_new.id,
    jsonb_build_object('status', v_old.status),
    jsonb_build_object(
      'status', v_new.status,
      'cancelled_at', v_new.cancelled_at,
      'cancelled_by', v_new.cancelled_by,
      'reason', v_new.cancellation_reason
    )
  );
end;
$$;

revoke all on function public.clinical_cast_page(text, text, integer, integer) from public, anon, authenticated, service_role;
revoke all on function public.clinical_cast_detail(bigint) from public, anon, authenticated, service_role;
revoke all on function public.clinical_cast_attendance_options(bigint) from public, anon, authenticated, service_role;
revoke all on function public.create_clinical_cast(bigint, bigint, text, text, timestamptz, timestamptz, text, boolean) from public, anon, authenticated, service_role;
revoke all on function public.update_clinical_cast_expected_removal(bigint, timestamptz, text) from public, anon, authenticated, service_role;
revoke all on function public.remove_clinical_cast(bigint, timestamptz, text) from public, anon, authenticated, service_role;
revoke all on function public.cancel_clinical_cast(bigint, text) from public, anon, authenticated, service_role;

grant execute on function public.clinical_cast_page(text, text, integer, integer) to authenticated;
grant execute on function public.clinical_cast_detail(bigint) to authenticated;
grant execute on function public.clinical_cast_attendance_options(bigint) to authenticated;
grant execute on function public.create_clinical_cast(bigint, bigint, text, text, timestamptz, timestamptz, text, boolean) to authenticated;
grant execute on function public.update_clinical_cast_expected_removal(bigint, timestamptz, text) to authenticated;
grant execute on function public.remove_clinical_cast(bigint, timestamptz, text) to authenticated;
grant execute on function public.cancel_clinical_cast(bigint, text) to authenticated;
