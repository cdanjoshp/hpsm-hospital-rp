-- A assinatura anterior continua disponível; delega à criação atual para compartilhar
-- o lock da consulta e a verificação de tipo já solicitado.
create or replace function public.create_consultation_clinical_exam(
  p_consultation_id bigint,
  p_exam_type_id bigint,
  p_indication text,
  p_clinical_context text default null
)
returns bigint
language sql
security definer
set search_path = ''
as $$
  select public.create_consultation_clinical_exam(
    p_consultation_id,
    p_exam_type_id,
    p_indication,
    p_clinical_context,
    null::bigint,
    null::jsonb
  );
$$;
