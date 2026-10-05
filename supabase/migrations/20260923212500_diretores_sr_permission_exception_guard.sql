-- A categoria externa possui matriz fixa: concessões individuais anteriores
-- ficam inertes e novas exceções não podem ampliar seu acesso.
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
      and not profile.must_change_password
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
      and not profile.must_change_password
      and position.advancement_mode <> 'external'
      and permission_grant.revoked_at is null
      and permission_grant.valid_from <= now()
      and (permission_grant.expires_at is null or permission_grant.expires_at > now())
      and (
        permission_grant.permission_code <> 'recruitment.manage'
        or position.level between 11 and 14
      )
  ) effective;
$$;

revoke all on function public.effective_permission_codes(uuid) from public, anon;
grant execute on function public.effective_permission_codes(uuid) to authenticated, service_role;

create or replace function private.prevent_external_permission_grant()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.profiles profile
    join public.staff_positions position on position.id = profile.position_id
    where profile.user_id = new.user_id
      and position.advancement_mode = 'external'
  ) then
    raise exception using
      errcode = '42501',
      message = 'A categoria institucional externa utiliza uma matriz de acesso fixa.';
  end if;
  return new;
end;
$$;

revoke all on function private.prevent_external_permission_grant() from public, anon, authenticated;

drop trigger if exists user_permission_grants_external_guard on public.user_permission_grants;
create trigger user_permission_grants_external_guard
before insert or update of user_id, permission_code on public.user_permission_grants
for each row execute function private.prevent_external_permission_grant();
