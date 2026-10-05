import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("Sol writes a complete direct clinical report with strict output", async () => {
  const edge = await read("supabase/functions/exam-ai-generate/index.ts");
  assert.match(edge, /const SOL_MODEL = "gpt-6-sol"/);
  assert.match(edge, /const REPORT_PROMPT_VERSION = "exam-sol-legacy-report-v1"/);
  assert.match(edge, /const REASONING_EFFORT = "medium"/);
  assert.match(edge, /Você é a redatora clínica do laudo/);
  assert.match(edge, /Declare os achados diretamente/);
  assert.match(edge, /Conduta \/ Próximos passos/);
  assert.match(edge, /não inclua doses, posologia, protocolos ou instruções cirúrgicas detalhadas/i);
  assert.match(edge, /store: false/);
  assert.doesNotMatch(edge, /gpt-5\.6-(?:terra|sol)|fallback/i);

  const schema = edge.slice(edge.indexOf("function reportSchema"), edge.indexOf("function validateLaboratorySuggestion"));
  assert.match(schema, /hpsm\.ai\.clinical_report\.v3/);
  assert.match(schema, /required: \["schema", "technique", "findings", "conclusion", "conduct"\]/);
  assert.match(schema, /minItems: 1, maxItems: 4/);
  assert.match(schema, /additionalProperties: false/);
  assert.doesNotMatch(schema, /summary|rp_note/);
});

test("v3 rejects defensive language while historical report schemas remain readable", async () => {
  const [edge, migration] = await Promise.all([
    read("supabase/functions/exam-ai-generate/index.ts"),
    read("supabase/migrations/20260901180425_luna_clinical_report_v3.sql"),
  ]);
  assert.match(edge, /possível/);
  assert.match(edge, /provavelmente/);
  assert.match(edge, /pode\\s\+\(\?:ser\|representar\|indicar\)/);
  assert.match(migration, /hpsm\.ai\.clinical_report\.v3/);
  assert.match(migration, /hpsm\.ai\.simple_report\.v1', 'hpsm\.ai\.simple_report\.v2/);
  assert.match(migration, /hpsm\.ai\.report_suggestion\.v1/);
  assert.match(migration, /O laudo deve declarar diretamente os achados do exame fictício/);
  assert.match(migration, /exam-rp-luna-v1', 'exam-rp-luna-v2', 'exam-rp-luna-v3/);
});

test("the unified case summary and selected private image are the only clinical inputs", async () => {
  const [contextMigration, edge, reportMigration] = await Promise.all([
    read("supabase/migrations/20260901163458_simplify_exam_request_and_filter_attendances.sql"),
    read("supabase/functions/exam-ai-generate/index.ts"),
    read("supabase/migrations/20260901180425_luna_clinical_report_v3.sql"),
  ]);
  const safeInput = edge.slice(edge.indexOf("const safeInput"), edge.indexOf("const visualDataUrl"));
  assert.match(contextMigration, /'case_context', jsonb_build_object\('summary', private\.clinical_exam_case_summary/);
  assert.match(safeInput, /case_context: \{ summary: clinicalCaseSummary\(context\.case_context\) \}/);
  assert.match(edge, /context\?\.summary \|\| \[context\?\.main_suspicion, context\?\.short_context\]/);
  assert.equal((edge.match(/type: "input_image"/g) ?? []).length, 1);
  assert.match(edge, /clinical_exam_ai_visual_input/);
  assert.match(edge, /image_url: visualDataUrl/);
  assert.doesNotMatch(edge, /\/v1\/images\/generations|gpt-image-2/);
  assert.match(reportMigration, /source_image_generation_id is distinct from p_image_generation_id/);
});

test("applying v3 maps report fields and conduct to the canonical exam draft", async () => {
  const migration = await read("supabase/migrations/20260901180425_luna_clinical_report_v3.sql");
  assert.match(migration, /'technique', nullif\(btrim\(p_payload->>'technique'\), ''\)/);
  assert.match(migration, /string_agg\('- ' \|\| btrim\(item\), E'\\n'\)/);
  assert.match(migration, /'conclusion', nullif\(btrim\(p_payload->>'conclusion'\), ''\)/);
  assert.match(migration, /'conduct', nullif\(btrim\(p_payload->>'conduct'\), ''\)/);
  assert.match(migration, /jsonb_set\(v_exam\.result_data, '\{notes\}', to_jsonb\(v_conduct\), true\)/);
  assert.match(migration, /status = 'applied', applied_at = now\(\)/);
  assert.doesNotMatch(migration, /status = 'completed'.*reviewed_by/s);
});

test("the UI sends generated content to human review without restoring Observacao RP", async () => {
  const [assistant, center, report, types, flow] = await Promise.all([
    read("app/components/exam-ai-assistant.tsx"),
    read("app/components/exam-center.tsx"),
    read("app/components/exam-report-view.tsx"),
    read("app/lib/exams.ts"),
    read("app/lib/exam-ai-flow.ts"),
  ]);
  assert.match(center, /Sol está preparando o laudo/);
  assert.match(center, /Enviando à revisão humana/);
  assert.match(flow, /callImage\(examId, "apply_bundle"/);
  assert.doesNotMatch(assistant, /Aplicar ao rascunho|Aplicar exame/);
  assert.match(center, /Conduta \/ Próximos passos/);
  assert.match(report, /clinicalReportV3Applied/);
  assert.match(types, /hpsm\.ai\.clinical_report\.v3/);
  assert.match(types, /hpsm\.ai\.simple_report\.v1/);
  assert.match(types, /hpsm\.ai\.simple_report\.v2/);
  assert.doesNotMatch(`${assistant}\n${center}\n${report}`, /Observação RP/);
});
