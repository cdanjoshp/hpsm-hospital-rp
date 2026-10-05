import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("phase 4.3 stores image metadata separately in a private constrained bucket", async () => {
  const migration = await read("supabase/migrations/20260830152853_phase43_imaging_exam_storage.sql");
  assert.match(migration, /create table public\.clinical_exam_images/);
  assert.match(migration, /exam_id bigint not null references public\.clinical_exams\(id\) on delete restrict/);
  assert.match(migration, /storage_path text not null unique/);
  assert.match(migration, /source text not null default 'upload'/);
  assert.match(migration, /'clinical-exam-images', 'clinical-exam-images', false, 10485760/);
  assert.match(migration, /array\['image\/jpeg', 'image\/png', 'image\/webp'\]/);
  assert.doesNotMatch(migration, /on delete cascade/i);
});

test("storage remains private and authenticated manual insertion is removed", async () => {
  const [base, fix, automatic] = await Promise.all([
    read("supabase/migrations/20260830152853_phase43_imaging_exam_storage.sql"),
    read("supabase/migrations/20260830154251_fix_imaging_storage_path_policy.sql"),
    read("supabase/migrations/20260901193000_complete_exam_ai_v4_automatic_review.sql"),
  ]);
  const migration = `${base}\n${fix}`;
  assert.match(migration, /alter table public\.clinical_exam_images force row level security/);
  assert.match(migration, /clinical_exam_images_storage_read[\s\S]*image\.storage_path = name[\s\S]*'exams\.view'/);
  assert.match(migration, /clinical_exam_images_storage_insert[\s\S]*exam\.status = 'in_progress'[\s\S]*'exams\.perform'[\s\S]*'exams\.review'/);
  assert.match(migration, /clinical_exam_images_storage_delete[\s\S]*exam\.status = 'in_progress'/);
  assert.match(fix, /exam\.id = case[\s\S]*\^\[0-9\]\+\$[\s\S]*else null/);
  assert.match(automatic, /drop policy if exists clinical_exam_images_storage_insert/);
  assert.match(automatic, /revoke execute on function public\.register_clinical_exam_image[\s\S]*from authenticated/);
  assert.doesNotMatch(migration, /grant (?:insert|update|delete|all) on public\.clinical_exam_images to authenticated/i);
});

test("imaging templates and results preserve versioned snapshots", async () => {
  const [migration, library] = await Promise.all([
    read("supabase/migrations/20260830152853_phase43_imaging_exam_storage.sql"),
    read("app/lib/exams.ts"),
  ]);
  assert.match(migration, /hpsm\.image_template\.v1/);
  assert.match(migration, /hpsm\.image_result\.v1/);
  assert.match(migration, /p_candidate->'template_snapshot' is distinct from p_existing->'template_snapshot'/);
  assert.match(migration, /p_candidate->'template_version' is distinct from p_existing->'template_version'/);
  assert.match(library, /missingRequiredImagingFields/);
  assert.match(library, /supports_laterality/);
  assert.match(library, /supports_contrast/);
});

test("manual upload endpoint is closed while read and protected removal remain", async () => {
  const api = await read("app/api/exams/images/route.ts");
  assert.match(api, /export async function POST\(\)/);
  assert.match(api, /envio manual de imagens foi desativado/);
  assert.match(api, /status: 405/);
  assert.doesNotMatch(api, /request\.formData|uploadImage/);
  assert.match(api, /restore_clinical_exam_image/);
});

test("signed URLs are short lived, server generated and absent from the exam list", async () => {
  const [api, center] = await Promise.all([
    read("app/api/exams/images/route.ts"),
    read("app/components/exam-center.tsx"),
  ]);
  assert.match(api, /object\/sign\/clinical-exam-images/);
  assert.match(api, /expiresIn: 120/);
  assert.match(api, /cache-control": "private, no-store"/);
  assert.doesNotMatch(center, /exam-table[\s\S]{0,500}signed_url/);
});

test("review and completion lock image mutations and required images are checked twice", async () => {
  const [migration, center] = await Promise.all([
    read("supabase/migrations/20260830152853_phase43_imaging_exam_storage.sql"),
    read("app/components/exam-center.tsx"),
  ]);
  assert.match(migration, /v_exam\.status <> 'in_progress'.*imagens só podem ser alteradas/is);
  assert.match(migration, /requires_image[\s\S]*public\.clinical_exam_images/);
  assert.match(center, /editable=\{exam\.status === "in_progress" && canOperate\}/);
  assert.match(center, /confirmedImageCount < 1/);
});

test("AI gallery remains available for viewing and removal without file upload", async () => {
  const component = await read("app/components/imaging-results.tsx");
  assert.match(component, /Imagens geradas por IA/);
  assert.match(component, /Visualização ampliada/);
  assert.match(component, /Imagem anterior/);
  assert.match(component, /Próxima imagem/);
  assert.match(component, /Remover/);
  assert.doesNotMatch(component, /Adicionar imagem|type="file"|accept="image\//);
});
