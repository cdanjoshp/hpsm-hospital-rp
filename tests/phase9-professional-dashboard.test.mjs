import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");

test("página inicial preserva a leitura de preferências e comunicados", async () => {
  const [page, service, component, layout, shell] = await Promise.all([
    read("app/painel/page.tsx"),
    read("app/lib/dashboard.ts"),
    read("app/components/professional-dashboard.tsx"),
    read("app/layout.tsx"),
    read("app/components/persistent-app-shell.tsx"),
  ]);
  assert.match(page, /getSessionBootstrap\(\)/);
  assert.match(page, /getProfessionalDashboard\(accessToken\)/);
  assert.doesNotMatch(page, /getEffectivePermissionCodes|getOperationalDashboardSummary|Promise\.all/);
  assert.match(service, /"hpsm_dashboard_bundle"/);
  assert.match(service, /buildWeeklyProgress/);
  assert.match(component, /<DashboardAnnouncements/);
  assert.match(component, /<ShortcutCard/);
  assert.doesNotMatch(component, /Minha semana|Minha produção|Precisa da minha atenção|Visão do Hospital/);
  assert.match(layout, /dashboardGreeting=\{dashboardGreeting\}/);
  assert.doesNotMatch(shell.slice(shell.indexOf("function routeHeading")), /new Date\(/);
  assert.doesNotMatch(page + component, /Operação e gestão|Operação sem controle de estoque|Fase 2/);
});

test("agregador repete sessão, permissões efetivas e não consulta filas sem autorização", async () => {
  const migration = await read("supabase/migrations/20260911170000_phase9_final_professional_dashboard.sql");
  assert.match(migration, /private\.hpsm_current_actor\(\)/);
  assert.match(migration, /public\.effective_permission_codes\(v_actor\)/);
  assert.match(migration, /if 'recruitment\.manage' = any\(v_permissions\) then[\s\S]*?from public\.recruitment_applications/);
  assert.match(migration, /if 'healthplans\.review' = any\(v_permissions\) then[\s\S]*?from public\.patient_health_plan_requests/);
  assert.match(migration, /if 'casts\.view' = any\(v_permissions\) and 'casts\.manage' = any\(v_permissions\) then/);
  assert.match(migration, /revoke all on function public\.hpsm_dashboard_summary\(\)[\s\S]*?from public, anon, authenticated, service_role/);
  assert.match(migration, /grant execute on function public\.hpsm_dashboard_summary\(\)[\s\S]*?to authenticated/);
});

test("produção e gestão reutilizam as regras financeiras e os Relatórios da Fase 8", async () => {
  const migration = await read("supabase/migrations/20260911170000_phase9_final_professional_dashboard.sql");
  assert.match(migration, /attendance\.performed_by = v_actor/);
  assert.match(migration, /attendance\.status = 'completed'/);
  assert.match(migration, /sum\(attendance\.total\)/);
  assert.match(migration, /sum\(item\.quantity\)/);
  assert.match(migration, /public\.hpsm_report_overview\(v_week_start, v_week_end\)/);
  assert.doesNotMatch(migration, /public\.service_catalog|clinical_exams|dashboard_stats/);
});

test("motor canônico de carreira permanece no agregador", async () => {
  const migration = await read("supabase/migrations/20260911170000_phase9_final_professional_dashboard.sql");
  assert.match(migration, /private\.get_staff_progression_status\(v_actor\)/);
  assert.doesNotMatch(migration, /TCC/i);
});

test("comunicados são compactos, priorizam não lidos e preservam leitura canônica", async () => {
  const [migration, component] = await Promise.all([
    read("supabase/migrations/20260911170000_phase9_final_professional_dashboard.sql"),
    read("app/components/dashboard-announcements.tsx"),
  ]);
  assert.match(migration, /notification\.kind = 'announcement'/);
  assert.match(migration, /order by \(read\.read_at is null\) desc/);
  assert.match(migration, /limit 3/);
  assert.doesNotMatch(migration.slice(migration.indexOf("Três comunicados")), /notification\.body/);
  assert.match(component, /hpsm:notifications-read/);
  assert.match(component, /Ler comunicado/);
  assert.match(component, /if \(!unread\.length\) return null/);
  assert.doesNotMatch(component, /announcement\.body/);
});

test("atalhos de todos os módulos e layout mobile respeitam permissões", async () => {
  const [component, css, customization, sidebar, administrative] = await Promise.all([
    read("app/components/professional-dashboard.tsx"),
    read("app/brand.css"),
    read("app/lib/dashboard-customization.ts"),
    read("app/lib/sidebar-navigation.ts"),
    read("app/lib/administrative.ts"),
  ]);
  for (const code of ["attendances.create", "patients.view", "exams.view", "casts.view", "hr.reports.view"]) {
    assert.match(sidebar + administrative, new RegExp(code.replaceAll(".", "\\.")));
  }
  assert.match(customization, /buildSidebarNavigation\(permissionCodes/);
  assert.match(customization, /visibleAdministrativeAreas\(permissionCodes\)/);
  assert.match(customization, /visibleDashboardShortcuts\(selectedIds: readonly string\[], permissionCodes: readonly string\[]\)/);
  assert.match(css, /\.professional-home \.dashboard-shortcut-card \{[^}]*aspect-ratio: 1 \/ 1/);
  assert.match(css, /@media \(max-width: 620px\) \{ \.professional-home \.dashboard-shortcut-grid/);
  assert.match(component, /aria-label="Módulos do sistema"/);
});
