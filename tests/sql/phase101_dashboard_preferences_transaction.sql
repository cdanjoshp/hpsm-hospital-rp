begin;

create temporary table phase101_context as
with candidates as (
  select profile.user_id, session.id as session_id, position.level,
    private.has_permission(profile.user_id, 'hr.reports.view') as has_hospital_view
  from public.profiles profile
  join public.staff_positions position on position.id = profile.position_id
  join lateral (
    select active_session.id
    from auth.sessions active_session
    where active_session.user_id = profile.user_id
      and (active_session.not_after is null or active_session.not_after > now())
    order by active_session.created_at desc
    limit 1
  ) session on true
  where profile.status = 'active' and not profile.must_change_password
), limited_actor as (
  select user_id, session_id from candidates where not has_hospital_view order by level limit 1
), other_actor as (
  select candidate.user_id, candidate.session_id
  from candidates candidate
  where candidate.user_id <> (select user_id from limited_actor)
  order by candidate.level desc
  limit 1
)
select user_id, session_id, 1::bigint as actor_order from limited_actor
union all
select user_id, session_id, 2::bigint as actor_order from other_actor;

do $$ begin
  if (select count(*) from phase101_context) < 2 then
    raise exception 'A Fase 10.1 requer duas sessões profissionais ativas, incluindo uma sem visão hospitalar.';
  end if;
end $$;

delete from public.dashboard_preferences
where user_id in (select user_id from phase101_context);
grant select on phase101_context to authenticated;

set local role authenticated;

do $$
declare
  v_actor uuid := (select user_id from phase101_context where actor_order = 1);
  v_session uuid := (select session_id from phase101_context where actor_order = 1);
  v_config jsonb := $config${
    "configVersion": 1,
    "hiddenWidgets": [],
    "layouts": {
      "lg": [
        {"i":"my_week","x":0,"y":0,"w":4,"h":9}, {"i":"my_production","x":4,"y":0,"w":4,"h":9},
        {"i":"career","x":8,"y":0,"w":4,"h":9}, {"i":"attention","x":0,"y":9,"w":12,"h":6},
        {"i":"communications","x":0,"y":15,"w":8,"h":8}, {"i":"shortcuts","x":8,"y":15,"w":4,"h":8},
        {"i":"hospital_overview","x":0,"y":23,"w":12,"h":7}
      ],
      "md": [
        {"i":"my_week","x":0,"y":0,"w":4,"h":9}, {"i":"attention","x":4,"y":0,"w":4,"h":9},
        {"i":"my_production","x":0,"y":9,"w":4,"h":9}, {"i":"career","x":4,"y":9,"w":4,"h":9},
        {"i":"communications","x":0,"y":18,"w":8,"h":8}, {"i":"shortcuts","x":0,"y":26,"w":8,"h":8},
        {"i":"hospital_overview","x":0,"y":34,"w":8,"h":10}
      ],
      "sm": [
        {"i":"my_week","x":0,"y":0,"w":1,"h":10}, {"i":"attention","x":0,"y":10,"w":1,"h":11},
        {"i":"my_production","x":0,"y":21,"w":1,"h":11}, {"i":"career","x":0,"y":32,"w":1,"h":14},
        {"i":"communications","x":0,"y":46,"w":1,"h":14}, {"i":"shortcuts","x":0,"y":60,"w":1,"h":16},
        {"i":"hospital_overview","x":0,"y":76,"w":1,"h":27}
      ]
    },
    "shortcuts": ["overview","patients","audit"]
  }$config$::jsonb;
  v_saved jsonb;
  v_bundle jsonb;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_actor, 'role', 'authenticated', 'session_id', v_session)::text, true);
  v_saved := public.save_dashboard_preferences(v_config);
  if v_saved <> v_config then raise exception 'Preferência retornada divergiu da configuração válida.'; end if;
  if (select count(*) from public.dashboard_preferences) <> 1 then raise exception 'Usuário A não enxergou exatamente a própria preferência.'; end if;
  if (select user_id from public.dashboard_preferences) <> v_actor then raise exception 'Preferência foi atribuída a outro usuário.'; end if;
  begin
    insert into public.dashboard_preferences(user_id, layout_json) values (v_actor, '{}'::jsonb);
    raise exception 'Escrita direta na tabela foi aceita.';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.save_dashboard_preferences(v_config || jsonb_build_object('userId', gen_random_uuid()));
    raise exception 'Identidade manipulada foi aceita.';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.save_dashboard_preferences(jsonb_set(v_config, '{shortcuts,0}', '"rota_inexistente"'::jsonb));
    raise exception 'Atalho fora da lista fechada foi aceito.';
  exception when invalid_parameter_value then null;
  end;
  v_saved := public.save_dashboard_preferences(jsonb_set(v_config, '{layouts,lg,5,x}', '0'::jsonb));
  if v_saved #>> '{layouts,lg,5,x}' <> '0' then raise exception 'Posição estrutural legada do Acesso Direto não foi ignorada.'; end if;
  v_saved := public.save_dashboard_preferences(jsonb_set(jsonb_set(v_config, '{hiddenWidgets}', '["my_production"]'::jsonb), '{layouts,lg,1,x}', '0'::jsonb));
  if v_saved -> 'hiddenWidgets' <> '["my_production"]'::jsonb then raise exception 'Posição de widget oculto não foi ignorada.'; end if;
  v_saved := public.save_dashboard_preferences(jsonb_set(v_config, '{layouts,lg,6,y}', '0'::jsonb));
  if v_saved #>> '{layouts,lg,6,y}' <> '0' then raise exception 'Posição inativa da Visão do Hospital não foi ignorada.'; end if;
  begin
    perform public.save_dashboard_preferences(jsonb_set(v_config, '{layouts,lg,1,x}', '0'::jsonb));
    raise exception 'Sobreposição de widgets foi aceita.';
  exception when invalid_parameter_value then null;
  end;
  v_saved := public.save_dashboard_preferences(v_config);
  v_bundle := public.hpsm_dashboard_bundle();
  if v_bundle -> 'preferences' <> v_config then raise exception 'Bundle não devolveu a preferência do próprio usuário.'; end if;
  if v_bundle -> 'hospital' <> 'null'::jsonb then raise exception 'Layout tentou liberar a Visão do Hospital sem permissão.'; end if;
end;
$$;

do $$
declare
  v_actor uuid := (select user_id from phase101_context where actor_order = 2);
  v_session uuid := (select session_id from phase101_context where actor_order = 2);
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_actor, 'role', 'authenticated', 'session_id', v_session)::text, true);
  if exists (select 1 from public.dashboard_preferences) then raise exception 'Usuário B enxergou a preferência do usuário A.'; end if;
end;
$$;

reset role;
rollback;

select jsonb_build_object(
  'phase', '10.1',
  'status', 'ok',
  'own_preference_only', true,
  'direct_write_blocked', true,
  'identity_tampering_blocked', true,
  'unknown_shortcut_blocked', true,
  'structural_shortcut_overlap_ignored', true,
  'hidden_widget_overlap_ignored', true,
  'permission_filtered_widget_overlap_ignored', true,
  'overlap_blocked', true,
  'layout_did_not_grant_hospital_data', true,
  'residue', false
) as result;
