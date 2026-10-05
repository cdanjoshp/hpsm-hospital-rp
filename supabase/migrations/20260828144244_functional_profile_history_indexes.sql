-- Supports the on-demand functional profile without introducing a duplicate
-- timeline table. These indexes cover full history, including withdrawn TCCs
-- and revoked/expired individual permission grants.

create index if not exists tcc_submissions_employee_history_idx
  on public.tcc_submissions (employee_id, submitted_at desc);

create index if not exists user_permission_grants_user_history_idx
  on public.user_permission_grants (user_id, granted_at desc);
