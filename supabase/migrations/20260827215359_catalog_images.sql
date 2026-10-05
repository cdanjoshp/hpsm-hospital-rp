-- HPSM · imagens administráveis no catálogo
-- Mantém o arquivo fora da tabela e armazena apenas seu caminho seguro.

alter table public.service_catalog
  add column if not exists image_path text;

alter table public.service_catalog
  drop constraint if exists service_catalog_image_path_check;

alter table public.service_catalog
  add constraint service_catalog_image_path_check
  check (
    image_path is null
    or image_path ~ '^items/[0-9]+/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\.(jpg|png|webp)$'
  );

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'catalog-images',
  'catalog-images',
  false,
  2097152,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists catalog_images_read_authorized on storage.objects;
create policy catalog_images_read_authorized
on storage.objects for select to authenticated
using (
  bucket_id = 'catalog-images'
  and (
    private.has_permission((select auth.uid()), 'catalog.view')
    or private.has_permission((select auth.uid()), 'catalog.manage')
  )
);

drop policy if exists catalog_images_insert_manager on storage.objects;
create policy catalog_images_insert_manager
on storage.objects for insert to authenticated
with check (
  bucket_id = 'catalog-images'
  and private.has_permission((select auth.uid()), 'catalog.manage')
);

drop policy if exists catalog_images_update_manager on storage.objects;
create policy catalog_images_update_manager
on storage.objects for update to authenticated
using (
  bucket_id = 'catalog-images'
  and private.has_permission((select auth.uid()), 'catalog.manage')
)
with check (
  bucket_id = 'catalog-images'
  and private.has_permission((select auth.uid()), 'catalog.manage')
);

drop policy if exists catalog_images_delete_manager on storage.objects;
create policy catalog_images_delete_manager
on storage.objects for delete to authenticated
using (
  bucket_id = 'catalog-images'
  and private.has_permission((select auth.uid()), 'catalog.manage')
);

grant update (image_path, updated_by) on public.service_catalog to authenticated;
