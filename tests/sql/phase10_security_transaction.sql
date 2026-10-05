begin;
create temporary table phase10_context as
select p.user_id, s.id as session_id, p.passport
from public.profiles p join auth.sessions s on s.user_id = p.user_id
where p.status = 'active' and not p.must_change_password
  and private.has_permission(p.user_id, 'attendances.create')
  and private.has_permission(p.user_id, 'attendances.manage')
order by s.created_at desc limit 1;
grant select on phase10_context to authenticated;
do $$ begin
  if not exists (select 1 from phase10_context) then raise exception 'Sessão administrativa necessária para regressão.'; end if;
end $$;

-- A signed JWT whose session is gone must not authorize RLS or legacy RPCs.
select set_config('request.jwt.claims', jsonb_build_object('sub',user_id,'role','authenticated','session_id',gen_random_uuid())::text,true) from phase10_context;
set local role authenticated;
do $$ begin
  if private.has_permission(auth.uid(),'patients.view') then raise exception 'Token revogado manteve permissão.'; end if;
  if exists (select 1 from public.patients) then raise exception 'RLS expôs pacientes sem sessão.'; end if;
  begin
    perform public.clinical_exam_reference_data();
    raise exception 'RPC clínica aceitou sessão revogada.';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- First access remains usable, but temporary-password accounts cannot operate.
update public.profiles set must_change_password = true where user_id = (select user_id from phase10_context);
select set_config('request.jwt.claims', jsonb_build_object('sub',user_id,'role','authenticated','session_id',session_id)::text,true) from phase10_context;
set local role authenticated;
do $$ declare v_bootstrap jsonb; begin
  v_bootstrap := public.hpsm_session_bootstrap();
  if not (v_bootstrap #>> '{profile,must_change_password}')::boolean or jsonb_array_length(v_bootstrap->'permissionCodes') <> 0 then
    raise exception 'Bootstrap do primeiro acesso incorreto.';
  end if;
  if not exists (select 1 from public.profiles where user_id=auth.uid()) then raise exception 'Primeiro acesso perdeu a própria identificação.'; end if;
  if exists (select 1 from public.patients) then raise exception 'Primeiro acesso expôs pacientes.'; end if;
  begin
    perform public.hpsm_dashboard_summary();
    raise exception 'Senha temporária acessou Dashboard.';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
update public.profiles set must_change_password = false where user_id = (select user_id from phase10_context);

set local role authenticated;
do $$
declare v_catalog public.service_catalog; v_id bigint; v_total numeric; v_items numeric; v_snapshot numeric;
begin
  select * into v_catalog from public.service_catalog where active and lower(btrim(category)) in ('insumos','medicamentos') order by id limit 1;
  if v_catalog.id is null then raise exception 'Catálogo de venda avulsa necessário.'; end if;
  begin
    insert into public.attendances(patient_name,patient_passport,subtotal,discount,performed_by)
    values ('Venda avulsa','—',1,0,auth.uid());
    raise exception 'Insert financeiro direto foi aceito.';
  exception when insufficient_privilege then null;
  end;
  v_id := public.create_attendance(null,jsonb_build_array(jsonb_build_object('service_id',v_catalog.id,'quantity',2)),null,null);
  select total into v_total from public.attendances where id=v_id;
  select sum(line_total),min(unit_price) into v_items,v_snapshot from public.attendance_items where attendance_id=v_id;
  if v_total <> v_catalog.unit_price*2 or v_items <> v_total or v_snapshot <> v_catalog.unit_price then
    raise exception 'RPC financeira perdeu consistência de total/snapshot.';
  end if;
  begin
    update public.attendances set subtotal=1 where id=v_id;
    raise exception 'Update financeiro direto foi aceito.';
  exception when insufficient_privilege then null;
  end;
  if not public.cancel_attendance(v_id) then raise exception 'Cancelamento autorizado falhou.'; end if;
  if public.cancel_attendance(v_id) then raise exception 'Segundo cancelamento não foi idempotente.'; end if;
  if (select total from public.attendances where id=v_id) <> v_total then raise exception 'Cancelamento alterou preço histórico.'; end if;
end $$;
reset role;
rollback;
select jsonb_build_object('phase','10','status','ok','revoked_session_blocked',true,'first_access_isolated',true,'financial_writes_rpc_only',true,'residue',false) as result;
