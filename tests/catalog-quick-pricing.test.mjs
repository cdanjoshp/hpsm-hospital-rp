import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("Tabela de Preços preserva o editor completo e oferece preço rápido", async () => {
  const component = await read("app/components/catalog-management.tsx");
  assert.match(component, /saveChanges\(event/);
  assert.match(component, /Salvar alterações/);
  assert.match(component, /action: "unit_price"/);
  assert.match(component, /Alterar rapidamente o preço/);
  assert.match(component, /onKeyDown=\{quickPriceKeyDown\}/);
  assert.match(component, /invalidateCatalogClientCache\(\)/);
});

test("descontos em massa exigem os três benefícios e confirmação interna", async () => {
  const component = await read("app/components/catalog-management.tsx");
  assert.match(component, /Descontos em massa/);
  assert.match(component, /action: "bulk_discounts"/);
  assert.match(component, /Aplicar os mesmos descontos aos \{services\.length\} itens/);
  assert.match(component, /aria-modal="true"/);
  assert.match(component, /Atendimentos já registrados não serão alterados/);
  assert.doesNotMatch(component, /window\.confirm|window\.alert/);
});

test("API repete sessão, permissão e validação dos percentuais", async () => {
  const route = await read("app/api/services/pricing/route.ts");
  assert.match(route, /getSessionContext\(\)/);
  assert.match(route, /hasPermission\(context\.profile, "catalog\.manage"\)/);
  assert.match(route, /update_catalog_unit_price/);
  assert.match(route, /update_catalog_discounts_bulk/);
  assert.match(route, /discountPercent < 0 \|\| discountPercent > 100/);
  assert.doesNotMatch(route, /serviceRoleKey|SUPABASE_SERVICE_ROLE_KEY/);
});

test("migration mantém as operações atômicas, auditáveis e sem tocar histórico", async () => {
  const initial = await read("supabase/migrations/20260916155133_post1_catalog_quick_pricing.sql");
  const correction = await read("supabase/migrations/20260916155407_fix_post1_catalog_quick_pricing_actor.sql");
  const migrations = `${initial}\n${correction}`;
  assert.match(correction, /v_actor uuid := \(select auth\.uid\(\)\)/);
  assert.match(correction, /private\.has_permission\(v_actor, 'catalog\.manage'\)/);
  assert.doesNotMatch(correction, /private\.hpsm_current_actor\(\)/);
  assert.match(migrations, /security invoker/g);
  assert.match(migrations, /update public\.service_catalog/);
  assert.match(migrations, /update public\.plan_discounts/);
  assert.match(migrations, /discount\.discount_percent is distinct from input\.discount_percent/);
  assert.doesNotMatch(migrations, /update public\.attendances|update public\.attendance_items/);
  assert.match(migrations, /revoke all on function public\.update_catalog_unit_price/);
  assert.match(migrations, /grant execute on function public\.update_catalog_discounts_bulk\(jsonb\)\s+to authenticated/);
});

test("cache operacional é invalidado após alteração de catálogo", async () => {
  const cache = await read("app/lib/catalog-client-cache.ts");
  const attendance = await read("app/components/attendance-desk.tsx");
  assert.match(cache, /hpsm-catalog-version/);
  assert.match(attendance, /catalogCache\.version !== readCatalogCacheVersion\(\)/);
  assert.match(attendance, /version: readCatalogCacheVersion\(\)/);
});

test("controles rápidos cobrem tema escuro e telas menores", async () => {
  const css = await read("app/globals.css");
  assert.match(css, /\.catalog-bulk-discounts/);
  assert.match(css, /\.catalog-quick-price/);
  assert.match(css, /html\[data-theme="dark"\] \.catalog-bulk-discounts/);
  assert.match(css, /@media \(max-width: 700px\)[\s\S]*\.catalog-bulk-fields \{ grid-template-columns: 1fr;/);
});
