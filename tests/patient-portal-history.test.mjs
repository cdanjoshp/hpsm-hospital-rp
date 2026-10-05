import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("phase 6.3 database APIs derive identity from the opaque session and remain service-only", async () => {
  const migration = await read("supabase/migrations/20260909230326_phase63_patient_portal_history_attendances.sql");

  assert.match(migration, /private\.patient_portal_session_record\(p_token_hash\)/g);
  assert.match(migration, /private\.patient_portal_attendance_metrics\(v_session\.patient_id\)/g);
  assert.match(migration, /attendance\.status = 'completed'/g);
  assert.match(migration, /exam\.status = 'completed'/);
  assert.match(migration, /cast_record\.status in \('in_use', 'removed'\)/);
  assert.match(migration, /request\.status = 'approved'/);
  assert.match(migration, /\(event\.event_at, event\.event_key\) < \(p_cursor_at, p_cursor_key\)/);
  assert.match(migration, /\(attendance\.created_at, attendance\.id\) < \(p_cursor_at, p_cursor_id\)/);
  assert.match(migration, /limit v_limit \+ 1/g);
  assert.match(migration, /attendance\.patient_id = v_session\.patient_id[\s\S]*?attendance\.status = 'completed'/);
  assert.match(migration, /item\.service_name[\s\S]*?item\.unit_price[\s\S]*?item\.discount_percent[\s\S]*?item\.line_total/);
  assert.doesNotMatch(migration, /grant execute[\s\S]*?to (?:anon|authenticated)/i);

  for (const signature of [
    "patient_portal_history_page\\(text, timestamptz, text, integer\\)",
    "patient_portal_attendance_page\\(text, timestamptz, bigint, integer\\)",
    "patient_portal_attendance_detail\\(text, bigint\\)",
  ]) {
    assert.match(migration, new RegExp(`revoke all on function public\\.${signature}[\\s\\S]*?from public, anon, authenticated, service_role`));
    assert.match(migration, new RegExp(`grant execute on function public\\.${signature}[\\s\\S]*?to service_role`));
  }
});

test("history and attendance surfaces are paginated, no-store and read-only", async () => {
  const [service, shell, history, attendances, historyRoute, attendanceRoute, detailRoute, styles] = await Promise.all([
    read("app/lib/patient-portal.ts"),
    read("app/components/patient-portal-shell.tsx"),
    read("app/components/patient-portal-history.tsx"),
    read("app/components/patient-portal-attendances.tsx"),
    read("app/api/patient-portal/history/route.ts"),
    read("app/api/patient-portal/attendances/route.ts"),
    read("app/api/patient-portal/attendances/[id]/route.ts"),
    read("app/brand.css"),
  ]);

  assert.match(service, /p_limit: 20/g);
  assert.doesNotMatch(service, /p_patient_id|patientId/);
  assert.match(shell, /Resumo/);
  assert.match(shell, /Histórico/);
  assert.match(shell, /Atendimentos/);
  assert.doesNotMatch(shell, /Gastos/);
  assert.match(history, /Carregar mais/);
  assert.match(history, /Ver atendimento/);
  assert.match(attendances, /Total gasto no hospital/);
  assert.match(attendances, /Valores históricos/);
  assert.match(attendances, /Valor unitário/);
  assert.match(attendances, /Desconto aplicado/);
  assert.match(attendances, /Total final/);
  assert.doesNotMatch(`${history}\n${attendances}`, /Editar|Excluir|Cancelar atendimento|Emitir laudo/);
  for (const route of [historyRoute, attendanceRoute, detailRoute]) {
    assert.match(route, /"cache-control": "private, no-store"/);
    assert.match(route, /vary: "Cookie"/);
  }
  assert.match(styles, /html\[data-theme="dark"\][\s\S]*?\.patient-portal-timeline/);
  assert.match(styles, /@media \(max-width: 520px\)[\s\S]*?\.patient-portal-attendance-list/);
  assert.match(styles, /@media \(prefers-reduced-motion: reduce\)[\s\S]*?\.patient-portal-nav a/);
});
