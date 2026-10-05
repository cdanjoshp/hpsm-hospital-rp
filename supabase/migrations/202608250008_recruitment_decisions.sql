-- HPSM - decisoes imutaveis sobre candidaturas.
-- A operacao atomica registra o resultado e o membro da Diretoria responsável.

create table if not exists public.recruitment_decisions (
  id bigint generated always as identity primary key,
  application_id uuid not null references public.recruitment_applications(id) on delete cascade,
  decision text not null,
  reason text,
  decided_by uuid not null references auth.users(id) on delete restrict,
  decided_at timestamptz not null default now(),
  constraint recruitment_decision_valid check (decision in ('approved', 'rejected')),
  constraint recruitment_decision_reason_valid check (
    (decision = 'approved' and reason is null)
    or (
      decision = 'rejected'
      and char_length(btrim(reason)) between 10 and 2000
    )
  )
);

create index if not exists recruitment_decisions_application_idx
  on public.recruitment_decisions (application_id, decided_at desc);

create index if not exists recruitment_decisions_decided_by_idx
  on public.recruitment_decisions (decided_by);

alter table public.recruitment_decisions enable row level security;
alter table public.recruitment_decisions force row level security;

drop policy if exists recruitment_decisions_read_directors on public.recruitment_decisions;
create policy recruitment_decisions_read_directors
on public.recruitment_decisions for select
to authenticated
using ((select private.is_director()));

revoke all on public.recruitment_decisions from public, anon, authenticated, service_role;
grant select on public.recruitment_decisions to authenticated;
grant select, insert, update, delete on public.recruitment_decisions to service_role;

create or replace function public.decide_recruitment_application(
  p_application_id uuid,
  p_decision text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_decided_at timestamptz := now();
  v_reason text;
  v_decision_id bigint;
begin
  if v_actor is null or not (select private.is_director()) then
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
    reviewed_by = v_actor,
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
    v_actor,
    v_decided_at
  )
  returning id into v_decision_id;

  return jsonb_build_object(
    'application_id', p_application_id,
    'decision_id', v_decision_id,
    'decision', p_decision,
    'reason', v_reason,
    'decided_by', v_actor,
    'decided_at', v_decided_at
  );
end;
$$;

revoke all on function public.decide_recruitment_application(uuid, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.decide_recruitment_application(uuid, text, text)
  to authenticated;

drop trigger if exists recruitment_applications_audit on public.recruitment_applications;
create trigger recruitment_applications_audit
after update on public.recruitment_applications
for each row execute function private.audit_row_change();

drop trigger if exists recruitment_decisions_audit on public.recruitment_decisions;
create trigger recruitment_decisions_audit
after insert on public.recruitment_decisions
for each row execute function private.audit_row_change();

comment on table public.recruitment_decisions is
  'Histórico imutável das aprovações e recusas registradas pela Diretoria.';
comment on function public.decide_recruitment_application(uuid, text, text) is
  'Decide uma candidatura e registra a autoria em uma única transação.';

notify pgrst, 'reload schema';
