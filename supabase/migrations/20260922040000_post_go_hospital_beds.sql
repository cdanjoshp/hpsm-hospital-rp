-- HPSM · Rollup pós-go · Controle de Leitos e Internações
-- Dez leitos canônicos compartilhados por pacientes HPSM e pacientes externos do HP Norte.

insert into public.system_permissions (code, module, label, description, sort_order) values
  ('hospitalizations.view', 'Internações e Leitos', 'Visualizar leitos e internações', 'Consulta o mapa atual dos leitos e os dados das internações.', 45),
  ('hospitalizations.create', 'Internações e Leitos', 'Registrar internações', 'Registra uma nova internação em um leito disponível.', 46),
  ('hospitalizations.update', 'Internações e Leitos', 'Corrigir e cancelar internações', 'Corrige dados clínico-administrativos e cancela registros indevidos.', 47),
  ('hospitalizations.discharge', 'Internações e Leitos', 'Registrar altas', 'Registra a alta de uma internação ativa.', 48),
  ('hospitalizations.history', 'Internações e Leitos', 'Consultar histórico de internações', 'Consulta o histórico paginado de internações.', 49)
on conflict (code) do update set
  module = excluded.module,
  label = excluded.label,
  description = excluded.description,
  sort_order = excluded.sort_order;

with grants(permission_code, min_level) as (
  values
    ('hospitalizations.view', 1),
    ('hospitalizations.create', 1),
    ('hospitalizations.update', 11),
    ('hospitalizations.discharge', 1),
    ('hospitalizations.history', 1)
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

create table public.hospital_beds (
  id bigint generated always as identity primary key,
  number smallint not null unique,
  code text not null unique,
  label text not null unique,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint hospital_beds_number_check check (number between 1 and 10),
  constraint hospital_beds_code_check check (code = 'LEITO_' || lpad(number::text, 2, '0')),
  constraint hospital_beds_label_check check (label = 'Leito ' || lpad(number::text, 2, '0'))
);

insert into public.hospital_beds (number, code, label)
select number, 'LEITO_' || lpad(number::text, 2, '0'), 'Leito ' || lpad(number::text, 2, '0')
from generate_series(1, 10) as number
on conflict (number) do update set code = excluded.code, label = excluded.label, active = true;

create table public.hospitalizations (
  id bigint generated always as identity primary key,
  bed_id bigint not null references public.hospital_beds(id) on delete restrict,
  source text not null,
  patient_id bigint references public.patients(id) on delete restrict,
  external_patient_name text,
  external_passport text,
  reason text not null,
  notes text,
  admitted_at timestamptz not null,
  admitted_by uuid not null references public.profiles(user_id) on delete restrict,
  status text not null default 'active',
  discharged_at timestamptz,
  discharged_by uuid references public.profiles(user_id) on delete restrict,
  cancelled_at timestamptz,
  cancelled_by uuid references public.profiles(user_id) on delete restrict,
  cancellation_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint hospitalizations_source_check check (source in ('hpsm', 'hp_norte')),
  constraint hospitalizations_status_check check (status in ('active', 'discharged', 'cancelled')),
  constraint hospitalizations_reason_check check (char_length(btrim(reason)) between 2 and 2000),
  constraint hospitalizations_notes_check check (notes is null or char_length(btrim(notes)) between 2 and 2000),
  constraint hospitalizations_external_name_check check (external_patient_name is null or char_length(btrim(external_patient_name)) between 2 and 120),
  constraint hospitalizations_external_passport_check check (external_passport is null or char_length(btrim(external_passport)) between 2 and 32),
  constraint hospitalizations_patient_source_check check (
    (source = 'hpsm' and patient_id is not null and external_patient_name is null and external_passport is null)
    or
    (source = 'hp_norte' and patient_id is null and external_patient_name is not null)
  ),
  constraint hospitalizations_state_check check (
    (
      status = 'active'
      and discharged_at is null and discharged_by is null
      and cancelled_at is null and cancelled_by is null and cancellation_reason is null
    )
    or (
      status = 'discharged'
      and discharged_at is not null and discharged_by is not null and discharged_at >= admitted_at
      and cancelled_at is null and cancelled_by is null and cancellation_reason is null
    )
    or (
      status = 'cancelled'
      and discharged_at is null and discharged_by is null
      and cancelled_at is not null and cancelled_by is not null and cancellation_reason is not null
    )
  ),
  constraint hospitalizations_cancellation_reason_check check (
    cancellation_reason is null or char_length(btrim(cancellation_reason)) between 2 and 500
  )
);

create unique index hospitalizations_one_active_per_bed_uidx
  on public.hospitalizations (bed_id) where status = 'active';
create unique index hospitalizations_one_active_per_patient_uidx
  on public.hospitalizations (patient_id) where status = 'active' and patient_id is not null;
create index hospitalizations_bed_history_idx on public.hospitalizations (bed_id, admitted_at desc, id desc);
create index hospitalizations_patient_history_idx on public.hospitalizations (patient_id, admitted_at desc, id desc) where patient_id is not null;
create index hospitalizations_source_history_idx on public.hospitalizations (source, admitted_at desc, id desc);
create index hospitalizations_status_history_idx on public.hospitalizations (status, admitted_at desc, id desc);
create index hospitalizations_admitted_by_idx on public.hospitalizations (admitted_by, admitted_at desc);
create index hospitalizations_discharged_by_idx on public.hospitalizations (discharged_by, discharged_at desc) where discharged_by is not null;
create index hospitalizations_cancelled_by_idx on public.hospitalizations (cancelled_by, cancelled_at desc) where cancelled_by is not null;

create trigger hospital_beds_touch_updated_at
before update on public.hospital_beds
for each row execute function private.touch_updated_at();

create trigger hospitalizations_touch_updated_at
before update on public.hospitalizations
for each row execute function private.touch_updated_at();

alter table public.hospital_beds enable row level security;
alter table public.hospital_beds force row level security;
alter table public.hospitalizations enable row level security;
alter table public.hospitalizations force row level security;

create policy hospital_beds_read_authorized
on public.hospital_beds for select to authenticated
using (
  (select private.hpsm_session_valid(true))
  and (select private.has_permission((select auth.uid()), 'hospitalizations.view'))
);

create policy hospitalizations_read_authorized
on public.hospitalizations for select to authenticated
using (
  (select private.hpsm_session_valid(true))
  and (select private.has_permission((select auth.uid()), 'hospitalizations.view'))
);

revoke all on public.hospital_beds from public, anon, authenticated, service_role;
revoke all on public.hospitalizations from public, anon, authenticated, service_role;
grant select on public.hospital_beds, public.hospitalizations to authenticated;
grant select, insert, update on public.hospital_beds, public.hospitalizations to service_role;
grant usage, select on sequence public.hospital_beds_id_seq, public.hospitalizations_id_seq to service_role;

create or replace function private.audit_hospitalization_action(
  p_actor_id uuid,
  p_action text,
  p_hospitalization_id bigint,
  p_old_values jsonb,
  p_new_values jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_passport text;
begin
  select profile.passport into v_passport
  from public.profiles profile
  where profile.user_id = p_actor_id and profile.status = 'active';
  if v_passport is null then raise exception 'Profissional não autorizado.' using errcode = '42501'; end if;
  insert into public.audit_logs (actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values)
  values (p_actor_id, v_passport, p_action, 'hospitalizations', p_hospitalization_id::text, p_old_values, p_new_values);
end;
$$;

revoke all on function private.audit_hospitalization_action(uuid, text, bigint, jsonb, jsonb)
from public, anon, authenticated, service_role;

create or replace function public.hospital_bed_board()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_result jsonb;
begin
  if not private.has_permission(v_actor, 'hospitalizations.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  with board as (
    select
      bed.id,
      bed.number,
      bed.code,
      bed.label,
      hospitalization.id as hospitalization_id,
      hospitalization.source,
      hospitalization.patient_id,
      coalesce(patient.name, hospitalization.external_patient_name) as patient_name,
      coalesce(patient.passport, hospitalization.external_passport) as patient_passport,
      hospitalization.reason,
      hospitalization.notes,
      hospitalization.admitted_at,
      hospitalization.admitted_by,
      admitted.display_name as admitted_by_name
    from public.hospital_beds bed
    left join public.hospitalizations hospitalization
      on hospitalization.bed_id = bed.id and hospitalization.status = 'active'
    left join public.patients patient on patient.id = hospitalization.patient_id
    left join public.profiles admitted on admitted.user_id = hospitalization.admitted_by
    where bed.active
    order by bed.number
  )
  select jsonb_build_object(
    'total', count(*),
    'available', count(*) filter (where hospitalization_id is null),
    'occupied', count(*) filter (where hospitalization_id is not null),
    'hpsm', count(*) filter (where source = 'hpsm'),
    'hp_norte', count(*) filter (where source = 'hp_norte'),
    'beds', coalesce(jsonb_agg(to_jsonb(board) order by number), '[]'::jsonb)
  ) into v_result from board;
  return v_result;
end;
$$;

create or replace function public.hospitalization_history_page(
  p_search text default null,
  p_source text default null,
  p_bed_id bigint default null,
  p_status text default null,
  p_date_from date default null,
  p_date_to date default null,
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
  v_result jsonb;
begin
  if not private.has_permission(v_actor, 'hospitalizations.history') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if p_source is not null and p_source not in ('hpsm', 'hp_norte') then raise exception 'Origem inválida.'; end if;
  if p_status is not null and p_status not in ('active', 'discharged', 'cancelled') then raise exception 'Status inválido.'; end if;
  if p_date_from is not null and p_date_to is not null and p_date_to < p_date_from then raise exception 'Período inválido.'; end if;

  with filtered as (
    select
      hospitalization.id,
      hospitalization.bed_id,
      bed.number as bed_number,
      bed.label as bed_label,
      hospitalization.source,
      hospitalization.patient_id,
      coalesce(patient.name, hospitalization.external_patient_name) as patient_name,
      coalesce(patient.passport, hospitalization.external_passport) as patient_passport,
      hospitalization.reason,
      hospitalization.notes,
      hospitalization.admitted_at,
      hospitalization.admitted_by,
      admitted.display_name as admitted_by_name,
      hospitalization.status,
      hospitalization.discharged_at,
      hospitalization.discharged_by,
      discharged.display_name as discharged_by_name,
      hospitalization.cancelled_at,
      hospitalization.cancelled_by,
      cancelled.display_name as cancelled_by_name,
      hospitalization.cancellation_reason,
      hospitalization.created_at,
      hospitalization.updated_at
    from public.hospitalizations hospitalization
    join public.hospital_beds bed on bed.id = hospitalization.bed_id
    left join public.patients patient on patient.id = hospitalization.patient_id
    join public.profiles admitted on admitted.user_id = hospitalization.admitted_by
    left join public.profiles discharged on discharged.user_id = hospitalization.discharged_by
    left join public.profiles cancelled on cancelled.user_id = hospitalization.cancelled_by
    where (p_source is null or hospitalization.source = p_source)
      and (p_bed_id is null or hospitalization.bed_id = p_bed_id)
      and (p_status is null or hospitalization.status = p_status)
      and (p_date_from is null or hospitalization.admitted_at >= p_date_from::timestamptz)
      and (p_date_to is null or hospitalization.admitted_at < (p_date_to + 1)::timestamptz)
      and (
        nullif(btrim(p_search), '') is null
        or coalesce(patient.name, hospitalization.external_patient_name) ilike '%' || btrim(p_search) || '%'
        or coalesce(patient.passport, hospitalization.external_passport, '') ilike btrim(p_search) || '%'
      )
  ), counted as (
    select count(*)::integer as total from filtered
  ), page_rows as (
    select * from filtered
    order by case when status = 'active' then 0 else 1 end, admitted_at desc, id desc
    limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'items', coalesce((select jsonb_agg(to_jsonb(page_rows) order by case when status = 'active' then 0 else 1 end, admitted_at desc, id desc) from page_rows), '[]'::jsonb),
    'total', (select total from counted)
  ) into v_result;
  return v_result;
end;
$$;

create or replace function public.patient_hospitalization_page(
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
  if not private.has_permission(v_actor, 'hospitalizations.history')
     or not private.has_permission(v_actor, 'patients.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.patients where id = p_patient_id) then raise exception 'Paciente não localizado.'; end if;
  return jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(to_jsonb(item) order by item.admitted_at desc, item.id desc)
      from (
        select hospitalization.id, hospitalization.bed_id, bed.label as bed_label, hospitalization.source,
          hospitalization.reason, hospitalization.notes, hospitalization.admitted_at, hospitalization.status,
          hospitalization.discharged_at, hospitalization.cancelled_at, hospitalization.cancellation_reason,
          admitted.display_name as admitted_by_name,
          discharged.display_name as discharged_by_name
        from public.hospitalizations hospitalization
        join public.hospital_beds bed on bed.id = hospitalization.bed_id
        join public.profiles admitted on admitted.user_id = hospitalization.admitted_by
        left join public.profiles discharged on discharged.user_id = hospitalization.discharged_by
        where hospitalization.patient_id = p_patient_id
        order by hospitalization.admitted_at desc, hospitalization.id desc
        limit v_limit offset v_offset
      ) item
    ), '[]'::jsonb),
    'total', (select count(*)::integer from public.hospitalizations where patient_id = p_patient_id)
  );
end;
$$;

create or replace function public.create_hospitalization(
  p_bed_id bigint,
  p_source text,
  p_patient_id bigint,
  p_external_patient_name text,
  p_external_passport text,
  p_admitted_at timestamptz,
  p_reason text,
  p_notes text default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_record public.hospitalizations;
  v_name text := nullif(btrim(coalesce(p_external_patient_name, '')), '');
  v_passport text := nullif(upper(btrim(coalesce(p_external_passport, ''))), '');
  v_reason text := btrim(coalesce(p_reason, ''));
  v_notes text := nullif(btrim(coalesce(p_notes, '')), '');
begin
  if not private.has_permission(v_actor, 'hospitalizations.create') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if p_source not in ('hpsm', 'hp_norte') then raise exception 'Origem inválida.'; end if;
  if p_admitted_at is null then raise exception 'Informe a data e hora da internação.'; end if;
  if char_length(v_reason) not between 2 and 2000 then raise exception 'Informe o motivo da internação.'; end if;
  if v_notes is not null and char_length(v_notes) not between 2 and 2000 then raise exception 'A observação deve ter entre 2 e 2000 caracteres.'; end if;

  perform id from public.hospital_beds where id = p_bed_id and active for update;
  if not found then raise exception 'Leito não localizado.'; end if;
  if exists (select 1 from public.hospitalizations where bed_id = p_bed_id and status = 'active') then
    raise exception 'Este leito acabou de ser ocupado por outra internação.' using errcode = '23505', detail = 'HPSM_BED_OCCUPIED';
  end if;

  if p_source = 'hpsm' then
    if p_patient_id is null then raise exception 'Selecione um paciente HPSM.'; end if;
    perform id from public.patients where id = p_patient_id for update;
    if not found then raise exception 'Paciente HPSM não localizado.'; end if;
    if exists (select 1 from public.hospitalizations where patient_id = p_patient_id and status = 'active') then
      raise exception 'Este paciente HPSM já possui uma internação ativa.' using errcode = '23505', detail = 'HPSM_PATIENT_ALREADY_ADMITTED';
    end if;
    v_name := null; v_passport := null;
  else
    if p_patient_id is not null then raise exception 'Paciente externo do HP Norte não deve ser vinculado a um cadastro HPSM.'; end if;
    if v_name is null or char_length(v_name) not between 2 and 120 then raise exception 'Informe o nome do paciente externo.'; end if;
    if v_passport is not null and char_length(v_passport) not between 2 and 32 then raise exception 'Passaporte externo inválido.'; end if;
  end if;

  insert into public.hospitalizations (
    bed_id, source, patient_id, external_patient_name, external_passport, reason, notes, admitted_at, admitted_by
  ) values (
    p_bed_id, p_source, case when p_source = 'hpsm' then p_patient_id else null end,
    v_name, v_passport, v_reason, v_notes, p_admitted_at, v_actor
  ) returning * into v_record;

  perform private.audit_hospitalization_action(v_actor, 'HOSPITALIZATION_CREATED', v_record.id, null,
    jsonb_build_object('bed_id', v_record.bed_id, 'source', v_record.source, 'patient_id', v_record.patient_id,
      'external_patient_name', v_record.external_patient_name, 'external_passport', v_record.external_passport,
      'reason', v_record.reason, 'notes', v_record.notes, 'admitted_at', v_record.admitted_at, 'status', v_record.status));
  return v_record.id;
exception when unique_violation then
  if exists (select 1 from public.hospitalizations where bed_id = p_bed_id and status = 'active') then
    raise exception 'Este leito acabou de ser ocupado por outra internação.' using errcode = '23505', detail = 'HPSM_BED_OCCUPIED';
  end if;
  if p_patient_id is not null and exists (select 1 from public.hospitalizations where patient_id = p_patient_id and status = 'active') then
    raise exception 'Este paciente HPSM já possui uma internação ativa.' using errcode = '23505', detail = 'HPSM_PATIENT_ALREADY_ADMITTED';
  end if;
  raise;
end;
$$;

create or replace function public.update_hospitalization(
  p_hospitalization_id bigint,
  p_bed_id bigint,
  p_source text,
  p_patient_id bigint,
  p_external_patient_name text,
  p_external_passport text,
  p_admitted_at timestamptz,
  p_reason text,
  p_notes text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_old public.hospitalizations;
  v_new public.hospitalizations;
  v_name text := nullif(btrim(coalesce(p_external_patient_name, '')), '');
  v_passport text := nullif(upper(btrim(coalesce(p_external_passport, ''))), '');
  v_reason text := btrim(coalesce(p_reason, ''));
  v_notes text := nullif(btrim(coalesce(p_notes, '')), '');
begin
  if not private.has_permission(v_actor, 'hospitalizations.update') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  select * into v_old from public.hospitalizations where id = p_hospitalization_id for update;
  if v_old.id is null then raise exception 'Internação não localizada.'; end if;
  if v_old.status = 'cancelled' then raise exception 'Uma internação cancelada não pode ser corrigida.'; end if;
  if p_source not in ('hpsm', 'hp_norte') then raise exception 'Origem inválida.'; end if;
  if p_admitted_at is null then raise exception 'Informe a data e hora da internação.'; end if;
  if v_old.discharged_at is not null and p_admitted_at > v_old.discharged_at then raise exception 'A internação não pode ocorrer depois da alta.'; end if;
  if char_length(v_reason) not between 2 and 2000 then raise exception 'Informe o motivo da internação.'; end if;
  if v_notes is not null and char_length(v_notes) not between 2 and 2000 then raise exception 'A observação deve ter entre 2 e 2000 caracteres.'; end if;

  perform id from public.hospital_beds where id = p_bed_id and active for update;
  if not found then raise exception 'Leito não localizado.'; end if;
  if v_old.status = 'active' and exists (
    select 1 from public.hospitalizations where bed_id = p_bed_id and status = 'active' and id <> p_hospitalization_id
  ) then raise exception 'O leito selecionado já está ocupado.' using errcode = '23505', detail = 'HPSM_BED_OCCUPIED'; end if;

  if p_source = 'hpsm' then
    if p_patient_id is null then raise exception 'Selecione um paciente HPSM.'; end if;
    perform id from public.patients where id = p_patient_id for update;
    if not found then raise exception 'Paciente HPSM não localizado.'; end if;
    if v_old.status = 'active' and exists (
      select 1 from public.hospitalizations where patient_id = p_patient_id and status = 'active' and id <> p_hospitalization_id
    ) then raise exception 'Este paciente HPSM já possui uma internação ativa.' using errcode = '23505', detail = 'HPSM_PATIENT_ALREADY_ADMITTED'; end if;
    v_name := null; v_passport := null;
  else
    if v_name is null or char_length(v_name) not between 2 and 120 then raise exception 'Informe o nome do paciente externo.'; end if;
    if v_passport is not null and char_length(v_passport) not between 2 and 32 then raise exception 'Passaporte externo inválido.'; end if;
  end if;

  update public.hospitalizations set
    bed_id = p_bed_id,
    source = p_source,
    patient_id = case when p_source = 'hpsm' then p_patient_id else null end,
    external_patient_name = case when p_source = 'hp_norte' then v_name else null end,
    external_passport = case when p_source = 'hp_norte' then v_passport else null end,
    admitted_at = p_admitted_at,
    reason = v_reason,
    notes = v_notes
  where id = p_hospitalization_id
  returning * into v_new;

  perform private.audit_hospitalization_action(v_actor, 'HOSPITALIZATION_UPDATED', v_new.id,
    jsonb_build_object('bed_id', v_old.bed_id, 'source', v_old.source, 'patient_id', v_old.patient_id,
      'external_patient_name', v_old.external_patient_name, 'external_passport', v_old.external_passport,
      'reason', v_old.reason, 'notes', v_old.notes, 'admitted_at', v_old.admitted_at),
    jsonb_build_object('bed_id', v_new.bed_id, 'source', v_new.source, 'patient_id', v_new.patient_id,
      'external_patient_name', v_new.external_patient_name, 'external_passport', v_new.external_passport,
      'reason', v_new.reason, 'notes', v_new.notes, 'admitted_at', v_new.admitted_at));
exception when unique_violation then
  raise exception 'O leito ou paciente selecionado já possui uma internação ativa.' using errcode = '23505', detail = 'HPSM_HOSPITALIZATION_CONFLICT';
end;
$$;

create or replace function public.discharge_hospitalization(p_hospitalization_id bigint, p_discharged_at timestamptz)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_old public.hospitalizations;
  v_new public.hospitalizations;
begin
  if not private.has_permission(v_actor, 'hospitalizations.discharge') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  select * into v_old from public.hospitalizations where id = p_hospitalization_id for update;
  if v_old.id is null then raise exception 'Internação não localizada.'; end if;
  if v_old.status <> 'active' then raise exception 'Somente uma internação ativa pode receber alta.'; end if;
  if p_discharged_at is null then raise exception 'Informe a data e hora da alta.'; end if;
  if p_discharged_at < v_old.admitted_at then raise exception 'A alta não pode ocorrer antes da internação.'; end if;
  update public.hospitalizations set status = 'discharged', discharged_at = p_discharged_at, discharged_by = v_actor
  where id = p_hospitalization_id returning * into v_new;
  perform private.audit_hospitalization_action(v_actor, 'HOSPITALIZATION_DISCHARGED', v_new.id,
    jsonb_build_object('status', v_old.status),
    jsonb_build_object('status', v_new.status, 'discharged_at', v_new.discharged_at, 'discharged_by', v_new.discharged_by));
end;
$$;

create or replace function public.cancel_hospitalization(p_hospitalization_id bigint, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_old public.hospitalizations;
  v_new public.hospitalizations;
  v_reason text := btrim(coalesce(p_reason, ''));
begin
  if not private.has_permission(v_actor, 'hospitalizations.update') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if char_length(v_reason) not between 2 and 500 then raise exception 'Informe o motivo do cancelamento.'; end if;
  select * into v_old from public.hospitalizations where id = p_hospitalization_id for update;
  if v_old.id is null then raise exception 'Internação não localizada.'; end if;
  if v_old.status <> 'active' then raise exception 'Somente uma internação ativa pode ser cancelada.'; end if;
  update public.hospitalizations set
    status = 'cancelled', cancelled_at = now(), cancelled_by = v_actor, cancellation_reason = v_reason
  where id = p_hospitalization_id returning * into v_new;
  perform private.audit_hospitalization_action(v_actor, 'HOSPITALIZATION_CANCELLED', v_new.id,
    jsonb_build_object('status', v_old.status),
    jsonb_build_object('status', v_new.status, 'cancelled_at', v_new.cancelled_at,
      'cancelled_by', v_new.cancelled_by, 'reason', v_new.cancellation_reason));
end;
$$;

revoke all on function public.hospital_bed_board() from public, anon, authenticated, service_role;
revoke all on function public.hospitalization_history_page(text, text, bigint, text, date, date, integer, integer) from public, anon, authenticated, service_role;
revoke all on function public.patient_hospitalization_page(bigint, integer, integer) from public, anon, authenticated, service_role;
revoke all on function public.create_hospitalization(bigint, text, bigint, text, text, timestamptz, text, text) from public, anon, authenticated, service_role;
revoke all on function public.update_hospitalization(bigint, bigint, text, bigint, text, text, timestamptz, text, text) from public, anon, authenticated, service_role;
revoke all on function public.discharge_hospitalization(bigint, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.cancel_hospitalization(bigint, text) from public, anon, authenticated, service_role;

grant execute on function public.hospital_bed_board() to authenticated;
grant execute on function public.hospitalization_history_page(text, text, bigint, text, date, date, integer, integer) to authenticated;
grant execute on function public.patient_hospitalization_page(bigint, integer, integer) to authenticated;
grant execute on function public.create_hospitalization(bigint, text, bigint, text, text, timestamptz, text, text) to authenticated;
grant execute on function public.update_hospitalization(bigint, bigint, text, bigint, text, text, timestamptz, text, text) to authenticated;
grant execute on function public.discharge_hospitalization(bigint, timestamptz) to authenticated;
grant execute on function public.cancel_hospitalization(bigint, text) to authenticated;

comment on table public.hospital_beds is 'Dez leitos canônicos compartilhados pelo HPSM e pelo HP Norte; a ocupação é derivada de internações ativas.';
comment on table public.hospitalizations is 'Histórico preservado de internações, altas, correções e cancelamentos dos leitos HPSM.';
