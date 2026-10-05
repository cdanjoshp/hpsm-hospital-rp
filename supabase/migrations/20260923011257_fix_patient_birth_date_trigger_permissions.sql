-- Corrige o segundo bloqueio do cadastro autenticado de pacientes.
-- O trigger de nascimento precisa consultar o contexto privado e deny-all usado
-- exclusivamente pelo importador HP Norte, sem conceder acesso à tabela.

set lock_timeout = '5s';
set statement_timeout = '30s';

alter function private.enforce_patient_birth_date() security definer;
alter function private.enforce_patient_birth_date() set search_path = '';

revoke all on function private.enforce_patient_birth_date()
from public, anon, authenticated, service_role;

comment on function private.enforce_patient_birth_date() is
  'Trigger privado que exige nascimento no fluxo operacional e reconhece somente o contexto fechado do importador HP Norte.';
