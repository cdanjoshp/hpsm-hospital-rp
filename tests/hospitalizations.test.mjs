import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("bed control seeds exactly ten canonical beds and derives occupancy", async () => {
  const migration = await read("supabase/migrations/20260922040000_post_go_hospital_beds.sql");
  assert.match(migration, /from generate_series\(1, 10\)/);
  assert.match(migration, /number between 1 and 10/);
  assert.match(migration, /Leito ' \|\| lpad\(number::text, 2, '0'\)/);
  assert.match(migration, /left join public\.hospitalizations hospitalization[\s\S]*hospitalization\.status = 'active'/);
  const bedTable = migration.match(/create table public\.hospital_beds \(([\s\S]*?)\n\);/)?.[1] ?? "";
  assert.ok(bedTable);
  assert.doesNotMatch(bedTable, /\bstatus\b/i);
});

test("database prevents active bed and canonical patient duplication", async () => {
  const migration = await read("supabase/migrations/20260922040000_post_go_hospital_beds.sql");
  assert.match(migration, /create unique index hospitalizations_one_active_per_bed_uidx[\s\S]*where status = 'active'/);
  assert.match(migration, /create unique index hospitalizations_one_active_per_patient_uidx[\s\S]*patient_id is not null/);
  assert.match(migration, /from public\.hospital_beds where id = p_bed_id and active for update/);
  assert.match(migration, /from public\.patients where id = p_patient_id for update/);
  assert.match(migration, /HPSM_BED_OCCUPIED/);
  assert.match(migration, /HPSM_PATIENT_ALREADY_ADMITTED/);
});

test("HPSM and HP Norte have separated identities without creating patients", async () => {
  const migration = await read("supabase/migrations/20260922040000_post_go_hospital_beds.sql");
  assert.match(migration, /source in \('hpsm', 'hp_norte'\)/);
  assert.match(migration, /source = 'hpsm' and patient_id is not null/);
  assert.match(migration, /source = 'hp_norte' and patient_id is null and external_patient_name is not null/);
  assert.doesNotMatch(migration, /insert into public\.patients/i);
});

test("discharge, cancellation and immutable history preserve audit", async () => {
  const migration = await read("supabase/migrations/20260922040000_post_go_hospital_beds.sql");
  assert.match(migration, /p_discharged_at < v_old\.admitted_at/);
  assert.match(migration, /Somente uma internação ativa pode receber alta/);
  assert.match(migration, /Somente uma internação ativa pode ser cancelada/);
  assert.match(migration, /HOSPITALIZATION_CREATED/);
  assert.match(migration, /HOSPITALIZATION_UPDATED/);
  assert.match(migration, /HOSPITALIZATION_DISCHARGED/);
  assert.match(migration, /HOSPITALIZATION_CANCELLED/);
  assert.doesNotMatch(migration, /delete from public\.hospitalizations/i);
});

test("module uses granular permissions, forced RLS and authenticated RPCs", async () => {
  const [migration, api, page] = await Promise.all([
    read("supabase/migrations/20260922040000_post_go_hospital_beds.sql"),
    read("app/api/hospitalizations/route.ts"),
    read("app/internacoes/page.tsx"),
  ]);
  for (const permission of ["hospitalizations.view", "hospitalizations.create", "hospitalizations.update", "hospitalizations.discharge", "hospitalizations.history"]) {
    assert.match(migration, new RegExp(permission.replace(".", "\\.")));
  }
  assert.equal((migration.match(/force row level security/g) ?? []).length, 2);
  assert.match(migration, /revoke all on public\.hospitalizations from public, anon, authenticated, service_role/);
  assert.match(migration, /grant execute on function public\.create_hospitalization[\s\S]*to authenticated/);
  assert.match(api, /requirePermission\(permissions, "hospitalizations\.discharge"\)/);
  assert.match(page, /permissions\.includes\("hospitalizations\.view"\)/);
});

test("responsive UI exposes board, history and lazy patient profile integration", async () => {
  const [component, navigation, shell, profile, styles] = await Promise.all([
    read("app/components/hospitalization-center.tsx"),
    read("app/lib/sidebar-navigation.ts"),
    read("app/components/persistent-app-shell.tsx"),
    read("app/components/patient-profile.tsx"),
    read("app/brand.css"),
  ]);
  assert.match(component, /10 leitos compartilhados/);
  assert.match(component, /Paciente externo do HP Norte/);
  assert.match(component, /Paciente ou passaporte/);
  assert.match(component, /Registrar alta/);
  assert.match(navigation, /href: "\/internacoes"/);
  assert.match(shell, /pathname\.startsWith\("\/internacoes"\)/);
  assert.match(profile, /dynamic\(\(\) => import\("\.\/patient-hospitalizations-tab"\)/);
  assert.match(styles, /\.bed-grid \{ display: grid; grid-template-columns: repeat\(5/);
  assert.match(styles, /@media \(max-width: 430px\)[\s\S]*\.bed-grid \{ grid-template-columns: 1fr/);
  assert.match(styles, /html\[data-theme="dark"\][^\n]*\.bed-toolbar/);
});
