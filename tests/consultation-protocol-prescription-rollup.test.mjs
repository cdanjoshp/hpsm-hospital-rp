import assert from "node:assert/strict";
import { readFile, rm } from "node:fs/promises";
import test, { after, before } from "node:test";
import { pathToFileURL } from "node:url";
import { build } from "esbuild";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");
const quantityBundle = `/tmp/hpsm-rp-quantity-${process.pid}.mjs`;
const recipeBundle = `/tmp/hpsm-rp-recipe-${process.pid}.mjs`;
let calculateRpQuantity;
let hasOptionalMedicationUse;
let renderPrescriptionDocumentPng;

before(async () => {
  await Promise.all([
    build({ bundle: true, entryPoints: [new URL("../app/lib/rp-medications.ts", import.meta.url).pathname], format: "esm", outfile: quantityBundle, platform: "node", target: "node22" }),
    build({ bundle: true, entryPoints: [new URL("../app/lib/prescription-document-png.ts", import.meta.url).pathname], format: "esm", loader: { ".woff2": "dataurl", ".png": "dataurl" }, outfile: recipeBundle, platform: "node", target: "node22" }),
  ]);
  ({ calculateRpQuantity, hasOptionalMedicationUse } = await import(`${pathToFileURL(quantityBundle).href}?${Date.now()}`));
  ({ renderPrescriptionDocumentPng } = await import(`${pathToFileURL(recipeBundle).href}?${Date.now()}`));
});
after(async () => { await Promise.all([rm(quantityBundle, { force: true }), rm(recipeBundle, { force: true })]); });

test("catálogo Anjos Pharma possui exatamente os 26 medicamentos canônicos e nenhum estoque", async () => {
  const migration = await read("supabase/migrations/20260924214500_clinical_protocols_anjos_pharma_prescriptions.sql");
  const seeded = [...migration.matchAll(/^\s*\('([A-Z0-9_]+)',\s*'[^']+',\s*'[^']+',/gm)].map((match) => match[1]);
  assert.deepEqual(seeded, ["ANALGEX","PARADOR","CEFALIV","MUSCULIV","DORMAX","GLICOVIDA","ORGABLOQ","FERTIPLUS","GESTAVIDA","CALCIFORT","MATERPLUS","CALMIVITA","ALERGICOR","ALERGIX","RESPIMAX","GRIPEX","BACTRIMED","BACTERON","INFLAMOL","INFLAMAX","GASTRIX","GASILIV","HEPAVIDA","NAUSEAZERO","COLICACALM","RESSAK"]);
  const catalogTable = /create table public\.rp_medications \(([\s\S]*?)\n\);/.exec(migration)?.[1] ?? "";
  assert.doesNotMatch(catalogTable, /stock|estoque|saldo|entrada|saída|movimenta/i);
});

test("quantidade RP usa administrações regulares por dia vezes dias", () => {
  assert.deepEqual(calculateRpQuantity("2x/dia", 7), { dosesPerDay: 2, quantity: 14 });
  assert.deepEqual(calculateRpQuantity("a cada 8 horas", 7), { dosesPerDay: 3, quantity: 21 });
  assert.equal(calculateRpQuantity("a cada 6 horas, se necessário", 3), null);
  assert.equal(hasOptionalMedicationUse("Administrar quando necessário."), true);
  assert.equal(hasOptionalMedicationUse("Administrar na frequência prescrita."), false);
  assert.equal(calculateRpQuantity("frequência livre", 3), null);
});

test("síntese v6 mantém uma chamada, schema estrito compatível e validações no backend", async () => {
  const [edge, learning, catalog] = await Promise.all([
    read("supabase/functions/consultation-ai/index.ts"),
    read("supabase/migrations/20260924214600_clinical_protocol_learning_and_prescription_documents.sql"),
    read("supabase/migrations/20260924214500_clinical_protocols_anjos_pharma_prescriptions.sql"),
  ]);
  assert.match(edge, /consultation-assistant-v8/);
  assert.doesNotMatch(edge, /uniqueItems/);
  assert.match(edge, /complete_consultation_ai_generation_v3/);
  assert.match(edge, /case_signature/);
  assert.match(edge, /medication_suggestions/);
  assert.match(edge, /\["case_signature", "options"\]/);
  assert.match(learning, /rp_medication_context_compatible/);
  assert.match(catalog, /allergy_keywords/);
  assert.match(catalog, /A sugestão de medicamento não pertence ao diagnóstico selecionado/);
});

test("assistência da consulta possui limite no navegador e sempre libera o botão", async () => {
  const workspace = await read("app/components/consultation-workspace.tsx");
  assert.match(workspace, /AI_REQUEST_TIMEOUT_MS = 75_000/);
  assert.match(workspace, /new AbortController\(\)/);
  assert.match(workspace, /signal: controller\.signal/);
  assert.match(workspace, /O rascunho foi preservado e o botão foi liberado/);
  assert.match(workspace, /finally \{ setBusy\(null\); \}/);
});

test("protocolos aprendem só na conclusão, sem dados pessoais, autoreforço ou sugestões rejeitadas", async () => {
  const [migration, catalog] = await Promise.all([read("supabase/migrations/20260924214600_clinical_protocol_learning_and_prescription_documents.sql"), read("supabase/migrations/20260924214500_clinical_protocols_anjos_pharma_prescriptions.sql")]);
  assert.match(migration, /perform private\.learn_completed_consultation\(p_consultation_id\)/);
  assert.match(catalog, /consultation_id bigint not null unique references public\.clinical_consultations/);
  assert.match(migration, /protocol_deidentify/);
  assert.match(migration, /from public\.consultation_prescription_items item/);
  const learningFunction = /create or replace function private\.learn_completed_consultation[\s\S]*?\n\$\$;/.exec(migration)?.[0] ?? "";
  assert.match(learningFunction, /private\.protocol_deidentify[\s\S]*v_patient\.name, v_patient\.passport/);
  assert.doesNotMatch(learningFunction, /selected_diagnosis->'medication_suggestions'/);
  assert.match(migration, /set_clinical_protocol_settings/);
  assert.match(migration, /CLINICAL_PROTOCOL_SETTINGS_UPDATED/);
});

test("prescrição materializa sugestões, mantém edição humana e gera Receita compartilhável", async () => {
  const [component, consultationApi, api, migration, catalog, automatic, recipeRoute, deletion] = await Promise.all([
    read("app/components/consultation-prescription.tsx"),
    read("app/api/consultations/route.ts"),
    read("app/api/consultations/prescription/route.ts"),
    read("supabase/migrations/20260924214600_clinical_protocol_learning_and_prescription_documents.sql"),
    read("supabase/migrations/20260924214500_clinical_protocols_anjos_pharma_prescriptions.sql"),
    read("supabase/migrations/20260925144418_consultation_diagnosis_iterations_and_automatic_prescription.sql"),
    read("app/api/consultations/prescription/document/route.ts"), read("supabase/functions/consultation-delete/index.ts"),
  ]);
  assert.doesNotMatch(component, /Sugestões da síntese clínica|Aceitar e revisar|>Rejeitar</);
  assert.match(component, /Itens da prescrição/);
  assert.match(component, /Sugestão do sistema/);
  assert.match(component, />Editar</);
  assert.match(component, />Remover</);
  assert.match(component, /Adicionar manualmente/);
  assert.match(component, /Motivo do ajuste manual/);
  assert.match(consultationApi, /select_consultation_diagnosis/);
  assert.match(api, /upsert_consultation_prescription_item/);
  assert.match(automatic, /automatic_medications_inserted/);
  assert.match(automatic, /private\.rp_medication_context_compatible/);
  assert.match(automatic, /decision in \('removed', 'rejected'\)/);
  assert.match(catalog, /hpsm\.rp_prescription\.v1/);
  assert.match(catalog, /PRESCRIPTION_FINALIZED/);
  assert.match(migration, /prescription-document-png-v1/);
  assert.match(recipeRoute, /recordPrescriptionDocumentAccess/);
  assert.match(deletion, /consultations\|prescriptions/);
});

test("Receita renderiza PNG institucional com aviso obrigatório RP", async () => {
  const professionalId = "11111111-1111-4111-8111-111111111111";
  const tinyPng = Uint8Array.from(Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=", "base64"));
  const result = await renderPrescriptionDocumentPng({
    schema: "hpsm.rp_prescription.v1", prescription_id: "22222222-2222-4222-8222-222222222222", consultation_id: 42,
    patient: { name: "Paciente de Teste", passport: "0007" }, professional: { id: professionalId, name: "Profissional de Teste", crm_code: "05321409", role: "Médica", signature_image_path: "professionals/a/b/signature.png" },
    created_at: "2026-09-24T12:00:00.000Z", finalized_at: "2026-09-24T13:00:00.000Z",
    items: [{ id: "33333333-3333-4333-8333-333333333333", medication_id: "ANALGEX", rp_name_snapshot: "Analgex", reference_name_snapshot: "Dipirona", dose_snapshot: "500 mg", frequency_snapshot: "a cada 6 horas", duration_snapshot: "3 dias", route_snapshot: "Oral", reason_snapshot: "Dor RP", instructions_snapshot: "Administrar na frequência prescrita durante todo o período indicado.", justification_snapshot: null, calculated_quantity_snapshot: 12, final_quantity_snapshot: 12, quantity_override_snapshot: false, override_reason: null }],
    rp_notice: "As posologias, dosagens e orientações são regras fictícias e simplificadas, destinadas exclusivamente ao uso em RP.",
  }, { bytes: tinyPng, personId: professionalId });
  assert.deepEqual(Array.from(result.bytes.slice(0, 8)), [137,80,78,71,13,10,26,10]);
  assert.equal(result.width, 1200);
  assert.ok(result.height > 1_000 && result.height <= 14_000);
});
