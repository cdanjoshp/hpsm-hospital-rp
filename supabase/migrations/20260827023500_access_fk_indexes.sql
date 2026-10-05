-- Índices de apoio para as novas chaves estrangeiras de acesso e resolução.
create index notifications_resolved_by_idx on public.notifications (resolved_by) where resolved_by is not null;
create index staff_position_permissions_granted_by_idx on public.staff_position_permissions (granted_by);
create index staff_positions_created_by_idx on public.staff_positions (created_by);
create index staff_positions_updated_by_idx on public.staff_positions (updated_by);
create index user_permission_grants_granted_by_idx on public.user_permission_grants (granted_by);
create index user_permission_grants_revoked_by_idx on public.user_permission_grants (revoked_by) where revoked_by is not null;
