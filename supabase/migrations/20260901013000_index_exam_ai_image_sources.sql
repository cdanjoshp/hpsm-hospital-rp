-- HPSM — índices de cobertura para as referências imagem → laudo.

create index exam_ai_generations_source_image_generation_idx
  on public.exam_ai_generations(source_image_generation_id)
  where source_image_generation_id is not null;

create index exam_ai_generations_source_image_id_idx
  on public.exam_ai_generations(source_image_id)
  where source_image_id is not null;

