-- Índices de apoio para as chaves estrangeiras introduzidas na carreira.
create index staff_position_transition_rules_to_position_idx
  on public.staff_position_transition_rules (to_position_id);
create index staff_position_transition_rules_updated_by_idx
  on public.staff_position_transition_rules (updated_by);
