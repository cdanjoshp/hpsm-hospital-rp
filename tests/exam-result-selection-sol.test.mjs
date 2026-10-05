import assert from "node:assert/strict";
import { readFile, rm } from "node:fs/promises";
import test, { after, before } from "node:test";
import { pathToFileURL } from "node:url";
import { build } from "esbuild";

const bundlePath = `/tmp/hpsm-exam-sol-${process.pid}.mjs`;
let flow;
before(async () => {
  await build({ bundle: true, entryPoints: [new URL("../app/lib/exam-ai-flow.ts", import.meta.url).pathname], format: "esm", outfile: bundlePath, platform: "node", target: "node22" });
  flow = await import(pathToFileURL(bundlePath).href);
});
after(async () => { await rm(bundlePath, { force: true }); });

const detail = (reportId = null, promptVersion = "exam-sol-report-v3") => ({ exam: { status: "in_progress", result_state: { report_generation_id: reportId }, ai_generations: reportId ? [{ id: reportId, generation_type: "generate_report", status: "completed", prompt_version: promptVersion }] : [] } });

test("analysis requests only result options and persists a short variable list", async () => {
  const original = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async (_url, options) => {
    const body = JSON.parse(options.body);
    calls.push(body);
    return Response.json({ result_state: { status: "ready", options: [{ id: "option_1" }, { id: "option_2" }] } });
  };
  try {
    const state = await flow.analyzeExamResults(42);
    assert.equal(state.options.length, 2);
    assert.deepEqual(calls.map((call) => call.operation), ["result_options"]);
    assert.equal(calls[0].reanalyze, false);
  } finally { globalThis.fetch = original; }
});

test("new imaging exam waits for human selection, then generates report before visual study", async () => {
  const original = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async (url, options) => {
    if (!options?.body) { calls.push("detail"); return Response.json(detail()); }
    const body = JSON.parse(options.body);
    const action = body.operation ?? body.action;
    calls.push(action);
    if (action === "select_result") return Response.json({ result: { title: "Fratura não desviada" } });
    if (action === "generate_report") { assert.equal(body.imageGenerationId, null); return Response.json({ generation: { generation_id: "report-1" }, suggestion: { schema: "hpsm.ai.clinical_report.v3" } }); }
    if (action === "status") return Response.json({ draft: null });
    if (action === "generate") return Response.json({ draft: { id: "image-1", status: "completed" } });
    if (action === "apply_bundle") { assert.equal(body.reportGenerationId, "report-1"); return Response.json({ ok: true }); }
    throw new Error(`Unexpected ${url}`);
  };
  try {
    await flow.selectExamResult(42, "option_1");
    await flow.generateSelectedExamWithAi(42, true, () => undefined);
    assert.deepEqual(calls, ["select_result", "detail", "generate_report", "status", "generate", "apply_bundle"]);
  } finally { globalThis.fetch = original; }
});

test("visual retry reuses completed Sol report and does not request new clinical generation", async () => {
  const original = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async (_url, options) => {
    if (!options?.body) return Response.json(detail("report-saved"));
    const body = JSON.parse(options.body);
    calls.push(body.operation ?? body.action);
    if (body.action === "status") return Response.json({ draft: null });
    if (body.action === "generate") return Response.json({ draft: { id: "image-new", status: "completed" } });
    if (body.action === "apply_bundle") { assert.equal(body.reportGenerationId, "report-saved"); return Response.json({ ok: true }); }
    throw new Error("Clinical report was regenerated");
  };
  try {
    await flow.generateSelectedExamWithAi(42, true, () => undefined);
    assert.deepEqual(calls, ["status", "generate", "apply_bundle"]);
  } finally { globalThis.fetch = original; }
});

test("a stale report requires a new report and a matching new image", async () => {
  const original = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async (_url, options) => {
    if (!options?.body) return Response.json(detail("old-report", "exam-sol-report-v2"));
    const body = JSON.parse(options.body);
    calls.push(body.operation ?? body.action);
    if (body.operation === "generate_report") return Response.json({ generation: { generation_id: "new-report" }, suggestion: { schema: "hpsm.ai.clinical_report.v3" } });
    if (body.action === "status") return Response.json({ draft: { id: "old-image", status: "completed" } });
    if (body.action === "generate") return Response.json({ draft: { id: "new-image", status: "completed" } });
    if (body.action === "apply_bundle") { assert.equal(body.reportGenerationId, "new-report"); assert.equal(body.generationId, "new-image"); return Response.json({ ok: true }); }
    throw new Error("Unexpected request");
  };
  try {
    await flow.generateSelectedExamWithAi(42, true, () => undefined);
    assert.deepEqual(calls, ["generate_report", "status", "generate", "apply_bundle"]);
  } finally { globalThis.fetch = original; }
});

test("migration gates final generation, preserves active legacy exams and configures multicorte", async () => {
  const sql = await readFile(new URL("../supabase/migrations/20260929151420_exam_result_selection_sol.sql", import.meta.url), "utf8");
  assert.match(sql, /select id, 'legacy' from public\.clinical_exams where status = 'in_progress'/);
  assert.match(sql, /coalesce\(v_result_choice\.status,'not_started'\) not in \('legacy','selected'\)/);
  assert.match(sql, /status = 'selected' and selected_snapshot is not null/);
  assert.match(sql, /code in \('tomografia', 'ressonancia_magnetica'\) then 6/);
  assert.match(sql, /force row level security/);
  assert.match(sql, /v_result_choice\.report_generation_id is distinct from p_report_generation_id/);
});

test("AI prompts receive clinical choice without the professional audit identifier", async () => {
  const textEdge = await readFile(new URL("../supabase/functions/exam-ai-generate/index.ts", import.meta.url), "utf8");
  const imageEdge = await readFile(new URL("../supabase/functions/exam-ai-image/index.ts", import.meta.url), "utf8");
  assert.match(textEdge, /selected_result: clinicalSelection\(context\.selected_result\)/);
  assert.match(imageEdge, /selected_result: selectedClinical/);
  assert.doesNotMatch(textEdge.slice(textEdge.indexOf("function clinicalSelection"), textEdge.indexOf("function clinicalCaseSummary")), /professional_id|selected_at/);
});

test("service completion supports sb_secret keys without exposing RPCs to authenticated users", async () => {
  const sql = await readFile(new URL("../supabase/migrations/20260929161330_exam_result_service_key_compat.sql", import.meta.url), "utf8");
  assert.doesNotMatch(sql, /current_setting\('request\.jwt\.claim\.role'/);
  assert.match(sql, /revoke all on function public\.complete_clinical_exam_result_options[\s\S]*from public,anon,authenticated/);
  assert.match(sql, /revoke all on function public\.fail_clinical_exam_result_options[\s\S]*from public,anon,authenticated/);
  assert.match(sql, /grant execute on function public\.complete_clinical_exam_result_options[\s\S]*to service_role/);
});

test("an abandoned analysis becomes retriable while the client refreshes without another AI call", async () => {
  const [sql, center] = await Promise.all([
    readFile(new URL("../supabase/migrations/20260929161500_exam_result_stale_state.sql", import.meta.url), "utf8"),
    readFile(new URL("../app/components/exam-center.tsx", import.meta.url), "utf8"),
  ]);
  assert.match(sql, /requested_at < now\(\)-interval '2 minutes' then 'failed'/);
  assert.match(center, /resultState\?\.status !== "analyzing" \|\| working/);
  assert.match(center, /window\.setTimeout\(\(\) => \{ void onChanged\(\)/);
});

test("new clinical generations use Sol in both selection and legacy flows while historical Luna rows remain valid", async () => {
  const [sql, edge, center, assistant] = await Promise.all([
    readFile(new URL("../supabase/migrations/20260929163500_sol_all_exam_reports.sql", import.meta.url), "utf8"),
    readFile(new URL("../supabase/functions/exam-ai-generate/index.ts", import.meta.url), "utf8"),
    readFile(new URL("../app/components/exam-center.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/components/exam-ai-assistant.tsx", import.meta.url), "utf8"),
  ]);
  assert.match(sql, /new\.model := 'gpt-6-sol'/);
  assert.match(sql, /when 'generate_report' then case when coalesce\(v_selected,false\) then 'exam-sol-report-v1' else 'exam-sol-legacy-report-v1' end/);
  assert.match(sql, /when 'generate_lab_results' then 'exam-sol-lab-v1'/);
  assert.match(sql, /exam-clinical-report-v4/); // historical rows remain valid
  assert.match(edge, /const model = SOL_MODEL/);
  assert.match(edge, /A ausência de informação sobre incidências ou protocolo não prova que o estudo foi insuficiente/);
  assert.match(edge, /não solicite repetição do mesmo exame para confirmar um resultado estabelecido/);
  assert.doesNotMatch(center + assistant, /Luna/);
});
