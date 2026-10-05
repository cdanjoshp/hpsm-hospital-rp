begin;

do $$
begin
  if private.attendance_item_limit('adrenalina', null) is not null
     or private.attendance_item_limit('atadura', 'plano_saude') is not null then
    raise exception 'A função de compatibilidade ainda está impondo limite.';
  end if;
end;
$$;

create temporary table post1_attendance_limit_context (
  key text primary key,
  value text not null
) on commit drop;

do $$
declare
  v_actor uuid;
  v_session uuid;
  v_service bigint;
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

  select id into v_service
  from public.service_catalog
  where code = 'adrenalina' and active;

  if v_actor is null or v_session is null or v_service is null then
    raise exception 'Ator ou Adrenalina indisponível para o teste transacional.';
  end if;

  insert into post1_attendance_limit_context values
    ('actor', v_actor::text),
    ('session', v_session::text),
    ('service', v_service::text),
    ('before', (select count(*)::text from public.attendances));
end;
$$;

grant select, insert, update on post1_attendance_limit_context to authenticated;
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', (select value from post1_attendance_limit_context where key = 'actor'),
  'session_id', (select value from post1_attendance_limit_context where key = 'session'),
  'role', 'authenticated'
)::text, true);
set local role authenticated;

do $$
declare
  v_service bigint := (select value::bigint from post1_attendance_limit_context where key = 'service');
  v_attendance bigint;
begin
  v_attendance := public.create_attendance(null, jsonb_build_array(
    jsonb_build_object('service_id', v_service, 'quantity', 4)
  ), null, null, null);
  insert into post1_attendance_limit_context values ('attendance', v_attendance::text);
end;
$$;

reset role;

do $$
declare
  v_before bigint := (select value::bigint from post1_attendance_limit_context where key = 'before');
  v_attendance bigint := (select value::bigint from post1_attendance_limit_context where key = 'attendance');
begin
  if (select count(*) from public.attendances) <> v_before + 1 then
    raise exception 'A venda acima da referência não criou exatamente um lançamento financeiro.';
  end if;
  if (select quantity from public.attendance_items where attendance_id = v_attendance) <> 4 then
    raise exception 'Quantidade acima da referência não foi preservada.';
  end if;
end;
$$;

rollback;

select jsonb_build_object(
  'phase', 'post1_attendance_item_limits',
  'shortcut_only', true,
  'above_reference_accepted', true,
  'residue', false
) as result;
