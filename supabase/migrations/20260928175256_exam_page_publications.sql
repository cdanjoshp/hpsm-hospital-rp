-- Links individuais dos arquivos A4 dos laudos. Apenas o servidor acessa esta tabela.
create table public.clinical_exam_page_publications (
  id bigint generated always as identity primary key,
  exam_id bigint not null references public.clinical_exams(id) on delete cascade,
  document_id uuid not null references public.clinical_exam_documents(id) on delete cascade,
  page_number integer not null check (page_number between 1 and 8),
  external_asset_id text not null,
  cdn_url text not null check (cdn_url ~ '^https://([a-z0-9-]+\.)*fivemanage\.com/'),
  created_at timestamptz not null default now(),
  unique (document_id, page_number)
);

create index clinical_exam_page_publications_exam_idx on public.clinical_exam_page_publications(exam_id, document_id);
alter table public.clinical_exam_page_publications enable row level security;
alter table public.clinical_exam_page_publications force row level security;
revoke all on public.clinical_exam_page_publications from public, anon, authenticated, service_role;
grant select, insert, update, delete on public.clinical_exam_page_publications to service_role;
revoke all on sequence public.clinical_exam_page_publications_id_seq from public, anon, authenticated, service_role;
grant usage on sequence public.clinical_exam_page_publications_id_seq to service_role;
