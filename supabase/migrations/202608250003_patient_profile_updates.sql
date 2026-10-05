-- HP Sul — Fase 2.1: correção cadastral de pacientes pela equipe ativa.

drop policy if exists patients_update_director on public.patients;

create policy patients_update_active
on public.patients
for update
to authenticated
using ((select private.is_active_user()))
with check (
  (select private.is_active_user())
  and updated_by = (select auth.uid())
);

comment on policy patients_update_active on public.patients is
  'Permite que funcionários ativos corrijam o cadastro administrativo do paciente; alterações permanecem auditadas.';
