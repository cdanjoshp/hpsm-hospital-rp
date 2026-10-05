create index if not exists rh_week_closures_started_by_idx
  on public.rh_week_closures (started_by);

create index if not exists rh_week_closures_closed_by_idx
  on public.rh_week_closures (closed_by)
  where closed_by is not null;
