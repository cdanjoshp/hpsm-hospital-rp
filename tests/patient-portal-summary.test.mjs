import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("portal summary is a single service-only aggregation derived from the opaque session", async () => {
  const [migration, service, route, page] = await Promise.all([
    read("supabase/migrations/20260909183947_phase62_patient_portal_summary.sql"),
    read("app/lib/patient-portal.ts"),
    read("app/api/patient-portal/summary/route.ts"),
    read("app/portal-paciente/page.tsx"),
  ]);

  assert.match(migration, /private\.patient_portal_session_record\(p_token_hash\)/);
  assert.match(migration, /attendance\.status = 'completed'/);
  assert.match(migration, /coalesce\(sum\(attendance\.total\), 0\)/);
  assert.match(migration, /order by exam\.requested_at desc, exam\.id desc[\s\S]*?limit 3/);
  assert.match(migration, /cast_record\.status = 'in_use'[\s\S]*?order by cast_record\.expected_removal_at/);
  assert.match(migration, /revoke all on function public\.patient_portal_summary\(text\)[\s\S]*?from public, anon, authenticated, service_role/);
  assert.match(migration, /grant execute on function public\.patient_portal_summary\(text\)[\s\S]*?to service_role/);
  assert.match(service, /patient_portal_summary/);
  assert.match(route, /getPatientPortalSummary/);
  assert.match(route, /"cache-control": "private, no-store"/);
  assert.match(page, /getPatientPortalSummary/);
  assert.match(page, /PatientPortalSummaryView/);
  for (const source of [migration, service, route, page]) {
    assert.doesNotMatch(source, /p_patient_id|patientId/);
  }
});

test("patient portal renders the shared phase 6.3 navigation and read-only summary cards", async () => {
  const [view, shell, styles, loading] = await Promise.all([
    read("app/components/patient-portal-summary.tsx"),
    read("app/components/patient-portal-shell.tsx"),
    read("app/brand.css"),
    read("app/portal-paciente/loading.tsx"),
  ]);

  assert.match(view, /Atendimentos realizados/);
  assert.match(view, /Último atendimento/);
  assert.match(view, /Total gasto no hospital/);
  assert.match(view, /Plano de Saúde/);
  assert.match(view, /Exames recentes/);
  assert.match(view, /Gessos em uso/);
  assert.match(shell, /href: "\/portal-paciente", key: "summary", label: "Resumo"/);
  assert.match(shell, /href: "\/portal-paciente\/historico", key: "history", label: "Histórico"/);
  assert.match(shell, /href: "\/portal-paciente\/atendimentos", key: "attendances", label: "Atendimentos"/);
  assert.match(shell, /aria-current=\{active === area\.key \? "page" : undefined\}/);
  assert.doesNotMatch(view, /aria-disabled|Em breve|Editar|Remover|Renovar/);
  assert.match(styles, /\.patient-portal-metrics/);
  assert.match(styles, /@media \(max-width: 520px\)[\s\S]*?\.patient-portal-metrics/);
  assert.match(styles, /html\[data-theme="dark"\][\s\S]*?\.patient-portal-metric/);
  assert.match(loading, /aria-busy="true"/);
});
