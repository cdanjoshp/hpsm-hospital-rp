import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("birth date is optional in patient creation and edit flows", async () => {
  const [migration, api, create, edit, attendance, patientType, directory] = await Promise.all([
    read("supabase/migrations/20260923152912_patient_portal_pin_and_self_service.sql"),
    read("app/api/patients/route.ts"),
    read("app/components/patient-create-form.tsx"),
    read("app/components/patient-edit-form.tsx"),
    read("app/components/attendance-desk.tsx"),
    read("app/lib/operational-data.ts"),
    read("app/lib/patient-center.ts"),
  ]);

  assert.match(migration, /new\.birth_date is not null and new\.birth_date > current_date/);
  assert.doesNotMatch(migration.match(/create or replace function private\.enforce_patient_birth_date[\s\S]*?\$\$;/)?.[0] ?? "", /birth_date is null/);
  assert.match(migration, /to_jsonb\(new\) - 'birth_date'/);
  assert.match(api, /body\.birthDate\.trim\(\) \|\| null/);
  assert.match(api, /birthDate && !isValidBirthDate\(birthDate\)/);
  assert.match(api, /birth_date: birthDate/g);
  for (const source of [create, edit, attendance]) {
    assert.match(source, /Data de nascimento \(opcional\)/);
    assert.match(source, /type="date"/);
    assert.doesNotMatch(source, /Data de nascimento<input required/);
    assert.match(source, /birthDate/);
  }
  assert.match(patientType, /birth_date: string \| null/);
  assert.match(directory, /birth_date/);
});

test("patient portal uses an opaque HttpOnly session and never accepts a patient id", async () => {
  const [session, login, me, logout, page, summaryView, shell] = await Promise.all([
    read("app/lib/patient-portal.ts"),
    read("app/api/patient-portal/login/route.ts"),
    read("app/api/patient-portal/me/route.ts"),
    read("app/api/patient-portal/logout/route.ts"),
    read("app/portal-paciente/page.tsx"),
    read("app/components/patient-portal-summary.tsx"),
    read("app/components/patient-portal-shell.tsx"),
  ]);

  assert.match(session, /crypto\.getRandomValues\(new Uint8Array\(32\)\)/);
  assert.match(session, /crypto\.subtle\.digest\("SHA-256"/);
  assert.match(login, /httpOnly: true/);
  assert.match(login, /sameSite: "lax"/);
  assert.match(login, /secure: process\.env\.NODE_ENV === "production"/);
  assert.match(login, /PATIENT_PORTAL_COOKIE_EXPIRES/);
  assert.match(me, /resolvePatientPortalSession/);
  assert.match(logout, /patient_portal_revoke_session/);
  assert.match(shell, /Olá,/);
  assert.match(shell, /somente para consulta/i);
  for (const source of [session, login, me, logout, page, summaryView, shell]) {
    assert.doesNotMatch(source, /patientId|patient_id/);
    assert.doesNotMatch(source, /localStorage|sessionStorage/);
  }
});

test("portal database surface is service-only, PIN rate limited and patient-scoped", async () => {
  const [foundation, migration] = await Promise.all([
    read("supabase/migrations/20260909165000_phase61_patient_portal_foundation.sql"),
    read("supabase/migrations/20260923152912_patient_portal_pin_and_self_service.sql"),
  ]);
  assert.match(foundation, /create table if not exists public\.patient_portal_sessions/);
  assert.match(foundation, /token_hash text not null/);
  assert.match(foundation, /patient_id bigint not null references public\.patients/);
  assert.doesNotMatch(foundation.match(/create table if not exists public\.patient_portal_sessions[\s\S]*?\);/)?.[0] ?? "", /birth_date|passport/);
  assert.match(migration, /create table private\.patient_portal_credentials/);
  assert.match(migration, /extensions\.crypt\(p_pin, extensions\.gen_salt\('bf', 12\)\)/);
  assert.match(migration, /force row level security/);
  assert.match(migration, /revoke all on private\.patient_portal_credentials[\s\S]*?service_role/);
  assert.match(migration, /grant execute on function public\.patient_portal_create_session\(text, text, text, text, text\) to service_role/);
  assert.match(migration, /v_passport_failures >= 5/);
  assert.match(migration, /v_origin_failures >= 20/);
  assert.doesNotMatch(migration.match(/create function public\.patient_portal_create_session[\s\S]*?\$\$;/)?.[0] ?? "", /birth_date|p_birth_date/);
  assert.match(migration, /private\.patient_portal_session_record\(p_token_hash\)/);
  assert.doesNotMatch(migration, /grant (?:select|all)[\s\S]*?patient_portal_credentials[\s\S]*?to anon/i);
});

test("public entry clearly separates professional and patient access", async () => {
  const [home, accessChoice, portal, shell, patientLogin] = await Promise.all([
    read("app/page.tsx"),
    read("app/components/login-form.tsx"),
    read("app/portal-paciente/page.tsx"),
    read("app/components/patient-portal-shell.tsx"),
    read("app/api/patient-portal/login/route.ts"),
  ]);
  assert.match(home, /public-access-card/);
  assert.match(accessChoice, /Sou Profissional/);
  assert.match(accessChoice, /Sou Paciente/);
  assert.match(accessChoice, /access === "professional"/);
  assert.match(accessChoice, /access === "patient"/);
  assert.match(accessChoice, /fetch\("\/api\/patient-portal\/login"/);
  assert.match(shell, /action="\/api\/patient-portal\/logout"/);
  assert.match(accessChoice, /PRIMEIRO ACESSO/);
  assert.doesNotMatch(accessChoice, /Formato DD\/MM\/AAAA|Data de nascimento/);
  assert.match(portal, /redirect\(errorCode/);
  assert.match(patientLogin, /patient_portal_create_session/);
});
