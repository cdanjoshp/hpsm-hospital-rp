-- O Diretor Geral pode excluir um agendamento cancelado ou com ausência registrada
-- quando ele não chegou a gerar uma consulta clínica. O trigger de auditoria
-- registra a exclusão e preserva o histórico da decisão.
create or replace function public.delete_terminal_patient_appointment(p_appointment_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_appointment public.patient_appointments;
begin
  if p_appointment_id is null or p_appointment_id < 1 then
    raise exception 'Agendamento inválido.';
  end if;

  if not private.has_permission(v_actor, 'consultations.delete') or not exists (
    select 1
    from public.profiles profile
    join public.staff_positions position on position.id = profile.position_id
    where profile.user_id = v_actor
      and profile.status = 'active'
      and position.official
      and position.active
      and position.level = 14
  ) then
    raise exception 'Somente o Diretor Geral pode excluir este agendamento.' using errcode = '42501';
  end if;

  select * into v_appointment
  from public.patient_appointments appointment
  where appointment.id = p_appointment_id
  for update;

  if v_appointment.id is null then
    raise exception 'Agendamento não localizado.';
  end if;
  if v_appointment.status not in ('cancelled', 'no_show') then
    raise exception 'Somente agendamentos cancelados ou com ausência registrada podem ser excluídos.';
  end if;
  if exists (
    select 1 from public.clinical_consultations consultation
    where consultation.appointment_id = p_appointment_id
  ) then
    raise exception 'Este agendamento possui uma consulta clínica vinculada e não pode ser excluído por este fluxo.';
  end if;

  delete from public.patient_appointments appointment
  where appointment.id = p_appointment_id;

  return jsonb_build_object('appointment_id', p_appointment_id, 'deleted', true);
end;
$$;

revoke all on function public.delete_terminal_patient_appointment(bigint)
from public, anon, authenticated, service_role;
grant execute on function public.delete_terminal_patient_appointment(bigint) to authenticated;

comment on function public.delete_terminal_patient_appointment(bigint) is
  'Exclusão auditada exclusiva do Diretor Geral para agendamentos cancelados ou sem comparecimento e sem prontuário clínico.';
