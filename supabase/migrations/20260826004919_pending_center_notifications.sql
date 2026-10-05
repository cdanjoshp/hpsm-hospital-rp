-- HPSM · roadmap 3 e 4
-- Central de pendencias, notificacoes pessoais e mural institucional.

create table public.notifications (
  id bigint generated always as identity primary key,
  kind text not null,
  recipient_id uuid references auth.users(id) on delete cascade,
  audience text,
  priority text not null default 'normal',
  title text not null,
  body text not null,
  action_url text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz,
  archived_at timestamptz,
  archived_by uuid references auth.users(id) on delete set null,
  constraint notifications_kind_check
    check (kind in ('personal', 'system', 'announcement')),
  constraint notifications_scope_check check (
    (kind = 'personal' and recipient_id is not null and audience is null)
    or
    (kind in ('system', 'announcement') and recipient_id is null and audience is not null)
  ),
  constraint notifications_audience_check
    check (audience is null or audience in ('all', 'directors', 'employees')),
  constraint notifications_priority_check
    check (priority in ('normal', 'important', 'urgent')),
  constraint notifications_title_check
    check (char_length(btrim(title)) between 4 and 120),
  constraint notifications_body_check
    check (char_length(btrim(body)) between 10 and 2000),
  constraint notifications_action_url_check
    check (action_url is null or (action_url ~ '^/[A-Za-z0-9_/?#=&.-]*$' and char_length(action_url) <= 240)),
  constraint notifications_expiration_check
    check (expires_at is null or expires_at > created_at),
  constraint notifications_archive_check
    check (
      (archived_at is null and archived_by is null)
      or (archived_at is not null and archived_by is not null)
    )
);

create table public.notification_reads (
  notification_id bigint not null references public.notifications(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (notification_id, user_id)
);

create index notifications_recipient_active_idx
  on public.notifications (recipient_id, created_at desc)
  where recipient_id is not null and archived_at is null;
create index notifications_audience_active_idx
  on public.notifications (audience, created_at desc)
  where audience is not null and archived_at is null;
create index notifications_created_by_idx
  on public.notifications (created_by)
  where created_by is not null;
create index notifications_archived_by_idx
  on public.notifications (archived_by)
  where archived_by is not null;
create index notification_reads_user_idx
  on public.notification_reads (user_id, read_at desc);

create function private.can_view_notification(p_notification_id bigint, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.notifications n
    join public.profiles p on p.user_id = p_user_id
    where n.id = p_notification_id
      and p.status = 'active'
      and n.archived_at is null
      and (n.expires_at is null or n.expires_at > now())
      and (
        n.recipient_id = p_user_id
        or n.audience = 'all'
        or (n.audience = 'directors' and p.role_code in ('diretor_geral', 'diretoria'))
        or (n.audience = 'employees' and p.role_code = 'funcionario')
      )
  );
$$;

create function public.publish_notification_announcement(
  p_title text,
  p_body text,
  p_audience text,
  p_priority text,
  p_expires_at timestamptz,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.notifications;
  v_actor_passport text;
begin
  if not private.is_director_user(p_actor_id) then
    raise exception using errcode = '42501', message = 'Apenas a Diretoria pode publicar avisos.';
  end if;
  if char_length(btrim(coalesce(p_title, ''))) not between 4 and 120 then
    raise exception using errcode = '22023', message = 'Informe um titulo entre 4 e 120 caracteres.';
  end if;
  if char_length(btrim(coalesce(p_body, ''))) not between 10 and 2000 then
    raise exception using errcode = '22023', message = 'Informe uma mensagem entre 10 e 2000 caracteres.';
  end if;
  if p_audience not in ('all', 'directors', 'employees') then
    raise exception using errcode = '22023', message = 'Publico do aviso invalido.';
  end if;
  if p_priority not in ('normal', 'important', 'urgent') then
    raise exception using errcode = '22023', message = 'Prioridade do aviso invalida.';
  end if;
  if p_expires_at is not null and p_expires_at <= now() then
    raise exception using errcode = '22023', message = 'A validade deve estar no futuro.';
  end if;

  insert into public.notifications (
    kind, audience, priority, title, body, created_by, expires_at
  ) values (
    'announcement', p_audience, p_priority, btrim(p_title), btrim(p_body), p_actor_id, p_expires_at
  ) returning * into v_row;

  select passport into v_actor_passport
  from public.profiles
  where user_id = p_actor_id;

  insert into public.audit_logs (
    actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values
  ) values (
    p_actor_id, v_actor_passport, 'INSERT', 'notifications', v_row.id::text, null, to_jsonb(v_row)
  );

  return to_jsonb(v_row);
end;
$$;

create function public.archive_notification_announcement(
  p_notification_id bigint,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old public.notifications;
  v_row public.notifications;
  v_actor_passport text;
begin
  if not private.is_director_user(p_actor_id) then
    raise exception using errcode = '42501', message = 'Apenas a Diretoria pode arquivar avisos.';
  end if;

  select * into v_old
  from public.notifications
  where id = p_notification_id
  for update;

  if not found or v_old.kind <> 'announcement' or v_old.archived_at is not null then
    raise exception using errcode = 'P0002', message = 'Aviso nao encontrado ou ja arquivado.';
  end if;

  update public.notifications
  set archived_at = now(), archived_by = p_actor_id
  where id = p_notification_id
  returning * into v_row;

  select passport into v_actor_passport
  from public.profiles
  where user_id = p_actor_id;

  insert into public.audit_logs (
    actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values
  ) values (
    p_actor_id, v_actor_passport, 'UPDATE', 'notifications', v_row.id::text, to_jsonb(v_old), to_jsonb(v_row)
  );

  return to_jsonb(v_row);
end;
$$;

create function public.mark_notification_read(
  p_notification_id bigint,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.notification_reads;
begin
  if not private.can_view_notification(p_notification_id, p_actor_id) then
    raise exception using errcode = '42501', message = 'Notificacao indisponivel para este usuario.';
  end if;

  insert into public.notification_reads (notification_id, user_id)
  values (p_notification_id, p_actor_id)
  on conflict (notification_id, user_id) do update
  set read_at = excluded.read_at
  returning * into v_row;

  return to_jsonb(v_row);
end;
$$;

create function public.mark_all_notifications_read(p_actor_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not exists (
    select 1 from public.profiles
    where user_id = p_actor_id and status = 'active'
  ) then
    raise exception using errcode = '42501', message = 'Usuario sem acesso ativo.';
  end if;

  insert into public.notification_reads (notification_id, user_id)
  select n.id, p_actor_id
  from public.notifications n
  where private.can_view_notification(n.id, p_actor_id)
  on conflict (notification_id, user_id) do update
  set read_at = excluded.read_at;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create function private.notify_absence_workflow()
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
      'system', 'directors', 'important', 'Nova justificativa de ausencia',
      'Uma justificativa de ausencia aguarda analise da Diretoria.',
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
          then 'Sua justificativa foi aprovada com isencao da meta nas semanas atingidas.'
        when new.status = 'approved'
          then 'Sua justificativa foi aprovada para registro, sem alteracao da meta semanal.'
        else 'Sua justificativa foi recusada. Consulte o Meu RH para ver a decisao registrada.'
      end,
      '/meu-rh', new.reviewed_by
    );
  end if;
  return new;
end;
$$;

create function private.notify_warning_workflow()
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
      format('%sª advertencia do ciclo', new.sequence_in_cycle),
      case
        when new.sequence_in_cycle = 3
          then 'A terceira advertencia do ciclo foi registrada e seu acesso foi suspenso para analise da Diretoria.'
        else format('Uma advertencia foi registrada. Contagem atual: %s/3 neste ciclo mensal.', new.sequence_in_cycle)
      end,
      '/meu-rh', new.issued_by
    );
  elsif tg_op = 'UPDATE' and old.status = 'active' and new.status = 'annulled' then
    insert into public.notifications (
      kind, recipient_id, priority, title, body, action_url, created_by
    ) values (
      'personal', new.employee_id, 'normal', 'Advertencia anulada',
      'Uma advertencia deste ciclo foi anulada pela Diretoria e deixou de contar no limite mensal.',
      '/meu-rh', new.annulled_by
    );
  end if;
  return new;
end;
$$;

create function private.notify_disciplinary_workflow()
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
      'system', 'directors', 'urgent', 'Analise disciplinar urgente',
      'Um colaborador atingiu tres advertencias no ciclo e foi suspenso para analise.',
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
        else 'Suspensao mantida'
      end,
      case
        when new.status = 'reactivated' then 'A analise disciplinar foi concluida e seu acesso foi reativado.'
        when new.status = 'dismissed' then 'A Diretoria concluiu a analise disciplinar com o desligamento do hospital.'
        else 'A Diretoria concluiu a analise disciplinar e manteve a suspensao.'
      end,
      '/meu-rh', new.decided_by
    );
  end if;
  return new;
end;
$$;

create function private.notify_recruitment_submission()
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
      'Uma nova candidatura aguarda avaliacao na fila de recrutamento.',
      '/pendencias#recrutamento'
    );
  end if;
  return new;
end;
$$;

create trigger notifications_absence_workflow
after insert or update on public.rh_absence_requests
for each row execute function private.notify_absence_workflow();
create trigger notifications_warning_workflow
after insert or update on public.rh_warnings
for each row execute function private.notify_warning_workflow();
create trigger notifications_disciplinary_workflow
after insert or update on public.rh_disciplinary_reviews
for each row execute function private.notify_disciplinary_workflow();
create trigger notifications_recruitment_submission
after insert on public.recruitment_applications
for each row execute function private.notify_recruitment_submission();

alter table public.notifications enable row level security;
alter table public.notifications force row level security;
alter table public.notification_reads enable row level security;
alter table public.notification_reads force row level security;

create policy notifications_read_visible
on public.notifications for select to authenticated
using (private.can_view_notification(id, (select auth.uid())));
create policy notification_reads_read_own
on public.notification_reads for select to authenticated
using (
  (select auth.uid()) is not null
  and user_id = (select auth.uid())
  and (select private.is_active_user())
);

revoke all on public.notifications from public, anon, authenticated, service_role;
revoke all on public.notification_reads from public, anon, authenticated, service_role;
grant select on public.notifications to authenticated, service_role;
grant select on public.notification_reads to authenticated, service_role;
grant insert, update on public.notifications to service_role;
grant insert, update on public.notification_reads to service_role;
grant usage, select on sequence public.notifications_id_seq to service_role;

revoke all on function private.can_view_notification(bigint, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.publish_notification_announcement(text, text, text, text, timestamptz, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.archive_notification_announcement(bigint, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.mark_notification_read(bigint, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.mark_all_notifications_read(uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.notify_absence_workflow()
  from public, anon, authenticated, service_role;
revoke all on function private.notify_warning_workflow()
  from public, anon, authenticated, service_role;
revoke all on function private.notify_disciplinary_workflow()
  from public, anon, authenticated, service_role;
revoke all on function private.notify_recruitment_submission()
  from public, anon, authenticated, service_role;

grant execute on function private.can_view_notification(bigint, uuid) to authenticated, service_role;
grant execute on function public.publish_notification_announcement(text, text, text, text, timestamptz, uuid) to service_role;
grant execute on function public.archive_notification_announcement(bigint, uuid) to service_role;
grant execute on function public.mark_notification_read(bigint, uuid) to service_role;
grant execute on function public.mark_all_notifications_read(uuid) to service_role;

comment on table public.notifications is
  'Notificacoes pessoais, alertas de fluxo e avisos institucionais do mural interno.';
comment on table public.notification_reads is
  'Confirmacoes individuais de leitura das notificacoes visiveis para cada usuario.';

notify pgrst, 'reload schema';
