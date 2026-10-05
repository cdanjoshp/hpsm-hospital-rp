import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { ModuleKind, ScriptTarget, transpileModule } from "typescript";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

const phoneSource = await read("app/lib/phone.ts");
const phoneCode = transpileModule(phoneSource, {
  compilerOptions: { module: ModuleKind.ESNext, target: ScriptTarget.ES2022 },
}).outputText;
const phoneRuntime = await import(`data:text/javascript;base64,${Buffer.from(phoneCode).toString("base64")}`);

test("patients page creates a patient directly without starting a sale", async () => {
  const [center, form] = await Promise.all([
    read("app/components/patient-center.tsx"),
    read("app/components/patient-create-form.tsx"),
  ]);
  assert.match(center, /＋ Novo paciente/);
  assert.match(center, /<PatientCreateForm/);
  assert.match(center, /setCreating\(true\)/);
  assert.match(form, /fetch\("\/api\/patients"/);
  assert.match(form, /method: "POST"/);
  assert.match(form, /Cadastrar paciente/);
  assert.doesNotMatch(form, /attendance|sale|atendimento|venda/i);
});

test("patient phone is optional, keeps the fixed 055 mask when filled and preserves the emergency pair", async () => {
  const [phone, create, attendance, edit, api, phoneMigration, emergencyMigration] = await Promise.all([
    read("app/lib/phone.ts"),
    read("app/components/patient-create-form.tsx"),
    read("app/components/attendance-desk.tsx"),
    read("app/components/patient-edit-form.tsx"),
    read("app/api/patients/route.ts"),
    read("supabase/migrations/20260917030234_optional_patient_phone.sql"),
    read("supabase/migrations/20260901040000_optional_patient_emergency_contact.sql"),
  ]);
  assert.match(phone, /HPSM_PHONE_PREFIX = "\(055\) "/);
  assert.match(phone, /HPSM_PHONE_PATTERN = \/\^\\\(055\\\) \[0-9\]\{3\}-\[0-9\]\{3\}\$\//);
  assert.match(phone, /digits\.startsWith\("055"\)/);
  for (const source of [create, attendance, edit]) {
    assert.match(source, /ensureHpsmPhonePrefix/);
    assert.match(source, /formatHpsmPhoneInput/);
    assert.match(source, /clearOptionalHpsmPhonePrefix/);
    assert.match(source, /parseOptionalHpsmPhone/);
    assert.match(source, /parseOptionalEmergencyContact/);
    assert.match(source, /pattern="\\\(055\\\) \[0-9\]\{3\}-\[0-9\]\{3\}"/);
    assert.match(source, /Telefone de contato \(opcional\)/);
    assert.doesNotMatch(source, /Telefone de contato \(opcional\)<input required/);
    assert.match(source, /Contato de emergência \(opcional\)/);
    assert.match(source, /Telefone de emergência \(opcional\)/);
    assert.doesNotMatch(source, /Contato de emergência \(opcional\)<input required/);
    assert.doesNotMatch(source, /Telefone de emergência \(opcional\)<input required/);
  }
  assert.match(api, /parseOptionalHpsmPhone/);
  assert.match(api, /phone: primaryPhone\.phone/);
  assert.match(api, /parseOptionalEmergencyContact/);
  assert.match(api, /emergency_contact_name: emergencyContact\.name/);
  assert.match(api, /emergency_contact_phone: emergencyContact\.phone/);
  assert.match(phoneMigration, /alter column phone drop not null/);
  assert.match(phoneMigration, /phone is null/);
  assert.match(phoneMigration, /patients_phone_check/);
  assert.match(emergencyMigration, /alter column emergency_contact_name drop not null/);
  assert.match(emergencyMigration, /alter column emergency_contact_phone drop not null/);
  assert.match(emergencyMigration, /patients_emergency_contact_pair_check/);
  assert.match(emergencyMigration, /emergency_contact_name is null/);
});

test("optional patient phone parser saves empty values as null and rejects malformed values", () => {
  assert.deepEqual(phoneRuntime.parseOptionalHpsmPhone(""), { error: null, phone: null });
  assert.deepEqual(phoneRuntime.parseOptionalHpsmPhone("(055) "), { error: null, phone: null });
  assert.deepEqual(phoneRuntime.parseOptionalHpsmPhone(" (055) 123-456 "), { error: null, phone: "(055) 123-456" });
  assert.equal(phoneRuntime.parseOptionalHpsmPhone("123456").phone, null);
  assert.match(phoneRuntime.parseOptionalHpsmPhone("123456").error, /deixe o campo em branco/);
  assert.equal(phoneRuntime.clearOptionalHpsmPhonePrefix("(055) "), "");
});

test("passport remains unique for patients and system users", async () => {
  const [patientsFoundation, profilesFoundation, patientApi, userApi, invariantMigration] = await Promise.all([
    read("supabase/migrations/202608240003_patient_registry.sql"),
    read("supabase/migrations/202608240001_phase1_foundation.sql"),
    read("app/api/patients/route.ts"),
    read("app/api/users/route.ts"),
    read("supabase/migrations/20260901040000_optional_patient_emergency_contact.sql"),
  ]);

  assert.match(patientsFoundation, /create unique index patients_passport_unique_idx/);
  assert.match(profilesFoundation, /passport text collate "C" not null unique/);
  assert.equal((patientApi.match(/Passaporte já cadastrado\./g) ?? []).length, 2);
  assert.match(userApi, /profiles\?select=user_id&passport=eq\./);
  assert.match(userApi, /Este passaporte já pertence a outro profissional\./);
  assert.match(userApi, /profileResponse\.status === 409/);
  assert.match(invariantMigration, /Existem pacientes com passaporte duplicado\./);
  assert.match(invariantMigration, /Existem profissionais com passaporte duplicado\./);
});
