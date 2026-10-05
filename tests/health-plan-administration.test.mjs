import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("administrative health-plan access is restricted to official levels 11–14", async () => {
  const [page, route, migration] = await Promise.all([
    read("app/pacientes/[id]/page.tsx"),
    read("app/api/health-plans/admin/route.ts"),
    read("supabase/migrations/20260916160902_administrative_health_plan_activation.sql"),
  ]);

  assert.match(page, /permissions\.includes\("healthplans\.review"\)[\s\S]*positionLevel >= 11[\s\S]*positionLevel <= 14/);
  assert.match(route, /context\.positionLevel < 11[\s\S]*context\.positionLevel > 14[\s\S]*healthplans\.review/);
  assert.match(migration, /private\.has_permission\(v_actor, 'healthplans\.review'\)[\s\S]*private\.current_position_level\(v_actor\)[\s\S]*between 11 and 14/);
  assert.doesNotMatch(route, /service[_-]?role/i);
});

test("administrative grant is append-only, canonical and has no financial origin", async () => {
  const migration = await read("supabase/migrations/20260916160902_administrative_health_plan_activation.sql");

  assert.match(migration, /alter column attendance_id drop not null/);
  assert.match(migration, /origin = 'administrative'[\s\S]*attendance_id is null[\s\S]*status = 'approved'/);
  assert.match(migration, /insert into public\.patient_health_plan_requests/);
  assert.doesNotMatch(migration, /update public\.patient_health_plan_requests[\s\S]{0,500}administrative_action/);
  assert.match(migration, /'financial_value', 0/);
  assert.match(migration, /order by request\.reviewed_at desc nulls last, request\.id desc/g);
  assert.match(migration, /patient_plan_history_page/);
  assert.match(migration, /patient_timeline/);
});

test("patient profile explains and confirms the no-charge operation accessibly", async () => {
  const [profile, styles, cache, attendance, patientLookup] = await Promise.all([
    read("app/components/patient-profile.tsx"),
    read("app/globals.css"),
    read("app/lib/patient-client-cache.ts"),
    read("app/components/attendance-desk.tsx"),
    read("app/components/patient-passport-combobox.tsx"),
  ]);

  assert.match(profile, /Conceder plano sem cobrança/);
  assert.match(profile, /Esta operação não cria venda, atendimento ou valor financeiro/);
  assert.match(profile, /Nenhuma venda, atendimento ou cobrança será criada/);
  assert.match(profile, /aria-modal="true"/);
  assert.match(profile, /event\.key === "Escape"/);
  assert.doesNotMatch(profile, /window\.confirm|\bconfirm\(/);
  assert.match(profile, /payload\.financialValue !== 0/);
  assert.match(profile, /invalidatePatientClientCache\(\)/);
  assert.match(cache, /localStorage/);
  assert.match(attendance, /clearPatientPassportLookupCache/);
  assert.match(patientLookup, /readPatientCacheVersion/);
  assert.match(styles, /patient-plan-admin-overlay/);
  assert.match(styles, /\[data-theme="dark"\][\s\S]*patient-plan-admin/);
  assert.match(styles, /@media \(max-width: 620px\)[\s\S]*patient-plan-admin/);
});

test("pending paid plan is resolved through the existing review flow", async () => {
  const [profile, migration] = await Promise.all([
    read("app/components/patient-profile.tsx"),
    read("supabase/migrations/20260916160902_administrative_health_plan_activation.sql"),
  ]);

  assert.match(profile, /Solicitação aguardando confirmação/);
  assert.match(profile, /Abrir Pendências/);
  assert.match(migration, /v_action = 'grant'[\s\S]*status = 'pending'[\s\S]*Analise a pendência/);
});
