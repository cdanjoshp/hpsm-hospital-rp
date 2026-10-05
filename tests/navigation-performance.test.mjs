import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("authenticated sidebar prefetches only the operational hot path", async () => {
  const [source, navigation] = await Promise.all([
    read("app/components/app-sidebar.tsx"),
    read("app/lib/sidebar-navigation.ts"),
  ]);
  for (const href of ["/painel", "/pacientes", "/atendimentos", "/exames", "/gessos", "/meu-rh", "/catalogo", "/administrativo", "/auditoria", "/notificacoes"]) {
    assert.match(navigation, new RegExp(`href:\\s*["']${href.replaceAll("/", "\\/")}["']`), `${href} precisa permanecer na configuração canônica`);
  }
  assert.match(source, /href=\{item\.href!\}[\s\S]*?prefetch=\{shouldPrefetchRoute\(item\.href!\)\}/);
  assert.match(source, /href=\{child\.href\}[\s\S]*?prefetch=\{shouldPrefetchRoute\(child\.href\)\}/);
  assert.match(source, /function shouldPrefetchRoute\(href: string\)[\s\S]*?return href === "\/atendimentos"/);
  assert.doesNotMatch(source, /<Link[^>]*\sprefetch(?:\s|>)/);
});

test("modern sidebar reuses the permission source and safe flyout primitives", async () => {
  const [source, navigation, styles] = await Promise.all([
    read("app/components/app-sidebar.tsx"),
    read("app/lib/sidebar-navigation.ts"),
    read("app/brand.css"),
  ]);
  assert.match(source, /visibleAdministrativeAreas\(permissionCodes\)/);
  assert.match(source, /buildSidebarNavigation\(permissionCodes, pendingCount, administrativeChildren\)/);
  assert.match(navigation, /administrativeChildren\.length > 0/);
  assert.match(source, /createPortal\(panel, document\.body\)/);
  assert.match(source, /hp-sul-sidebar:/);
  assert.match(source, /event\.key !== "Escape"/);
  assert.match(source, /prefetch=\{shouldPrefetchRoute\(/);
  assert.match(styles, /\.sidebar-modern \.sidebar-nav-item > \.sidebar-nav-label \{ width: auto; min-width: 0; flex: 1 1 auto;/);
});

test("session and access lookups are request-memoized", async () => {
  const [session, access] = await Promise.all([
    read("app/lib/session.ts"),
    read("app/lib/access.ts"),
  ]);
  assert.match(session, /export const getSessionBootstrap = cache\(loadSessionBootstrap\)/);
  assert.match(session, /export const getSessionContext = cache\(loadSessionContext\)/);
  assert.match(session, /"hpsm_session_bootstrap"/);
  assert.doesNotMatch(session, /\/auth\/v1\/user/);
  assert.match(access, /export const getEffectivePermissionCodes = cache\(loadEffectivePermissionCodes\)/);
  assert.match(access, /export const getPositionDisplayName = cache\(loadPositionDisplayName\)/);
});

test("dashboard uses one permission-aware summary without operational list waterfalls", async () => {
  const [page, data] = await Promise.all([
    read("app/painel/page.tsx"),
    read("app/lib/dashboard.ts"),
  ]);
  assert.match(page, /getProfessionalDashboard/);
  assert.match(page, /getSessionBootstrap/);
  assert.doesNotMatch(page, /getAttendanceHistory|getServiceCatalog|getEffectivePermissionCodes/);
  assert.match(data, /"hpsm_dashboard_bundle"/);
  assert.doesNotMatch(data, /attendances\?select=|profiles\?/);
});

test("catalog images use one batch signature and lazy browser loading", async () => {
  const [data, image, fallback] = await Promise.all([
    read("app/lib/operational-data.ts"),
    read("app/components/catalog-image.tsx"),
    read("app/api/services/image/route.ts"),
  ]);
  assert.match(data, /\/storage\/v1\/object\/sign\/catalog-images/);
  assert.match(data, /paths:\s*withImages\.map/);
  assert.match(image, /loading=\{size === "preview" \? "eager" : "lazy"\}/);
  assert.match(image, /const source = imageUrl && failedSource !== imageUrl \? imageUrl : fallbackUrl/);
  assert.match(image, /failedSource !== fallbackUrl/);
  assert.match(fallback, /"cache-control":\s*"private, max-age=540"/);
});

test("compact brand caption has a dedicated decorative token", async () => {
  const [globals, brand] = await Promise.all([
    read("app/globals.css"),
    read("app/brand.css"),
  ]);
  assert.match(globals, /--type-brand-caption:\s*0\.5625rem/);
  assert.match(brand, /\.sidebar-brand \.hpsm-wordmark > span[\s\S]*?font-size:\s*var\(--type-brand-caption\)/);
  assert.match(brand, /\.mobile-brand \.hpsm-wordmark > span\s*\{\s*font-size:\s*var\(--type-brand-caption\)/);
});
