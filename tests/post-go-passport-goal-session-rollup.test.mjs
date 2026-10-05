import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("manual HPSM patient selection uses one accessible passport combobox", async () => {
  const [combobox, attendance, exams, casts, certificates, hospitalizations] = await Promise.all([
    read("app/components/patient-passport-combobox.tsx"),
    read("app/components/attendance-desk.tsx"),
    read("app/components/exam-center.tsx"),
    read("app/components/cast-control.tsx"),
    read("app/components/medical-certificate-center.tsx"),
    read("app/components/hospitalization-center.tsx"),
  ]);

  assert.match(combobox, /normalizePatientPassport\(value\)/);
  assert.match(combobox, /DEBOUNCE_MS = 150/);
  assert.match(combobox, /AbortController/);
  assert.match(combobox, /role="combobox"/);
  assert.match(combobox, /role="listbox"/);
  assert.match(combobox, /ArrowDown/);
  assert.match(combobox, /ArrowUp/);
  assert.match(combobox, /Nenhum paciente encontrado/);
  assert.match(combobox, /mousedown/);
  for (const source of [attendance, exams, casts, certificates, hospitalizations]) {
    assert.match(source, /PatientPassportCombobox/);
  }
  for (const source of [exams, casts, certificates, hospitalizations]) {
    assert.doesNotMatch(source, /view: "list", page: "1", pageSize: "8", search: patientSearch/);
  }
  assert.match(hospitalizations, /source === "hpsm"/);
  assert.match(hospitalizations, /Nome do paciente externo/);
  assert.match(hospitalizations, /Passaporte externo \(opcional\)/);
});

test("RH mostra no hero a meta acumulada do contador da cidade", async () => {
  const [hr, dashboard, card, compact, shell] = await Promise.all([
    read("app/lib/hr.ts"),
    read("app/components/professional-dashboard.tsx"),
    read("app/components/hr-week-card.tsx"),
    read("app/components/hr-week-compact.tsx"),
    read("app/components/persistent-app-shell.tsx"),
  ]);

  assert.match(hr, /baseRequiredMinutes: 600/);
  assert.match(hr, /counterTargetMinutes/);
  assert.match(hr, /Math\.max\(0, requiredMinutes - previousSegment\.workedMinutes\)/);
  assert.match(hr, /const previousSegment = calculateWorkedMinutes/);
  for (const source of [card, compact]) {
    assert.match(source, /Objetivo no contador/);
    assert.match(source, /monthlyAccumulated/);
    assert.match(source, /workedMinutes/);
    assert.match(source, /requiredMinutes/);
  }
  assert.match(hr, /targetMinutes: weekBaselineMinutes === null \? null : weekBaselineMinutes \+ requiredMinutes/);
  assert.match(dashboard, /const target = progress\.counterTargetMinutes/);
  assert.match(dashboard, /const current = progress\.monthlyAccumulated/);
  assert.match(dashboard, /Meta no contador da cidade/);
  assert.match(dashboard, /<DashboardHeroGoal progress=\{weeklyProgress\}/);
  assert.match(shell, /pathname !== "\/painel" && live\.weeklyProgress \? <HrWeekCompact/);
  assert.match(card, /percent/);
  assert.match(compact, /percent/);
});

test("professional and patient sessions persist while explicit revocation remains", async () => {
  const [worker, professionalLogin, cookiePolicy, portal, portalLogin, migration, professionalLogout, portalLogout] = await Promise.all([
    read("worker/index.ts"),
    read("app/api/auth/login/route.ts"),
    read("app/lib/session-cookie-policy.ts"),
    read("app/lib/patient-portal.ts"),
    read("app/api/patient-portal/login/route.ts"),
    read("supabase/migrations/20260923200706_persistent_patient_portal_sessions.sql"),
    read("app/api/auth/logout/route.ts"),
    read("app/api/patient-portal/logout/route.ts"),
  ]);

  assert.match(worker, /grant_type=refresh_token/);
  assert.match(worker, /autoRefreshToken: true, persistSession: true/);
  assert.match(worker, /hp_access_token/);
  assert.match(worker, /hp_refresh_token/);
  assert.match(worker, /sessionUnavailable/);
  assert.match(professionalLogin, /persistentSessionCookieExpires\(\)/);
  assert.match(cookiePolicy, /9999-12-31/);
  assert.doesNotMatch(portal, /PATIENT_PORTAL_SESSION_SECONDS/);
  assert.match(portalLogin, /PATIENT_PORTAL_COOKIE_EXPIRES\(\)/);
  assert.match(migration, /alter column expires_at drop not null/);
  assert.match(migration, /new\.expires_at := null/);
  assert.match(migration, /session\.expires_at is null or session\.expires_at > clock_timestamp\(\)/);
  assert.match(professionalLogout, /maxAge: 0/);
  assert.match(portalLogout, /patient_portal_revoke_session/);
});
