import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");
const migrationPath = "supabase/migrations/20260922144500_post_go_canonical_patient_passports.sql";
const triggerFixPath = "supabase/migrations/20260923010857_fix_patient_passport_trigger_permissions.sql";
const birthDateTriggerFixPath = "supabase/migrations/20260923011257_fix_patient_birth_date_trigger_permissions.sql";

test("pacientes usam uma normalização canônica de quatro dígitos sem alterar profissionais", async () => {
  const [passport, patientsApi, professionalAuth] = await Promise.all([
    read("app/lib/passport.ts"),
    read("app/api/patients/route.ts"),
    read("app/lib/supabase-server.ts"),
  ]);
  assert.match(passport, /normalizePatientPassport[\s\S]*?PASSPORT_PATTERN\.test[\s\S]*?padStart\(4, "0"\)/);
  assert.match(passport, /normalizePatientSearch[\s\S]*?normalizePatientPassport/);
  assert.match(patientsApi, /normalizePatientPassport\(value\)/);
  assert.match(patientsApi, /Passaporte já cadastrado\./);
  assert.match(professionalAuth, /export function normalizePassport[\s\S]*?return normalized;/);
  const normalizerStart = professionalAuth.indexOf("export function normalizePassport");
  const normalizerEnd = professionalAuth.indexOf("\nexport function", normalizerStart + 1);
  const professionalNormalizer = professionalAuth.slice(
    normalizerStart,
    normalizerEnd === -1 ? undefined : normalizerEnd,
  );
  assert.doesNotMatch(professionalNormalizer, /padStart/);
});

test("cadastro rejeita caracteres arbitrários em vez de removê-los silenciosamente", async () => {
  const [createForm, editForm, attendance, combobox] = await Promise.all([
    read("app/components/patient-create-form.tsx"),
    read("app/components/patient-edit-form.tsx"),
    read("app/components/attendance-desk.tsx"),
    read("app/components/patient-passport-combobox.tsx"),
  ]);
  for (const source of [createForm, editForm, attendance, combobox]) {
    assert.match(source, /normalizePatientPassport/);
    assert.doesNotMatch(source, /sanitizePassportInput/);
  }
  assert.match(createForm, /passport: canonicalPassport/);
  assert.match(editForm, /passport: canonicalPassport/);
  assert.match(attendance, /PatientPassportCombobox/);
  assert.match(combobox, /void lookup\(normalized\)/);
});

test("banco normaliza antes da unicidade e mantém auditoria da conciliação", async () => {
  const sql = await read(migrationPath);
  assert.match(sql, /create or replace function private\.normalize_patient_passport/);
  assert.match(sql, /return lpad\(v_value, 4, '0'\)/);
  assert.match(sql, /create trigger patients_canonicalize_passport[\s\S]*?before insert or update of passport/);
  assert.match(sql, /patients_passport_check check \(passport ~ '\^\[0-9\]\{4\}\$'\)/);
  assert.match(sql, /create table if not exists public\.patient_identity_reconciliations/);
  assert.match(sql, /Conflito de passaporte % possui vínculos e exige conciliação manual/);
  assert.match(sql, /Existem colisões de passaporte que exigem revisão manual/);
  assert.doesNotMatch(sql, /update public\.profiles[\s\S]*?passport/);
});

test("trigger canônico alcança o helper privado sem expô-lo à Data API", async () => {
  const [sql, birthDateSql, transaction] = await Promise.all([
    read(triggerFixPath),
    read(birthDateTriggerFixPath),
    read("tests/sql/post_go_patient_registration_transaction.sql"),
  ]);
  assert.match(sql, /alter function private\.canonicalize_patient_passport\(\) security definer/);
  assert.match(sql, /set search_path = ''/);
  assert.match(sql, /revoke all on function private\.canonicalize_patient_passport\(\)[\s\S]*?authenticated/);
  assert.match(birthDateSql, /alter function private\.enforce_patient_birth_date\(\) security definer/);
  assert.match(birthDateSql, /set search_path = ''/);
  assert.match(birthDateSql, /revoke all on function private\.enforce_patient_birth_date\(\)[\s\S]*?authenticated/);
  assert.match(transaction, /set local role authenticated/);
  assert.match(transaction, /insert into public\.patients/);
  assert.match(transaction, /private\.normalize_patient_passport\(text\)/);
  assert.match(transaction, /rollback/);
});

test("RPCs, Portal, módulos clínicos e Busca Global reutilizam a chave canônica", async () => {
  const sql = await read(migrationPath);
  for (const functionName of [
    "hpsm_patient_quick_lookup",
    "patient_portal_create_session",
    "hpsm_partnership_patient_lookup",
    "clinical_cast_page",
    "clinical_exam_page",
    "medical_certificate_page",
    "hospitalization_history_page",
    "hpsm_global_search",
  ]) {
    assert.match(sql, new RegExp(`create function public\\.${functionName}`));
  }
  assert.match(sql, /private\.normalize_patient_search\(p_search\)/);
  assert.match(sql, /hpsm_global_search_pre_canonical\(v_canonical, p_limit\)/);
  assert.match(sql, /patient_portal_create_session_pre_canonical\([\s\S]*?private\.normalize_patient_passport\(p_passport\)/);
});

test("diretório e documentos apresentam passaportes de pacientes em quatro dígitos", async () => {
  const [directory, formatter, pdf, png, certificate] = await Promise.all([
    read("app/lib/patient-center.ts"),
    read("app/lib/passport.ts"),
    read("app/lib/final-exam-pdf.ts"),
    read("app/lib/final-exam-png.ts"),
    read("app/lib/medical-certificate-png.ts"),
  ]);
  assert.match(directory, /normalizePatientSearch\(cleanSearch\(options\.search\)\)/);
  assert.match(directory, /passport", `eq\.\$\{search\}`/);
  assert.match(formatter, /formatPatientPassport[\s\S]*?padStart\(4, "0"\)/);
  for (const source of [pdf, png, certificate]) assert.match(source, /formatPatientPassport/);
});
