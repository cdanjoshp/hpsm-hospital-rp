-- Diretores do SR: categoria institucional externa ao quadro médico.
-- Leitura ampla, simulação comercial e operação de pacientes/leitos, sem
-- metas, carreira, apuração semanal, advertências ou produção própria.

alter table public.staff_positions
  alter column level drop not null;

alter table public.staff_positions
  drop constraint if exists staff_positions_level_check,
  drop constraint if exists staff_positions_advancement_mode_check;

alter table public.staff_positions
  add constraint staff_positions_level_check
    check (level is null or level between 1 and 14),
  add constraint staff_positions_advancement_mode_check
    check (advancement_mode in ('progression', 'appointment', 'succession', 'external'));

insert into public.system_permissions (code, module, label, description, sort_order)
values (
  'sr.directors.view',
  'Institucional',
  'Visão institucional dos Diretores do SR',
  'Consulta ampla e simulação comercial sem autorizar decisões, vendas ou alterações administrativas.',
  53
)
on conflict (code) do update set
  module = excluded.module,
  label = excluded.label,
  description = excluded.description,
  sort_order = excluded.sort_order;

insert into public.staff_positions (
  code, name, level, advancement_mode, official, active, sort_order, created_by, updated_by
)
values (
  'diretores_sr',
  'Diretores do SR',
  null,
  'external',
  false,
  true,
  150,
  (select user_id from public.profiles where role_code = 'diretor_geral' and status = 'active' order by created_at limit 1),
  (select user_id from public.profiles where role_code = 'diretor_geral' and status = 'active' order by created_at limit 1)
)
on conflict (code) do update set
  name = excluded.name,
  level = null,
  advancement_mode = 'external',
  official = false,
  active = true,
  sort_order = excluded.sort_order,
  updated_by = excluded.updated_by,
  updated_at = now();

delete from public.staff_position_permissions
where position_id = (select id from public.staff_positions where code = 'diretores_sr');

insert into public.staff_position_permissions (position_id, permission_code, granted_by)
select
  position.id,
  permission.code,
  actor.user_id
from public.staff_positions position
cross join lateral (
  select user_id from public.profiles
  where role_code = 'diretor_geral' and status = 'active'
  order by created_at
  limit 1
) actor
join public.system_permissions permission on permission.code = any(array[
  'sr.directors.view',
  'profile.self.view',
  'patients.view',
  'catalog.view',
  'exams.view',
  'casts.view',
  'hospitalizations.view',
  'hospitalizations.create',
  'hospitalizations.update',
  'hospitalizations.discharge',
  'hospitalizations.history',
  'atestados.view',
  'audit.view',
  'partnerships.view',
  'hr.team.view',
  'hr.reports.view',
  'courses.view',
  'institutional.timeline.view'
]::text[])
where position.code = 'diretores_sr'
on conflict (position_id, permission_code) do update
set granted_by = excluded.granted_by,
    granted_at = now();

insert into public.staff_position_permissions (position_id, permission_code, granted_by)
select position.id, 'sr.directors.view', actor.user_id
from public.staff_positions position
cross join lateral (
  select user_id from public.profiles
  where role_code = 'diretor_geral' and status = 'active'
  order by created_at
  limit 1
) actor
where position.level = 14
on conflict (position_id, permission_code) do update
set granted_by = excluded.granted_by,
    granted_at = now();

create or replace function private.is_hpsm_workforce(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select position.official
    from public.profiles profile
    join public.staff_positions position on position.id = profile.position_id
    where profile.user_id = p_user_id
  ), false);
$$;

revoke all on function private.is_hpsm_workforce(uuid) from public, anon;
grant execute on function private.is_hpsm_workforce(uuid) to authenticated, service_role;

create or replace function private.require_hpsm_workforce_subject()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_hpsm_workforce(new.employee_id) then
    raise exception using
      errcode = '42501',
      message = 'A conta institucional externa não participa das rotinas de RH.';
  end if;
  return new;
end;
$$;

revoke all on function private.require_hpsm_workforce_subject() from public, anon, authenticated;

drop trigger if exists rh_hour_snapshots_require_workforce on public.rh_hour_snapshots;
create trigger rh_hour_snapshots_require_workforce
before insert or update of employee_id on public.rh_hour_snapshots
for each row execute function private.require_hpsm_workforce_subject();

drop trigger if exists rh_weekly_records_require_workforce on public.rh_weekly_records;
create trigger rh_weekly_records_require_workforce
before insert or update of employee_id on public.rh_weekly_records
for each row execute function private.require_hpsm_workforce_subject();

drop trigger if exists rh_warnings_require_workforce on public.rh_warnings;
create trigger rh_warnings_require_workforce
before insert or update of employee_id on public.rh_warnings
for each row execute function private.require_hpsm_workforce_subject();

-- Preserva as versões canônicas atuais das funções de RH e acrescenta a
-- exclusão institucional sem duplicar toda a lógica de fechamento/ADV.
do $$
declare
  v_function record;
  v_definition text;
begin
  for v_function in
    select procedure.oid, procedure.proname
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname in ('close_hr_week', 'finalize_hr_week_closure', 'issue_hr_warning')
  loop
    v_definition := pg_get_functiondef(v_function.oid);
    if v_function.proname in ('close_hr_week', 'issue_hr_warning') then
      v_definition := replace(
        v_definition,
        'if not found or v_profile.role_code = ''diretor_geral'' or v_profile.status = ''inactive'' then',
        'if not found or v_profile.role_code = ''diretor_geral'' or v_profile.status = ''inactive'' or not private.is_hpsm_workforce(p_employee_id) then'
      );
    else
      v_definition := replace(
        v_definition,
        'where profile.role_code <> ''diretor_geral''',
        'where profile.role_code <> ''diretor_geral'' and private.is_hpsm_workforce(profile.user_id)'
      );
    end if;
    execute v_definition;
  end loop;
end;
$$;

-- Relatórios consideram apenas o quadro médico oficial, mesmo quando uma
-- conta muda de cargo depois de possuir histórico anterior.
do $$
declare
  v_function record;
  v_definition text;
begin
  for v_function in
    select procedure.oid, procedure.proname
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname in ('public', 'private')
      and procedure.proname in (
        'hpsm_report_hours',
        'hpsm_report_staff_search',
        'hpsm_report_overview',
        'hpsm_report_hr',
        'hpsm_report_financial',
        'hpsm_report_team',
        'hpsm_report_individual',
        'hpsm_report_partnerships',
        'hpsm_hr_production'
      )
  loop
    v_definition := pg_get_functiondef(v_function.oid);
    v_definition := replace(
      v_definition,
      'profile.role_code <> ''diretor_geral''',
      'profile.role_code <> ''diretor_geral'' and private.is_hpsm_workforce(profile.user_id)'
    );
    v_definition := replace(
      v_definition,
      'attendance.status = ''completed''',
      'attendance.status = ''completed'' and private.is_hpsm_workforce(attendance.performed_by)'
    );
    v_definition := replace(v_definition, 'where warning.', 'where private.is_hpsm_workforce(warning.employee_id) and warning.');
    v_definition := replace(v_definition, 'where record.', 'where private.is_hpsm_workforce(record.employee_id) and record.');
    v_definition := replace(v_definition, 'where snapshot.', 'where private.is_hpsm_workforce(snapshot.employee_id) and snapshot.');
    v_definition := replace(v_definition, 'where request.', 'where private.is_hpsm_workforce(request.employee_id) and request.');
    v_definition := replace(v_definition, 'where absence.', 'where private.is_hpsm_workforce(absence.employee_id) and absence.');
    v_definition := replace(v_definition, 'where history.', 'where private.is_hpsm_workforce(history.employee_id) and history.');
    v_definition := replace(
      v_definition,
      'private.has_permission(v_actor, ''attendances.manage'')',
      '(private.has_permission(v_actor, ''attendances.manage'') or private.has_permission(v_actor, ''sr.directors.view''))'
    );
    execute v_definition;
  end loop;
end;
$$;

-- O painel e a navegação não calculam meta semanal para categorias externas.
do $$
declare
  v_function record;
  v_definition text;
begin
  for v_function in
    select procedure.oid
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname in ('hpsm_dashboard_summary', 'hpsm_shell_snapshot')
  loop
    v_definition := pg_get_functiondef(v_function.oid);
    v_definition := replace(
      v_definition,
      'if v_role_code <> ''diretor_geral'' then',
      'if v_role_code <> ''diretor_geral'' and private.is_hpsm_workforce(v_actor) then'
    );
    execute v_definition;
  end loop;
end;
$$;

-- Progressão e identidade médica não se aplicam aos Diretores do SR.
do $$
declare
  v_oid oid;
  v_definition text;
begin
  select procedure.oid into v_oid
  from pg_proc procedure
  join pg_namespace namespace on namespace.oid = procedure.pronamespace
  where namespace.nspname = 'private' and procedure.proname = 'get_staff_progression_status';
  v_definition := pg_get_functiondef(v_oid);
  v_definition := replace(
    v_definition,
    'select * into v_position from public.staff_positions where id = v_profile.position_id;',
    'select * into v_position from public.staff_positions where id = v_profile.position_id;
  if not coalesce(v_position.official, false) then
    return jsonb_build_object(''employee_id'', p_employee_id, ''position_id'', v_position.id, ''position_name'', v_position.name, ''eligible'', false, ''reason'', ''Categoria institucional externa ao quadro médico'');
  end if;'
  );
  execute v_definition;
end;
$$;

create or replace function private.provision_professional_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_registration_date date := (new.created_at at time zone 'America/Sao_Paulo')::date;
begin
  if new.must_change_password or not private.is_hpsm_workforce(new.user_id) then
    return new;
  end if;

  insert into public.professional_identities (user_id, crm_code, registration_date)
  values (
    new.user_id,
    private.hpsm_build_internal_crm(new.passport, v_registration_date),
    v_registration_date
  )
  on conflict (user_id) do nothing;

  return new;
end;
$$;

revoke all on function private.provision_professional_identity() from public, anon, authenticated, service_role;

-- Consultas de recrutamento ficam visíveis, enquanto UPDATE/decisão continua
-- restrito a recruitment.manage.
alter policy recruitment_read_directors on public.recruitment_applications
using (
  (select private.has_permission((select auth.uid()), 'recruitment.manage'))
  or (select private.has_permission((select auth.uid()), 'sr.directors.view'))
);

alter policy recruitment_decisions_read_directors on public.recruitment_decisions
using (
  (select private.has_permission((select auth.uid()), 'recruitment.manage'))
  or (select private.has_permission((select auth.uid()), 'sr.directors.view'))
);

-- Busca global e pendências de gesso também respeitam o papel observador.
do $$
declare
  v_function record;
  v_definition text;
begin
  for v_function in
    select procedure.oid, procedure.proname
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname in ('hpsm_global_search', 'clinical_cast_overdue_page')
  loop
    v_definition := pg_get_functiondef(v_function.oid);
    if v_function.proname = 'hpsm_global_search' then
      v_definition := replace(
        v_definition,
        '''recruitment.manage'' = any(v_permissions)',
        '(''recruitment.manage'' = any(v_permissions) or ''sr.directors.view'' = any(v_permissions))'
      );
      v_definition := replace(
        v_definition,
        '''catalog.manage'' = any(v_permissions)',
        '(''catalog.manage'' = any(v_permissions) or ''catalog.view'' = any(v_permissions))'
      );
    else
      v_definition := replace(
        v_definition,
        'or not private.has_permission(v_actor, ''casts.manage'')',
        'or not (private.has_permission(v_actor, ''casts.manage'') or private.has_permission(v_actor, ''sr.directors.view''))'
      );
    end if;
    execute v_definition;
  end loop;
end;
$$;

comment on function private.is_hpsm_workforce(uuid) is
  'Identifica contas que pertencem ao quadro médico oficial e podem participar de RH, carreira, metas e relatórios como sujeito.';
comment on column public.staff_positions.official is
  'Cargos oficiais integram o quadro médico; categorias externas usam false e ficam fora de RH, carreira e relatórios como sujeito.';
