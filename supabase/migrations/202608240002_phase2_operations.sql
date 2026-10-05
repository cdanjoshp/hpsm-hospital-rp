-- HP Sul — Fase 2: atendimentos, calculadora e gestão avançada da equipe.
-- Os preços começam vazios e são administrados pela Diretoria.

create or replace function private.is_active_user()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and exists (
      select 1
      from public.profiles
      where user_id = (select auth.uid())
        and status = 'active'
    );
$$;

revoke all on function private.is_active_user() from public, anon, authenticated, service_role;
grant execute on function private.is_active_user() to authenticated;

create table public.service_catalog (
  id bigint generated always as identity primary key,
  name text not null
    constraint service_catalog_name_check
    check (char_length(btrim(name)) between 2 and 100),
  category text not null default 'Geral'
    constraint service_catalog_category_check
    check (char_length(btrim(category)) between 2 and 60),
  unit_price numeric(14, 2) not null
    constraint service_catalog_unit_price_check
    check (unit_price >= 0),
  active boolean not null default true,
  sort_order integer not null default 0
    constraint service_catalog_sort_order_check
    check (sort_order between -10000 and 10000),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index service_catalog_name_unique_idx
  on public.service_catalog (lower(btrim(name)));
create index service_catalog_active_sort_idx
  on public.service_catalog (category, sort_order, name)
  where active = true;
create index service_catalog_created_by_idx
  on public.service_catalog (created_by)
  where created_by is not null;
create index service_catalog_updated_by_idx
  on public.service_catalog (updated_by)
  where updated_by is not null;

create table public.attendances (
  id bigint generated always as identity primary key,
  patient_name text not null
    constraint attendances_patient_name_check
    check (char_length(btrim(patient_name)) between 2 and 100),
  patient_passport text not null
    constraint attendances_patient_passport_check
    check (patient_passport ~ '^[A-Za-z0-9.-]{2,32}$'),
  status text not null default 'completed'
    constraint attendances_status_check
    check (status in ('completed', 'cancelled')),
  subtotal numeric(18, 2) not null
    constraint attendances_subtotal_check
    check (subtotal >= 0),
  discount numeric(18, 2) not null default 0
    constraint attendances_discount_check
    check (discount >= 0 and discount <= subtotal),
  total numeric(18, 2) generated always as (subtotal - discount) stored,
  notes text
    constraint attendances_notes_check
    check (notes is null or char_length(notes) <= 1000),
  performed_by uuid not null references auth.users(id) on delete restrict,
  cancelled_by uuid references auth.users(id) on delete restrict,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint attendances_cancellation_state_check check (
    (status = 'completed' and cancelled_by is null and cancelled_at is null)
    or
    (status = 'cancelled' and cancelled_by is not null and cancelled_at is not null)
  )
);

create index attendances_created_at_idx
  on public.attendances (created_at desc);
create index attendances_performed_by_created_idx
  on public.attendances (performed_by, created_at desc);
create index attendances_status_created_idx
  on public.attendances (status, created_at desc);
create index attendances_cancelled_by_idx
  on public.attendances (cancelled_by)
  where cancelled_by is not null;

create table public.attendance_items (
  id bigint generated always as identity primary key,
  attendance_id bigint not null references public.attendances(id) on delete cascade,
  service_id bigint not null references public.service_catalog(id) on delete restrict,
  service_name text not null,
  unit_price numeric(14, 2) not null
    constraint attendance_items_unit_price_check
    check (unit_price >= 0),
  quantity smallint not null
    constraint attendance_items_quantity_check
    check (quantity between 1 and 99),
  line_total numeric(18, 2) generated always as (unit_price * quantity) stored,
  created_at timestamptz not null default now(),
  constraint attendance_items_service_name_check
    check (char_length(btrim(service_name)) between 2 and 100),
  constraint attendance_items_attendance_service_unique
    unique (attendance_id, service_id)
);

create index attendance_items_attendance_id_idx
  on public.attendance_items (attendance_id);
create index attendance_items_service_id_idx
  on public.attendance_items (service_id);

create or replace function private.guard_director_general()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.role_code = 'diretor_geral'
     and (new.role_code <> 'diretor_geral' or new.status <> 'active') then
    raise exception 'A conta do Diretor Geral não pode ser rebaixada ou bloqueada.';
  end if;
  return new;
end;
$$;

revoke all on function private.guard_director_general() from public, anon, authenticated, service_role;

drop trigger if exists profiles_guard_director_general on public.profiles;
create trigger profiles_guard_director_general
before update on public.profiles
for each row execute function private.guard_director_general();

create or replace function private.guard_attendance_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status <> 'completed' then
    raise exception 'Um atendimento cancelado não pode ser alterado.';
  end if;

  if new.patient_name is distinct from old.patient_name
     or new.patient_passport is distinct from old.patient_passport
     or new.subtotal is distinct from old.subtotal
     or new.discount is distinct from old.discount
     or new.notes is distinct from old.notes
     or new.performed_by is distinct from old.performed_by
     or new.created_at is distinct from old.created_at then
    raise exception 'Os dados financeiros do atendimento são imutáveis.';
  end if;

  return new;
end;
$$;

revoke all on function private.guard_attendance_update() from public, anon, authenticated, service_role;

create trigger attendances_guard_update
before update on public.attendances
for each row execute function private.guard_attendance_update();

create or replace function private.audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid;
  actor_code text;
  row_id text;
  row_values jsonb;
begin
  actor_id := auth.uid();
  row_values := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;

  if actor_id is null then
    actor_id := coalesce(
      nullif(row_values ->> 'updated_by', '')::uuid,
      nullif(row_values ->> 'cancelled_by', '')::uuid,
      nullif(row_values ->> 'created_by', '')::uuid,
      nullif(row_values ->> 'performed_by', '')::uuid,
      nullif(row_values ->> 'password_reset_by', '')::uuid
    );
  end if;

  select passport into actor_code
  from public.profiles
  where user_id = actor_id;

  row_id := coalesce(row_values ->> 'id', row_values ->> 'key');

  insert into public.audit_logs (
    actor_user_id,
    actor_passport,
    action,
    entity_name,
    entity_id,
    old_values,
    new_values
  ) values (
    actor_id,
    actor_code,
    tg_op,
    tg_table_name,
    row_id,
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) else null end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) else null end
  );

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function private.audit_row_change() from public, anon, authenticated, service_role;

create trigger service_catalog_touch_updated_at
before update on public.service_catalog
for each row execute function private.touch_updated_at();

create trigger attendances_touch_updated_at
before update on public.attendances
for each row execute function private.touch_updated_at();

create trigger service_catalog_audit
after insert or update or delete on public.service_catalog
for each row execute function private.audit_row_change();

create trigger attendances_audit
after insert or update or delete on public.attendances
for each row execute function private.audit_row_change();

create trigger attendance_items_audit
after insert or update or delete on public.attendance_items
for each row execute function private.audit_row_change();

alter table public.service_catalog enable row level security;
alter table public.service_catalog force row level security;
alter table public.attendances enable row level security;
alter table public.attendances force row level security;
alter table public.attendance_items enable row level security;
alter table public.attendance_items force row level security;

create policy service_catalog_read_active_or_director
on public.service_catalog for select
to authenticated
using (
  (select private.is_active_user())
  and (active or (select private.is_director()))
);

create policy service_catalog_insert_director
on public.service_catalog for insert
to authenticated
with check (
  (select private.is_director())
  and created_by = (select auth.uid())
  and updated_by = (select auth.uid())
);

create policy service_catalog_update_director
on public.service_catalog for update
to authenticated
using ((select private.is_director()))
with check (
  (select private.is_director())
  and updated_by = (select auth.uid())
);

create policy attendances_read_own_or_director
on public.attendances for select
to authenticated
using (
  (select private.is_active_user())
  and (
    performed_by = (select auth.uid())
    or (select private.is_director())
  )
);

create policy attendances_insert_own
on public.attendances for insert
to authenticated
with check (
  (select private.is_active_user())
  and performed_by = (select auth.uid())
  and status = 'completed'
  and cancelled_by is null
  and cancelled_at is null
);

create policy attendances_cancel_director
on public.attendances for update
to authenticated
using ((select private.is_director()))
with check (
  (select private.is_director())
  and status = 'cancelled'
  and cancelled_by = (select auth.uid())
  and cancelled_at is not null
);

create policy attendance_items_read_visible_attendance
on public.attendance_items for select
to authenticated
using (
  (select private.is_active_user())
  and exists (
    select 1
    from public.attendances
    where attendances.id = attendance_items.attendance_id
      and (
        attendances.performed_by = (select auth.uid())
        or (select private.is_director())
      )
  )
);

create policy attendance_items_insert_own_attendance
on public.attendance_items for insert
to authenticated
with check (
  (select private.is_active_user())
  and exists (
    select 1
    from public.attendances
    where attendances.id = attendance_items.attendance_id
      and attendances.performed_by = (select auth.uid())
      and attendances.status = 'completed'
  )
);

create or replace function public.create_attendance(
  p_patient_name text,
  p_patient_passport text,
  p_items jsonb,
  p_discount numeric default 0,
  p_notes text default null
)
returns bigint
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_attendance_id bigint;
  v_discount numeric(18, 2);
  v_input_count integer;
  v_valid_count integer;
  v_subtotal numeric(18, 2);
begin
  if not (select private.is_active_user()) then
    raise exception 'Usuário sem acesso ativo.';
  end if;

  if char_length(btrim(coalesce(p_patient_name, ''))) not between 2 and 100 then
    raise exception 'Nome do paciente inválido.';
  end if;

  if coalesce(p_patient_passport, '') !~ '^[A-Za-z0-9.-]{2,32}$' then
    raise exception 'Passaporte do paciente inválido.';
  end if;

  if p_notes is not null and char_length(p_notes) > 1000 then
    raise exception 'Observação muito longa.';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'Inclua ao menos um procedimento.';
  end if;

  v_input_count := jsonb_array_length(p_items);
  if v_input_count < 1 or v_input_count > 50 then
    raise exception 'Quantidade de procedimentos inválida.';
  end if;

  with input_items as (
    select service_id, quantity
    from jsonb_to_recordset(p_items) as item(service_id bigint, quantity integer)
  )
  select count(*), coalesce(sum(catalog.unit_price * input_items.quantity), 0)
  into v_valid_count, v_subtotal
  from input_items
  join public.service_catalog as catalog
    on catalog.id = input_items.service_id
   and catalog.active = true
  where input_items.quantity between 1 and 99;

  if v_valid_count <> v_input_count then
    raise exception 'Um dos procedimentos não está disponível.';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_items) as item(service_id bigint, quantity integer)
    group by service_id
    having sum(quantity) > 99
  ) then
    raise exception 'Quantidade total de um procedimento acima do permitido.';
  end if;

  v_discount := round(coalesce(p_discount, 0), 2);
  if v_discount < 0 or v_discount > v_subtotal then
    raise exception 'Desconto inválido.';
  end if;

  insert into public.attendances (
    patient_name,
    patient_passport,
    subtotal,
    discount,
    notes,
    performed_by
  ) values (
    btrim(p_patient_name),
    p_patient_passport,
    v_subtotal,
    v_discount,
    nullif(btrim(coalesce(p_notes, '')), ''),
    (select auth.uid())
  )
  returning id into v_attendance_id;

  insert into public.attendance_items (
    attendance_id,
    service_id,
    service_name,
    unit_price,
    quantity
  )
  select
    v_attendance_id,
    catalog.id,
    catalog.name,
    catalog.unit_price,
    sum(input_items.quantity)::smallint
  from jsonb_to_recordset(p_items) as input_items(service_id bigint, quantity integer)
  join public.service_catalog as catalog
    on catalog.id = input_items.service_id
   and catalog.active = true
  group by catalog.id, catalog.name, catalog.unit_price;

  return v_attendance_id;
end;
$$;

create or replace function public.cancel_attendance(p_attendance_id bigint)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not (select private.is_director()) then
    raise exception 'Somente a Diretoria pode cancelar atendimentos.';
  end if;

  update public.attendances
  set status = 'cancelled',
      cancelled_by = (select auth.uid()),
      cancelled_at = now()
  where id = p_attendance_id
    and status = 'completed';

  return found;
end;
$$;

revoke all on public.service_catalog from public, anon, authenticated, service_role;
revoke all on public.attendances from public, anon, authenticated, service_role;
revoke all on public.attendance_items from public, anon, authenticated, service_role;
revoke all on sequence public.service_catalog_id_seq from public, anon, authenticated, service_role;
revoke all on sequence public.attendances_id_seq from public, anon, authenticated, service_role;
revoke all on sequence public.attendance_items_id_seq from public, anon, authenticated, service_role;
revoke all on function public.create_attendance(text, text, jsonb, numeric, text) from public, anon, authenticated, service_role;
revoke all on function public.cancel_attendance(bigint) from public, anon, authenticated, service_role;

grant select, insert, update on public.service_catalog to authenticated;
grant select, insert, update on public.attendances to authenticated;
grant select, insert on public.attendance_items to authenticated;
grant usage, select on sequence public.service_catalog_id_seq to authenticated;
grant usage, select on sequence public.attendances_id_seq to authenticated;
grant usage, select on sequence public.attendance_items_id_seq to authenticated;
grant execute on function public.create_attendance(text, text, jsonb, numeric, text) to authenticated;
grant execute on function public.cancel_attendance(bigint) to authenticated;

grant select, insert, update on public.service_catalog to service_role;
grant select, insert, update on public.attendances to service_role;
grant select, insert on public.attendance_items to service_role;
grant usage, select on sequence public.service_catalog_id_seq to service_role;
grant usage, select on sequence public.attendances_id_seq to service_role;
grant usage, select on sequence public.attendance_items_id_seq to service_role;

comment on table public.service_catalog is
  'Catálogo de procedimentos e valores administrado pela Diretoria.';
comment on table public.attendances is
  'Atendimentos financeiros do hospital; não contém prontuário clínico.';
comment on table public.attendance_items is
  'Itens imutáveis do atendimento, com nome e valor preservados no momento do registro.';
