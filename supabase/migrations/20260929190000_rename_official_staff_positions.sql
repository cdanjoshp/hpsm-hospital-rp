-- Apenas os nomes exibidos dos 14 cargos oficiais; códigos, níveis,
-- modos de avanço e vínculos de permissão permanecem intactos.
do $$
declare
  v_updated integer;
begin
  update public.staff_positions position
  set name = names.name
  from (values
    ('estagiario_enfermagem', 1, 'Estagiário de Enfermagem'),
    ('socorrista', 2, 'Estagiário de Medicina'),
    ('enfermeiro', 3, 'Auxiliar de Enfermagem'),
    ('residente_i', 4, 'Técnico de Enfermagem'),
    ('medico_junior', 5, 'Enfermeiro'),
    ('medico', 6, 'Enfermeiro Chefe'),
    ('medico_pleno', 7, 'Médico 3'),
    ('medico_senior', 8, 'Médico 2'),
    ('especialista', 9, 'Médico 1'),
    ('especialista_senior', 10, 'Médico Cirurgião'),
    ('supervisor_clinico', 11, 'Médico Chefe'),
    ('coordenador_clinico', 12, 'Diretor Administrativo'),
    ('diretor_clinico', 13, 'Diretor Executivo'),
    ('diretor_geral', 14, 'Diretor Geral')
  ) as names(code, level, name)
  where position.code = names.code
    and position.level = names.level
    and position.official;

  get diagnostics v_updated = row_count;
  if v_updated <> 14 then
    raise exception 'A atualização dos cargos exige os 14 níveis oficiais intactos (encontrados: %).', v_updated;
  end if;
end;
$$;

-- Atualiza somente a mensagem de erro da nomeação de nível 13.
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
    raise exception using errcode = '42501', message = 'Somente o Diretor Geral pode nomear o Diretor Executivo.';
  elsif v_to.level = 14 and not (
      private.has_permission(p_actor_id, 'succession.manage') and v_actor_level = 14 and p_actor_id <> p_employee_id
    ) then
    raise exception using errcode = '42501', message = 'A nomeação para Diretor Geral exige outro Diretor Geral ativo.';
  end if;

  perform set_config('hpsm.position_change_authorized', 'true', true);
  update public.profiles
  set position_id = v_to.id,
      role_code = case when v_to.level = 14 then 'diretor_geral' else role_code end,
      updated_by = p_actor_id,
      updated_at = now()
  where user_id = p_employee_id;

  insert into public.staff_position_history (
    employee_id, from_position_id, to_position_id, event_type, decided_by, note
  ) values (
    p_employee_id, v_from.id, v_to.id,
    'appointment',
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

