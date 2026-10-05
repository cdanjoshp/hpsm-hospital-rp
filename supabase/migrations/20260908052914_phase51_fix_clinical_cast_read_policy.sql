-- HPSM · Fase 5.1 · correção da policy de leitura direta
-- A policy usa auth.uid como as demais tabelas; as RPCs continuam exigindo hpsm_current_actor.

drop policy if exists clinical_casts_read_authorized on public.clinical_casts;
create policy clinical_casts_read_authorized
on public.clinical_casts for select to authenticated
using ((select private.has_permission((select auth.uid()), 'casts.view')));
