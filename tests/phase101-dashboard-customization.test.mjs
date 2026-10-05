import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");

test("página inicial mantém boas-vindas e comunicados sem blocos de indicadores", async () => {
  const [page, component, service] = await Promise.all([
    read("app/painel/page.tsx"), read("app/components/professional-dashboard.tsx"), read("app/lib/dashboard.ts"),
  ]);
  assert.match(page, /getProfessionalDashboard\(accessToken\)/);
  assert.match(service, /"hpsm_dashboard_bundle"/);
  assert.match(component, /dashboard-hero/);
  assert.match(component, /<DashboardAnnouncements initialAnnouncements=/);
  assert.match(component, /<ShortcutCard onCustomize=/);
  assert.doesNotMatch(component, /dashboard-focus-grid|dashboard-detail-grid|HospitalCard|Minha semana|Minha produção|Em foco/);
  assert.doesNotMatch(component, /ResponsiveGridLayout|dragConfig|resizeConfig|hideWidget|restoreWidget/);
});

test("todos os atalhos autorizados são exibidos e a preferência só altera a ordem", async () => {
  const [config, component, route] = await Promise.all([
    read("app/lib/dashboard-customization.ts"), read("app/components/professional-dashboard.tsx"), read("app/api/dashboard-preferences/route.ts"),
  ]);
  assert.match(config, /buildSidebarNavigation\(permissionCodes/);
  assert.match(config, /visibleAdministrativeAreas\(permissionCodes\)/);
  assert.match(config, /\.\.\.selectedIds\.map/);
  assert.match(config, /\.\.\.catalog\.map\(\(entry\) => entry\.id\)/);
  assert.match(component, /Organizar atalhos/);
  assert.match(component, /Restaurar ordem/);
  assert.match(component, /shortcuts: \[\.\.\.draftShortcuts, \.\.\.unavailable\]/);
  assert.match(component, /moveShortcut\(shortcut\.id/);
  assert.doesNotMatch(component, /Remover atalho|Ocultar atalho|Adicionar atalho/);
  assert.match(component, /fetch\("\/api\/dashboard-preferences"/);
  assert.doesNotMatch(component, /Adicionar widget|Ocultar widget|Personalizar dashboard/);
  assert.match(route, /validateDashboardPreference\(body, dashboardInactiveWidgetIds\(bootstrap\.permissionCodes\)\)/);
});

test("atalhos de vendas, consultas, internações e Meu RH usam o catálogo autorizado", async () => {
  const [config, migration, css, component] = await Promise.all([
    read("app/lib/dashboard-customization.ts"),
    read("supabase/migrations/20260930161300_home_all_modules_shortcut_order.sql"),
    read("app/brand.css"),
    read("app/components/professional-dashboard.tsx"),
  ]);
  assert.match(config, /label: "Nova Venda"/);
  for (const id of ["patients", "consultations", "hospitalizations", "my_hr", "certificates", "records"]) {
    assert.ok(config.includes(`"${id}"`), id);
    assert.ok(migration.includes(`'${id}'`), id);
  }
  assert.match(config, /id === "attendances" \|\| id === "overview"/);
  assert.match(migration, /v_count > 32/);
  assert.match(css, /\.professional-home \.dashboard-shortcut-card \{[^}]*aspect-ratio: 1 \/ 1/);
  assert.match(css, /\.professional-home \.dashboard-shortcut-card \{[^}]*align-items: center; justify-content: center/);
  assert.match(css, /\.professional-home \.dashboard-shortcut-card-icon svg \{ width: 34px; height: 34px/);
  assert.match(css, /\.professional-home \.dashboard-shortcut-card strong \{[^}]*white-space: normal/);
  assert.doesNotMatch(component.slice(component.indexOf("function ShortcutCard"), component.indexOf("function DashboardDialog")), /shortcut\.description|<small>|↗/);
  assert.match(css, /\.professional-home \.dashboard-shortcut-grid \{ grid-template-columns: repeat\(2/);
});
