import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("todos os documentos clínicos derivam do template institucional oficial único", async () => {
  const [template, exam, certificate, consultation, prescription, examVersion] = await Promise.all([
    read("app/lib/institutional-document-png.ts"),
    read("app/lib/final-exam-png.ts"),
    read("app/lib/medical-certificate-png.ts"),
    read("app/lib/consultation-document-png.ts"),
    read("app/lib/prescription-document-png.ts"),
    read("app/lib/exam-document-version.ts"),
  ]);

  assert.match(template, /export async function renderOfficialInstitutionalDocument/);
  for (const renderer of [exam, certificate, consultation, prescription]) {
    assert.match(renderer, /renderOfficialInstitutionalDocument/);
  }
  assert.match(examVersion, /exam-document-png-v10/);
  assert.match(certificate, /medical-certificate-png-v7/);
  assert.match(consultation, /consultation-document-png-v7/);
  assert.match(prescription, /prescription-document-png-v6/);
});

test("template repete cabeçalho e rodapé, pagina em A4 e assina somente a última página", async () => {
  const template = await read("app/lib/institutional-document-png.ts");
  assert.match(template, /pageHeight: 1697/);
  assert.match(template, /pageCount/);
  assert.match(template, /officialPageShell/);
  assert.match(template, /lastPageBottom: true/);
  assert.match(template, /hpsm-compass-original\.png\?inline/);
  assert.match(template, /identity\.signatureBytes/);
  assert.match(template, /identity\.rubricBytes/);
  assert.match(template, /seu-hospital\.example/);
  assert.match(template, /Cuidar de pessoas transforma realidades\./);
  assert.match(template, /Documento gerado exclusivamente para uso em RP\./);
  assert.doesNotMatch(template, /2344-3000|Rua Santa Marcelina|CEP 04863/);
});

test("laudos usam somente o médico solicitante como responsável visual", async () => {
  const [model, png, pdf, component, publicApi] = await Promise.all([
    read("app/lib/final-exam-document.ts"),
    read("app/lib/final-exam-png.ts"),
    read("app/lib/final-exam-pdf.ts"),
    read("app/components/final-exam-document.tsx"),
    read("app/api/patient-portal/exams/[id]/route.ts"),
  ]);

  assert.match(model, /executedBy: snapshot\?\.requested_by \?\? exam\.requested_by/);
  for (const output of [png, pdf, component, publicApi]) {
    assert.doesNotMatch(output, /Médico aprovador|Revisado por/);
  }
  assert.doesNotMatch(publicApi, /reviewedBy:/);
});

test("migração invalida documentos antigos e exige as novas versões oficiais", async () => {
  const migration = await read("supabase/migrations/20260924222500_official_institutional_document_template.sql");
  assert.match(migration, /exam-document-png-v6/);
  assert.match(migration, /consultation-document-png-v3/);
  assert.match(migration, /prescription-document-png-v2/);
  assert.match(migration, /medical-certificate-png-v3/);
  assert.match(migration, /notify pgrst, 'reload schema'/);
});

test("marca institucional preserva as facetas da rosa dos ventos em tela, PNG e PDF", async () => {
  const [brand, logo, png, pdf, migration] = await Promise.all([
    read("app/lib/hpsm-brand.ts"),
    read("app/components/hpsm-logo.tsx"),
    read("app/lib/institutional-document-png.ts"),
    read("app/lib/final-exam-pdf.ts"),
    read("supabase/migrations/20260927034600_hpsm_brand_documents.sql"),
  ]);
  assert.equal((brand.match(/tone: "/g) ?? []).length, 16);
  for (const consumer of [logo, png, pdf]) assert.match(consumer, /HPSM_COMPASS_FACETS/);
  assert.doesNotMatch(pdf, /drawCircle\(/);
  assert.match(migration, /exam-document-png-v7/);
  assert.match(migration, /clinical_exam_document_shares/);
});
