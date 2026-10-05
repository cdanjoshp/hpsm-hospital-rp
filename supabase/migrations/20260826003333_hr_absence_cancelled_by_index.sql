-- Índice de apoio para a chave estrangeira usada nas anulações de justificativa.

create index rh_absence_requests_cancelled_by_idx
  on public.rh_absence_requests (cancelled_by)
  where cancelled_by is not null;
