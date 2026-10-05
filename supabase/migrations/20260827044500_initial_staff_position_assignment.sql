-- Regularização segura de perfis legados ainda sem cargo oficial.
create or replace function public.assign_initial_staff_position(
  p_employee_id uuid,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles;
  v_position public.staff_positions;
  v_history public.staff_position_history;
begin
  if not private.has_permission(p_actor_id, 'access.manage')
     or private.current_position_level(p_actor_id) <> 14 then
    raise exception using errcode = '42501', message = 'Somente o Diretor Geral pode definir o cargo inicial de perfis legados.';
  end if;
  select * into v_profile from public.profiles where user_id = p_employee_id for update;
  if not found or v_profile.status = 'inactive' or v_profile.position_id is not null then
    raise exception using errcode = '22023', message = 'Este perfil não está disponível para atribuição inicial.';
  end if;
  select * into v_position from public.staff_positions where level = 1 and active;
  perform set_config('hpsm.position_change_authorized', 'true', true);
  update public.profiles
  set position_id = v_position.id, role_code = 'funcionario', updated_by = p_actor_id, updated_at = now()
  where user_id = p_employee_id;
  insert into public.staff_position_history (
    employee_id, from_position_id, to_position_id, event_type, decided_by, effective_at, note
  ) values (
    p_employee_id, null, v_position.id, 'initial_assignment', p_actor_id,
    now(), 'Ingresso de perfil legado na hierarquia oficial.'
  ) returning * into v_history;
  insert into public.notifications (
    kind, recipient_id, priority, title, body, action_url, created_by
  ) values (
    'personal', p_employee_id, 'normal', 'Cargo inicial definido',
    'Seu cargo inicial foi registrado na hierarquia oficial.', '/meu-rh', p_actor_id
  );
  return to_jsonb(v_history);
end;
$$;

revoke all on function public.assign_initial_staff_position(uuid, uuid) from public, anon, authenticated, service_role;
grant execute on function public.assign_initial_staff_position(uuid, uuid) to service_role;
