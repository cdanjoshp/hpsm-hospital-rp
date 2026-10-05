-- Recrutamento: cargos oficiais 11–14, com autorização repetida no banco.

insert into public.staff_position_permissions (position_id, permission_code, granted_by)
select
  position.id,
  'recruitment.manage',
  coalesce(
    (
      select existing.granted_by
      from public.staff_position_permissions existing
      where existing.permission_code = 'recruitment.manage'
        and existing.granted_by is not null
      order by existing.granted_at
      limit 1
    ),
    (
      select director.user_id
      from public.profiles director
      join public.staff_positions director_position on director_position.id = director.position_id
      where director.status = 'active'
        and director_position.level = 14
      order by director.created_at
      limit 1
    )
  )
from public.staff_positions position
where position.official
  and position.active
  and position.level between 11 and 14
on conflict (position_id, permission_code) do nothing;

delete from public.staff_position_permissions permission
using public.staff_positions position
where permission.position_id = position.id
  and permission.permission_code = 'recruitment.manage'
  and position.level not between 11 and 14;

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
    join public.staff_positions current_position
      on current_position.id = profile.position_id
     and current_position.active
    where profile.user_id = p_user_id
      and profile.status = 'active'
      and (
        p_permission_code <> 'recruitment.manage'
        or current_position.level between 11 and 14
      )
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

create or replace function public.effective_permission_codes(p_user_id uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(distinct effective.permission_code order by effective.permission_code), array[]::text[])
  from (
    select position_permission.permission_code
    from public.profiles profile
    join public.staff_positions position on position.id = profile.position_id and position.active
    join public.staff_position_permissions position_permission on position_permission.position_id = position.id
    where profile.user_id = p_user_id
      and profile.status = 'active'
      and (
        position_permission.permission_code <> 'recruitment.manage'
        or position.level between 11 and 14
      )
    union all
    select permission_grant.permission_code
    from public.profiles profile
    join public.staff_positions position on position.id = profile.position_id and position.active
    join public.user_permission_grants permission_grant on permission_grant.user_id = profile.user_id
    where profile.user_id = p_user_id
      and profile.status = 'active'
      and permission_grant.revoked_at is null
      and permission_grant.valid_from <= now()
      and (permission_grant.expires_at is null or permission_grant.expires_at > now())
      and (
        permission_grant.permission_code <> 'recruitment.manage'
        or position.level between 11 and 14
      )
  ) effective;
$$;

drop policy if exists recruitment_read_directors on public.recruitment_applications;
create policy recruitment_read_directors
on public.recruitment_applications for select
to authenticated
using ((select private.has_permission((select auth.uid()), 'recruitment.manage')));

drop policy if exists recruitment_update_directors on public.recruitment_applications;
create policy recruitment_update_directors
on public.recruitment_applications for update
to authenticated
using ((select private.has_permission((select auth.uid()), 'recruitment.manage')))
with check (
  (select private.has_permission((select auth.uid()), 'recruitment.manage'))
  and (reviewed_by is null or reviewed_by = (select auth.uid()))
);

drop policy if exists recruitment_decisions_read_directors on public.recruitment_decisions;
create policy recruitment_decisions_read_directors
on public.recruitment_decisions for select
to authenticated
using ((select private.has_permission((select auth.uid()), 'recruitment.manage')));

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
    raise exception using errcode = '42501', message = 'Apenas os cargos 11 a 14 podem decidir candidaturas.';
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

comment on function public.decide_recruitment_application(uuid, text, text, uuid) is
  'RPC exclusiva do backend: cargos oficiais 11–14 decidem candidaturas com permissão recruitment.manage.';

notify pgrst, 'reload schema';
