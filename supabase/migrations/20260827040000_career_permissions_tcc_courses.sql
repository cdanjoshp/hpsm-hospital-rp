-- HPSM · cargos oficiais, progressão, permissões granulares, TCC e cursos.
-- Migração aditiva: reutiliza staff_positions, system_permissions,
-- user_permission_grants, profiles, rh_warnings, notifications e audit_logs.

-- ---------------------------------------------------------------------------
-- Cargos oficiais e separação definitiva entre cargo e autorização
-- ---------------------------------------------------------------------------

alter table public.staff_positions
  add column level smallint,
  add column advancement_mode text,
  add column official boolean not null default false;

alter table public.staff_positions
  add constraint staff_positions_level_check check (level between 1 and 14),
  add constraint staff_positions_advancement_mode_check check (
    advancement_mode in ('progression', 'appointment', 'succession')
  );

create unique index staff_positions_level_unique_idx
  on public.staff_positions (level)
  where level is not null;

with actor as (
  select user_id from public.profiles
  where role_code = 'diretor_geral'
  order by created_at
  limit 1
), official_positions(code, name, level, advancement_mode) as (
  values
    ('estagiario_enfermagem', 'Estagiário de Enfermagem', 1, 'progression'),
    ('socorrista', 'Socorrista', 2, 'progression'),
    ('enfermeiro', 'Enfermeiro', 3, 'progression'),
    ('residente_i', 'Residente I', 4, 'progression'),
    ('medico_junior', 'Médico Júnior', 5, 'progression'),
    ('medico', 'Médico', 6, 'progression'),
    ('medico_pleno', 'Médico Pleno', 7, 'progression'),
    ('medico_senior', 'Médico Sênior', 8, 'progression'),
    ('especialista', 'Especialista', 9, 'progression'),
    ('especialista_senior', 'Especialista Sênior', 10, 'progression'),
    ('supervisor_clinico', 'Supervisor Clínico', 11, 'appointment'),
    ('coordenador_clinico', 'Coordenador Clínico', 12, 'appointment'),
    ('diretor_clinico', 'Diretor Clínico', 13, 'appointment'),
    ('diretor_geral', 'Diretor Geral', 14, 'succession')
)
insert into public.staff_positions (
  code, name, level, advancement_mode, official, active, sort_order, created_by, updated_by
)
select position.code, position.name, position.level, position.advancement_mode,
       true, true, position.level * 10, actor.user_id, actor.user_id
from official_positions position cross join actor
on conflict (code) do update set
  name = excluded.name,
  level = excluded.level,
  advancement_mode = excluded.advancement_mode,
  official = true,
  active = true,
  sort_order = excluded.sort_order,
  updated_by = excluded.updated_by,
  updated_at = now();

alter table public.staff_positions
  alter column level set not null,
  alter column advancement_mode set not null;

-- O único Diretor Geral já existente recebe o cargo 14. Nenhum outro perfil é
-- reclassificado automaticamente para evitar atribuições incorretas.
update public.profiles profile
set position_id = position.id,
    updated_at = now()
from public.staff_positions position
where profile.role_code = 'diretor_geral'
  and position.level = 14
  and profile.position_id is distinct from position.id;

-- Catálogo granular. Os códigos amplos existentes permanecem apenas para
-- compatibilidade de funções antigas durante a migração das rotas.
insert into public.system_permissions (code, module, label, description, sort_order) values
  ('profile.self.view', 'Pessoal', 'Visualizar os próprios dados', 'Consulta os dados básicos do próprio perfil.', 1),
  ('hr.self.view', 'RH', 'Visualizar o próprio RH', 'Consulta horas, afastamentos, advertências, progressão, TCC e cursos próprios.', 2),
  ('patients.view', 'Operação', 'Acessar pacientes', 'Consulta o cadastro de pacientes necessário ao atendimento.', 3),
  ('catalog.view', 'Operação', 'Acessar catálogo', 'Consulta procedimentos, valores e benefícios ativos.', 4),
  ('attendances.create', 'Operação', 'Registrar atendimentos', 'Registra procedimentos e vendas realizados pelo próprio profissional.', 5),
  ('operations.full', 'Operação', 'Acesso operacional completo', 'Pacote operacional para o corpo clínico, sem administração sensível.', 6),
  ('clinical.advanced', 'Clínico', 'Recursos clínicos avançados', 'Reserva o acesso aos recursos clínicos avançados quando forem disponibilizados.', 7),
  ('hr.team.view', 'RH', 'Visualizar RH da equipe', 'Consulta dados funcionais da equipe sem alterar decisões.', 31),
  ('hr.hours.import', 'RH', 'Importar horas em lote', 'Importa leituras acumuladas e valida a prévia por passaporte.', 32),
  ('hr.weeks.close', 'RH', 'Executar fechamento semanal', 'Apura e confirma o fechamento semanal da equipe.', 33),
  ('hr.weeks.reopen', 'RH', 'Reabrir semana fechada', 'Reabre fechamento mediante motivo e auditoria.', 34),
  ('hr.warnings.issue', 'RH', 'Emitir advertências', 'Aplica advertências manuais ou decorrentes de fechamento.', 35),
  ('hr.warnings.annul', 'RH', 'Anular advertências', 'Anula advertências e recalcula o estado disciplinar.', 36),
  ('hr.warnings.progression', 'RH', 'Sinalizar impacto na progressão', 'Define se uma advertência ativa aumenta o prazo de promoção.', 37),
  ('hr.discipline.review', 'RH', 'Analisar suspensões', 'Analisa pendências disciplinares e desligamentos.', 38),
  ('admin.pending.manage', 'Administrativo', 'Gerenciar pendências', 'Consulta e encaminha pendências administrativas.', 39),
  ('progression.review', 'Carreira', 'Analisar promoções', 'Analisa elegibilidade e efetiva uma promoção por vez.', 40),
  ('appointments.manage', 'Carreira', 'Realizar nomeações', 'Nomeia cargos de gestão conforme a hierarquia autorizada.', 41),
  ('succession.manage', 'Carreira', 'Realizar sucessão', 'Transfere o cargo único de Diretor Geral com histórico.', 42),
  ('tcc.submit', 'Formação', 'Enviar TCC', 'Permite ao Residente I enviar o próprio trabalho.', 43),
  ('tcc.vote', 'Formação', 'Votar em TCC', 'Registra voto individual de aprovação ou reprovação.', 44),
  ('courses.view', 'Formação', 'Visualizar cursos', 'Consulta cursos vinculados ao próprio perfil.', 45),
  ('courses.manage', 'Formação', 'Gerenciar cursos', 'Cria, edita, ativa e inativa cursos.', 46),
  ('courses.completions.manage', 'Formação', 'Registrar conclusões de cursos', 'Vincula cursos e registra conclusão por colaborador.', 47),
  ('team.dismiss', 'Acessos', 'Desligar colaboradores', 'Marca o colaborador como inativo após decisão autorizada.', 48),
  ('access.grants.manage', 'Acessos', 'Gerenciar exceções individuais', 'Concede e revoga permissões permanentes ou temporárias.', 49),
  ('institutional.timeline.view', 'Administrativo', 'Acessar timeline institucional', 'Reserva acesso à timeline institucional avançada.', 50),
  ('admin.advanced', 'Administrativo', 'Acessar administração avançada', 'Reserva acesso a rotinas administrativas sensíveis.', 51),
  ('settings.critical', 'Segurança', 'Alterar configurações críticas', 'Permite administrar configurações críticas do sistema.', 52)
on conflict (code) do update set
  module = excluded.module,
  label = excluded.label,
  description = excluded.description,
  sort_order = excluded.sort_order;

-- Matriz padrão cumulativa dos 14 cargos. Ela é configurável pela função já
-- existente e serve como valor inicial, não como regra fixa no frontend.
with actor as (
  select user_id from public.profiles where role_code = 'diretor_geral' limit 1
), grants(permission_code, min_level) as (
  values
    ('profile.self.view', 1), ('hr.self.view', 1), ('patients.view', 1),
    ('catalog.view', 1), ('attendances.create', 1), ('courses.view', 1),
    ('operations.full', 5), ('clinical.advanced', 8),
    ('hr.team.view', 11), ('hr.absences.review', 11),
    ('hr.justifications.review', 11), ('hr.warnings.issue', 11),
    ('hr.warnings.progression', 11), ('courses.manage', 11),
    ('courses.completions.manage', 11), ('tcc.vote', 11),
    ('progression.review', 11),
    ('hr.hours.import', 12), ('hr.weeks.close', 12),
    ('recruitment.manage', 12), ('admin.pending.manage', 12),
    ('hr.reports.view', 12),
    ('hr.weeks.reopen', 13), ('hr.warnings.annul', 13),
    ('hr.discipline.review', 13), ('team.dismiss', 13),
    ('appointments.manage', 13), ('institutional.timeline.view', 13),
    ('admin.advanced', 13), ('team.manage', 13),
    ('communications.manage', 13), ('catalog.manage', 13),
    ('attendances.manage', 13),
    ('access.manage', 14), ('access.grants.manage', 14),
    ('audit.view', 14), ('settings.critical', 14),
    ('succession.manage', 14),
    ('hr.hours.manage', 14), ('hr.discipline.manage', 14)
)
insert into public.staff_position_permissions (position_id, permission_code, granted_by)
select position.id, grant_row.permission_code, actor.user_id
from public.staff_positions position
join grants grant_row on position.level >= grant_row.min_level
cross join actor
where position.official
on conflict (position_id, permission_code) do nothing;

-- TCC é uma capacidade própria do Residente I, não um pacote de todos os
-- cargos inferiores.
with actor as (
  select user_id from public.profiles where role_code = 'diretor_geral' limit 1
)
insert into public.staff_position_permissions (position_id, permission_code, granted_by)
select position.id, 'tcc.submit', actor.user_id
from public.staff_positions position cross join actor
where position.level = 4
on conflict (position_id, permission_code) do nothing;

-- O Diretor Geral herda o catálogo inteiro. As validações operacionais (como
-- envio de TCC apenas no nível 4) continuam sendo aplicadas pelas próprias ações.
with actor as (
  select user_id from public.profiles where role_code = 'diretor_geral' limit 1
)
insert into public.staff_position_permissions (position_id, permission_code, granted_by)
select position.id, permission.code, actor.user_id
from public.staff_positions position
cross join public.system_permissions permission
cross join actor
where position.level = 14
on conflict (position_id, permission_code) do nothing;

-- ---------------------------------------------------------------------------
-- Permissões individuais permanentes e temporárias
-- ---------------------------------------------------------------------------

alter table public.user_permission_grants
  add column grant_kind text not null default 'temporary';

alter table public.user_permission_grants
  alter column expires_at drop not null,
  alter column reason drop not null,
  drop constraint user_permission_grants_window_check,
  drop constraint user_permission_grants_reason_check;

alter table public.user_permission_grants
  add constraint user_permission_grants_kind_check check (grant_kind in ('individual', 'temporary')),
  add constraint user_permission_grants_window_check check (
    (grant_kind = 'individual' and expires_at is null)
    or
    (grant_kind = 'temporary' and expires_at is not null and expires_at > valid_from)
  ),
  add constraint user_permission_grants_reason_check check (
    reason is null or char_length(btrim(reason)) between 2 and 1000
  );

drop index user_permission_grants_user_active_idx;
drop index user_permission_grants_permission_active_idx;
create index user_permission_grants_user_active_idx
  on public.user_permission_grants (user_id, permission_code, valid_from, expires_at)
  where revoked_at is null;
create index user_permission_grants_permission_active_idx
  on public.user_permission_grants (permission_code, user_id, valid_from, expires_at)
  where revoked_at is null;

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
        exists (
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
            and (permission_grant.expires_at is null or permission_grant.expires_at > now())
        )
      )
  );
$$;

create or replace function private.current_position_level(p_user_id uuid)
returns smallint
language sql
stable
security definer
set search_path = ''
as $$
  select position.level
  from public.profiles profile
  join public.staff_positions position on position.id = profile.position_id
  where profile.user_id = p_user_id and profile.status <> 'inactive' and position.active;
$$;

-- As rotinas de RH existentes passam a consultar capacidades específicas.
-- O corpo de cálculo permanece único e reaproveitado; somente a guarda muda.
do $$
declare
  item record;
  function_definition text;
  patched_definition text;
begin
  for item in
    select * from (values
      ('review_hr_leave_request', 'hr.absences.review', 'hr.absences.review'),
      ('close_hr_week', 'hr.hours.manage', 'hr.weeks.close'),
      ('finalize_hr_week_closure', 'hr.hours.manage', 'hr.weeks.close'),
      ('reopen_hr_week_closure', 'hr.hours.manage', 'hr.weeks.reopen'),
      ('record_hr_hour_snapshot', 'hr.hours.manage', 'hr.hours.import'),
      ('import_hr_hour_snapshots', 'hr.hours.manage', 'hr.hours.import'),
      ('review_hr_hour_justification', 'hr.justifications.review', 'hr.justifications.review'),
      ('issue_hr_warning', 'hr.discipline.manage', 'hr.warnings.issue'),
      ('annul_hr_warning', 'hr.discipline.manage', 'hr.warnings.annul'),
      ('decide_hr_disciplinary_review', 'hr.discipline.manage', 'hr.discipline.review')
    ) mapped(function_name, old_permission, new_permission)
  loop
    select pg_get_functiondef(function.oid) into function_definition
    from pg_proc function
    join pg_namespace namespace on namespace.oid = function.pronamespace
    where namespace.nspname = 'public' and function.proname = item.function_name
    order by function.oid desc limit 1;
    patched_definition := replace(
      function_definition,
      format('if not (private.is_director_user(p_actor_id) or private.has_permission(p_actor_id, %L)) then', item.old_permission),
      format('if not private.has_permission(p_actor_id, %L) then', item.new_permission)
    );
    if patched_definition = function_definition then
      raise exception 'Guarda granular da função % não foi localizada.', item.function_name;
    end if;
    execute patched_definition;
  end loop;
end;
$$;

create or replace function public.grant_user_permission(
  p_user_id uuid,
  p_permission_code text,
  p_grant_kind text,
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
  if not private.has_permission(p_actor_id, 'access.grants.manage') then
    raise exception using errcode = '42501', message = 'Você não possui permissão para conceder acessos.';
  end if;
  if p_user_id = p_actor_id then
    raise exception using errcode = '42501', message = 'Você não pode conceder uma permissão para si próprio.';
  end if;
  if not exists (select 1 from public.profiles where user_id = p_user_id and status <> 'inactive')
     or not exists (select 1 from public.system_permissions where code = p_permission_code)
     or p_permission_code in ('access.manage', 'access.grants.manage', 'succession.manage', 'settings.critical')
     or p_grant_kind not in ('individual', 'temporary')
     or (p_grant_kind = 'individual' and p_expires_at is not null)
     or (p_grant_kind = 'temporary' and (
       p_expires_at is null or p_expires_at <= v_start or p_expires_at > v_start + interval '180 days'
     ))
     or (p_reason is not null and char_length(btrim(p_reason)) not between 2 and 1000) then
    raise exception using errcode = '22023', message = 'Confira o profissional, a permissão e a validade.';
  end if;
  if exists (
    select 1 from public.user_permission_grants grant_row
    where grant_row.user_id = p_user_id
      and grant_row.permission_code = p_permission_code
      and grant_row.revoked_at is null
      and grant_row.valid_from <= coalesce(p_expires_at, 'infinity'::timestamptz)
      and coalesce(grant_row.expires_at, 'infinity'::timestamptz) > v_start
  ) then
    raise exception using errcode = '23505', message = 'Já existe uma concessão ativa ou sobreposta para esta permissão.';
  end if;
  insert into public.user_permission_grants (
    user_id, permission_code, grant_kind, valid_from, expires_at, reason, granted_by
  ) values (
    p_user_id, p_permission_code, p_grant_kind, v_start,
    case when p_grant_kind = 'temporary' then p_expires_at else null end,
    nullif(btrim(coalesce(p_reason, '')), ''), p_actor_id
  ) returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

create or replace function public.grant_temporary_permission(
  p_user_id uuid,
  p_permission_code text,
  p_valid_from timestamptz,
  p_expires_at timestamptz,
  p_reason text,
  p_actor_id uuid
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select public.grant_user_permission(
    p_user_id, p_permission_code, 'temporary', p_valid_from,
    p_expires_at, p_reason, p_actor_id
  );
$$;

create or replace function public.revoke_temporary_permission(
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
  if not private.has_permission(p_actor_id, 'access.grants.manage') then
    raise exception using errcode = '42501', message = 'Você não possui permissão para revogar acessos.';
  end if;
  if char_length(btrim(coalesce(p_reason, ''))) not between 10 and 1000 then
    raise exception using errcode = '22023', message = 'Informe o motivo da revogação.';
  end if;
  update public.user_permission_grants
  set revoked_at = now(), revoked_by = p_actor_id, revoked_reason = btrim(p_reason)
  where id = p_grant_id
    and revoked_at is null
    and (expires_at is null or expires_at > now())
  returning * into v_row;
  if not found then
    raise exception using errcode = 'P0002', message = 'Permissão não encontrada ou já encerrada.';
  end if;
  return to_jsonb(v_row);
end;
$$;

-- ---------------------------------------------------------------------------
-- Histórico de cargos e progressão manual
-- ---------------------------------------------------------------------------

create table public.staff_position_history (
  id bigint generated always as identity primary key,
  employee_id uuid not null references public.profiles(user_id) on delete restrict,
  from_position_id bigint references public.staff_positions(id) on delete restrict,
  to_position_id bigint not null references public.staff_positions(id) on delete restrict,
  event_type text not null,
  decided_by uuid not null references public.profiles(user_id) on delete restrict,
  effective_at timestamptz not null default now(),
  note text,
  created_at timestamptz not null default now(),
  constraint staff_position_history_event_check check (
    event_type in ('initial_assignment', 'promotion', 'appointment', 'succession')
  ),
  constraint staff_position_history_note_check check (
    note is null or char_length(btrim(note)) between 2 and 2000
  ),
  constraint staff_position_history_change_check check (
    from_position_id is null or from_position_id <> to_position_id
  )
);

create index staff_position_history_employee_idx
  on public.staff_position_history (employee_id, effective_at desc);
create index staff_position_history_decided_by_idx
  on public.staff_position_history (decided_by, effective_at desc);
create index staff_position_history_from_position_idx
  on public.staff_position_history (from_position_id) where from_position_id is not null;
create index staff_position_history_to_position_idx
  on public.staff_position_history (to_position_id);

insert into public.staff_position_history (
  employee_id, from_position_id, to_position_id, event_type, decided_by, effective_at, note
)
select profile.user_id, null, profile.position_id, 'initial_assignment', profile.user_id,
       profile.created_at, 'Cargo oficial inicial preservado na implantação.'
from public.profiles profile
where profile.position_id is not null
  and not exists (
    select 1 from public.staff_position_history history where history.employee_id = profile.user_id
  );

create table public.staff_position_transition_rules (
  id bigint generated always as identity primary key,
  from_position_id bigint not null references public.staff_positions(id) on delete restrict,
  to_position_id bigint not null references public.staff_positions(id) on delete restrict,
  transition_type text not null,
  min_days smallint not null default 15,
  min_worked_minutes integer not null default 1800,
  min_attendances smallint not null default 3,
  requires_tcc boolean not null default false,
  active boolean not null default true,
  updated_by uuid not null references public.profiles(user_id) on delete restrict,
  updated_at timestamptz not null default now(),
  constraint staff_position_transition_rules_unique unique (from_position_id, to_position_id),
  constraint staff_position_transition_rules_type_check check (transition_type in ('progression', 'appointment', 'succession')),
  constraint staff_position_transition_rules_minimums_check check (
    min_days between 0 and 3650 and min_worked_minutes between 0 and 1000000 and min_attendances between 0 and 10000
  )
);

with actor as (
  select user_id from public.profiles where role_code = 'diretor_geral' limit 1
)
insert into public.staff_position_transition_rules (
  from_position_id, to_position_id, transition_type, min_days,
  min_worked_minutes, min_attendances, requires_tcc, updated_by
)
select current_position.id, next_position.id,
       case
         when next_position.level <= 10 then 'progression'
         when next_position.level = 14 then 'succession'
         else 'appointment'
       end,
       case when next_position.level <= 10 then 15 else 0 end,
       case when next_position.level <= 10 then 1800 else 0 end,
       case when next_position.level <= 10 then 3 else 0 end,
       current_position.level = 4,
       actor.user_id
from public.staff_positions current_position
join public.staff_positions next_position on next_position.level = current_position.level + 1
cross join actor
where current_position.official and next_position.official;

create table public.staff_promotion_reviews (
  id bigint generated always as identity primary key,
  employee_id uuid not null references public.profiles(user_id) on delete restrict,
  from_position_id bigint not null references public.staff_positions(id) on delete restrict,
  to_position_id bigint not null references public.staff_positions(id) on delete restrict,
  status text not null default 'pending',
  required_days smallint not null,
  elapsed_days integer not null,
  worked_minutes integer not null,
  attendance_count integer not null,
  flagged_warning_count integer not null,
  tcc_approved boolean not null,
  created_at timestamptz not null default now(),
  decided_by uuid references public.profiles(user_id) on delete restrict,
  decided_at timestamptz,
  decision_note text,
  updated_at timestamptz not null default now(),
  constraint staff_promotion_reviews_status_check check (status in ('pending', 'promoted', 'deferred', 'cancelled')),
  constraint staff_promotion_reviews_metrics_check check (
    required_days >= 0 and elapsed_days >= 0 and worked_minutes >= 0
    and attendance_count >= 0 and flagged_warning_count >= 0
  ),
  constraint staff_promotion_reviews_decision_check check (
    (status = 'pending' and decided_by is null and decided_at is null and decision_note is null)
    or
    (status <> 'pending' and decided_by is not null and decided_at is not null)
  ),
  constraint staff_promotion_reviews_note_check check (
    decision_note is null or char_length(btrim(decision_note)) between 2 and 2000
  )
);

create unique index staff_promotion_reviews_pending_employee_idx
  on public.staff_promotion_reviews (employee_id) where status = 'pending';
create index staff_promotion_reviews_status_idx
  on public.staff_promotion_reviews (status, created_at desc);
create index staff_promotion_reviews_from_position_idx on public.staff_promotion_reviews (from_position_id);
create index staff_promotion_reviews_to_position_idx on public.staff_promotion_reviews (to_position_id);
create index staff_promotion_reviews_decided_by_idx
  on public.staff_promotion_reviews (decided_by) where decided_by is not null;

alter table public.rh_warnings
  add column impacts_progression boolean not null default false,
  add column progression_flagged_by uuid references public.profiles(user_id) on delete restrict,
  add column progression_flagged_at timestamptz,
  add column progression_impact_note text;

alter table public.rh_warnings
  add constraint rh_warnings_progression_state_check check (
    (not impacts_progression and progression_flagged_by is null and progression_flagged_at is null and progression_impact_note is null)
    or
    (impacts_progression and progression_flagged_by is not null and progression_flagged_at is not null)
  ),
  add constraint rh_warnings_progression_note_check check (
    progression_impact_note is null or char_length(btrim(progression_impact_note)) between 2 and 1000
  );

create index rh_warnings_progression_idx
  on public.rh_warnings (employee_id, issued_at desc)
  where status = 'active' and impacts_progression;
create index rh_warnings_progression_flagged_by_idx
  on public.rh_warnings (progression_flagged_by) where progression_flagged_by is not null;

-- ---------------------------------------------------------------------------
-- Estrutura flexível de TCC e cursos
-- ---------------------------------------------------------------------------

create table public.tcc_submissions (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.profiles(user_id) on delete restrict,
  title text not null,
  storage_path text not null unique,
  original_filename text not null,
  mime_type text not null,
  size_bytes bigint not null,
  status text not null default 'submitted',
  submitted_at timestamptz not null default now(),
  approved_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint tcc_submissions_title_check check (char_length(btrim(title)) between 3 and 180),
  constraint tcc_submissions_filename_check check (char_length(btrim(original_filename)) between 1 and 240),
  constraint tcc_submissions_path_check check (char_length(btrim(storage_path)) between 10 and 500),
  constraint tcc_submissions_size_check check (size_bytes between 1 and 26214400),
  constraint tcc_submissions_status_check check (status in ('submitted', 'approved', 'withdrawn')),
  constraint tcc_submissions_approval_check check (
    (status = 'approved' and approved_at is not null)
    or
    (status <> 'approved' and approved_at is null)
  )
);

create unique index tcc_submissions_open_employee_idx
  on public.tcc_submissions (employee_id) where status in ('submitted', 'approved');
create index tcc_submissions_status_idx on public.tcc_submissions (status, submitted_at desc);

create table public.tcc_votes (
  id bigint generated always as identity primary key,
  submission_id uuid not null references public.tcc_submissions(id) on delete restrict,
  vote text not null,
  voted_by uuid not null references public.profiles(user_id) on delete restrict,
  voted_at timestamptz not null default now(),
  constraint tcc_votes_unique unique (submission_id, voted_by),
  constraint tcc_votes_value_check check (vote in ('approve', 'reject'))
);

create index tcc_votes_voted_by_idx on public.tcc_votes (voted_by, voted_at desc);

create table public.courses (
  id bigint generated always as identity primary key,
  name text not null,
  description text not null default '',
  active boolean not null default true,
  created_by uuid not null references public.profiles(user_id) on delete restrict,
  updated_by uuid not null references public.profiles(user_id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint courses_name_check check (char_length(btrim(name)) between 2 and 120),
  constraint courses_description_check check (char_length(description) <= 4000)
);

create unique index courses_name_unique_idx on public.courses (lower(btrim(name)));
create index courses_active_name_idx on public.courses (active, name);
create index courses_created_by_idx on public.courses (created_by);
create index courses_updated_by_idx on public.courses (updated_by);

create table public.staff_course_records (
  id bigint generated always as identity primary key,
  course_id bigint not null references public.courses(id) on delete restrict,
  employee_id uuid not null references public.profiles(user_id) on delete restrict,
  status text not null default 'pending',
  assigned_by uuid not null references public.profiles(user_id) on delete restrict,
  assigned_at timestamptz not null default now(),
  completed_by uuid references public.profiles(user_id) on delete restrict,
  completed_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint staff_course_records_unique unique (course_id, employee_id),
  constraint staff_course_records_status_check check (status in ('pending', 'completed')),
  constraint staff_course_records_completion_check check (
    (status = 'pending' and completed_by is null and completed_at is null)
    or
    (status = 'completed' and completed_by is not null and completed_at is not null)
  )
);

create index staff_course_records_employee_idx
  on public.staff_course_records (employee_id, status, assigned_at desc);
create index staff_course_records_assigned_by_idx on public.staff_course_records (assigned_by);
create index staff_course_records_completed_by_idx
  on public.staff_course_records (completed_by) where completed_by is not null;

-- O bucket é privado. O limite técnico é apenas de segurança operacional e não
-- define o futuro padrão acadêmico do TCC.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'tcc-documents', 'tcc-documents', false, 26214400,
  array[
    'application/pdf',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.oasis.opendocument.text'
  ]
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- ---------------------------------------------------------------------------
-- Regras centrais de carreira, TCC, cursos e nomeações
-- ---------------------------------------------------------------------------

create or replace function private.get_staff_progression_status(p_employee_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles;
  v_position public.staff_positions;
  v_next public.staff_positions;
  v_rule public.staff_position_transition_rules;
  v_since timestamptz;
  v_elapsed integer := 0;
  v_worked integer := 0;
  v_attendances integer := 0;
  v_warnings integer := 0;
  v_required_days integer := 15;
  v_tcc boolean := false;
  v_eligible boolean := false;
begin
  select * into v_profile from public.profiles where user_id = p_employee_id;
  if not found or v_profile.position_id is null then
    return jsonb_build_object('employee_id', p_employee_id, 'eligible', false, 'reason', 'Cargo não definido');
  end if;
  select * into v_position from public.staff_positions where id = v_profile.position_id;
  if v_position.level >= 10 then
    return jsonb_build_object(
      'employee_id', p_employee_id, 'position_id', v_position.id,
      'level', v_position.level, 'eligible', false,
      'reason', case when v_position.level = 10 then 'Próximo cargo depende de nomeação' else 'Cargo de gestão' end
    );
  end if;
  select * into v_next from public.staff_positions where level = v_position.level + 1 and active;
  select * into v_rule from public.staff_position_transition_rules
  where from_position_id = v_position.id and to_position_id = v_next.id and active;
  select coalesce(max(history.effective_at), v_profile.created_at) into v_since
  from public.staff_position_history history
  where history.employee_id = p_employee_id and history.to_position_id = v_position.id;
  v_elapsed := greatest(0, floor(extract(epoch from (now() - v_since)) / 86400)::integer);
  select coalesce(sum(record.worked_minutes), 0)::integer into v_worked
  from public.rh_weekly_records record
  where record.employee_id = p_employee_id
    and record.closure_status = 'closed'
    and record.week_start >= v_since::date;
  select count(*)::integer into v_attendances
  from public.attendances attendance
  where attendance.performed_by = p_employee_id
    and attendance.status = 'completed'
    and attendance.created_at >= v_since;
  select count(*)::integer into v_warnings
  from public.rh_warnings warning
  where warning.employee_id = p_employee_id
    and warning.status = 'active'
    and warning.impacts_progression
    and warning.issued_at >= v_since;
  v_required_days := case when v_warnings = 0 then v_rule.min_days when v_warnings = 1 then 30 else 60 end;
  select exists (
    select 1 from public.tcc_submissions submission
    where submission.employee_id = p_employee_id and submission.status = 'approved'
  ) into v_tcc;
  v_eligible := v_profile.status = 'active'
    and v_warnings < 3
    and v_elapsed >= v_required_days
    and v_worked >= v_rule.min_worked_minutes
    and v_attendances >= v_rule.min_attendances
    and (not v_rule.requires_tcc or v_tcc);
  return jsonb_build_object(
    'employee_id', p_employee_id,
    'position_id', v_position.id,
    'position_name', v_position.name,
    'level', v_position.level,
    'next_position_id', v_next.id,
    'next_position_name', v_next.name,
    'since', v_since,
    'elapsed_days', v_elapsed,
    'required_days', v_required_days,
    'worked_minutes', v_worked,
    'required_worked_minutes', v_rule.min_worked_minutes,
    'attendance_count', v_attendances,
    'required_attendances', v_rule.min_attendances,
    'flagged_warning_count', v_warnings,
    'requires_tcc', v_rule.requires_tcc,
    'tcc_approved', v_tcc,
    'eligible', v_eligible,
    'blocked', v_warnings >= 3 or v_profile.status <> 'active'
  );
end;
$$;

create or replace function private.ensure_staff_promotion_review(p_employee_id uuid)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status jsonb;
  v_id bigint;
begin
  v_status := private.get_staff_progression_status(p_employee_id);
  if coalesce((v_status ->> 'eligible')::boolean, false) is not true then return null; end if;
  select id into v_id from public.staff_promotion_reviews
  where employee_id = p_employee_id and status in ('pending', 'deferred')
  order by created_at desc limit 1;
  if v_id is not null then return v_id; end if;
  insert into public.staff_promotion_reviews (
    employee_id, from_position_id, to_position_id, required_days,
    elapsed_days, worked_minutes, attendance_count, flagged_warning_count, tcc_approved
  ) values (
    p_employee_id, (v_status ->> 'position_id')::bigint,
    (v_status ->> 'next_position_id')::bigint,
    (v_status ->> 'required_days')::smallint,
    (v_status ->> 'elapsed_days')::integer,
    (v_status ->> 'worked_minutes')::integer,
    (v_status ->> 'attendance_count')::integer,
    (v_status ->> 'flagged_warning_count')::integer,
    (v_status ->> 'tcc_approved')::boolean
  ) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.get_staff_progression_status(
  p_employee_id uuid,
  p_actor_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_actor_id <> p_employee_id
     and not private.has_permission(p_actor_id, 'progression.review')
     and not private.has_permission(p_actor_id, 'hr.team.view') then
    raise exception using errcode = '42501', message = 'Você não possui permissão para consultar esta progressão.';
  end if;
  return private.get_staff_progression_status(p_employee_id);
end;
$$;

create or replace function public.refresh_staff_promotion_reviews(p_actor_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile record;
  v_created integer := 0;
  v_before bigint;
  v_after bigint;
begin
  if not private.has_permission(p_actor_id, 'progression.review')
     or coalesce(private.current_position_level(p_actor_id), 0) < 11 then
    raise exception using errcode = '42501', message = 'Você não possui permissão para analisar progressões.';
  end if;
  for v_profile in
    select profile.user_id
    from public.profiles profile
    join public.staff_positions position on position.id = profile.position_id
    where profile.status = 'active' and position.level between 1 and 9
  loop
    select id into v_before from public.staff_promotion_reviews
    where employee_id = v_profile.user_id and status in ('pending', 'deferred')
    order by created_at desc limit 1;
    v_after := private.ensure_staff_promotion_review(v_profile.user_id);
    if v_before is null and v_after is not null then v_created := v_created + 1; end if;
  end loop;
  return jsonb_build_object('created', v_created);
end;
$$;

create or replace function public.decide_staff_promotion_review(
  p_review_id bigint,
  p_decision text,
  p_note text,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_review public.staff_promotion_reviews;
  v_status jsonb;
  v_row public.staff_promotion_reviews;
begin
  if not private.has_permission(p_actor_id, 'progression.review')
     or coalesce(private.current_position_level(p_actor_id), 0) < 11 then
    raise exception using errcode = '42501', message = 'Você não possui permissão para decidir promoções.';
  end if;
  if p_decision not in ('promoted', 'deferred')
     or (p_note is not null and char_length(btrim(p_note)) not between 2 and 2000) then
    raise exception using errcode = '22023', message = 'Decisão ou observação inválida.';
  end if;
  select * into v_review from public.staff_promotion_reviews where id = p_review_id for update;
  if not found or v_review.status not in ('pending', 'deferred')
     or (v_review.status = 'deferred' and p_decision = 'deferred') then
    raise exception using errcode = 'P0002', message = 'Análise de promoção não encontrada ou já decidida.';
  end if;
  if p_decision = 'promoted' then
    v_status := private.get_staff_progression_status(v_review.employee_id);
    if coalesce((v_status ->> 'eligible')::boolean, false) is not true
       or (v_status ->> 'position_id')::bigint <> v_review.from_position_id
       or (v_status ->> 'next_position_id')::bigint <> v_review.to_position_id then
      raise exception using errcode = '23514', message = 'O colaborador não atende mais aos requisitos da promoção.';
    end if;
    perform set_config('hpsm.position_change_authorized', 'true', true);
    update public.profiles
    set position_id = v_review.to_position_id, updated_by = p_actor_id, updated_at = now()
    where user_id = v_review.employee_id and position_id = v_review.from_position_id;
    if not found then
      raise exception using errcode = '40001', message = 'O cargo foi alterado durante a análise. Atualize a página.';
    end if;
    insert into public.staff_position_history (
      employee_id, from_position_id, to_position_id, event_type, decided_by, note
    ) values (
      v_review.employee_id, v_review.from_position_id, v_review.to_position_id,
      'promotion', p_actor_id, nullif(btrim(coalesce(p_note, '')), '')
    );
  end if;
  update public.staff_promotion_reviews
  set status = p_decision, decided_by = p_actor_id, decided_at = now(),
      decision_note = nullif(btrim(coalesce(p_note, '')), ''), updated_at = now()
  where id = p_review_id
  returning * into v_row;
  perform private.resolve_flow_notifications('staff_promotion_review', p_review_id::text, p_actor_id);
  insert into public.notifications (
    kind, recipient_id, priority, title, body, action_url, created_by
  ) values (
    'personal', v_review.employee_id,
    case when p_decision = 'promoted' then 'important' else 'normal' end,
    case when p_decision = 'promoted' then 'Promoção registrada' else 'Promoção mantida em análise' end,
    case when p_decision = 'promoted'
      then 'Seu novo cargo foi registrado. Consulte seu histórico no Meu RH.'
      else 'A análise foi concluída sem promoção neste momento. Sua elegibilidade continua visível.' end,
    '/meu-rh', p_actor_id
  );
  return to_jsonb(v_row);
end;
$$;

create or replace function public.appoint_staff_position(
  p_employee_id uuid,
  p_to_position_id bigint,
  p_note text,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_level smallint;
  v_employee public.profiles;
  v_from public.staff_positions;
  v_to public.staff_positions;
  v_old_general uuid;
  v_level_13_id bigint;
  v_history public.staff_position_history;
begin
  v_actor_level := private.current_position_level(p_actor_id);
  select * into v_employee from public.profiles where user_id = p_employee_id for update;
  select * into v_from from public.staff_positions where id = v_employee.position_id;
  select * into v_to from public.staff_positions where id = p_to_position_id and active;
  if not found or v_employee.status = 'inactive' or v_from.level + 1 <> v_to.level or v_to.level < 11 then
    raise exception using errcode = '22023', message = 'A nomeação deve avançar somente um cargo na hierarquia.';
  end if;
  if char_length(btrim(coalesce(p_note, ''))) not between 10 and 2000 then
    raise exception using errcode = '22023', message = 'Informe a fundamentação da nomeação.';
  end if;
  if v_to.level in (11, 12) and not (
      private.has_permission(p_actor_id, 'appointments.manage') and v_actor_level >= 13
    ) then
    raise exception using errcode = '42501', message = 'Somente os níveis 13 e 14 podem realizar esta nomeação.';
  elsif v_to.level = 13 and not (
      private.has_permission(p_actor_id, 'appointments.manage') and v_actor_level = 14
    ) then
    raise exception using errcode = '42501', message = 'Somente o Diretor Geral pode nomear o Diretor Clínico.';
  elsif v_to.level = 14 then
    if not (private.has_permission(p_actor_id, 'succession.manage') and v_actor_level = 14 and p_actor_id <> p_employee_id) then
      raise exception using errcode = '42501', message = 'A sucessão é exclusiva do Diretor Geral e exige outro Diretor Clínico.';
    end if;
    select user_id into v_old_general from public.profiles where role_code = 'diretor_geral' for update;
    select id into v_level_13_id from public.staff_positions where level = 13;
    perform set_config('hpsm.position_change_authorized', 'true', true);
    update public.profiles
    set role_code = 'funcionario', position_id = v_level_13_id, updated_by = p_actor_id, updated_at = now()
    where user_id = v_old_general;
    insert into public.staff_position_history (
      employee_id, from_position_id, to_position_id, event_type, decided_by, note
    ) values (
      v_old_general, v_to.id, v_level_13_id, 'succession', p_actor_id,
      'Saída da Direção Geral. ' || btrim(p_note)
    );
    update public.profiles
    set role_code = 'diretor_geral', position_id = v_to.id, updated_by = p_actor_id, updated_at = now()
    where user_id = p_employee_id;
  else
    perform set_config('hpsm.position_change_authorized', 'true', true);
    update public.profiles
    set position_id = v_to.id, updated_by = p_actor_id, updated_at = now()
    where user_id = p_employee_id;
  end if;
  insert into public.staff_position_history (
    employee_id, from_position_id, to_position_id, event_type, decided_by, note
  ) values (
    p_employee_id, v_from.id, v_to.id,
    case when v_to.level = 14 then 'succession' else 'appointment' end,
    p_actor_id, btrim(p_note)
  ) returning * into v_history;
  insert into public.notifications (
    kind, recipient_id, priority, title, body, action_url, created_by
  ) values (
    'personal', p_employee_id, 'important', 'Novo cargo registrado',
    format('Sua nomeação para %s foi registrada.', v_to.name), '/meu-rh', p_actor_id
  );
  return to_jsonb(v_history);
end;
$$;

create or replace function public.set_warning_progression_impact(
  p_warning_id bigint,
  p_impacts boolean,
  p_note text,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.rh_warnings;
begin
  if not private.has_permission(p_actor_id, 'hr.warnings.progression') then
    raise exception using errcode = '42501', message = 'Você não pode alterar o impacto de advertências.';
  end if;
  if p_impacts is null or (p_note is not null and char_length(btrim(p_note)) not between 2 and 1000) then
    raise exception using errcode = '22023', message = 'Dados de impacto inválidos.';
  end if;
  update public.rh_warnings
  set impacts_progression = p_impacts,
      progression_flagged_by = case when p_impacts then p_actor_id else null end,
      progression_flagged_at = case when p_impacts then now() else null end,
      progression_impact_note = case when p_impacts then nullif(btrim(coalesce(p_note, '')), '') else null end,
      updated_at = now()
  where id = p_warning_id and status = 'active'
  returning * into v_row;
  if not found then
    raise exception using errcode = 'P0002', message = 'Advertência ativa não encontrada.';
  end if;
  return to_jsonb(v_row);
end;
$$;

create or replace function public.register_tcc_submission(
  p_submission_id uuid,
  p_title text,
  p_storage_path text,
  p_original_filename text,
  p_mime_type text,
  p_size_bytes bigint,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.tcc_submissions;
begin
  if p_submission_id is null or p_actor_id is null
     or private.current_position_level(p_actor_id) <> 4
     or not private.has_permission(p_actor_id, 'tcc.submit') then
    raise exception using errcode = '42501', message = 'O envio de TCC é exclusivo do Residente I.';
  end if;
  if exists (select 1 from public.tcc_submissions where employee_id = p_actor_id and status in ('submitted', 'approved')) then
    raise exception using errcode = '23505', message = 'Já existe um TCC ativo para este colaborador.';
  end if;
  insert into public.tcc_submissions (
    id, employee_id, title, storage_path, original_filename, mime_type, size_bytes
  ) values (
    p_submission_id, p_actor_id, btrim(p_title), p_storage_path,
    btrim(p_original_filename), p_mime_type, p_size_bytes
  ) returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

create or replace function public.cast_tcc_vote(
  p_submission_id uuid,
  p_vote text,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_submission public.tcc_submissions;
  v_vote public.tcc_votes;
  v_approvals integer;
begin
  if not private.has_permission(p_actor_id, 'tcc.vote')
     or coalesce(private.current_position_level(p_actor_id), 0) < 11 then
    raise exception using errcode = '42501', message = 'Você não possui permissão para votar em TCC.';
  end if;
  if p_vote not in ('approve', 'reject') then
    raise exception using errcode = '22023', message = 'Voto inválido.';
  end if;
  select * into v_submission from public.tcc_submissions where id = p_submission_id for update;
  if not found or v_submission.status <> 'submitted' or v_submission.employee_id = p_actor_id then
    raise exception using errcode = '22023', message = 'Este TCC não está disponível para votação.';
  end if;
  insert into public.tcc_votes (submission_id, vote, voted_by)
  values (p_submission_id, p_vote, p_actor_id)
  returning * into v_vote;
  select count(*)::integer into v_approvals from public.tcc_votes
  where submission_id = p_submission_id and vote = 'approve';
  if v_approvals >= 3 then
    update public.tcc_submissions
    set status = 'approved', approved_at = now(), updated_at = now()
    where id = p_submission_id;
    perform private.resolve_flow_notifications('tcc_submission', p_submission_id::text, p_actor_id);
    insert into public.notifications (
      kind, recipient_id, priority, title, body, action_url, created_by
    ) values (
      'personal', v_submission.employee_id, 'important', 'TCC aprovado',
      'Seu TCC recebeu três votos positivos e foi aprovado.', '/meu-rh', p_actor_id
    );
    perform private.ensure_staff_promotion_review(v_submission.employee_id);
  end if;
  return jsonb_build_object('vote', to_jsonb(v_vote), 'approval_count', v_approvals, 'approved', v_approvals >= 3);
exception when unique_violation then
  raise exception using errcode = '23505', message = 'Você já registrou seu voto neste TCC.';
end;
$$;

create or replace function public.create_course(
  p_name text,
  p_description text,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_row public.courses;
begin
  if not private.has_permission(p_actor_id, 'courses.manage')
     or coalesce(private.current_position_level(p_actor_id), 0) < 11 then
    raise exception using errcode = '42501', message = 'Você não possui permissão para criar cursos.';
  end if;
  insert into public.courses (name, description, created_by, updated_by)
  values (btrim(p_name), btrim(coalesce(p_description, '')), p_actor_id, p_actor_id)
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

create or replace function public.update_course(
  p_course_id bigint,
  p_name text,
  p_description text,
  p_active boolean,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_row public.courses;
begin
  if not private.has_permission(p_actor_id, 'courses.manage')
     or coalesce(private.current_position_level(p_actor_id), 0) < 11 then
    raise exception using errcode = '42501', message = 'Você não possui permissão para alterar cursos.';
  end if;
  update public.courses
  set name = btrim(p_name), description = btrim(coalesce(p_description, '')),
      active = p_active, updated_by = p_actor_id, updated_at = now()
  where id = p_course_id returning * into v_row;
  if not found then raise exception using errcode = 'P0002', message = 'Curso não encontrado.'; end if;
  return to_jsonb(v_row);
end;
$$;

create or replace function public.record_staff_course_status(
  p_course_id bigint,
  p_employee_id uuid,
  p_status text,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_row public.staff_course_records;
begin
  if not private.has_permission(p_actor_id, 'courses.completions.manage')
     or coalesce(private.current_position_level(p_actor_id), 0) < 11 then
    raise exception using errcode = '42501', message = 'Você não possui permissão para registrar cursos.';
  end if;
  if p_status not in ('pending', 'completed')
     or not exists (select 1 from public.courses where id = p_course_id)
     or not exists (select 1 from public.profiles where user_id = p_employee_id and status <> 'inactive') then
    raise exception using errcode = '22023', message = 'Curso, colaborador ou situação inválida.';
  end if;
  insert into public.staff_course_records (
    course_id, employee_id, status, assigned_by, completed_by, completed_at
  ) values (
    p_course_id, p_employee_id, p_status, p_actor_id,
    case when p_status = 'completed' then p_actor_id else null end,
    case when p_status = 'completed' then now() else null end
  )
  on conflict (course_id, employee_id) do update set
    status = excluded.status,
    completed_by = excluded.completed_by,
    completed_at = excluded.completed_at,
    updated_at = now()
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

-- ---------------------------------------------------------------------------
-- Proteções de integridade, notificações e auditoria
-- ---------------------------------------------------------------------------

create or replace function private.guard_director_general()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.role_code = 'diretor_geral'
     and (new.role_code <> 'diretor_geral' or new.status <> 'active')
     and current_setting('hpsm.position_change_authorized', true) <> 'true' then
    raise exception 'A conta do Diretor Geral só pode ser alterada pelo fluxo de sucessão.';
  end if;
  return new;
end;
$$;

create or replace function private.guard_profile_position_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.position_id is distinct from old.position_id
     and current_setting('hpsm.position_change_authorized', true) <> 'true' then
    raise exception 'Altere o cargo somente pelos fluxos de promoção ou nomeação.';
  end if;
  return new;
end;
$$;

create trigger profiles_guard_position_change
before update of position_id on public.profiles
for each row execute function private.guard_profile_position_change();

create or replace function private.record_initial_staff_position()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.position_id is not null then
    insert into public.staff_position_history (
      employee_id, from_position_id, to_position_id, event_type, decided_by, effective_at, note
    ) values (
      new.user_id, null, new.position_id, 'initial_assignment',
      coalesce(new.created_by, new.user_id), new.created_at, 'Ingresso na hierarquia oficial.'
    );
  end if;
  return new;
end;
$$;

create trigger profiles_record_initial_staff_position
after insert on public.profiles
for each row execute function private.record_initial_staff_position();

create or replace function private.notify_staff_promotion_review()
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
      'system', 'directors', 'important', 'Promoção elegível para análise',
      'Um colaborador atingiu os requisitos mínimos. A promoção continua dependendo de decisão humana.',
      '/rh?aba=career', new.employee_id,
      'staff_promotion_review', new.id::text, 'progression.review'
    );
  end if;
  return new;
end;
$$;

create trigger staff_promotion_reviews_notify
after insert on public.staff_promotion_reviews
for each row execute function private.notify_staff_promotion_review();

create or replace function private.notify_tcc_submission()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' and new.status = 'submitted' then
    insert into public.notifications (
      kind, audience, priority, title, body, action_url, created_by,
      source_type, source_id, required_permission
    ) values (
      'system', 'directors', 'important', 'Novo TCC para votação',
      'Um Residente I enviou um TCC. São necessários três votos positivos para aprovação.',
      '/rh?aba=career', new.employee_id,
      'tcc_submission', new.id::text, 'tcc.vote'
    );
  end if;
  return new;
end;
$$;

create trigger tcc_submissions_notify
after insert on public.tcc_submissions
for each row execute function private.notify_tcc_submission();

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
    left join public.staff_positions position on position.id = profile.position_id
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
            (notification.required_permission is not null and private.has_permission(p_user_id, notification.required_permission))
            or (notification.required_permission is null and position.level >= 11)
          )
        )
        or (notification.audience = 'employees' and coalesce(position.level, 1) <= 10)
      )
  );
$$;

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
      nullif(row_values ->> 'voted_by', '')::uuid,
      nullif(row_values ->> 'completed_by', '')::uuid,
      nullif(row_values ->> 'assigned_by', '')::uuid,
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
    row_values ->> 'id', row_values ->> 'key', row_values ->> 'user_id',
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

create trigger staff_position_history_audit
after insert or update or delete on public.staff_position_history
for each row execute function private.audit_row_change();
create trigger staff_position_transition_rules_touch_updated_at
before update on public.staff_position_transition_rules
for each row execute function private.touch_updated_at();
create trigger staff_position_transition_rules_audit
after insert or update or delete on public.staff_position_transition_rules
for each row execute function private.audit_row_change();
create trigger staff_promotion_reviews_touch_updated_at
before update on public.staff_promotion_reviews
for each row execute function private.touch_updated_at();
create trigger staff_promotion_reviews_audit
after insert or update or delete on public.staff_promotion_reviews
for each row execute function private.audit_row_change();
create trigger tcc_submissions_touch_updated_at
before update on public.tcc_submissions
for each row execute function private.touch_updated_at();
create trigger tcc_submissions_audit
after insert or update or delete on public.tcc_submissions
for each row execute function private.audit_row_change();
create trigger tcc_votes_audit
after insert or update or delete on public.tcc_votes
for each row execute function private.audit_row_change();
create trigger courses_touch_updated_at
before update on public.courses
for each row execute function private.touch_updated_at();
create trigger courses_audit
after insert or update or delete on public.courses
for each row execute function private.audit_row_change();
create trigger staff_course_records_touch_updated_at
before update on public.staff_course_records
for each row execute function private.touch_updated_at();
create trigger staff_course_records_audit
after insert or update or delete on public.staff_course_records
for each row execute function private.audit_row_change();

-- Cargos oficiais não podem ser renomeados ou inativados. Sua matriz de
-- permissões continua configurável.
create or replace function public.update_staff_position(
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
  v_current public.staff_positions;
  v_row public.staff_positions;
begin
  if not private.has_permission(p_actor_id, 'access.manage') then
    raise exception using errcode = '42501', message = 'Você não possui permissão para alterar cargos.';
  end if;
  select * into v_current from public.staff_positions where id = p_position_id;
  if not found then raise exception using errcode = 'P0002', message = 'Cargo não encontrado.'; end if;
  if v_current.official and (btrim(p_name) <> v_current.name or p_active is not true) then
    raise exception using errcode = '42501', message = 'Os 14 cargos oficiais não podem ser renomeados ou inativados.';
  end if;
  update public.staff_positions
  set name = btrim(p_name), active = p_active, updated_by = p_actor_id, updated_at = now()
  where id = p_position_id returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

create or replace function public.set_staff_position_permissions(
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
  v_level smallint;
begin
  if not private.has_permission(p_actor_id, 'access.manage')
     or private.current_position_level(p_actor_id) <> 14 then
    raise exception using errcode = '42501', message = 'Somente o Diretor Geral pode configurar os pacotes de acesso.';
  end if;
  select level into v_level from public.staff_positions where id = p_position_id;
  if v_level is null or p_permission_codes is null or jsonb_typeof(p_permission_codes) <> 'array' then
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
  if v_level = 14 and exists (
    select 1 from public.system_permissions permission where not (permission.code = any(v_codes))
  ) then
    raise exception using errcode = '23514', message = 'O Diretor Geral deve manter acesso total.';
  end if;
  if v_level <> 14 and v_codes && array['access.manage', 'access.grants.manage', 'succession.manage', 'settings.critical']::text[] then
    raise exception using errcode = '42501', message = 'Permissões críticas são exclusivas do Diretor Geral.';
  end if;
  if v_level <> 4 and 'tcc.submit' = any(v_codes) then
    raise exception using errcode = '23514', message = 'O envio de TCC é exclusivo do Residente I.';
  end if;
  delete from public.staff_position_permissions where position_id = p_position_id;
  insert into public.staff_position_permissions (position_id, permission_code, granted_by)
  select p_position_id, code, p_actor_id from unnest(v_codes) code;
  update public.staff_positions set updated_by = p_actor_id, updated_at = now() where id = p_position_id;
  return jsonb_build_object('position_id', p_position_id, 'permission_codes', to_jsonb(v_codes));
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS, políticas e privilégios
-- ---------------------------------------------------------------------------

alter table public.staff_position_history enable row level security;
alter table public.staff_position_history force row level security;
alter table public.staff_position_transition_rules enable row level security;
alter table public.staff_position_transition_rules force row level security;
alter table public.staff_promotion_reviews enable row level security;
alter table public.staff_promotion_reviews force row level security;
alter table public.tcc_submissions enable row level security;
alter table public.tcc_submissions force row level security;
alter table public.tcc_votes enable row level security;
alter table public.tcc_votes force row level security;
alter table public.courses enable row level security;
alter table public.courses force row level security;
alter table public.staff_course_records enable row level security;
alter table public.staff_course_records force row level security;

create policy staff_position_history_read_own_or_manager
on public.staff_position_history for select to authenticated
using (
  employee_id = (select auth.uid())
  or private.has_permission((select auth.uid()), 'hr.team.view')
  or private.has_permission((select auth.uid()), 'progression.review')
);
create policy staff_position_transition_rules_read_authenticated
on public.staff_position_transition_rules for select to authenticated
using (true);
create policy staff_promotion_reviews_read_own_or_manager
on public.staff_promotion_reviews for select to authenticated
using (
  employee_id = (select auth.uid())
  or private.has_permission((select auth.uid()), 'progression.review')
);
create policy tcc_submissions_read_own_or_voter
on public.tcc_submissions for select to authenticated
using (
  employee_id = (select auth.uid())
  or private.has_permission((select auth.uid()), 'tcc.vote')
);
create policy tcc_votes_read_own_submission_or_voter
on public.tcc_votes for select to authenticated
using (
  private.has_permission((select auth.uid()), 'tcc.vote')
  or exists (
    select 1 from public.tcc_submissions submission
    where submission.id = tcc_votes.submission_id and submission.employee_id = (select auth.uid())
  )
);
create policy courses_read_active_or_manager
on public.courses for select to authenticated
using (active or private.has_permission((select auth.uid()), 'courses.manage'));
create policy staff_course_records_read_own_or_manager
on public.staff_course_records for select to authenticated
using (
  employee_id = (select auth.uid())
  or private.has_permission((select auth.uid()), 'courses.completions.manage')
  or private.has_permission((select auth.uid()), 'hr.team.view')
);

drop policy if exists tcc_documents_insert_own on storage.objects;
create policy tcc_documents_insert_own
on storage.objects for insert to authenticated
with check (
  bucket_id = 'tcc-documents'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and private.has_permission((select auth.uid()), 'tcc.submit')
);
drop policy if exists tcc_documents_read_own_or_voter on storage.objects;
create policy tcc_documents_read_own_or_voter
on storage.objects for select to authenticated
using (
  bucket_id = 'tcc-documents'
  and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or private.has_permission((select auth.uid()), 'tcc.vote')
  )
);

revoke all on public.staff_position_history from public, anon, authenticated, service_role;
revoke all on public.staff_position_transition_rules from public, anon, authenticated, service_role;
revoke all on public.staff_promotion_reviews from public, anon, authenticated, service_role;
revoke all on public.tcc_submissions from public, anon, authenticated, service_role;
revoke all on public.tcc_votes from public, anon, authenticated, service_role;
revoke all on public.courses from public, anon, authenticated, service_role;
revoke all on public.staff_course_records from public, anon, authenticated, service_role;

grant select on public.staff_position_history to authenticated, service_role;
grant select on public.staff_position_transition_rules to authenticated, service_role;
grant select on public.staff_promotion_reviews to authenticated, service_role;
grant select on public.tcc_submissions to authenticated, service_role;
grant select on public.tcc_votes to authenticated, service_role;
grant select on public.courses to authenticated, service_role;
grant select on public.staff_course_records to authenticated, service_role;
grant insert, update, delete on public.staff_position_history to service_role;
grant insert, update, delete on public.staff_position_transition_rules to service_role;
grant insert, update, delete on public.staff_promotion_reviews to service_role;
grant insert, update on public.tcc_submissions to service_role;
grant insert on public.tcc_votes to service_role;
grant insert, update on public.courses to service_role;
grant insert, update on public.staff_course_records to service_role;
grant usage, select on sequence public.staff_position_history_id_seq to service_role;
grant usage, select on sequence public.staff_position_transition_rules_id_seq to service_role;
grant usage, select on sequence public.staff_promotion_reviews_id_seq to service_role;
grant usage, select on sequence public.tcc_votes_id_seq to service_role;
grant usage, select on sequence public.courses_id_seq to service_role;
grant usage, select on sequence public.staff_course_records_id_seq to service_role;

revoke all on function private.current_position_level(uuid) from public, anon, authenticated, service_role;
revoke all on function private.get_staff_progression_status(uuid) from public, anon, authenticated, service_role;
revoke all on function private.ensure_staff_promotion_review(uuid) from public, anon, authenticated, service_role;
revoke all on function public.get_staff_progression_status(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public.grant_user_permission(uuid, text, text, timestamptz, timestamptz, text, uuid) from public, anon, authenticated, service_role;
revoke all on function public.refresh_staff_promotion_reviews(uuid) from public, anon, authenticated, service_role;
revoke all on function public.decide_staff_promotion_review(bigint, text, text, uuid) from public, anon, authenticated, service_role;
revoke all on function public.appoint_staff_position(uuid, bigint, text, uuid) from public, anon, authenticated, service_role;
revoke all on function public.set_warning_progression_impact(bigint, boolean, text, uuid) from public, anon, authenticated, service_role;
revoke all on function public.register_tcc_submission(uuid, text, text, text, text, bigint, uuid) from public, anon, authenticated, service_role;
revoke all on function public.cast_tcc_vote(uuid, text, uuid) from public, anon, authenticated, service_role;
revoke all on function public.create_course(text, text, uuid) from public, anon, authenticated, service_role;
revoke all on function public.update_course(bigint, text, text, boolean, uuid) from public, anon, authenticated, service_role;
revoke all on function public.record_staff_course_status(bigint, uuid, text, uuid) from public, anon, authenticated, service_role;

grant execute on function private.current_position_level(uuid) to service_role;
grant execute on function private.get_staff_progression_status(uuid) to service_role;
grant execute on function public.get_staff_progression_status(uuid, uuid) to service_role;
grant execute on function public.grant_user_permission(uuid, text, text, timestamptz, timestamptz, text, uuid) to service_role;
grant execute on function public.refresh_staff_promotion_reviews(uuid) to service_role;
grant execute on function public.decide_staff_promotion_review(bigint, text, text, uuid) to service_role;
grant execute on function public.appoint_staff_position(uuid, bigint, text, uuid) to service_role;
grant execute on function public.set_warning_progression_impact(bigint, boolean, text, uuid) to service_role;
grant execute on function public.register_tcc_submission(uuid, text, text, text, text, bigint, uuid) to service_role;
grant execute on function public.cast_tcc_vote(uuid, text, uuid) to service_role;
grant execute on function public.create_course(text, text, uuid) to service_role;
grant execute on function public.update_course(bigint, text, text, boolean, uuid) to service_role;
grant execute on function public.record_staff_course_status(bigint, uuid, text, uuid) to service_role;

comment on table public.staff_position_history is 'Histórico permanente de cargo, promoções, nomeações e sucessões.';
comment on table public.staff_promotion_reviews is 'Pendências de promoção criadas quando os requisitos mínimos são atendidos; nunca promove automaticamente.';
comment on table public.tcc_submissions is 'Estrutura flexível de envio e aprovação de TCC do Residente I.';
comment on table public.tcc_votes is 'Um voto imutável por avaliador e TCC; três votos positivos aprovam.';
comment on table public.courses is 'Catálogo flexível de cursos do RP; cursos com histórico são inativados, não apagados.';
comment on table public.staff_course_records is 'Vínculos pendentes ou concluídos entre curso e colaborador.';
comment on table public.user_permission_grants is 'Exceções individuais permanentes ou temporárias, com validade, revogação e auditoria.';
