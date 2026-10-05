-- A função de sessão é privada; as RPCs invocadoras usam auth.uid() e
-- repetem a sessão/permissão por private.has_permission e pelas policies RLS.

create or replace function public.update_catalog_unit_price(
  p_service_id bigint,
  p_unit_price numeric
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_unit_price numeric(18, 2);
begin
  if v_actor is null or not private.has_permission(v_actor, 'catalog.manage') then
    raise exception using errcode = '42501', message = 'Você não possui permissão para alterar preços.';
  end if;

  if p_service_id is null or p_service_id < 1 then
    raise exception using errcode = '22023', message = 'Selecione um item válido.';
  end if;

  if p_unit_price is null
     or p_unit_price = 'NaN'::numeric
     or p_unit_price < 0
     or p_unit_price > 9999999999999999.99 then
    raise exception using errcode = '22023', message = 'Informe um preço válido entre R$ 0,00 e R$ 9.999.999.999.999.999,99.';
  end if;

  v_unit_price := round(p_unit_price, 2);

  update public.service_catalog
  set unit_price = v_unit_price,
      updated_by = v_actor
  where id = p_service_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Item não localizado.';
  end if;

  return jsonb_build_object(
    'service_id', p_service_id,
    'unit_price', v_unit_price
  );
end;
$$;

create or replace function public.update_catalog_discounts_bulk(
  p_discounts jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_valid_count integer;
  v_service_count integer;
  v_discount_count integer;
  v_updated_count integer;
  v_discounts jsonb;
begin
  if v_actor is null or not private.has_permission(v_actor, 'catalog.manage') then
    raise exception using errcode = '42501', message = 'Você não possui permissão para alterar os descontos.';
  end if;

  if p_discounts is null
     or jsonb_typeof(p_discounts) <> 'array'
     or jsonb_array_length(p_discounts) <> 3 then
    raise exception using errcode = '22023', message = 'Informe os três descontos: Plano de Saúde, Parceiros do HP e Policiais/Arcanjos.';
  end if;

  select count(*)
  into v_valid_count
  from jsonb_to_recordset(p_discounts) as item(plan_code text, discount_percent numeric)
  join public.benefit_plans plan on plan.code = item.plan_code
  where item.discount_percent is not null
    and item.discount_percent <> 'NaN'::numeric
    and item.discount_percent between 0 and 100;

  if v_valid_count <> 3
     or exists (
       select 1
       from jsonb_to_recordset(p_discounts) as item(plan_code text, discount_percent numeric)
       group by item.plan_code
       having count(*) <> 1
     ) then
    raise exception using errcode = '22023', message = 'Cada desconto deve aparecer uma vez e estar entre 0% e 100%.';
  end if;

  select count(*) into v_service_count
  from public.service_catalog;

  select count(*) into v_discount_count
  from public.plan_discounts;

  if v_discount_count <> v_service_count * 3 then
    raise exception using errcode = 'P0001', message = 'A configuração atual dos descontos está incompleta. Nenhuma alteração foi aplicada.';
  end if;

  with input as (
    select
      item.plan_code,
      round(item.discount_percent, 2) as discount_percent
    from jsonb_to_recordset(p_discounts) as item(plan_code text, discount_percent numeric)
  )
  update public.plan_discounts discount
  set discount_percent = input.discount_percent,
      updated_by = v_actor
  from input
  where discount.plan_code = input.plan_code
    and discount.discount_percent is distinct from input.discount_percent;

  get diagnostics v_updated_count = row_count;

  select jsonb_object_agg(item.plan_code, round(item.discount_percent, 2))
  into v_discounts
  from jsonb_to_recordset(p_discounts) as item(plan_code text, discount_percent numeric);

  return jsonb_build_object(
    'service_count', v_service_count,
    'updated_rows', v_updated_count,
    'discounts', v_discounts
  );
end;
$$;

revoke all on function public.update_catalog_unit_price(bigint, numeric)
from public, anon, authenticated, service_role;
grant execute on function public.update_catalog_unit_price(bigint, numeric)
to authenticated;

revoke all on function public.update_catalog_discounts_bulk(jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.update_catalog_discounts_bulk(jsonb)
to authenticated;

notify pgrst, 'reload schema';
