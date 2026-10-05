-- HP Sul — Fase 2.1: cadastro único de pacientes por passaporte.
-- Pacientes são registros administrativos e não recebem acesso ao sistema.

create table public.patients (
  id bigint generated always as identity primary key,
  passport text not null
    constraint patients_passport_check
    check (
      passport ~ '^[A-Z0-9.-]{2,32}$'
      and passport = upper(passport)
    ),
  name text not null
    constraint patients_name_check
    check (char_length(btrim(name)) between 2 and 100),
  phone text
    constraint patients_phone_check
    check (
      phone is null
      or char_length(btrim(phone)) between 3 and 24
    ),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index patients_passport_unique_idx
  on public.patients (passport);
create index patients_created_by_idx
  on public.patients (created_by)
  where created_by is not null;
create index patients_updated_by_idx
  on public.patients (updated_by)
  where updated_by is not null;

insert into public.patients (
  passport,
  name,
  created_by,
  updated_by,
  created_at,
  updated_at
)
select distinct on (upper(patient_passport))
  upper(patient_passport),
  btrim(patient_name),
  performed_by,
  performed_by,
  created_at,
  created_at
from public.attendances
order by upper(patient_passport), created_at desc;

alter table public.attendances
  add column patient_id bigint;

update public.attendances as attendance
set patient_id = patient.id
from public.patients as patient
where patient.passport = upper(attendance.patient_passport);

alter table public.attendances
  alter column patient_id set not null;

alter table public.attendances
  add constraint attendances_patient_id_fkey
  foreign key (patient_id)
  references public.patients(id)
  on delete restrict;

create index attendances_patient_created_idx
  on public.attendances (patient_id, created_at desc);

create or replace function private.guard_attendance_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status <> 'completed' then
    raise exception 'Um atendimento cancelado não pode ser alterado.';
  end if;

  if new.patient_id is distinct from old.patient_id
     or new.patient_name is distinct from old.patient_name
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

create trigger patients_touch_updated_at
before update on public.patients
for each row execute function private.touch_updated_at();

create trigger patients_audit
after insert or update or delete on public.patients
for each row execute function private.audit_row_change();

alter table public.patients enable row level security;
alter table public.patients force row level security;

create policy patients_read_active
on public.patients for select
to authenticated
using ((select private.is_active_user()));

create policy patients_insert_active
on public.patients for insert
to authenticated
with check (
  (select private.is_active_user())
  and created_by = (select auth.uid())
  and updated_by = (select auth.uid())
);

create policy patients_update_director
on public.patients for update
to authenticated
using ((select private.is_director()))
with check (
  (select private.is_director())
  and updated_by = (select auth.uid())
);

drop function public.create_attendance(text, text, jsonb, numeric, text);

create function public.create_attendance(
  p_patient_id bigint,
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
  v_patient_name text;
  v_patient_passport text;
  v_subtotal numeric(18, 2);
  v_valid_count integer;
begin
  if not (select private.is_active_user()) then
    raise exception 'Usuário sem acesso ativo.';
  end if;

  select patient.name, patient.passport
  into v_patient_name, v_patient_passport
  from public.patients as patient
  where patient.id = p_patient_id;

  if not found then
    raise exception 'Paciente não localizado.';
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
    patient_id,
    patient_name,
    patient_passport,
    subtotal,
    discount,
    notes,
    performed_by
  ) values (
    p_patient_id,
    v_patient_name,
    v_patient_passport,
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

revoke all on public.patients from public, anon, authenticated, service_role;
revoke all on sequence public.patients_id_seq from public, anon, authenticated, service_role;
revoke all on function public.create_attendance(bigint, jsonb, numeric, text) from public, anon, authenticated, service_role;

grant select, insert, update on public.patients to authenticated;
grant usage, select on sequence public.patients_id_seq to authenticated;
grant execute on function public.create_attendance(bigint, jsonb, numeric, text) to authenticated;

grant select, insert, update on public.patients to service_role;
grant usage, select on sequence public.patients_id_seq to service_role;

comment on table public.patients is
  'Cadastro administrativo de pacientes, sem identidade de acesso ao sistema.';
comment on column public.attendances.patient_id is
  'Vínculo com o cadastro único do paciente; nome e passaporte permanecem como fotografia histórica.';

notify pgrst, 'reload schema';
