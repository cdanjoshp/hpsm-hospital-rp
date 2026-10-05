import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("phase 6.5 RPCs derive the patient from the opaque session and expose sanitized read-only data", async () => {
  const migration = await read("supabase/migrations/20260910194115_phase65_patient_portal_health_plan_casts.sql");

  for (const name of ["patient_portal_health_plan_page", "patient_portal_cast_page"]) {
    assert.match(migration, new RegExp(`create or replace function public\\.${name}\\(`));
  }
  assert.match(migration, /private\.patient_portal_session_record\(p_token_hash\)/g);
  assert.match(migration, /private\.patient_portal_health_plan_state\(v_session\.patient_id\)/g);
  assert.match(migration, /request\.patient_id = v_session\.patient_id/);
  assert.match(migration, /cast_record\.patient_id = v_session\.patient_id/g);
  assert.match(migration, /limit v_limit \+ 1/g);
  assert.match(migration, /clinical_casts_patient_in_use_due_idx/);
  assert.doesNotMatch(migration, /patient_portal_(?:health_plan|cast)_page\([\s\S]{0,220}p_patient_id/);
  assert.doesNotMatch(migration, /grant execute[\s\S]{0,180}to (?:anon|authenticated)/i);
  assert.doesNotMatch(migration, /'rejection_reason'|'application_notes'|'removal_notes'|'cancellation_reason'/);
});

test("health-plan and casts surfaces are lazy, paginated, linked and read-only", async () => {
  const [service, shell, summary, history, plan, casts, planRoute, castsRoute, styles] = await Promise.all([
    read("app/lib/patient-portal.ts"),
    read("app/components/patient-portal-shell.tsx"),
    read("app/components/patient-portal-summary.tsx"),
    read("app/components/patient-portal-history.tsx"),
    read("app/components/patient-portal-health-plan.tsx"),
    read("app/components/patient-portal-casts.tsx"),
    read("app/api/patient-portal/health-plan/route.ts"),
    read("app/api/patient-portal/casts/route.ts"),
    read("app/brand.css"),
  ]);

  assert.match(service, /patient_portal_health_plan_page/);
  assert.match(service, /patient_portal_cast_page/);
  assert.doesNotMatch(service, /p_patient_id|patientId/);
  assert.match(shell, /href: "\/portal-paciente\/plano-saude", key: "health-plan", label: "Plano de Saúde"/);
  assert.match(shell, /href: "\/portal-paciente\/gessos", key: "casts", label: "Gessos"/);
  assert.match(summary, /href="\/portal-paciente\/plano-saude"/);
  assert.match(summary, /href="\/portal-paciente\/gessos"/);
  assert.match(history, /Ver plano/);
  assert.match(history, /Ver gessos/);
  assert.match(plan, /Sua ativação ainda está sendo processada\./);
  assert.match(plan, /Você não possui Plano de Saúde ativo\./);
  assert.match(plan, /Solicitação não aprovada/);
  assert.doesNotMatch(plan, /rejectionReason|rejection_reason|Motivo da recusa|Solicitar|Renovar|Editar/);
  assert.match(casts, /A data prevista para retirada já foi atingida\./);
  assert.match(casts, /Retirada prevista para hoje\./);
  assert.doesNotMatch(casts, /applicationNotes|removalNotes|cancellationReason|Criar gesso|Remover gesso|Cancelar gesso/);
  for (const route of [planRoute, castsRoute]) {
    assert.match(route, /"cache-control": "private, no-store"/);
    assert.match(route, /vary: "Cookie"/);
  }
  assert.match(styles, /html\[data-theme="dark"\][\s\S]*?\.patient-portal-plan-current/);
  assert.match(styles, /@media \(max-width: 520px\)[\s\S]*?\.patient-portal-casts-grid/);
  assert.match(styles, /@media \(prefers-reduced-motion: reduce\)[\s\S]*?\.patient-portal-metric-link/);
});
