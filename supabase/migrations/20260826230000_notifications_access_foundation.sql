-- HPSM · notificações resolvíveis e separação entre cargo e permissão.
-- Migração aditiva: preserva perfis, RH, leituras e comunicados existentes.

-- ---------------------------------------------------------------------------
-- Catálogo de cargos e permissões
-- ---------------------------------------------------------------------------

create table public.staff_positions (
  id bigint generated always as identity primary key,
  code text not null unique,
  name text not null unique,
  active boolean not null default true,
  sort_order integer not null default 0,
  created_by uuid not null references public.profiles(user_id) on delete restrict,
  updated_by uuid not null references public.profiles(user_id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint staff_positions_code_check check (code ~ '^[a-z0-9]+(?:_[a-z0-9]+)*$'),
  constraint staff_positions_name_check check (char_length(btrim(name)) between 2 and 80)
);

create table public.system_permissions (
  code text primary key,
  module text not null,
  label text not null,
  description text not null,
  sort_order integer not null default 0,
  constraint system_permissions_code_check check (code ~ '^[a-z0-9]+(?:\.[a-z0-9]+)*$'),
  constraint system_permissions_module_check check (char_length(btrim(module)) between 2 and 40),
  constraint system_permissions_label_check check (char_length(btrim(label)) between 2 and 100)
);

create table public.staff_position_permissions (
  position_id bigint not null references public.staff_positions(id) on delete cascade,
  permission_code text not null references public.system_permissions(code) on delete restrict,
  granted_by uuid not null references public.profiles(user_id) on delete restrict,
  granted_at timestamptz not null default now(),
  primary key (position_id, permission_code)
);

create table public.user_permission_grants (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(user_id) on delete restrict,
  permission_code text not null references public.system_permissions(code) on delete restrict,
  valid_from timestamptz not null default now(),
  expires_at timestamptz not null,
  reason text not null,
  granted_by uuid not null references public.profiles(user_id) on delete restrict,
  granted_at timestamptz not null default now(),
  revoked_at timestamptz,
  revoked_by uuid references public.profiles(user_id) on delete restrict,
  revoked_reason text,
  constraint user_permission_grants_window_check check (expires_at > valid_from),
  constraint user_permission_grants_reason_check check (char_length(btrim(reason)) between 10 and 1000),
  constraint user_permission_grants_revocation_check check (
    (revoked_at is null and revoked_by is null and revoked_reason is null)
    or
    (revoked_at is not null and revoked_by is not null and char_length(btrim(revoked_reason)) between 10 and 1000)
  )
);

alter table public.profiles
  add column position_id bigint references public.staff_positions(id) on delete set null;

create index profiles_position_idx on public.profiles (position_id) where position_id is not null;
create index staff_positions_active_idx on public.staff_positions (active, sort_order, name);
create index staff_position_permissions_code_idx on public.staff_position_permissions (permission_code, position_id);
create index user_permission_grants_user_active_idx
  on public.user_permission_grants (user_id, expires_at)
  where revoked_at is null;
create index user_permission_grants_permission_active_idx
  on public.user_permission_grants (permission_code, expires_at)
  where revoked_at is null;

insert into public.system_permissions (code, module, label, description, sort_order) values
  ('access.manage', 'Acessos', 'Configurar cargos e permissões', 'Cria cargos, define a matriz de permissões e concede acessos temporários.', 10),
  ('team.manage', 'Acessos', 'Gerenciar equipe e contas', 'Cria contas, altera situação, cargo e senha temporária dos profissionais.', 20),
  ('hr.hours.manage', 'RH', 'Gerenciar horas e fechamento', 'Importa leituras, apura, fecha e reabre semanas.', 30),
  ('hr.absences.review', 'RH', 'Analisar afastamentos', 'Aprova ou recusa afastamentos preventivos e define horas abatidas.', 40),
  ('hr.justifications.review', 'RH', 'Analisar justificativas', 'Aprova integral ou parcialmente e recusa justificativas de déficit.', 50),
  ('hr.discipline.manage', 'RH', 'Gerenciar disciplina', 'Aplica, anula e analisa advertências e suspensões.', 60),
  ('hr.reports.view', 'RH', 'Consultar relatórios administrativos', 'Consulta relatórios semanais, mensais e fichas individuais.', 70),
  ('recruitment.manage', 'Administrativo', 'Analisar candidaturas', 'Consulta e decide candidaturas recebidas.', 80),
  ('catalog.manage', 'Operação', 'Gerenciar preços e benefícios', 'Altera preços e percentuais dos benefícios.', 90),
  ('attendances.manage', 'Operação', 'Gerenciar atendimentos', 'Consulta e corrige registros operacionais de toda a equipe.', 100),
  ('communications.manage', 'Comunicação', 'Gerenciar comunicados', 'Publica, acompanha e arquiva comunicados institucionais.', 110),
  ('audit.view', 'Segurança', 'Consultar auditoria', 'Consulta o histórico de ações sensíveis do sistema.', 120);

create or replace function private.has_permission(p_user_id uuid, p_permission_code text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles profile
    where profile.user_id = p_user_id
      and profile.status = 'active'
      and (
        profile.role_code in ('diretor_geral', 'diretoria')
        or exists (
          select 1
          from public.staff_position_permissions position_permission
          join public.staff_positions position on position.id = position_permission.position_id
          where position_permission.position_id = profile.position_id
            and position_permission.permission_code = p_permission_code
            and position.active
        )
        or exists (
          select 1
          from public.user_permission_grants permission_grant
          where permission_grant.user_id = profile.user_id
            and permission_grant.permission_code = p_permission_code
            and permission_grant.revoked_at is null
            and permission_grant.valid_from <= now()
            and permission_grant.expires_at > now()
        )
      )
  );
$$;

create or replace function private.has_any_management_permission(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.system_permissions permission
    where private.has_permission(p_user_id, permission.code)
  );
$$;

create function public.create_staff_position(
  p_code text,
  p_name text,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.staff_positions;
begin
  if not private.has_permission(p_actor_id, 'access.manage') then
    raise exception using errcode = '42501', message = 'Você não possui permissão para criar cargos.';
  end if;
  if p_code is null or p_code !~ '^[a-z0-9]+(?:_[a-z0-9]+)*$'
     or char_length(btrim(coalesce(p_name, ''))) not between 2 and 80 then
    raise exception using errcode = '22023', message = 'Informe um nome de cargo válido.';
  end if;
  insert into public.staff_positions (code, name, created_by, updated_by)
  values (p_code, btrim(p_name), p_actor_id, p_actor_id)
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

create function public.update_staff_position(
  p_position_id bigint,
  p_name text,
  p_active boolean,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.staff_positions;
begin
  if not private.has_permission(p_actor_id, 'access.manage') then
    raise exception using errcode = '42501', message = 'Você não possui permissão para alterar cargos.';
  end if;
  if char_length(btrim(coalesce(p_name, ''))) not between 2 and 80 or p_active is null then
    raise exception using errcode = '22023', message = 'Dados do cargo inválidos.';
  end if;
  update public.staff_positions
  set name = btrim(p_name), active = p_active, updated_by = p_actor_id, updated_at = now()
  where id = p_position_id
  returning * into v_row;
  if not found then
    raise exception using errcode = 'P0002', message = 'Cargo não encontrado.';
  end if;
  return to_jsonb(v_row);
end;
$$;

create function public.set_staff_position_permissions(
  p_position_id bigint,
  p_permission_codes jsonb,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text;
  v_codes text[] := array[]::text[];
begin
  if not private.has_permission(p_actor_id, 'access.manage') then
    raise exception using errcode = '42501', message = 'Você não possui permissão para configurar acessos.';
  end if;
  if not exists (select 1 from public.staff_positions where id = p_position_id)
     or p_permission_codes is null or jsonb_typeof(p_permission_codes) <> 'array' then
    raise exception using errcode = '22023', message = 'Cargo ou permissões inválidas.';
  end if;
  for v_code in select jsonb_array_elements_text(p_permission_codes)
  loop
    if not exists (select 1 from public.system_permissions where code = v_code)
       or v_code = any(v_codes) then
      raise exception using errcode = '22023', message = 'A lista contém permissão inválida ou repetida.';
    end if;
    v_codes := array_append(v_codes, v_code);
  end loop;
  update public.staff_position_permissions
  set granted_by = p_actor_id, granted_at = now()
  where position_id = p_position_id;
  delete from public.staff_position_permissions where position_id = p_position_id;
  insert into public.staff_position_permissions (position_id, permission_code, granted_by)
  select p_position_id, code, p_actor_id from unnest(v_codes) code;
  update public.staff_positions set updated_by = p_actor_id, updated_at = now() where id = p_position_id;
  return jsonb_build_object('position_id', p_position_id, 'permission_codes', to_jsonb(v_codes));
end;
$$;

create function public.grant_temporary_permission(
  p_user_id uuid,
  p_permission_code text,
  p_valid_from timestamptz,
  p_expires_at timestamptz,
  p_reason text,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.user_permission_grants;
  v_start timestamptz := coalesce(p_valid_from, now());
begin
  if not private.has_permission(p_actor_id, 'access.manage') then
    raise exception using errcode = '42501', message = 'Você não possui permissão para conceder acessos temporários.';
  end if;
  if p_user_id = p_actor_id then
    raise exception using errcode = '42501', message = 'Você não pode conceder uma permissão temporária para si próprio.';
  end if;
  if not exists (select 1 from public.profiles where user_id = p_user_id and status <> 'inactive')
     or not exists (select 1 from public.system_permissions where code = p_permission_code)
     or p_expires_at is null or p_expires_at <= v_start or p_expires_at > v_start + interval '180 days'
     or char_length(btrim(coalesce(p_reason, ''))) not between 10 and 1000 then
    raise exception using errcode = '22023', message = 'Confira o profissional, a permissão, a validade e o motivo.';
  end if;
  insert into public.user_permission_grants (
    user_id, permission_code, valid_from, expires_at, reason, granted_by
  ) values (
    p_user_id, p_permission_code, v_start, p_expires_at, btrim(p_reason), p_actor_id
  ) returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

create function public.revoke_temporary_permission(
  p_grant_id bigint,
  p_reason text,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.user_permission_grants;
begin
  if not private.has_permission(p_actor_id, 'access.manage') then
    raise exception using errcode = '42501', message = 'Você não possui permissão para revogar acessos.';
  end if;
  if char_length(btrim(coalesce(p_reason, ''))) not between 10 and 1000 then
    raise exception using errcode = '22023', message = 'Informe o motivo da revogação.';
  end if;
  update public.user_permission_grants
  set revoked_at = now(), revoked_by = p_actor_id, revoked_reason = btrim(p_reason)
  where id = p_grant_id and revoked_at is null and expires_at > now()
  returning * into v_row;
  if not found then
    raise exception using errcode = 'P0002', message = 'Permissão temporária não encontrada ou já encerrada.';
  end if;
  return to_jsonb(v_row);
end;
$$;

-- ---------------------------------------------------------------------------
-- Notificações vinculadas ao estado da demanda
-- ---------------------------------------------------------------------------

alter table public.notifications
  add column source_type text,
  add column source_id text,
  add column required_permission text references public.system_permissions(code) on delete restrict,
  add column resolved_at timestamptz,
  add column resolved_by uuid references public.profiles(user_id) on delete set null;

alter table public.notifications
  add constraint notifications_source_pair_check check (
    (source_type is null and source_id is null)
    or
    (char_length(btrim(source_type)) between 2 and 60 and char_length(btrim(source_id)) between 1 and 100)
  ),
  add constraint notifications_resolution_check check (
    (resolved_at is null and resolved_by is null)
    or resolved_at is not null
  );

create index notifications_open_source_idx
  on public.notifications (source_type, source_id, created_at desc)
  where source_type is not null and resolved_at is null and archived_at is null;
create index notifications_required_permission_idx
  on public.notifications (required_permission, created_at desc)
  where required_permission is not null and archived_at is null;

-- Notificações operacionais antigas não tinham vínculo com a demanda. Elas são
-- encerradas na migração para não manter alertas históricos como pendências.
update public.notifications
set resolved_at = now()
where kind = 'system' and source_type is null and resolved_at is null;

create or replace function private.resolve_flow_notifications(
  p_source_type text,
  p_source_id text,
  p_actor_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  update public.notifications
  set resolved_at = coalesce(resolved_at, now()),
      resolved_by = coalesce(resolved_by, p_actor_id)
  where source_type = p_source_type
    and source_id = p_source_id
    and resolved_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function private.can_view_notification(p_notification_id bigint, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.notifications notification
    join public.profiles profile on profile.user_id = p_user_id
    where notification.id = p_notification_id
      and profile.status = 'active'
      and notification.archived_at is null
      and (notification.expires_at is null or notification.expires_at > now())
      and (
        notification.recipient_id = p_user_id
        or notification.audience = 'all'
        or (
          notification.audience = 'directors'
          and (
            profile.role_code in ('diretor_geral', 'diretoria')
            or (
              notification.required_permission is not null
              and private.has_permission(p_user_id, notification.required_permission)
            )
          )
        )
        or (notification.audience = 'employees' and profile.role_code = 'funcionario')
      )
  );
$$;

create or replace function private.notify_absence_workflow()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' and new.status = 'pending' then
    insert into public.notifications (
      kind, audience, priority, title, body, action_url, created_by,
      source_type, source_id, required_permission
    ) values (
      'system', 'directors', 'important', 'Novo afastamento solicitado',
      'Um afastamento preventivo aguarda análise e definição das horas abatidas.',
      '/rh?aba=absences', new.employee_id,
      'rh_leave', new.id::text, 'hr.absences.review'
    );
  elsif tg_op = 'UPDATE' and old.status = 'pending' and new.status in ('approved', 'rejected', 'cancelled') then
    perform private.resolve_flow_notifications('rh_leave', new.id::text, coalesce(new.reviewed_by, new.cancelled_by, new.employee_id));
    if new.status in ('approved', 'rejected') then
      insert into public.notifications (
        kind, recipient_id, priority, title, body, action_url, created_by
      ) values (
        'personal', new.employee_id,
        case when new.status = 'approved' then 'normal' else 'important' end,
        case when new.status = 'approved' then 'Afastamento aprovado' else 'Afastamento recusado' end,
        case when new.status = 'approved'
          then 'Seu afastamento foi aprovado e as horas autorizadas já foram abatidas das metas atingidas.'
          else 'Seu afastamento foi recusado. Consulte o Meu RH para ver a decisão registrada.' end,
        '/meu-rh', new.reviewed_by
      );
    end if;
  end if;
  return new;
end;
$$;

create or replace function private.notify_hr_week_deficit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.closure_status = 'awaiting_justification'
     and (tg_op = 'INSERT' or old.closure_status is distinct from new.closure_status) then
    insert into public.notifications (
      kind, recipient_id, priority, title, body, action_url, created_by,
      source_type, source_id
    ) values (
      'personal', new.employee_id, 'important', 'Justifique as horas da semana',
      format('A apuração de %s a %s identificou déficit de %sh%s. Envie sua justificativa pelo Meu RH.',
        to_char(new.week_start, 'DD/MM'), to_char(new.week_end, 'DD/MM'),
        new.remaining_deficit_minutes / 60, lpad((new.remaining_deficit_minutes % 60)::text, 2, '0')),
      '/meu-rh', new.closed_by,
      'rh_weekly_deficit', new.id::text
    );
  elsif tg_op = 'UPDATE' and old.closure_status = 'awaiting_justification'
        and new.closure_status <> 'awaiting_justification' then
    perform private.resolve_flow_notifications('rh_weekly_deficit', new.id::text, new.employee_id);
  end if;
  return new;
end;
$$;

create or replace function private.notify_hr_hour_justification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' and new.status = 'pending' then
    insert into public.notifications (
      kind, audience, priority, title, body, action_url, created_by,
      source_type, source_id, required_permission
    ) values (
      'system', 'directors', 'important', 'Justificativa de horas recebida',
      'Um colaborador respondeu a uma pendência semanal e aguarda análise.',
      '/rh?aba=absences', new.employee_id,
      'rh_hour_justification', new.id::text, 'hr.justifications.review'
    );
  elsif tg_op = 'UPDATE' and old.status = 'pending' and new.status in ('approved', 'rejected') then
    perform private.resolve_flow_notifications('rh_hour_justification', new.id::text, new.reviewed_by);
    insert into public.notifications (
      kind, recipient_id, priority, title, body, action_url, created_by
    ) values (
      'personal', new.employee_id,
      case when new.status = 'approved' then 'normal' else 'important' end,
      case when new.status = 'approved' then 'Justificativa de horas analisada' else 'Justificativa de horas recusada' end,
      case when new.status = 'approved'
        then format('Foram abonadas %sh%s do déficit informado. O resultado da semana foi recalculado.',
          new.credited_minutes / 60, lpad((new.credited_minutes % 60)::text, 2, '0'))
        else 'A justificativa foi recusada e o déficit da semana foi mantido.' end,
      '/meu-rh', new.reviewed_by
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
      kind, audience, priority, title, body, action_url, created_by,
      source_type, source_id, required_permission
    ) values (
      'system', 'directors', 'urgent', 'Análise disciplinar urgente',
      'Um colaborador atingiu três advertências no ciclo e foi suspenso para análise.',
      '/rh?aba=discipline', new.triggered_by,
      'rh_disciplinary_review', new.id::text, 'hr.discipline.manage'
    );
  elsif tg_op = 'UPDATE' and old.status in ('pending', 'suspension_maintained') and new.status <> old.status then
    perform private.resolve_flow_notifications('rh_disciplinary_review', new.id::text, new.decided_by);
    if new.status <> 'pending' then
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
          when new.status = 'dismissed' then 'A análise disciplinar foi concluída com o desligamento do hospital.'
          else 'A análise disciplinar foi concluída e a suspensão foi mantida.'
        end,
        '/meu-rh', new.decided_by
      );
    end if;
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
  if tg_op = 'INSERT' and new.status in ('submitted', 'under_review', 'interview') then
    insert into public.notifications (
      kind, audience, priority, title, body, action_url,
      source_type, source_id, required_permission
    ) values (
      'system', 'directors', 'normal', 'Nova candidatura recebida',
      'Uma nova candidatura aguarda avaliação na fila de recrutamento.',
      '/rh?aba=candidaturas&selecionar=' || new.id::text,
      'recruitment_application', new.id::text, 'recruitment.manage'
    );
  elsif tg_op = 'UPDATE' and old.status in ('submitted', 'under_review', 'interview')
        and new.status in ('approved', 'rejected') then
    perform private.resolve_flow_notifications('recruitment_application', new.id::text, new.reviewed_by);
  end if;
  return new;
end;
$$;

drop trigger if exists notifications_recruitment_submission on public.recruitment_applications;
create trigger notifications_recruitment_submission
after insert or update on public.recruitment_applications
for each row execute function private.notify_recruitment_submission();

-- ---------------------------------------------------------------------------
-- Permissões específicas nas rotinas já existentes
-- ---------------------------------------------------------------------------

do $$
declare
  item record;
  function_definition text;
  patched_definition text;
begin
  for item in
    select * from (values
      ('review_hr_leave_request', 'hr.absences.review'),
      ('close_hr_week', 'hr.hours.manage'),
      ('finalize_hr_week_closure', 'hr.hours.manage'),
      ('reopen_hr_week_closure', 'hr.hours.manage'),
      ('record_hr_hour_snapshot', 'hr.hours.manage'),
      ('import_hr_hour_snapshots', 'hr.hours.manage'),
      ('review_hr_hour_justification', 'hr.justifications.review'),
      ('issue_hr_warning', 'hr.discipline.manage'),
      ('annul_hr_warning', 'hr.discipline.manage'),
      ('decide_hr_disciplinary_review', 'hr.discipline.manage'),
      ('publish_notification_announcement', 'communications.manage'),
      ('archive_notification_announcement', 'communications.manage')
    ) mapped(function_name, permission_code)
  loop
    select pg_get_functiondef(function.oid)
    into function_definition
    from pg_proc function
    join pg_namespace namespace on namespace.oid = function.pronamespace
    where namespace.nspname = 'public' and function.proname = item.function_name
    order by function.oid desc
    limit 1;
    if function_definition is null then
      raise exception 'Função % não encontrada durante a migração.', item.function_name;
    end if;
    patched_definition := replace(
      function_definition,
      'if not private.is_director_user(p_actor_id) then',
      format('if not (private.is_director_user(p_actor_id) or private.has_permission(p_actor_id, %L)) then', item.permission_code)
    );
    if patched_definition = function_definition then
      raise exception 'Guarda da função % não foi localizada.', item.function_name;
    end if;
    execute patched_definition;
  end loop;
end;
$$;

create or replace function public.decide_recruitment_application(
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
  if not private.has_permission(p_actor_id, 'recruitment.manage') then
    raise exception using errcode = '42501', message = 'Você não possui permissão para decidir candidaturas.';
  end if;
  if p_decision not in ('approved', 'rejected') then
    raise exception using errcode = '22023', message = 'Decisão inválida.';
  end if;
  if p_decision = 'rejected' then
    v_reason := btrim(coalesce(p_reason, ''));
    if char_length(v_reason) not between 10 and 2000 then
      raise exception using errcode = '22023', message = 'Informe um motivo de recusa entre 10 e 2000 caracteres.';
    end if;
  else
    v_reason := null;
  end if;
  update public.recruitment_applications
  set status = p_decision, review_notes = v_reason,
      reviewed_by = p_actor_id, reviewed_at = v_decided_at
  where id = p_application_id and status in ('submitted', 'under_review', 'interview');
  if not found then
    raise exception using errcode = 'P0002', message = 'Candidatura não encontrada ou já decidida.';
  end if;
  insert into public.recruitment_decisions (
    application_id, decision, reason, decided_by, decided_at
  ) values (
    p_application_id, p_decision, v_reason, p_actor_id, v_decided_at
  ) returning id into v_decision_id;
  return jsonb_build_object(
    'application_id', p_application_id, 'decision_id', v_decision_id,
    'decision', p_decision, 'reason', v_reason,
    'decided_by', p_actor_id, 'decided_at', v_decided_at
  );
end;
$$;

create or replace function public.update_catalog_pricing(
  p_service_id bigint,
  p_unit_price numeric,
  p_discounts jsonb
)
returns boolean
language plpgsql
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not private.has_permission((select auth.uid()), 'catalog.manage') then
    raise exception 'Você não possui permissão para alterar preços e descontos.';
  end if;
  if p_service_id is null or round(coalesce(p_unit_price, -1), 2) < 0 then
    raise exception 'Valor inválido.';
  end if;
  if p_discounts is null or jsonb_typeof(p_discounts) <> 'array' then
    raise exception 'Informe os descontos dos três planos.';
  end if;
  select count(*) into v_count
  from jsonb_to_recordset(p_discounts) as item(plan_code text, discount_percent numeric)
  join public.benefit_plans plan on plan.code = item.plan_code
  where item.discount_percent between 0 and 100;
  if v_count <> 3 or jsonb_array_length(p_discounts) <> 3 or exists (
    select 1 from jsonb_to_recordset(p_discounts) as item(plan_code text, discount_percent numeric)
    group by item.plan_code having count(*) <> 1
  ) then
    raise exception 'Os descontos dos três planos devem ser válidos e únicos.';
  end if;
  update public.service_catalog
  set unit_price = round(p_unit_price, 2), updated_by = (select auth.uid())
  where id = p_service_id;
  if not found then raise exception 'Item não localizado.'; end if;
  update public.plan_discounts discount
  set discount_percent = round(input.discount_percent, 2), updated_by = (select auth.uid())
  from jsonb_to_recordset(p_discounts) as input(plan_code text, discount_percent numeric)
  where discount.service_id = p_service_id and discount.plan_code = input.plan_code;
  return true;
end;
$$;

create or replace function public.cancel_attendance(p_attendance_id bigint)
returns boolean
language plpgsql
set search_path = ''
as $$
begin
  if not private.has_permission((select auth.uid()), 'attendances.manage') then
    raise exception 'Você não possui permissão para cancelar atendimentos.';
  end if;
  update public.attendances
  set status = 'cancelled', cancelled_by = (select auth.uid()), cancelled_at = now()
  where id = p_attendance_id and status = 'completed';
  return found;
end;
$$;

drop policy if exists attendances_cancel_director on public.attendances;
drop policy if exists attendances_read_own_or_director on public.attendances;
create policy attendances_cancel_authorized on public.attendances
for update to authenticated
using (private.has_permission((select auth.uid()), 'attendances.manage'))
with check (
  private.has_permission((select auth.uid()), 'attendances.manage')
  and status = 'cancelled' and cancelled_by = (select auth.uid()) and cancelled_at is not null
);
create policy attendances_read_own_or_authorized on public.attendances
for select to authenticated
using (
  private.is_active_user()
  and (performed_by = (select auth.uid()) or private.has_permission((select auth.uid()), 'attendances.manage'))
);

drop policy if exists attendance_items_read_visible_attendance on public.attendance_items;
create policy attendance_items_read_visible_attendance on public.attendance_items
for select to authenticated
using (
  private.is_active_user()
  and exists (
    select 1 from public.attendances
    where attendances.id = attendance_items.attendance_id
      and (attendances.performed_by = (select auth.uid()) or private.has_permission((select auth.uid()), 'attendances.manage'))
  )
);

-- ---------------------------------------------------------------------------
-- RLS, auditoria e privilégios
-- ---------------------------------------------------------------------------

create or replace function private.audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid;
  actor_code text;
  row_id text;
  row_values jsonb;
begin
  actor_id := auth.uid();
  row_values := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  if actor_id is null then
    actor_id := coalesce(
      nullif(row_values ->> 'updated_by', '')::uuid,
      nullif(row_values ->> 'reviewed_by', '')::uuid,
      nullif(row_values ->> 'cancelled_by', '')::uuid,
      nullif(row_values ->> 'annulled_by', '')::uuid,
      nullif(row_values ->> 'decided_by', '')::uuid,
      nullif(row_values ->> 'closed_by', '')::uuid,
      nullif(row_values ->> 'issued_by', '')::uuid,
      nullif(row_values ->> 'triggered_by', '')::uuid,
      nullif(row_values ->> 'approved_by', '')::uuid,
      nullif(row_values ->> 'started_by', '')::uuid,
      nullif(row_values ->> 'reopened_by', '')::uuid,
      nullif(row_values ->> 'revoked_by', '')::uuid,
      nullif(row_values ->> 'granted_by', '')::uuid,
      nullif(row_values ->> 'created_by', '')::uuid,
      nullif(row_values ->> 'performed_by', '')::uuid,
      nullif(row_values ->> 'password_reset_by', '')::uuid,
      nullif(row_values ->> 'employee_id', '')::uuid
    );
  end if;
  select passport into actor_code from public.profiles where user_id = actor_id;
  row_id := coalesce(
    row_values ->> 'id',
    row_values ->> 'key',
    row_values ->> 'user_id',
    concat_ws(':', row_values ->> 'position_id', row_values ->> 'permission_code')
  );
  insert into public.audit_logs (
    actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values
  ) values (
    actor_id, actor_code, tg_op, tg_table_name, row_id,
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) else null end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) else null end
  );
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger staff_positions_touch_updated_at
before update on public.staff_positions
for each row execute function private.touch_updated_at();

create trigger staff_positions_audit
after insert or update or delete on public.staff_positions
for each row execute function private.audit_row_change();
create trigger staff_position_permissions_audit
after insert or update or delete on public.staff_position_permissions
for each row execute function private.audit_row_change();
create trigger user_permission_grants_audit
after insert or update or delete on public.user_permission_grants
for each row execute function private.audit_row_change();

alter table public.staff_positions enable row level security;
alter table public.staff_positions force row level security;
alter table public.system_permissions enable row level security;
alter table public.system_permissions force row level security;
alter table public.staff_position_permissions enable row level security;
alter table public.staff_position_permissions force row level security;
alter table public.user_permission_grants enable row level security;
alter table public.user_permission_grants force row level security;

create policy staff_positions_read_active_or_manager
on public.staff_positions for select to authenticated
using (active or private.has_permission((select auth.uid()), 'access.manage'));
create policy system_permissions_read_authenticated
on public.system_permissions for select to authenticated
using ((select auth.uid()) is not null and (select private.is_active_user()));
create policy staff_position_permissions_read_manager
on public.staff_position_permissions for select to authenticated
using (private.has_permission((select auth.uid()), 'access.manage'));
create policy user_permission_grants_read_own_or_manager
on public.user_permission_grants for select to authenticated
using (
  user_id = (select auth.uid())
  or private.has_permission((select auth.uid()), 'access.manage')
);

revoke all on public.staff_positions from public, anon, authenticated, service_role;
revoke all on public.system_permissions from public, anon, authenticated, service_role;
revoke all on public.staff_position_permissions from public, anon, authenticated, service_role;
revoke all on public.user_permission_grants from public, anon, authenticated, service_role;
grant select on public.staff_positions to authenticated, service_role;
grant select on public.system_permissions to authenticated, service_role;
grant select on public.staff_position_permissions to authenticated, service_role;
grant select on public.user_permission_grants to authenticated, service_role;
grant insert, update, delete on public.staff_positions to service_role;
grant insert, update, delete on public.staff_position_permissions to service_role;
grant insert, update on public.user_permission_grants to service_role;
grant usage, select on sequence public.staff_positions_id_seq to service_role;
grant usage, select on sequence public.user_permission_grants_id_seq to service_role;

revoke all on function private.has_permission(uuid, text) from public, anon, authenticated, service_role;
revoke all on function private.has_any_management_permission(uuid) from public, anon, authenticated, service_role;
revoke all on function private.resolve_flow_notifications(text, text, uuid) from public, anon, authenticated, service_role;
revoke all on function public.create_staff_position(text, text, uuid) from public, anon, authenticated, service_role;
revoke all on function public.update_staff_position(bigint, text, boolean, uuid) from public, anon, authenticated, service_role;
revoke all on function public.set_staff_position_permissions(bigint, jsonb, uuid) from public, anon, authenticated, service_role;
revoke all on function public.grant_temporary_permission(uuid, text, timestamptz, timestamptz, text, uuid) from public, anon, authenticated, service_role;
revoke all on function public.revoke_temporary_permission(bigint, text, uuid) from public, anon, authenticated, service_role;
grant execute on function private.has_permission(uuid, text) to service_role;
grant execute on function private.has_any_management_permission(uuid) to service_role;
grant execute on function public.create_staff_position(text, text, uuid) to service_role;
grant execute on function public.update_staff_position(bigint, text, boolean, uuid) to service_role;
grant execute on function public.set_staff_position_permissions(bigint, jsonb, uuid) to service_role;
grant execute on function public.grant_temporary_permission(uuid, text, timestamptz, timestamptz, text, uuid) to service_role;
grant execute on function public.revoke_temporary_permission(bigint, text, uuid) to service_role;

comment on table public.staff_positions is 'Cargos organizacionais da equipe, independentes do nível de acesso legado.';
comment on table public.system_permissions is 'Catálogo fechado de capacidades administrativas do HPSM.';
comment on table public.staff_position_permissions is 'Permissões permanentes herdadas pelo cargo ativo do profissional.';
comment on table public.user_permission_grants is 'Concessões individuais temporárias com validade, revogação e auditoria.';

notify pgrst, 'reload schema';
