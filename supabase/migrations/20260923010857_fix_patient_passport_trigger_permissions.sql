-- Corrige o cadastro autenticado de pacientes após a canonização de passaportes.
-- O trigger continua privado e sem EXECUTE direto; apenas executa sua normalização
-- mínima com os privilégios do proprietário para alcançar o helper privado revogado.

set lock_timeout = '5s';
set statement_timeout = '30s';

alter function private.canonicalize_patient_passport() security definer;
alter function private.canonicalize_patient_passport() set search_path = '';

revoke all on function private.canonicalize_patient_passport()
from public, anon, authenticated, service_role;

comment on function private.canonicalize_patient_passport() is
  'Trigger privado que normaliza passaportes de pacientes sem expor o helper canônico aos papéis da Data API.';
