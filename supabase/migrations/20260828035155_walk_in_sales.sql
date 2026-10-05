alter table public.attendances
  alter column patient_id drop not null;

create or replace function public.create_attendance(
  p_patient_id bigint,
  p_items jsonb,
  p_notes text default null,
  p_benefit_code text default null
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
  if not private.has_permission((select auth.uid()), 'attendances.create') then
    raise exception 'Você não possui permissão para registrar atendimentos.';
  end if;

  if p_patient_id is null then
    v_patient_name := 'Venda avulsa';
    v_patient_passport := '—';
  else
    select patient.name, patient.passport
    into v_patient_name, v_patient_passport
    from public.patients as patient
    where patient.id = p_patient_id;

    if not found then
      raise exception 'Paciente não localizado.';
    end if;
  end if;

  v_plan_code := nullif(btrim(coalesce(p_benefit_code, '')), '');
  if v_plan_code is not null then
    select plan.name
    into v_plan_name
    from public.benefit_plans as plan
    where plan.code = v_plan_code;
    if not found then
      raise exception 'Benefício inválido ou indisponível.';
    end if;
  end if;

  if p_notes is not null and char_length(p_notes) > 1000 then
    raise exception 'Observação muito longa.';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'Inclua ao menos um item.';
  end if;

  v_input_count := jsonb_array_length(p_items);
  if v_input_count < 1 or v_input_count > 50 then
    raise exception 'Quantidade de itens inválida.';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_items) as item(service_id bigint, quantity integer)
    group by service_id
    having count(*) <> 1
  ) then
    raise exception 'Cada item deve aparecer apenas uma vez.';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_items) as item(service_id bigint, quantity integer)
    join public.service_catalog as catalog on catalog.id = item.service_id
    where catalog.code = 'plano_saude_convenio'
      and item.quantity <> 1
  ) then
    raise exception 'O plano de saúde pode aparecer somente uma vez no atendimento.';
  end if;

  if p_patient_id is null and exists (
    select 1
    from jsonb_to_recordset(p_items) as item(service_id bigint, quantity integer)
    join public.service_catalog as catalog on catalog.id = item.service_id
    where lower(btrim(catalog.category)) not in ('insumos', 'medicamentos')
  ) then
    raise exception 'Venda avulsa aceita somente insumos e medicamentos.';
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
    patient_id, patient_name, patient_passport, plan_code, plan_name,
    subtotal, discount, notes, performed_by
  ) values (
    p_patient_id, v_patient_name, v_patient_passport, v_plan_code, v_plan_name,
    v_subtotal, v_discount, nullif(btrim(coalesce(p_notes, '')), ''), (select auth.uid())
  )
  returning id into v_attendance_id;

  insert into public.attendance_items (
    attendance_id, service_id, service_name, unit_price, quantity, discount_percent
  )
  select
    v_attendance_id, catalog.id, catalog.name, catalog.unit_price,
    input_items.quantity::smallint, coalesce(discount.discount_percent, 0)
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

revoke all on function public.create_attendance(bigint, jsonb, text, text) from public, anon, authenticated, service_role;
grant execute on function public.create_attendance(bigint, jsonb, text, text) to authenticated;
grant execute on function public.create_attendance(bigint, jsonb, text, text) to service_role;

comment on column public.attendances.patient_id is
  'Paciente vinculado ao atendimento; nulo somente para venda avulsa restrita a insumos e medicamentos.';
