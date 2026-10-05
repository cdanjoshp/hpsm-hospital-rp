import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("exclusão de consulta é exclusiva dos cargos oficiais de Diretoria", async () => {
  const [migration, page, api] = await Promise.all([
    read("supabase/migrations/20260924161731_delete_consultation_with_dependencies.sql"),
    read("app/consultas/[id]/page.tsx"),
    read("app/api/consultations/route.ts"),
  ]);

  assert.match(migration, /'consultations\.delete'/);
  assert.match(migration, /position\.official[\s\S]*position\.level in \(13, 14\)/i);
  assert.match(migration, /private\.has_permission\(v_actor, 'consultations\.delete'\)[\s\S]*position\.level in \(13, 14\)/i);
  assert.match(migration, /A exclusão de consultas é exclusiva dos cargos de Diretoria/);
  assert.match(page, /consultations\.delete/);
  assert.match(page, /context\.positionLevel === 13 \|\| context\.positionLevel === 14/);
  assert.match(api, /requirePermission\(permissions, "consultations\.delete"\)/);
  assert.match(api, /context\.positionLevel !== 13 && context\.positionLevel !== 14/);
});

test("RPC remove dependências clínicas e preserva apenas retornos já iniciados", async () => {
  const migration = await read("supabase/migrations/20260924161731_delete_consultation_with_dependencies.sql");

  for (const table of [
    "medical_certificate_exams",
    "medical_certificate_casts",
    "medical_certificates",
    "clinical_exam_document_shares",
    "clinical_exam_documents",
    "exam_ai_generations",
    "clinical_exam_images",
    "clinical_exam_report_versions",
    "clinical_exam_status_history",
    "clinical_exams",
    "clinical_casts",
    "hospitalizations",
    "consultation_ai_generations",
    "clinical_consultations",
  ]) {
    assert.match(migration, new RegExp(`delete from public\\.${table}`));
  }

  assert.match(migration, /child_consultation\.id is null/);
  assert.match(migration, /child_consultation\.id is not null/);
  assert.match(migration, /set follow_up_of_consultation_id = null/);
  assert.match(migration, /where appointment\.id = v_consultation\.appointment_id/);
  assert.match(migration, /set_config\('hpsm\.consultation_delete_id'/);
});

test("arquivos privados de exames e atestados entram na limpeza protegida", async () => {
  const [migration, edge] = await Promise.all([
    read("supabase/migrations/20260924161731_delete_consultation_with_dependencies.sql"),
    read("supabase/functions/consultation-delete/index.ts"),
  ]);

  assert.match(migration, /clinical_exam_images', v_exam_image_paths/);
  assert.match(migration, /clinical_exam_documents', v_clinical_document_paths/);
  assert.match(migration, /certificate\.final_png_path/);
  assert.match(edge, /const IMAGE_BUCKET = "clinical-exam-images"/);
  assert.match(edge, /const DOCUMENT_BUCKET = "clinical-exam-documents"/);
  assert.match(edge, /medical-certificates\\\/\\d\+\\\/documents/);
  assert.match(edge, /consultation_document_storage_paths_for_delete/);
  assert.match(edge, /consultations\|prescriptions/);
  assert.match(edge, /Promise\.all\([\s\S]*cleanupBucket/);
  assert.match(edge, /SUPABASE_SERVICE_ROLE_KEY/);
});

test("interface exige confirmação nominal antes da exclusão definitiva", async () => {
  const workspace = await read("app/components/consultation-workspace.tsx");

  assert.match(workspace, />Excluir consulta</);
  assert.match(workspace, /EXCLUIR \{consultation\.id\}/);
  assert.match(workspace, /deleteConfirmation === `EXCLUIR \$\{consultation\.id\}`/);
  assert.match(workspace, /incluindo atestados, exames, arquivos, gessos, internações, assistência de IA e retornos ainda não iniciados/);
  assert.match(workspace, /router\.replace\("\/consultas"\)/);
});
