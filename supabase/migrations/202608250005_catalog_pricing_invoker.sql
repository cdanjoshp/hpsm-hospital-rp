-- Mantém a RPC de preços sob RLS e elimina privilégios elevados desnecessários.

alter function public.update_catalog_pricing(bigint, numeric, jsonb) security invoker;

create policy plan_discounts_update_director
on public.plan_discounts for update
to authenticated
using ((select private.is_director()))
with check (
  (select private.is_director())
  and updated_by = (select auth.uid())
);

grant update (unit_price, updated_by) on public.service_catalog to authenticated;
grant update (discount_percent, updated_by) on public.plan_discounts to authenticated;

notify pgrst, 'reload schema';
