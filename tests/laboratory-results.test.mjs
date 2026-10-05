import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("laboratory templates reuse result_config and seed the four RP panels", async () => {
  const [migration, extension] = await Promise.all([
    read("supabase/migrations/20260830145628_phase42_lab_templates_and_results.sql"),
    read("supabase/migrations/20260830151900_extend_lab_template_catalog.sql"),
  ]);
  assert.doesNotMatch(migration, /create table public\.exam_(?:result_)?templates/i);
  assert.match(migration, /set result_config = seed\.config/);
  for (const code of ["hemograma", "bioquimica", "tipagem_sanguinea", "toxicologia"]) {
    assert.match(migration, new RegExp(`'${code}'`));
  }
  for (const fieldType of ["number", "percent", "text", "select", "observation"]) {
    assert.match(migration, new RegExp(`'${fieldType}'`));
  }
  assert.match(extension, /v_category_code = 'laboratorial'/);
  assert.match(extension, /'parameters', jsonb_build_array\(\)/);
});

test("each laboratory result keeps an immutable versioned template snapshot", async () => {
  const [migration, normalizationFix] = await Promise.all([
    read("supabase/migrations/20260830145628_phase42_lab_templates_and_results.sql"),
    read("supabase/migrations/20260830151100_fix_lab_result_normalization.sql"),
  ]);
  assert.match(migration, /'schema', 'hpsm\.lab_result\.v1'/);
  assert.match(migration, /'template_version'/);
  assert.match(migration, /'template_snapshot'/);
  assert.match(migration, /p_candidate->'template_snapshot' is distinct from p_existing->'template_snapshot'/);
  assert.match(migration, /private\.build_lab_result\(p_exam_type_id\)/);
  assert.match(normalizationFix, /candidate_parameter\.candidate->>'value'/);
});

test("drafts may be partial but submission validates required snapshot fields", async () => {
  const migration = await read("supabase/migrations/20260830145628_phase42_lab_templates_and_results.sql");
  assert.match(migration, /create or replace function public\.save_clinical_exam_draft/);
  assert.match(migration, /create or replace function public\.submit_clinical_exam_review/);
  assert.match(migration, /snapshot->>'required'/);
  assert.match(migration, /Preencha os parâmetros obrigatórios/);
  assert.match(migration, /clinical_exam\.result_saved/);
});

test("template administration is permission guarded and protects historical keys", async () => {
  const [migration, api] = await Promise.all([
    read("supabase/migrations/20260830145628_phase42_lab_templates_and_results.sql"),
    read("app/api/exams/route.ts"),
  ]);
  assert.match(migration, /private\.has_permission\(v_actor, 'exams\.catalog\.manage'\)/);
  assert.match(migration, /Parâmetros já usados em exames devem ser inativados, não removidos/);
  assert.match(migration, /p_expected_version is distinct from/);
  assert.match(migration, /revoke all on function public\.manage_exam_template/);
  assert.match(api, /view === "templates"/);
  assert.match(api, /action === "template"/);
  assert.match(api, /requirePermission\(permissions, "exams\.catalog\.manage"\)/);
});

test("laboratory UI renders structured forms and review without raw JSON", async () => {
  const [center, laboratory, styles] = await Promise.all([
    read("app/components/exam-center.tsx"),
    read("app/components/laboratory-results.tsx"),
    read("app/brand.css"),
  ]);
  assert.match(center, /LaboratoryResultEditor/);
  assert.match(center, /ExamReportView/);
  assert.match(center, /missingRequiredLabParameters/);
  assert.match(laboratory, /Grupo ABO|bloodTypeLabel/);
  assert.match(laboratory, /Alterações não salvas/);
  assert.doesNotMatch(laboratory, /JSON\.stringify\(result, null, 2\)/);
  assert.match(styles, /@media \(max-width: 700px\)[\s\S]*?\.lab-result-table article/);
  assert.match(styles, /html\[data-theme="dark"\][\s\S]*?\.lab-result-view/);
});

test("non-laboratory exams keep the generic result path", async () => {
  const [center, api] = await Promise.all([
    read("app/components/exam-center.tsx"),
    read("app/api/exams/route.ts"),
  ]);
  assert.match(center, /!laboratoryResult && !imagingResult \? <ReportEditorField/);
  assert.match(center, /name="observations"/);
  assert.match(api, /jsonObject\(body\.resultData\) \?\? \{ notes:/);
});
