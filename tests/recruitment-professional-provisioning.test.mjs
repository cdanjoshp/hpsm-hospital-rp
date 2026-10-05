import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");

test("recruitment approval keeps the application and links one canonical professional", async () => {
  const migration = await read("supabase/migrations/20260923030803_recruitment_professional_provisioning.sql");

  assert.match(migration, /add column professional_user_id uuid/);
  assert.match(migration, /foreign key \(professional_user_id\)[\s\S]*references public\.profiles\(user_id\)/);
  assert.match(migration, /professional_passport ~ '\^\[0-9\]\{4\}\$'/);
  assert.match(migration, /create unique index profiles_passport_canonical_unique_idx[\s\S]*lpad\(passport, 4, '0'\)/);
  assert.match(migration, /create unique index recruitment_professional_user_unique_idx/);
  assert.match(migration, /create unique index recruitment_professional_passport_unique_idx/);
  assert.match(migration, /provisioning_state text not null default 'not_started'/);
  const schemaSection = migration.split("create or replace function")[0];
  assert.doesNotMatch(schemaSection, /insert into public\.profiles|update public\.recruitment_applications/i);
});

test("approval is serialized, retryable and service-role only", async () => {
  const [migration, route] = await Promise.all([
    read("supabase/migrations/20260923030803_recruitment_professional_provisioning.sql"),
    read("app/api/recruitment/decide/route.ts"),
  ]);

  for (const functionName of [
    "begin_recruitment_professional_provisioning",
    "attach_recruitment_provisioning_auth_user",
    "complete_recruitment_professional_provisioning",
    "fail_recruitment_professional_provisioning",
  ]) {
    assert.match(migration, new RegExp(`function public\\.${functionName}`));
    assert.match(migration, new RegExp(`grant execute on function public\\.${functionName}[\\s\\S]*to service_role`));
  }
  assert.match(migration, /from public\.recruitment_applications[\s\S]*for update/);
  assert.match(migration, /provisioning_started_at > clock_timestamp\(\) - interval '5 minutes'/);
  assert.match(migration, /provisioning_attempts = provisioning_attempts \+ 1/);
  assert.match(route, /crypto\.randomUUID\(\)/);
  assert.match(route, /begin_recruitment_professional_provisioning/);
  assert.match(route, /findCompletedProvisioning/);
  assert.match(route, /fail_recruitment_professional_provisioning/);
  assert.match(route, /p_auth_user_id: authUserId/);
  assert.doesNotMatch(route, /deleteProfessionalAuthAccount/);
});

test("Auth creation is shared with Equipe e Acessos and never exposes the synthetic email", async () => {
  const [service, recruitmentRoute, usersRoute, bootstrap, resetRoute, normalization] = await Promise.all([
    read("app/lib/professional-account.ts"),
    read("app/api/recruitment/decide/route.ts"),
    read("app/api/users/route.ts"),
    read("app/api/bootstrap/route.ts"),
    read("app/api/users/reset-password/route.ts"),
    read("app/lib/supabase-server.ts"),
  ]);

  assert.match(service, /crypto\.getRandomValues/);
  assert.match(service, /deriveSyntheticEmail\(passport\)/);
  assert.match(service, /origin: "RECRUITMENT_APPLICATION"/);
  assert.match(service, /recruitment_application_id: applicationId/);
  assert.match(service, /findRecruitmentAuthUser/);
  assert.match(service, /response\.status === 404[\s\S]*return null/);
  assert.doesNotMatch(service, /console\.|temporaryPassword.*audit|password.*audit/i);
  assert.match(recruitmentRoute, /ensureRecruitmentProfessionalAuthAccount/);
  assert.match(usersRoute, /createProfessionalAuthAccount\(passport, \{ origin: "MANUAL" \}\)/);
  assert.match(bootstrap, /createProfessionalAuthAccount\(passport, \{ origin: "BOOTSTRAP" \}\)/);
  assert.match(resetRoute, /setProfessionalTemporaryPassword/);
  assert.match(normalization, /normalizePassport\(value\)\.padStart\(4, "0"\)/);
  assert.doesNotMatch(recruitmentRoute, /deriveSyntheticEmail|auth\/v1\/admin\/users/);
});

test("new profiles wait for first-access completion before CRM and signature flow", async () => {
  const [migration, passwordRoute] = await Promise.all([
    read("supabase/migrations/20260923030803_recruitment_professional_provisioning.sql"),
    read("app/api/auth/change-password/route.ts"),
  ]);

  assert.match(migration, /must_change_password,[\s\S]*true/);
  assert.match(migration, /if new\.must_change_password then[\s\S]*return new/);
  assert.match(migration, /after insert or update of must_change_password on public\.profiles/);
  assert.match(passwordRoute, /must_change_password: false[\s\S]*callProfessionalIdentityGeneration/);
});

test("recruitment UI confirms automatic creation and shows the credential only once", async () => {
  const [component, dataSource, styles] = await Promise.all([
    read("app/components/recruitment-management.tsx"),
    read("app/lib/recruitment-management.ts"),
    read("app/brand.css"),
  ]);

  assert.match(component, /cadastrado automaticamente como profissional do HPSM/);
  assert.match(component, /Candidatura aprovada · exibição única/);
  assert.match(component, /A senha não poderá ser consultada novamente/);
  assert.match(component, /Profissional criado/);
  assert.match(component, /Estagiário de Enfermagem/);
  assert.match(component, /\/administrativo\/perfis\?selecionar=/);
  assert.match(component, /Tentar cadastro novamente/);
  assert.match(dataSource, /professional_user_id,professional_passport,initial_position_id,professional_created_at,provisioning_state,provisioning_error_code/);
  assert.match(styles, /\.application-professional-action/);
  assert.match(styles, /html\[data-theme="dark"\] \.application-professional-action/);
  assert.match(styles, /@media \(max-width: 620px\)[\s\S]*\.application-professional-action/);
});

test("rejection remains isolated from professional provisioning", async () => {
  const [migration, route] = await Promise.all([
    read("supabase/migrations/20260923030803_recruitment_professional_provisioning.sql"),
    read("app/api/recruitment/decide/route.ts"),
  ]);

  assert.match(migration, /if p_decision = 'approved' then[\s\S]*A aprovação exige o provisionamento profissional automático/);
  assert.match(migration, /set status = 'rejected'/);
  assert.match(route, /if \(decision === "rejected"\)[\s\S]*registerRejection/);
  assert.doesNotMatch(route.match(/async function registerRejection[\s\S]*?\n}\n\nasync function approveAndProvision/)?.[0] ?? "", /createProfessionalAuthAccount|ensureRecruitmentProfessionalAuthAccount/);
});
