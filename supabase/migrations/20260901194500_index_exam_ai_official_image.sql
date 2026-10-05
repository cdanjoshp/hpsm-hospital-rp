create index if not exists exam_ai_generations_official_image_id_idx
  on public.exam_ai_generations (official_image_id)
  where official_image_id is not null;
