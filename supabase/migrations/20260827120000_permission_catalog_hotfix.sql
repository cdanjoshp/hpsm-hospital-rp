-- HPSM · correção pontual das três camadas de autorização operacional.
-- Preserva a matriz de cargos e passa a usá-la nas políticas já existentes.

-- As políticas RLS de atendimentos consultam private.has_permission. A função
-- permanece fora da Data API, mas precisa ser executável pelo papel autenticado
-- durante a avaliação interna das políticas.
grant execute on function private.has_permission(uuid, text) to authenticated;

drop policy if exists service_catalog_read_active_or_director on public.service_catalog;
create policy service_catalog_read_authorized
on public.service_catalog for select
to authenticated
using (
  (active and private.has_permission((select auth.uid()), 'catalog.view'))
  or private.has_permission((select auth.uid()), 'catalog.manage')
);

drop policy if exists service_catalog_update_director on public.service_catalog;
create policy service_catalog_update_authorized
on public.service_catalog for update
to authenticated
using (private.has_permission((select auth.uid()), 'catalog.manage'))
with check (
  private.has_permission((select auth.uid()), 'catalog.manage')
  and updated_by = (select auth.uid())
);

drop policy if exists benefit_plans_read_active on public.benefit_plans;
create policy benefit_plans_read_authorized
on public.benefit_plans for select
to authenticated
using (
  private.has_permission((select auth.uid()), 'catalog.view')
  or private.has_permission((select auth.uid()), 'catalog.manage')
);

drop policy if exists plan_discounts_read_active on public.plan_discounts;
create policy plan_discounts_read_authorized
on public.plan_discounts for select
to authenticated
using (
  private.has_permission((select auth.uid()), 'catalog.view')
  or private.has_permission((select auth.uid()), 'catalog.manage')
);

drop policy if exists plan_discounts_update_director on public.plan_discounts;
create policy plan_discounts_update_authorized
on public.plan_discounts for update
to authenticated
using (private.has_permission((select auth.uid()), 'catalog.manage'))
with check (
  private.has_permission((select auth.uid()), 'catalog.manage')
  and updated_by = (select auth.uid())
);

drop policy if exists attendances_insert_own on public.attendances;
create policy attendances_insert_own_authorized
on public.attendances for insert
to authenticated
with check (
  private.has_permission((select auth.uid()), 'attendances.create')
  and performed_by = (select auth.uid())
  and status = 'completed'
  and cancelled_by is null
  and cancelled_at is null
);

drop policy if exists attendance_items_insert_own_attendance on public.attendance_items;
create policy attendance_items_insert_own_authorized
on public.attendance_items for insert
to authenticated
with check (
  private.has_permission((select auth.uid()), 'attendances.create')
  and exists (
    select 1
    from public.attendances
    where attendances.id = attendance_items.attendance_id
      and attendances.performed_by = (select auth.uid())
      and attendances.status = 'completed'
  )
);

notify pgrst, 'reload schema';
