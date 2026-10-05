-- HPSM - restringe a RPC atomica ao backend administrativo do Site.
-- O Site valida a sessao da Diretoria e informa o usuario autenticado como autor.

revoke all on function public.decide_recruitment_application(uuid, text, text)
  from public, anon, authenticated, service_role;
drop function if exists public.decide_recruitment_application(uuid, text, text);

create function public.decide_recruitment_application(
  p_application_id uuid,
  p_decision text,
  p_reason text,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_decided_at timestamptz := now();
  v_reason text;
  v_decision_id bigint;
begin
  if p_actor_id is null or not exists (
    select 1
    from public.profiles
    where user_id = p_actor_id
      and status = 'active'
      and role_code in ('diretor_geral', 'diretoria')
  ) then
    raise exception using
      errcode = '42501',
      message = 'Apenas a Diretoria pode decidir candidaturas.';
  end if;

  if p_decision not in ('approved', 'rejected') then
    raise exception using
      errcode = '22023',
      message = 'Decisão inválida.';
  end if;

  if p_decision = 'rejected' then
    v_reason := btrim(coalesce(p_reason, ''));
    if char_length(v_reason) not between 10 and 2000 then
      raise exception using
        errcode = '22023',
        message = 'Informe um motivo de recusa entre 10 e 2000 caracteres.';
    end if;
  else
    v_reason := null;
  end if;

  update public.recruitment_applications
  set
    status = p_decision,
    review_notes = v_reason,
    reviewed_by = p_actor_id,
    reviewed_at = v_decided_at
  where id = p_application_id
    and status in ('submitted', 'under_review', 'interview');

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Candidatura não encontrada ou já decidida.';
  end if;

  insert into public.recruitment_decisions (
    application_id,
    decision,
    reason,
    decided_by,
    decided_at
  ) values (
    p_application_id,
    p_decision,
    v_reason,
    p_actor_id,
    v_decided_at
  )
  returning id into v_decision_id;

  return jsonb_build_object(
    'application_id', p_application_id,
    'decision_id', v_decision_id,
    'decision', p_decision,
    'reason', v_reason,
    'decided_by', p_actor_id,
    'decided_at', v_decided_at
  );
end;
$$;

revoke all on function public.decide_recruitment_application(uuid, text, text, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.decide_recruitment_application(uuid, text, text, uuid)
  to service_role;

comment on function public.decide_recruitment_application(uuid, text, text, uuid) is
  'RPC exclusiva do backend: decide uma candidatura e registra o membro autenticado da Diretoria.';

notify pgrst, 'reload schema';
