import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");

test("fase 8 substitui o relatório antigo por uma central lazy e paginada", async () => {
  const [page, component, route] = await Promise.all([
    read("app/administrativo/relatorios/page.tsx"),
    read("app/components/administrative-reports.tsx"),
    read("app/api/administrative-reports/route.ts"),
  ]);
  assert.match(page, /<AdministrativeReports/);
  assert.doesNotMatch(page, /getHrAdminData|getHrProductionData|<HrManagement/);
  assert.match(component, /Visão Geral/);
  assert.match(component, /RH e Jornada/);
  assert.match(component, /Atendimentos e Vendas/);
  assert.match(component, /Relatório Individual/);
  assert.match(component, /AbortController/);
  assert.match(component, /pageSize/);
  assert.match(route, /cache-control.*private, no-store/);
});

test("backend e banco repetem permissões totais e parciais", async () => {
  const [route, migration] = await Promise.all([
    read("app/api/administrative-reports/route.ts"),
    read("supabase/migrations/20260911160000_phase8_advanced_administrative_reports.sql"),
  ]);
  assert.match(route, /hr\.reports\.view/);
  assert.match(route, /attendances\.manage/);
  assert.match(migration, /private\.hpsm_current_actor\(\)/);
  assert.match(migration, /private\.has_permission\(v_actor, 'hr\.reports\.view'\)/);
  assert.match(migration, /private\.has_permission\(v_actor, 'attendances\.manage'\)/);
  assert.match(migration, /revoke all on function public\.hpsm_report_financial/);
  assert.match(migration, /grant execute on function public\.hpsm_report_financial[^;]+to authenticated/s);
});

test("financeiro usa snapshots e evita duplicidade por itens", async () => {
  const migration = await read("supabase/migrations/20260911160000_phase8_advanced_administrative_reports.sql");
  assert.match(migration, /attendance\.status = 'completed'/);
  assert.match(migration, /sum\(attendance\.total\)/);
  assert.match(migration, /group by item\.attendance_id/);
  assert.match(migration, /item\.service_name/);
  assert.match(migration, /sum\(item\.line_total\)/);
  assert.match(migration, /sum\(attendance\.discount\)/);
  assert.doesNotMatch(migration, /clinical_exams|final_report_snapshot|result_data/);
});

test("jornada usa snapshots canônicos e meta efetiva dos fechamentos", async () => {
  const migration = await read("supabase/migrations/20260911160000_phase8_advanced_administrative_reports.sql");
  assert.match(migration, /public\.rh_hour_snapshots/);
  assert.match(migration, /public\.rh_weekly_records/);
  assert.match(migration, /sum\(record\.leave_deduction_minutes\)/);
  assert.match(migration, /sum\(record\.required_minutes\)/);
  assert.match(migration, /fully_excused/);
  assert.doesNotMatch(migration, /TCC|performance score|melhor médico|estoque/i);
});

test("CSV é UTF-8, filtrado no backend e protegido contra formula injection", async () => {
  const route = await read("app/api/administrative-reports/route.ts");
  assert.match(route, /\\ufeff/);
  assert.match(route, /text\/csv; charset=utf-8/);
  assert.match(route, /\^\[=\+\\-@\]/);
  assert.match(route, /getReportHr\(accessToken, filters\)/);
  assert.match(route, /getReportFinancial\(accessToken, filters\)/);
});

test("interface cobre mobile, dark mode e impressão individual limpa", async () => {
  const css = await read("app/brand.css");
  assert.match(css, /Fase 8 — Central de Relatórios/);
  assert.match(css, /html\[data-theme="dark"\].*report-status/s);
  assert.match(css, /@media \(max-width: 620px\)[\s\S]*report-kpi-grid/);
  assert.match(css, /@media print[\s\S]*report-individual-sheet/);
});
