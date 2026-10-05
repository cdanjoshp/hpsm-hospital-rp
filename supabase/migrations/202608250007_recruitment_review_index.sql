-- Indexa o vínculo opcional com o diretor responsável pela análise.

create index if not exists recruitment_reviewed_by_idx
  on public.recruitment_applications (reviewed_by)
  where reviewed_by is not null;
