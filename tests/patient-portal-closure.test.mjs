import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("phase 6.6 keeps the portal session opaque, bounded and outside client storage", async () => {
  const [service, login, shell, guard] = await Promise.all([
    read("app/lib/patient-portal.ts"),
    read("app/api/patient-portal/login/route.ts"),
    read("app/components/patient-portal-shell.tsx"),
    read("app/components/patient-portal-session-guard.tsx"),
  ]);

  assert.match(service, /crypto\.getRandomValues\(new Uint8Array\(32\)\)/);
  assert.match(service, /crypto\.subtle\.digest\("SHA-256"/);
  assert.match(login, /MAX_LOGIN_BODY_LENGTH = 512/);
  assert.match(login, /PIN_PATTERN = \/\^\[0-9\]\{4\}\$\//);
  assert.match(login, /Object\.keys\(body\)\.some/);
  assert.doesNotMatch(login, /birthDate|p_birth_date/);
  assert.match(shell, /PatientPortalSessionGuard/);
  assert.match(guard, /event\.persisted/);
  assert.match(guard, /window\.location\.replace\(window\.location\.href\)/);
  for (const source of [service, login, shell, guard]) {
    assert.doesNotMatch(source, /localStorage|sessionStorage/);
  }
});

test("logout never reports success when database revocation fails", async () => {
  const [logout, portal] = await Promise.all([
    read("app/api/patient-portal/logout/route.ts"),
    read("app/portal-paciente/page.tsx"),
  ]);

  assert.match(logout, /patient_portal_revoke_session/);
  assert.match(logout, /destination\.searchParams\.set\("portalError", "logout"\)/);
  assert.match(logout, /cache-control", "private, no-store"/);
  assert.match(logout, /clear-site-data", '\"cache\"'/);
  assert.match(portal, /Não foi possível encerrar sua sessão com segurança/);
  assert.match(portal, /Sua sessão continua protegida e ativa/);
});

test("private portal endpoints and pages prohibit reusable patient responses", async () => {
  const paths = [
    "app/api/patient-portal/me/route.ts",
    "app/api/patient-portal/summary/route.ts",
    "app/api/patient-portal/history/route.ts",
    "app/api/patient-portal/attendances/route.ts",
    "app/api/patient-portal/consultations/route.ts",
    "app/api/patient-portal/exams/route.ts",
    "app/api/patient-portal/health-plan/route.ts",
    "app/api/patient-portal/casts/route.ts",
  ];
  const routes = await Promise.all(paths.map(read));
  for (const route of routes) assert.match(route, /no-store/);

  const pages = await Promise.all([
    "app/portal-paciente/page.tsx",
    "app/portal-paciente/historico/page.tsx",
    "app/portal-paciente/atendimentos/page.tsx",
    "app/portal-paciente/consultas/page.tsx",
    "app/portal-paciente/consultas/[kind]/[id]/page.tsx",
    "app/portal-paciente/exames/page.tsx",
    "app/portal-paciente/plano-saude/page.tsx",
    "app/portal-paciente/gessos/page.tsx",
  ].map(read));
  for (const page of pages) assert.match(page, /dynamic = "force-dynamic"/);
});

test("o portal aceita o laudo v2 e limita consultas ao paciente da sessão", async () => {
  const [service, migration, shell, document] = await Promise.all([
    read("app/lib/patient-portal.ts"),
    read("supabase/migrations/20260927041500_patient_portal_consultations.sql"),
    read("app/components/patient-portal-shell.tsx"),
    read("app/api/patient-portal/consultations/[kind]/[id]/document/route.ts"),
  ]);
  assert.match(service, /snapshot\.schema !== "hpsm\.exam_report_snapshot\.v2"/);
  assert.match(shell, /href: "\/portal-paciente\/consultas"/);
  assert.match(migration, /appointment\.patient_id = v_session\.patient_id/);
  assert.match(migration, /consultation\.patient_id = v_session\.patient_id/);
  assert.match(migration, /case when consultation\.status = 'completed' then consultation\.final_snapshot else null end/);
  assert.match(migration, /grant execute on function public\.patient_portal_consultation_detail.*to service_role/);
  assert.match(document, /getPatientPortalConsultationDetail/);
  assert.doesNotMatch(document, /getSessionBootstrap|runConsultationMutation/);
});

test("patient result sharing has warning, bounded ownership route and manual clipboard fallback", async () => {
  const [actions, route, styles] = await Promise.all([
    read("app/components/patient-portal-exam-actions.tsx"),
    read("app/api/patient-portal/exams/[id]/document/route.ts"),
    read("app/brand.css"),
  ]);

  assert.match(actions, /Qualquer pessoa com este link poderá visualizar este exame\./);
  assert.match(actions, /navigator\.clipboard\?\.writeText/);
  assert.match(actions, /Selecione e copie manualmente/);
  assert.match(actions, /readOnly value=\{manualShareUrl\}/);
  assert.match(route, /getPatientPortalExamDetail/);
  assert.match(route, /privateHeaders\(\)/);
  assert.match(styles, /patient-portal-manual-share/);
  assert.match(styles, /data-patient-portal-restoring/);
});
