-- The CID catalog follows the same restrictive active-session rule as other professional clinical catalogs.
drop policy if exists medical_cid10_catalog_valid_session on public.medical_cid10_catalog;
create policy medical_cid10_catalog_valid_session on public.medical_cid10_catalog as restrictive
for all to authenticated
using ((select private.hpsm_session_valid(true)))
with check ((select private.hpsm_session_valid(true)));
