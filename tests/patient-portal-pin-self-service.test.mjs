import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");
const migrationPath = "supabase/migrations/20260923152912_patient_portal_pin_and_self_service.sql";

test("patient login is passport plus four-digit PIN with a dedicated first-access path", async () => {
  const [route, form, migration] = await Promise.all([
    read("app/api/patient-portal/login/route.ts"),
    read("app/components/login-form.tsx"),
    read(migrationPath),
  ]);

  assert.match(route, /patient_portal_access_state/);
  assert.match(route, /patient_portal_create_pin_session/);
  assert.match(route, /PIN_PATTERN = \/\^\[0-9\]\{4\}\$\//);
  assert.match(route, /Paciente não encontrado\./);
  assert.match(route, /PIN incorreto\./);
  assert.match(form, /"passport" \| "create-pin" \| "pin"/);
  assert.match(form, /PRIMEIRO ACESSO/);
  assert.match(form, /Criar PIN e entrar/);
  assert.doesNotMatch(`${route}\n${form}`, /birthDate|Data de nascimento|p_birth_date/);
  assert.match(migration, /drop function if exists public\.patient_portal_create_session\(text, date, text, text, text\)/);
});

test("PIN storage is private, bcrypt-only and never returned or audited", async () => {
  const migration = await read(migrationPath);
  const credentials = migration.match(/create table private\.patient_portal_credentials[\s\S]*?\);/)?.[0] ?? "";
  const createPin = migration.match(/create or replace function public\.patient_portal_create_pin_session[\s\S]*?\n\$\$;/)?.[0] ?? "";

  assert.match(credentials, /pin_hash text not null/);
  assert.doesNotMatch(credentials, /\bpin\b text/);
  assert.match(migration, /alter table private\.patient_portal_credentials force row level security/);
  assert.match(migration, /revoke all on private\.patient_portal_credentials[\s\S]*?service_role/);
  assert.match(createPin, /extensions\.crypt\(p_pin, extensions\.gen_salt\('bf', 12\)\)/);
  const auditSection = createPin.slice(createPin.lastIndexOf("insert into public.audit_logs"));
  assert.doesNotMatch(auditSection, /p_pin|pin_hash/);
  assert.match(migration, /PATIENT_PORTAL_PIN_CREATED/);
});

test("patient self-service is session-owned and passport is not an update argument", async () => {
  const [migration, route, page, form, shell] = await Promise.all([
    read(migrationPath),
    read("app/api/patient-portal/profile/route.ts"),
    read("app/portal-paciente/meus-dados/page.tsx"),
    read("app/components/patient-portal-profile.tsx"),
    read("app/components/patient-portal-shell.tsx"),
  ]);
  const updateFunction = migration.match(/create or replace function public\.patient_portal_update_profile[\s\S]*?\n\$\$;/)?.[0] ?? "";

  assert.match(updateFunction, /private\.patient_portal_session_record\(p_token_hash\)/);
  assert.doesNotMatch(updateFunction.split("returns jsonb")[0] ?? "", /p_passport|p_patient_id/);
  assert.match(updateFunction, /PATIENT_PORTAL_PROFILE_UPDATED|hpsm\.patient_portal_patient_id/);
  assert.match(route, /Object\.keys\(body\)\.some/);
  assert.doesNotMatch(route.match(/const PROFILE_KEYS[\s\S]*?as const/)?.[0] ?? "", /passport|patientId/);
  assert.match(page, /dynamic = "force-dynamic"/);
  assert.match(form, /readOnly value=\{formatPatientPassport\(initialPatient\.passport\)\}/);
  assert.match(form, /não pode ser alterado pelo Portal/);
  assert.match(form, /“Não possui”/);
  assert.match(form, /function cancel\(\)/);
  assert.match(shell, /\/portal-paciente\/meus-dados/);
});

test("PIN reset is restricted to levels 11 through 14 and revokes all sessions", async () => {
  const [migration, route, profile] = await Promise.all([
    read(migrationPath),
    read("app/api/patient-portal/reset-pin/route.ts"),
    read("app/components/patient-profile.tsx"),
  ]);
  const resetFunction = migration.match(/create or replace function public\.reset_patient_portal_pin[\s\S]*?\n\$\$;/)?.[0] ?? "";

  assert.match(resetFunction, /private\.hpsm_current_actor\(\)/);
  assert.match(resetFunction, /coalesce\(private\.current_position_level\(v_actor\), 0\) not between 11 and 14/);
  assert.match(resetFunction, /delete from private\.patient_portal_credentials/);
  assert.match(resetFunction, /update public\.patient_portal_sessions[\s\S]*?revoked_at/);
  assert.match(resetFunction, /PATIENT_PORTAL_PIN_RESET/);
  assert.doesNotMatch(resetFunction, /temporary|temp_pin|p_pin/);
  assert.match(route, /positionLevel < 11 \|\| context\.positionLevel > 14/);
  assert.match(profile, /Redefinir o PIN do paciente\?/);
  assert.match(profile, /no próximo acesso, o paciente criará um novo PIN/);
});

test("portal profile works on small screens and both themes", async () => {
  const styles = await read("app/brand.css");
  assert.match(styles, /\.patient-portal-profile-grid/);
  assert.match(styles, /html\[data-theme="dark"\] \.patient-portal-profile-grid/);
  assert.match(styles, /@media \(max-width: 520px\)[\s\S]*?\.patient-portal-profile-grid \{ grid-template-columns: 1fr; \}/);
  assert.match(styles, /\.patient-first-access-copy/);
});
