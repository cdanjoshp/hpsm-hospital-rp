import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("medical certificates require a completed attendance for the same patient", async () => {
  const migration = await read("supabase/migrations/20260921212819_post_go_medical_certificates.sql");
  assert.match(migration, /attendance_id bigint not null references public\.attendances\(id\) on delete restrict/);
  assert.match(migration, /attendance\.patient_id = new\.patient_id/);
  assert.match(migration, /attendance\.status = 'completed'/);
  assert.match(migration, /O atendimento informado não pertence ao paciente ou não está concluído/);
  assert.match(migration, /certificate\.patient_id = exam\.patient_id/);
  assert.match(migration, /certificate\.patient_id = cast_record\.patient_id/);
});

test("leave days remain an exclusive medical decision in UI, AI and database", async () => {
  const [migration, edge, component] = await Promise.all([
    read("supabase/migrations/20260921212819_post_go_medical_certificates.sql"),
    read("supabase/functions/medical-certificate-ai/index.ts"),
    read("app/components/medical-certificate-center.tsx"),
  ]);
  assert.match(migration, /leave_days integer not null/);
  assert.match(migration, /medical_certificates_leave_days_check check \(leave_days between 1 and 365\)/);
  assert.match(migration, /medical_certificate_text_matches_days/);
  assert.match(migration, /O texto final precisa mencionar exatamente % dias/);
  assert.match(component, /Dias de afastamento/);
  assert.match(edge, /const MODEL = "gpt-5\.6-luna"/);
  assert.match(edge, /Nunca sugira, estime, altere, arredonde ou acrescente outro período de afastamento/);
  assert.match(edge, /textMatchesDays\(text, context\.leave_days\)/);
  assert.match(edge, /store: false/);
});

test("finalization freezes professional identity and prevents destructive changes", async () => {
  const migration = await read("supabase/migrations/20260921212819_post_go_medical_certificates.sql");
  assert.match(migration, /status in \('draft', 'finalized', 'cancelled'\)/);
  assert.match(migration, /professional_snapshot jsonb/);
  assert.match(migration, /hpsm\.medical_certificate_snapshot\.v1/);
  assert.match(migration, /identity\.signature_image_path is not null/);
  assert.match(migration, /Somente rascunhos podem ser editados/);
  assert.match(migration, /Somente um atestado finalizado pode ser cancelado/);
  assert.match(migration, /cancellation_reason/);
  assert.doesNotMatch(migration, /delete from public\.medical_certificates/i);
});

test("official PNG is private, centralized and contains no AI metadata", async () => {
  const [migration, png, template, storage, sharedStorage] = await Promise.all([
    read("supabase/migrations/20260921212819_post_go_medical_certificates.sql"),
    read("app/lib/medical-certificate-png.ts"),
    read("app/lib/institutional-document-png.ts"),
    read("app/lib/medical-certificate-storage.ts"),
    read("app/lib/exam-document-storage.ts"),
  ]);
  assert.match(migration, /medical-certificates\/.*\/documents\/.*\\\.png/);
  assert.match(png, /documentTitle: "Atestado Médico"/);
  assert.match(png, /renderOfficialInstitutionalDocument/);
  assert.match(template, /preserveAspectRatio="xMidYMid \$\{fit\}"/);
  assert.match(template, /text-anchor="\$\{anchor\}"/);
  assert.match(template, /Documento gerado exclusivamente para uso em RP/);
  assert.doesNotMatch(png, /inteligência artificial|gerad[oa] por ia|prompt/iu);
  assert.match(storage, /uploadStoredExamDocument/);
  assert.match(sharedStorage, /clinical-exam-documents/);
  assert.doesNotMatch(storage, /getPublicUrl|publicUrl/);
  assert.doesNotMatch(sharedStorage, /getPublicUrl|publicUrl/);
});

test("module is permissioned, responsive and exposed in profile and patient portal", async () => {
  const [migration, page, navigation, profile, portalShell, styles] = await Promise.all([
    read("supabase/migrations/20260921212819_post_go_medical_certificates.sql"),
    read("app/atestados/page.tsx"),
    read("app/lib/sidebar-navigation.ts"),
    read("app/components/patient-profile.tsx"),
    read("app/components/patient-portal-shell.tsx"),
    read("app/brand.css"),
  ]);
  for (const permission of ["atestados.view", "atestados.create", "atestados.finalize", "atestados.cancel"]) {
    assert.match(migration, new RegExp(permission.replace(".", "\\.")));
  }
  assert.match(migration, /force row level security/g);
  assert.match(migration, /certificate\.status = 'finalized'/);
  assert.match(page, /permissions\.includes\("atestados\.view"\)/);
  assert.match(navigation, /href: "\/atestados"/);
  assert.match(profile, /Atestados/);
  assert.match(portalShell, /\/portal-paciente\/atestados/);
  assert.match(styles, /html\[data-theme="dark"\][^\n]*\.certificate-summary-card/);
  assert.match(styles, /@media \(max-width: 700px\)[\s\S]*\.certificate-form/);
  assert.match(styles, /@media \(max-width: 375px\)[\s\S]*\.certificate-toolbar/);
});

test("every medical-certificate foreign key added by the rollup has index coverage", async () => {
  const indexes = await read("supabase/migrations/20260922033800_post_go_medical_certificate_fk_indexes.sql");
  assert.match(indexes, /medical_certificates_finalized_by_idx/);
  assert.match(indexes, /medical_certificates_cancelled_by_idx/);
  assert.match(indexes, /medical_certificate_exams_linked_by_idx/);
  assert.match(indexes, /medical_certificate_casts_linked_by_idx/);
});
