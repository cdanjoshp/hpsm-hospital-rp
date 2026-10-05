import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("banco limita somente a síntese clínica a três gerações preservadas", async () => {
  const migration = await read("supabase/migrations/20260925144418_consultation_diagnosis_iterations_and_automatic_prescription.sql");
  assert.match(migration, /add column if not exists attempt_number integer not null default 1/);
  assert.match(migration, /action_type = 'CLINICAL_SYNTHESIS' and attempt_number between 1 and 3/);
  assert.match(migration, /unique \(consultation_id, action_type, attempt_number\)/);
  assert.match(migration, /if v_completed_count >= 3/);
  assert.match(migration, /status = 'failed'[\s\S]*status = 'pending'/);
  assert.match(migration, /generation\.request_key = p_request_key/);
  assert.match(migration, /order by generation\.attempt_number desc, generation\.id desc/);
});

test("seleção diagnóstica materializa sugestões sem restaurar remoções explícitas", async () => {
  const [migration, route, workspace, prescription] = await Promise.all([
    read("supabase/migrations/20260925144418_consultation_diagnosis_iterations_and_automatic_prescription.sql"),
    read("app/api/consultations/route.ts"),
    read("app/components/consultation-workspace.tsx"),
    read("app/components/consultation-prescription.tsx"),
  ]);
  assert.match(route, /action === "select-diagnosis"/);
  assert.match(route, /select_consultation_diagnosis/);
  assert.match(workspace, /medicações incluídas.*automaticamente na prescrição/);
  assert.match(migration, /option\.value = p_selected_diagnosis/);
  assert.match(migration, /source, catalog_version[\s\S]*'ai'/);
  assert.match(migration, /case when v_medication\.requires_justification then v_reason else null end/);
  assert.match(migration, /v_latest_decision in \('removed', 'rejected'\)/);
  assert.doesNotMatch(prescription, /Sugestões da síntese clínica|Aceitar e revisar/);
});

test("contexto do atestado acompanha diagnóstico e plano até a edição manual", async () => {
  const workspace = await read("app/components/consultation-workspace.tsx");
  assert.match(workspace, /certificateContext\(diagnosis, finalPlan, anamnesis\)/);
  assert.match(workspace, /contextOverride \?\? defaultContext/);
  assert.match(workspace, /setContextOverride\(event\.target\.value\)/);
  assert.match(workspace, /Diagnóstico:/);
  assert.match(workspace, /Conduta e plano:/);
});
