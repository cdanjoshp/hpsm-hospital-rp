import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");

test("phase 10.3 provisions one immutable CRM identity for every professional", async () => {
  const migration = await read("supabase/migrations/20260915052812_phase103_professional_identity.sql");
  assert.match(migration, /create table public\.professional_identities/);
  assert.match(migration, /user_id uuid primary key references public\.profiles/);
  assert.match(migration, /crm_code text not null unique/);
  assert.match(migration, /lpad\(p_passport, 4, '0'\) \|\| to_char\(p_registration_date, 'DDMM'\)/);
  assert.match(migration, /professional_identities_crm_format check \(crm_code ~ '\^\[0-9\]\{8\}\$'\)/);
  assert.match(migration, /profiles_provision_professional_identity/);
  assert.match(migration, /insert into public\.professional_identities[\s\S]*from public\.profiles profile[\s\S]*on conflict \(user_id\) do nothing/);
});

test("generation is backend-only, idempotent and preserves access on failure", async () => {
  const [migration, edge, passwordRoute, initializer] = await Promise.all([
    read("supabase/migrations/20260915052812_phase103_professional_identity.sql"),
    read("supabase/functions/professional-identity/index.ts"),
    read("app/api/auth/change-password/route.ts"),
    read("app/components/professional-identity-initializer.tsx"),
  ]);
  assert.match(migration, /for update/);
  assert.match(migration, /current_generation_id = p_idempotency_key/);
  assert.match(migration, /generation_started_at > now\(\) - interval '5 minutes'/);
  assert.match(migration, /status = case when signature_image_path is not null and rubric_image_path is not null then 'active' else 'failed' end/);
  assert.match(edge, /Promise\.all\(\[\s*generateAsset[\s\S]*generateAsset/);
  assert.match(edge, /background: "transparent"/);
  assert.match(edge, /isTransparentPng/);
  assert.match(edge, /professionals\/\$\{targetUserId\}\/\$\{generationId\}\/signature\.png/);
  assert.match(edge, /professionals\/\$\{targetUserId\}\/\$\{generationId\}\/rubric\.png/);
  assert.doesNotMatch(edge, /upload aberto|manual upload|prompt.*body/i);
  assert.match(passwordRoute, /must_change_password: false[\s\S]*callProfessionalIdentityGeneration\(accessToken, \{ action: "ensure" \}\)[\s\S]*catch/);
  assert.match(passwordRoute, /return Response\.json\(\{ identityStatus, ok: true \}\)/);
  assert.match(initializer, /action: "ensure"/);
});

test("signature and rubric use coherent blue AI prompts without exposing them to the UI", async () => {
  const [edge, profile, api] = await Promise.all([
    read("supabase/functions/professional-identity/index.ts"),
    read("app/components/functional-profile.tsx"),
    read("app/api/professional-identity/route.ts"),
  ]);
  assert.match(edge, /gpt-image-2/);
  assert.match(edge, /#0B72B9/g);
  assert.match(edge, /styleDescriptor\(targetUserId\)/);
  assert.match(edge, /Não copie nem apenas reduza uma assinatura longa/);
  assert.match(edge, /parecer feita à mão com caneta sobre papel/);
  assert.match(edge, /variação humana de pressão/);
  assert.match(edge, /pequenas imperfeições naturais/);
  assert.match(edge, /Evite aparência de fonte/);
  assert.match(edge, /margens transparentes mínimas/);
  assert.match(profile, /Assinatura principal/);
  assert.match(profile, />Rubrica</);
  assert.doesNotMatch(profile, /signaturePrompt|rubricPrompt|OPENAI_API_KEY/);
  assert.doesNotMatch(api, /OPENAI_API_KEY|\/v1\/images\/generations/);
});

test("only the Director General receives audited correction and regeneration actions", async () => {
  const [migration, api, profile] = await Promise.all([
    read("supabase/migrations/20260915052812_phase103_professional_identity.sql"),
    read("app/api/professional-identity/route.ts"),
    read("app/components/functional-profile.tsx"),
  ]);
  assert.match(api, /context\.positionLevel !== 14/);
  assert.match(migration, /position\.level = 14/);
  assert.match(migration, /IDENTITY_CRM_CORRECTED/);
  assert.match(migration, /IDENTITY_SIGNATURE_REGENERATED/);
  assert.match(migration, /IDENTITY_RUBRIC_REGENERATED/);
  assert.match(migration, /IDENTITY_UNLOCKED/);
  assert.match(profile, /Ação exclusiva do Diretor Geral/);
  assert.match(profile, /Motivo obrigatório/);
  assert.match(profile, /event\.key === "Escape"/);
  assert.match(profile, /event\.key !== "Tab"/);
  assert.doesNotMatch(profile, /type="file"|canvas|pointermove/);
});

test("private versioned signature and rubric are embedded in official professional and patient documents", async () => {
  const [migration, legibilityMigration, frameMigration, officialMigration, identity, html, brand, pdf, png, template, portal] = await Promise.all([
    read("supabase/migrations/20260915052812_phase103_professional_identity.sql"),
    read("supabase/migrations/20260915141845_phase103_signature_legibility.sql"),
    read("supabase/migrations/20260918212239_signature_frame_v5.sql"),
    read("supabase/migrations/20260924222500_official_institutional_document_template.sql"),
    read("app/lib/professional-identity.ts"),
    read("app/components/final-exam-document.tsx"),
    read("app/brand.css"),
    read("app/lib/final-exam-pdf.ts"),
    read("app/lib/final-exam-png.ts"),
    read("app/lib/institutional-document-png.ts"),
    read("app/lib/patient-portal.ts"),
  ]);
  assert.match(migration, /'professional-identities', 'professional-identities', false/);
  assert.match(migration, /signature_image_path[\s\S]*rubric_image_path/);
  assert.match(migration, /'identity', case when responsible_identity\.status = 'active'/);
  assert.match(identity, /enrichClinicalExamIdentities/);
  assert.match(identity, /currentPosition \?\? person\.position/);
  assert.match(identity, /identidade profissional de \$\{person\.name\} ainda está sendo preparada/);
  assert.match(html, /CRM interno \{person\.identity\.crm_code\}/);
  assert.match(html, /signature_image_url/);
  assert.match(html, /rubric_image_url/);
  assert.match(brand, /final-exam-professional-identity \.final-exam-ink-signature \{[^}]*width: min\(320px, 100%\);[^}]*height: auto/);
  assert.match(pdf, /CRM interno \$\{this\.document\.executedBy\.identity\?\.crm_code/);
  assert.match(pdf, /drawImage\(signature/);
  assert.match(pdf, /drawImage\(rubric/);
  assert.match(png, /FINAL_EXAM_PNG_RENDER_VERSION/);
  assert.match(png, /renderOfficialInstitutionalDocument/);
  assert.match(template, /identity\.signatureBytes/);
  assert.match(template, /identity\.rubricBytes/);
  assert.match(template, /lastPageBottom: true/);
  assert.match(portal, /enrichClinicalExamIdentities/);
  assert.match(legibilityMigration, /'exam-document-png-v3',\s*'exam-document-png-v4'/);
  assert.match(legibilityMigration, /replace\(pg_get_functiondef\(v_function\), 'exam-document-png-v3', 'exam-document-png-v4'\)/);
  assert.match(frameMigration, /'exam-document-png-v4',\s*'exam-document-png-v5'/);
  assert.match(frameMigration, /replace\(pg_get_functiondef\(v_function\), 'exam-document-png-v4', 'exam-document-png-v5'\)/);
  assert.match(officialMigration, /'exam-document-png-v5',\s*'exam-document-png-v6'/);
});

test("identity storage and table reject direct authenticated writes", async () => {
  const migration = await read("supabase/migrations/20260915052812_phase103_professional_identity.sql");
  assert.match(migration, /force row level security/);
  assert.match(migration, /phase103_valid_session/);
  assert.match(migration, /revoke all on table public\.professional_identities from public, anon, authenticated, service_role/);
  assert.match(migration, /grant select on table public\.professional_identities to authenticated, service_role/);
  assert.doesNotMatch(migration, /create policy[\s\S]{0,120}professional-identities[\s\S]{0,120}for insert/i);
});
