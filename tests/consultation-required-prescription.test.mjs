import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("prescrição futura não aceita linguagem de uso condicional", async () => {
  const [migration, library, component, api] = await Promise.all([
    read("supabase/migrations/20260925155008_required_use_and_comprehensive_prescription.sql"),
    read("app/lib/rp-medications.ts"),
    read("app/components/consultation-prescription.tsx"),
    read("app/api/consultations/prescription/route.ts"),
  ]);
  assert.match(migration, /default_as_needed = false/);
  assert.match(migration, /consultation_prescription_required_use_guard/);
  assert.match(migration, /prescription\.status = 'draft'/);
  assert.match(migration, /Snapshots finalizados permanecem históricos e imutáveis/);
  assert.match(library, /hasOptionalMedicationUse/);
  assert.doesNotMatch(library, /a cada 6 horas, se necessário/);
  assert.match(component, /Todo item prescrito possui uso regular/);
  assert.match(api, /hasOptionalMedicationUse/);
});

test("síntese recebe contexto do catálogo e busca cobertura terapêutica coerente", async () => {
  const [edge, migration] = await Promise.all([
    read("supabase/functions/consultation-ai/index.ts"),
    read("supabase/migrations/20260925155008_required_use_and_comprehensive_prescription.sql"),
  ]);
  for (const field of ["allowed_body_systems", "allowed_case_tags", "disallowed_case_tags"]) {
    assert.match(edge, new RegExp(field));
    assert.match(migration, new RegExp(field));
  }
  assert.match(edge, /conjunto terapêutico coerente/);
  assert.match(edge, /trauma ou fratura dolorosa/);
  assert.match(edge, /Não sugira medicamento condicional/);
  assert.match(edge, /não imponha uma quantidade mínima/i);
});
