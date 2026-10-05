import assert from "node:assert/strict";
import { rm } from "node:fs/promises";
import test, { after, before } from "node:test";
import { pathToFileURL } from "node:url";
import { build } from "esbuild";
import { PDFDocument } from "pdf-lib";

const bundlePath = `/tmp/hpsm-final-exam-pdf-${process.pid}.mjs`;
let renderFinalExamPdf;

before(async () => {
  await build({
    bundle: true,
    entryPoints: [new URL("../app/lib/final-exam-pdf.ts", import.meta.url).pathname],
    format: "esm",
    outfile: bundlePath,
    platform: "node",
    target: "node22",
  });
  ({ renderFinalExamPdf } = await import(`${pathToFileURL(bundlePath).href}?${Date.now()}`));
});

after(async () => {
  await rm(bundlePath, { force: true });
});

test("renderer emits a readable multipage A4 PDF with ordered images", async () => {
  const document = model({
    exam: examType("imagem", "raio_x", "Raio-X"),
    images: [image("11111111-1111-4111-8111-111111111111", 10), image("22222222-2222-4222-8222-222222222222", 20)],
    resultData: imagingResult(),
  });
  const png = Uint8Array.from(Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=", "base64"));
  const bytes = await renderFinalExamPdf(document, document.images.map(({ id }) => ({ bytes: png, id, mimeType: "image/png" })));
  const pdf = await PDFDocument.load(bytes);

  assert.equal(bytes[0], 0x25);
  assert.equal(bytes[1], 0x50);
  assert.ok(pdf.getPageCount() >= 2);
  assert.equal(pdf.getTitle(), "EX-000123 - Raio-X");
  assert.equal(pdf.getSubject(), "Laudo final de exame concluído");
  for (const page of pdf.getPages()) assert.deepEqual(page.getSize(), { height: 841.89, width: 595.28 });
});

test("renderer supports every configured clinical document family", async () => {
  const variants = [
    model({ exam: examType("imagem", "raio_x", "Raio-X"), resultData: imagingResult() }),
    model({ exam: examType("imagem", "tomografia", "Tomografia"), resultData: imagingResult() }),
    model({ exam: examType("imagem", "ressonancia_magnetica", "Ressonância Magnética"), resultData: imagingResult() }),
    model({ exam: examType("imagem", "ultrassom", "Ultrassom"), resultData: imagingResult() }),
    model({ exam: examType("laboratorial", "hemograma", "Hemograma"), resultData: laboratoryResult("Hemoglobina", "13,5", "normal") }),
    model({ exam: examType("laboratorial", "bioquimica", "Bioquímica"), resultData: laboratoryResult("Glicose", "92", "normal") }),
    model({ exam: examType("laboratorial", "tipagem_sanguinea", "Tipagem Sanguínea"), resultData: bloodResult() }),
    model({ exam: examType("laboratorial", "toxicologia", "Toxicologia"), resultData: laboratoryResult("Análise toxicológica", "Negativo", "negative") }),
    model({ exam: examType("patologico", "biopsia", "Biópsia"), resultData: { material: "Fragmento de tecido", notes: "Acompanhamento clínico.", schema: "generic" } }),
    model({ exam: examType("patologico", "citologia", "Citologia"), resultData: { sample: "Amostra citológica", notes: "Acompanhamento clínico.", schema: "generic" } }),
    model({ exam: examType("cardiologia", "eletrocardiograma", "Eletrocardiograma"), resultData: { frequency: "72 bpm", notes: "Acompanhamento clínico.", rhythm: "Sinusal", schema: "generic" } }),
  ];

  for (const variant of variants) {
    const bytes = await renderFinalExamPdf(variant, []);
    const pdf = await PDFDocument.load(bytes);
    assert.ok(pdf.getPageCount() >= 1, variant.exam.name);
    assert.equal(pdf.getAuthor(), "Hospital Santa Marcelina");
  }
});

test("long laboratory tables paginate without leaving A4", async () => {
  const result = laboratoryResult("Parâmetro 1", "10", "normal");
  result.parameters = Array.from({ length: 48 }, (_, index) => ({
    ...result.parameters[0],
    key: `parametro_${index + 1}`,
    label: `Parâmetro laboratorial ${index + 1}`,
    sort_order: (index + 1) * 10,
  }));
  const bytes = await renderFinalExamPdf(model({ exam: examType("laboratorial", "hemograma", "Hemograma"), resultData: result }), []);
  const pdf = await PDFDocument.load(bytes);

  assert.ok(pdf.getPageCount() >= 2);
  for (const page of pdf.getPages()) assert.deepEqual(page.getSize(), { height: 841.89, width: 595.28 });
});

test("PDF renderer embeds institutional signatures without changing A4 output", async () => {
  const tinyPng = Uint8Array.from(Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=", "base64"));
  const document = model();
  document.executedBy.identity = identity(document.executedBy.id, "05321409");
  document.reviewedBy.identity = identity(document.reviewedBy.id, "00070301");
  const bytes = await renderFinalExamPdf(document, [], [
    { bytes: tinyPng, mimeType: "image/png", personId: document.executedBy.id },
    { bytes: tinyPng, mimeType: "image/png", personId: document.reviewedBy.id },
  ]);
  const pdf = await PDFDocument.load(bytes);
  assert.ok(pdf.getPageCount() >= 1);
  for (const page of pdf.getPages()) assert.deepEqual(page.getSize(), { height: 841.89, width: 595.28 });
});

function model(overrides = {}) {
  const exam = overrides.exam ?? examType("laboratorial", "hemograma", "Hemograma");
  return {
    clinicalContext: "Febre e mal-estar há dois dias.",
    completedAt: "2026-09-01T16:45:00.000Z",
    content: {
      conclusion: "Achados compatíveis com o contexto clínico informado.",
      findings: "Descrição objetiva dos achados do exame, preservada no resultado final aprovado.",
      observations: "Manter acompanhamento clínico conforme evolução.",
      technique: "Exame realizado conforme técnica aplicável.",
    },
    exam,
    examCode: "EX-000123",
    examDate: "2026-09-01T15:30:00.000Z",
    examId: 123,
    executedBy: { id: "11111111-1111-4111-8111-111111111111", name: "Maria Exemplo da Silva", position: "Médica" },
    filename: `HPSM_EX-000123_${exam.name}.pdf`,
    images: overrides.images ?? [],
    indication: "Investigação clínica do quadro apresentado.",
    issuedAt: "2026-09-02T13:00:00.000Z",
    patient: { id: 1, name: "José Exemplo de Ribeiro", passport: "0001" },
    reportConfig: {
      fields: {
        conclusion: { label: "Conclusão", required: true, visible: true },
        findings: { label: "Achados", required: true, visible: true },
        observations: { label: "Conduta", required: false, visible: true },
        technique: { label: "Técnica / Método", required: false, visible: true },
      },
      schema: "hpsm.report_config.v1",
    },
    resultData: overrides.resultData ?? laboratoryResult("Hemoglobina", "13,5", "normal"),
    reviewedBy: { id: "22222222-2222-4222-8222-222222222222", name: "Ana Exemplo de Souza", position: "Diretora Clínica" },
  };
}

function examType(categoryCode, code, name) {
  return { category_code: categoryCode, category_id: 1, category_name: categoryCode === "imagem" ? "Imagem" : categoryCode === "laboratorial" ? "Laboratorial" : categoryCode === "patologico" ? "Patológico" : "Cardiologia", code, id: 1, name, result_config: {} };
}

function image(id, sortOrder) {
  return { caption: null, created_at: "2026-09-01T15:40:00.000Z", id, mime_type: "image/png", original_filename: "imagem-gerada-ia.png", sort_order: sortOrder, source: "ai_generated", storage_path: `clinical-exams/123/${id}.png` };
}

function identity(userId, crmCode) {
  const generationId = "33333333-3333-4333-8333-333333333333";
  return { crm_code: crmCode, registration_date: "2026-09-14", rubric_image_path: `professionals/${userId}/${generationId}/rubric.png`, signature_image_path: `professionals/${userId}/${generationId}/signature.png` };
}

function laboratoryResult(label, value, flag) {
  return {
    notes: "Acompanhamento clínico.",
    parameters: [{ active: true, field_type: "text", flag, key: "parametro", label, options: [], reference: "Valor de referência", required: true, sort_order: 10, unit: "un", value }],
    schema: "hpsm.lab_result.v1",
    template_snapshot: { exam_type_code: "hemograma", exam_type_name: "Hemograma", kind: "laboratory", parameters: [], schema: "hpsm.lab_template.v1", version: 1 },
    template_version: 1,
  };
}

function bloodResult() {
  const result = laboratoryResult("Grupo ABO", "O", "normal");
  result.parameters = [
    { ...result.parameters[0], key: "abo", label: "Grupo ABO", unit: "", value: "O" },
    { ...result.parameters[0], key: "rh", label: "Fator Rh", unit: "", value: "Positivo" },
  ];
  result.template_snapshot.exam_type_code = "tipagem_sanguinea";
  result.template_snapshot.exam_type_name = "Tipagem Sanguínea";
  return result;
}

function imagingResult() {
  return {
    contrast: "not_applicable",
    laterality: "right",
    notes: "Acompanhamento clínico.",
    other_region: "",
    region: "Braço",
    schema: "hpsm.image_result.v1",
    template_snapshot: { allows_multiple_images: true, exam_type_code: "raio_x", exam_type_name: "Raio-X", kind: "imaging", region: { options: ["Braço"], required: true }, requires_image: true, schema: "hpsm.image_template.v1", supports_contrast: false, supports_laterality: true, version: 1 },
    template_version: 1,
  };
}
