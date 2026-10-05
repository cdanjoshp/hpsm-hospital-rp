-- Mantém as rotinas privilegiadas fora do schema exposto e deixa na API
-- somente um invólucro SECURITY INVOKER com validação interna de permissão.

drop function public.get_patient_health_plan_states(bigint[]);

alter function public.review_patient_health_plan_request(bigint, text, text)
  set schema private;

revoke all on function private.review_patient_health_plan_request(bigint, text, text)
from public, anon, authenticated, service_role;
grant execute on function private.review_patient_health_plan_request(bigint, text, text)
to authenticated, service_role;

create function public.review_patient_health_plan_request(
  p_request_id bigint,
  p_decision text,
  p_reason text default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.review_patient_health_plan_request(p_request_id, p_decision, p_reason);
$$;

revoke all on function public.review_patient_health_plan_request(bigint, text, text)
from public, anon, authenticated, service_role;
grant execute on function public.review_patient_health_plan_request(bigint, text, text)
to authenticated, service_role;

comment on function public.review_patient_health_plan_request(bigint, text, text) is
  'Entrada autenticada da API; a rotina privilegiada e sua validação permanecem no schema privado.';
