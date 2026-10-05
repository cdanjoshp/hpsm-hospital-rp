-- HP Sul — Fase 2.2: catálogo fixo, planos e descontos automáticos.

alter table public.service_catalog
  add column code text,
  add column icon text;

insert into public.service_catalog (code, icon, name, category, unit_price, active, sort_order)
values
  ('kitmed', '🧰', 'KITMED', 'Insumos', 1400.00, true, 1),
  ('bandagem', '🩹', 'BANDAGEM', 'Insumos', 300.00, true, 2),
  ('atadura', '🧻', 'ATADURA', 'Insumos', 200.00, true, 3),
  ('analgesico', '💊', 'ANALGÉSICO', 'Medicamentos', 250.00, true, 4),
  ('adrenalina', '💉', 'ADRENALINA', 'Medicamentos', 8100.00, true, 5),
  ('sinkalmy', '🧴', 'SINKALMY', 'Medicamentos', 500.00, true, 6),
  ('ritmoneury', '🧪', 'RITMONEURY', 'Medicamentos', 500.00, true, 7),
  ('tratamento', '💉', 'TRATAMENTO', 'Atendimentos', 1500.00, true, 8),
  ('medicamentos_especificos', '💊', 'MEDICAMENTOS ESPECÍFICOS', 'Medicamentos', 100.00, true, 9),
  ('calcifort', '🧴', 'CALCIFORT', 'Medicamentos', 200.00, true, 10),
  ('exames_raio_x', '🩻', 'EXAMES / RAIO-X', 'Exames', 2500.00, true, 11),
  ('gesso', '🦾', 'GESSO', 'Atendimentos', 2500.00, true, 12),
  ('queimadura', '🩺', 'QUEIMADURA', 'Atendimentos', 2500.00, true, 13),
  ('pelucias_bonecos', '🧸', 'PELÚCIAS/BONECOS', 'Produtos', 5000.00, true, 14),
  ('consultas', '🩺', 'CONSULTAS', 'Atendimentos', 18000.00, true, 15),
  ('desloc_norte', '🚑', 'DESLOC. NORTE', 'Deslocamento', 450.00, true, 16),
  ('desloc_sul', '🚑', 'DESLOC. SUL', 'Deslocamento', 900.00, true, 17),
  ('cirurgias', '🏥', 'CIRURGIAS', 'Atendimentos', 170000.00, true, 18),
  ('fert_in_vitro', '🧫', 'FERT. IN VITRO', 'Atendimentos', 50000.00, true, 19),
  ('resson_tomo', '🔬', 'RESSON. TOMO.', 'Exames', 4500.00, true, 20),
  ('internacao', '🛏️', 'INTERNAÇÃO', 'Atendimentos', 14400.00, true, 21),
  ('plano_saude_convenio', '🤝', 'PLANO DE SAÚDE / CONVÊNIO', 'Convênios', 50000.00, true, 22);

alter table public.service_catalog
  alter column code set not null,
  alter column icon set not null,
  add constraint service_catalog_code_check check (code ~ '^[a-z0-9_]{2,48}$'),
  add constraint service_catalog_icon_check check (char_length(icon) between 1 and 12),
  add constraint service_catalog_code_unique unique (code);

create table public.benefit_plans (
  code text primary key
    constraint benefit_plans_code_check
    check (code ~ '^[a-z0-9_]{2,48}$'),
  name text not null unique
    constraint benefit_plans_name_check
    check (char_length(btrim(name)) between 2 and 80),
  sort_order smallint not null unique
    constraint benefit_plans_sort_order_check
    check (sort_order between 1 and 100)
);

insert into public.benefit_plans (code, name, sort_order)
values
  ('plano_saude', 'Plano de Saúde', 1),
  ('parceiros_hp', 'Parceiros do HP', 2),
  ('policiais_arcanjos', 'Policiais/Arcanjos', 3);

create table public.plan_discounts (
  plan_code text not null references public.benefit_plans(code) on update restrict on delete restrict,
  service_id bigint not null references public.service_catalog(id) on update restrict on delete restrict,
  discount_percent numeric(5, 2) not null default 0
    constraint plan_discounts_percent_check
    check (discount_percent between 0 and 100),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key (plan_code, service_id)
);

create index plan_discounts_service_id_idx on public.plan_discounts (service_id);
create index plan_discounts_updated_by_idx on public.plan_discounts (updated_by) where updated_by is not null;

insert into public.plan_discounts (plan_code, service_id)
select plan.code, service.id
from public.benefit_plans as plan
cross join public.service_catalog as service;

alter table public.patients
  add column plan_code text references public.benefit_plans(code) on update restrict on delete restrict;

create index patients_plan_code_idx on public.patients (plan_code) where plan_code is not null;

alter table public.attendances
  add column plan_code text,
  add column plan_name text;

alter table public.attendances
  add constraint attendances_plan_snapshot_check check (
    (plan_code is null and plan_name is null)
    or
    (plan_code is not null and char_length(btrim(plan_name)) between 2 and 80)
  );

alter table public.attendance_items drop column line_total;
alter table public.attendance_items
  add column discount_percent numeric(5, 2) not null default 0
    constraint attendance_items_discount_percent_check
    check (discount_percent between 0 and 100),
  add column discount_amount numeric(18, 2)
    generated always as (round(unit_price * quantity * discount_percent / 100, 2)) stored,
  add column line_total numeric(18, 2)
    generated always as (unit_price * quantity - round(unit_price * quantity * discount_percent / 100, 2)) stored;

create or replace function private.guard_patient_plan_changes()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.plan_code is not null and not (select private.is_director()) then
      raise exception 'Somente a Diretoria pode vincular planos aos pacientes.';
    end if;
  elsif new.plan_code is distinct from old.plan_code
        and not (select private.is_director()) then
    raise exception 'Somente a Diretoria pode alterar o plano do paciente.';
  end if;
  return new;
end;
$$;

revoke all on function private.guard_patient_plan_changes() from public, anon, authenticated, service_role;

create trigger patients_guard_plan_changes
before insert or update on public.patients
for each row execute function private.guard_patient_plan_changes();

create trigger plan_discounts_touch_updated_at
before update on public.plan_discounts
for each row execute function private.touch_updated_at();

create trigger plan_discounts_audit
after update on public.plan_discounts
for each row execute function private.audit_row_change();

alter table public.benefit_plans enable row level security;
alter table public.benefit_plans force row level security;
alter table public.plan_discounts enable row level security;
alter table public.plan_discounts force row level security;

create policy benefit_plans_read_active
on public.benefit_plans for select
to authenticated
using ((select private.is_active_user()));

create policy plan_discounts_read_active
on public.plan_discounts for select
to authenticated
using ((select private.is_active_user()));

drop policy if exists service_catalog_insert_director on public.service_catalog;

create or replace function public.update_catalog_pricing(
  p_service_id bigint,
  p_unit_price numeric,
  p_discounts jsonb
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (select private.is_director()) then
    raise exception 'Somente a Diretoria pode alterar preços e descontos.';
  end if;

  if p_service_id is null or round(coalesce(p_unit_price, -1), 2) < 0 then
    raise exception 'Valor inválido.';
  end if;

  if p_discounts is null or jsonb_typeof(p_discounts) <> 'array' then
    raise exception 'Informe os descontos dos três planos.';
  end if;

  select count(*)
  into v_count
  from jsonb_to_recordset(p_discounts) as item(plan_code text, discount_percent numeric)
  join public.benefit_plans as plan on plan.code = item.plan_code
  where item.discount_percent between 0 and 100;

  if v_count <> 3
     or jsonb_array_length(p_discounts) <> 3
     or exists (
       select 1
       from jsonb_to_recordset(p_discounts) as item(plan_code text, discount_percent numeric)
       group by item.plan_code
       having count(*) <> 1
     ) then
    raise exception 'Os descontos dos três planos devem ser válidos e únicos.';
  end if;

  update public.service_catalog
  set unit_price = round(p_unit_price, 2),
      updated_by = (select auth.uid())
  where id = p_service_id;

  if not found then
    raise exception 'Item não localizado.';
  end if;

  update public.plan_discounts as discount
  set discount_percent = round(input.discount_percent, 2),
      updated_by = (select auth.uid())
  from jsonb_to_recordset(p_discounts) as input(plan_code text, discount_percent numeric)
  where discount.service_id = p_service_id
    and discount.plan_code = input.plan_code;

  return true;
end;
$$;

revoke all on function public.update_catalog_pricing(bigint, numeric, jsonb) from public, anon, authenticated, service_role;
grant execute on function public.update_catalog_pricing(bigint, numeric, jsonb) to authenticated;

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
     or new.plan_code is distinct from old.plan_code
     or new.plan_name is distinct from old.plan_name
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

drop function public.create_attendance(bigint, jsonb, numeric, text);

create function public.create_attendance(
  p_patient_id bigint,
  p_items jsonb,
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
  v_plan_code text;
  v_plan_name text;
  v_subtotal numeric(18, 2);
  v_valid_count integer;
begin
  if not (select private.is_active_user()) then
    raise exception 'Usuário sem acesso ativo.';
  end if;

  select patient.name, patient.passport, plan.code, plan.name
  into v_patient_name, v_patient_passport, v_plan_code, v_plan_name
  from public.patients as patient
  left join public.benefit_plans as plan on plan.code = patient.plan_code
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

  if exists (
    select 1
    from jsonb_to_recordset(p_items) as item(service_id bigint, quantity integer)
    group by service_id
    having count(*) <> 1
  ) then
    raise exception 'Cada item deve aparecer apenas uma vez.';
  end if;

  with input_items as (
    select service_id, quantity
    from jsonb_to_recordset(p_items) as item(service_id bigint, quantity integer)
  )
  select
    count(*),
    coalesce(sum(catalog.unit_price * input_items.quantity), 0),
    coalesce(sum(round(catalog.unit_price * input_items.quantity * coalesce(discount.discount_percent, 0) / 100, 2)), 0)
  into v_valid_count, v_subtotal, v_discount
  from input_items
  join public.service_catalog as catalog
    on catalog.id = input_items.service_id
   and catalog.active = true
  left join public.plan_discounts as discount
    on discount.service_id = catalog.id
   and discount.plan_code = v_plan_code
  where input_items.quantity between 1 and 99;

  if v_valid_count <> v_input_count then
    raise exception 'Um dos itens não está disponível.';
  end if;

  insert into public.attendances (
    patient_id,
    patient_name,
    patient_passport,
    plan_code,
    plan_name,
    subtotal,
    discount,
    notes,
    performed_by
  ) values (
    p_patient_id,
    v_patient_name,
    v_patient_passport,
    v_plan_code,
    v_plan_name,
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
    quantity,
    discount_percent
  )
  select
    v_attendance_id,
    catalog.id,
    catalog.name,
    catalog.unit_price,
    input_items.quantity::smallint,
    coalesce(discount.discount_percent, 0)
  from jsonb_to_recordset(p_items) as input_items(service_id bigint, quantity integer)
  join public.service_catalog as catalog
    on catalog.id = input_items.service_id
   and catalog.active = true
  left join public.plan_discounts as discount
    on discount.service_id = catalog.id
   and discount.plan_code = v_plan_code;

  return v_attendance_id;
end;
$$;

revoke all on public.benefit_plans from public, anon, authenticated, service_role;
revoke all on public.plan_discounts from public, anon, authenticated, service_role;
revoke all on public.service_catalog from authenticated;
revoke all on sequence public.service_catalog_id_seq from authenticated;
revoke all on function public.create_attendance(bigint, jsonb, text) from public, anon, authenticated, service_role;

grant select on public.benefit_plans to authenticated;
grant select on public.plan_discounts to authenticated;
grant select on public.service_catalog to authenticated;
grant execute on function public.create_attendance(bigint, jsonb, text) to authenticated;

grant select on public.benefit_plans to service_role;
grant select, insert, update, delete on public.plan_discounts to service_role;
grant select, insert, update, delete on public.service_catalog to service_role;
grant usage, select on sequence public.service_catalog_id_seq to service_role;

comment on table public.service_catalog is
  'Catálogo fixo de 22 produtos e procedimentos; somente preços podem ser ajustados pela Diretoria.';
comment on table public.benefit_plans is
  'Três planos fixos disponíveis para vínculo ao cadastro do paciente.';
comment on table public.plan_discounts is
  'Percentual de desconto definido pela Diretoria para cada combinação de plano e item.';
comment on column public.patients.plan_code is
  'Plano ativo atual do paciente. Nulo indica que o paciente não possui plano ativo.';
comment on column public.attendances.plan_name is
  'Nome do plano preservado no momento do atendimento.';
comment on column public.attendance_items.discount_percent is
  'Percentual automático do plano preservado no momento do atendimento.';

notify pgrst, 'reload schema';
