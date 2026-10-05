begin;

do $$
begin
  if not private.walk_in_service_allowed('tratamento', 'Atendimentos')
     or not private.walk_in_service_allowed('desloc_norte', 'Deslocamento')
     or not private.walk_in_service_allowed('desloc_sul', 'Outro rótulo')
     or private.walk_in_service_allowed('consulta', 'Atendimentos') then
    raise exception 'A regra canônica da venda avulsa não corresponde ao catálogo esperado.';
  end if;
end;
$$;

create temporary table walk_in_sale_context (
  key text primary key,
  value text not null
) on commit drop;

do $$
declare
  v_actor uuid;
  v_session uuid;
  v_allowed_ids jsonb;
  v_forbidden_id bigint;
begin
  select profile.user_id, session.id
  into v_actor, v_session
  from public.profiles profile
  join auth.sessions session on session.user_id = profile.user_id
  where profile.status = 'active'
    and not profile.must_change_password
    and private.has_permission(profile.user_id, 'attendances.create')
    and private.has_permission(profile.user_id, 'catalog.view')
    and (session.not_after is null or session.not_after > now())
  order by session.created_at desc
  limit 1;

  select jsonb_agg(id order by code)
  into v_allowed_ids
  from public.service_catalog
  where code in ('tratamento', 'desloc_norte', 'desloc_sul')
    and active;

  select id
  into v_forbidden_id
  from public.service_catalog
  where active
    and not private.walk_in_service_allowed(code, category)
  order by id
  limit 1;

  if v_actor is null or v_session is null
     or jsonb_array_length(coalesce(v_allowed_ids, '[]'::jsonb)) <> 3
     or v_forbidden_id is null then
    raise exception 'Ator, sessão ou catálogo indisponível para o teste transacional.';
  end if;

  insert into walk_in_sale_context values
    ('actor', v_actor::text),
    ('session', v_session::text),
    ('allowed_ids', v_allowed_ids::text),
    ('forbidden_id', v_forbidden_id::text),
    ('before', (select count(*)::text from public.attendances));
end;
$$;

grant select, insert on walk_in_sale_context to authenticated;
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', (select value from walk_in_sale_context where key = 'actor'),
  'session_id', (select value from walk_in_sale_context where key = 'session'),
  'role', 'authenticated'
)::text, true);
set local role authenticated;

do $$
declare
  v_attendance bigint;
  v_forbidden_id bigint := (select value::bigint from walk_in_sale_context where key = 'forbidden_id');
  v_items jsonb;
  v_rejected boolean := false;
begin
  select jsonb_agg(jsonb_build_object('service_id', allowed.id::bigint, 'quantity', 1))
  into v_items
  from jsonb_array_elements_text(
    (select value::jsonb from walk_in_sale_context where key = 'allowed_ids')
  ) allowed(id);

  v_attendance := public.create_attendance(null, v_items, null, null, null);
  insert into walk_in_sale_context values ('attendance', v_attendance::text);

  begin
    perform public.create_attendance(null, jsonb_build_array(
      jsonb_build_object('service_id', v_forbidden_id, 'quantity', 1)
    ), null, null, null);
  exception when others then
    if position('Venda avulsa aceita somente insumos, medicamentos, tratamento e deslocamentos.' in sqlerrm) > 0 then
      v_rejected := true;
    else
      raise;
    end if;
  end;

  if not v_rejected then
    raise exception 'Venda avulsa aceitou um procedimento fora do escopo.';
  end if;
end;
$$;

reset role;

do $$
declare
  v_before bigint := (select value::bigint from walk_in_sale_context where key = 'before');
  v_attendance bigint := (select value::bigint from walk_in_sale_context where key = 'attendance');
begin
  if (select count(*) from public.attendances) <> v_before + 1 then
    raise exception 'A venda avulsa válida não criou exatamente um atendimento.';
  end if;
  if (select count(*) from public.attendance_items where attendance_id = v_attendance) <> 3 then
    raise exception 'Tratamento e deslocamentos não foram preservados na venda avulsa.';
  end if;
end;
$$;

rollback;

select jsonb_build_object(
  'feature', 'walk_in_sale_catalog',
  'treatment_allowed', true,
  'transport_allowed', true,
  'other_procedures_rejected', true,
  'residue', false
) as result;
