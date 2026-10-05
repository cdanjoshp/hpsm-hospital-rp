-- HPSM · revisao dos textos automaticos exibidos no mural.

create or replace function private.notify_absence_workflow()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' and new.status = 'pending' then
    insert into public.notifications (
      kind, audience, priority, title, body, action_url, created_by
    ) values (
      'system', 'directors', 'important', 'Nova justificativa de ausência',
      'Uma justificativa de ausência aguarda análise da Diretoria.',
      '/pendencias#ausencias', new.employee_id
    );
  elsif tg_op = 'UPDATE' and old.status = 'pending' and new.status in ('approved', 'rejected') then
    insert into public.notifications (
      kind, recipient_id, priority, title, body, action_url, created_by
    ) values (
      'personal', new.employee_id,
      case when new.status = 'approved' then 'normal' else 'important' end,
      case when new.status = 'approved' then 'Justificativa aprovada' else 'Justificativa recusada' end,
      case
        when new.status = 'approved' and new.approval_effect = 'weekly_exemption'
          then 'Sua justificativa foi aprovada com isenção da meta nas semanas atingidas.'
        when new.status = 'approved'
          then 'Sua justificativa foi aprovada para registro, sem alteração da meta semanal.'
        else 'Sua justificativa foi recusada. Consulte o Meu RH para ver a decisão registrada.'
      end,
      '/meu-rh', new.reviewed_by
    );
  end if;
  return new;
end;
$$;

create or replace function private.notify_warning_workflow()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.notifications (
      kind, recipient_id, priority, title, body, action_url, created_by
    ) values (
      'personal', new.employee_id,
      case when new.sequence_in_cycle = 3 then 'urgent' else 'important' end,
      format('%sª advertência do ciclo', new.sequence_in_cycle),
      case
        when new.sequence_in_cycle = 3
          then 'A terceira advertência do ciclo foi registrada e seu acesso foi suspenso para análise da Diretoria.'
        else format('Uma advertência foi registrada. Contagem atual: %s/3 neste ciclo mensal.', new.sequence_in_cycle)
      end,
      '/meu-rh', new.issued_by
    );
  elsif tg_op = 'UPDATE' and old.status = 'active' and new.status = 'annulled' then
    insert into public.notifications (
      kind, recipient_id, priority, title, body, action_url, created_by
    ) values (
      'personal', new.employee_id, 'normal', 'Advertência anulada',
      'Uma advertência deste ciclo foi anulada pela Diretoria e deixou de contar no limite mensal.',
      '/meu-rh', new.annulled_by
    );
  end if;
  return new;
end;
$$;

create or replace function private.notify_disciplinary_workflow()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' and new.status = 'pending' then
    insert into public.notifications (
      kind, audience, priority, title, body, action_url, created_by
    ) values (
      'system', 'directors', 'urgent', 'Análise disciplinar urgente',
      'Um colaborador atingiu três advertências no ciclo e foi suspenso para análise.',
      '/pendencias#disciplina', new.triggered_by
    );
  elsif tg_op = 'UPDATE' and old.status = 'pending' and new.status <> 'pending' then
    insert into public.notifications (
      kind, recipient_id, priority, title, body, action_url, created_by
    ) values (
      'personal', new.employee_id,
      case when new.status = 'reactivated' then 'normal' else 'important' end,
      case
        when new.status = 'reactivated' then 'Acesso reativado'
        when new.status = 'dismissed' then 'Desligamento registrado'
        else 'Suspensão mantida'
      end,
      case
        when new.status = 'reactivated' then 'A análise disciplinar foi concluída e seu acesso foi reativado.'
        when new.status = 'dismissed' then 'A Diretoria concluiu a análise disciplinar com o desligamento do hospital.'
        else 'A Diretoria concluiu a análise disciplinar e manteve a suspensão.'
      end,
      '/meu-rh', new.decided_by
    );
  end if;
  return new;
end;
$$;

create or replace function private.notify_recruitment_submission()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status in ('submitted', 'under_review', 'interview') then
    insert into public.notifications (
      kind, audience, priority, title, body, action_url
    ) values (
      'system', 'directors', 'normal', 'Nova candidatura recebida',
      'Uma nova candidatura aguarda avaliação na fila de recrutamento.',
      '/pendencias#recrutamento'
    );
  end if;
  return new;
end;
$$;

revoke all on function private.notify_absence_workflow()
  from public, anon, authenticated, service_role;
revoke all on function private.notify_warning_workflow()
  from public, anon, authenticated, service_role;
revoke all on function private.notify_disciplinary_workflow()
  from public, anon, authenticated, service_role;
revoke all on function private.notify_recruitment_submission()
  from public, anon, authenticated, service_role;

notify pgrst, 'reload schema';
