-- HPSM 1.1.0 — os valores por benefício passam a ser atalhos da interface.
-- Mantém a assinatura auxiliar por compatibilidade com a RPC já publicada,
-- mas neutraliza a antiga rejeição de quantidades acima da referência.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function private.attendance_item_limit(
  p_service_code text,
  p_benefit_code text
)
returns integer
language sql
immutable
security invoker
set search_path = ''
as $$
  select null::integer;
$$;

revoke all on function private.attendance_item_limit(text, text)
from public, anon, authenticated, service_role;
grant execute on function private.attendance_item_limit(text, text) to service_role;

comment on function private.attendance_item_limit(text, text) is
  'Compatibilidade: não impõe limite. A matriz de benefício serve apenas ao atalho MAX da calculadora.';
