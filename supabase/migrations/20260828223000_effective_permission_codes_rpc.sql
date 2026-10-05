create or replace function public.effective_permission_codes(p_user_id uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(distinct permission_code order by permission_code), array[]::text[])
  from (
    select position_permission.permission_code
    from public.profiles profile
    join public.staff_positions position on position.id = profile.position_id and position.active
    join public.staff_position_permissions position_permission on position_permission.position_id = position.id
    where profile.user_id = p_user_id
      and profile.status = 'active'
    union all
    select permission_grant.permission_code
    from public.profiles profile
    join public.user_permission_grants permission_grant on permission_grant.user_id = profile.user_id
    where profile.user_id = p_user_id
      and profile.status = 'active'
      and permission_grant.revoked_at is null
      and permission_grant.valid_from <= now()
      and (permission_grant.expires_at is null or permission_grant.expires_at > now())
  ) effective;
$$;

revoke all on function public.effective_permission_codes(uuid) from public, anon, authenticated, service_role;
grant execute on function public.effective_permission_codes(uuid) to service_role;

comment on function public.effective_permission_codes(uuid) is
  'Resolve em uma única consulta as permissões ativas herdadas, individuais e temporárias de um colaborador.';
