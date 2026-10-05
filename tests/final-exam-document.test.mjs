import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("completed exams use one canonical final document for viewing, PNG sharing and printing", async () => {
  const [documentComponent, actions, center] = await Promise.all([
    read("app/components/final-exam-document.tsx"),
    read("app/components/final-exam-document-actions.tsx"),
    read("app/components/exam-center.tsx"),
  ]);

  assert.match(documentComponent, /export function FinalExamDocument/);
  assert.match(actions, /Visualizar imagem/);
  assert.match(actions, /Baixar imagem/);
  assert.match(actions, /Copiar link/);
  assert.doesNotMatch(actions, /Revogar link|Publicar imagem|Tentar publicar novamente/);
  assert.match(actions, /Imprimir/);
  assert.match(actions, /buildFinalExamDocument\(exam, images, issuedAt\)/);
  assert.match(center, /exam\.status === "completed" \? <FinalExamDocumentActions/);
  assert.match(actions, /if \(exam\.status !== "completed"\) return null/);
});

test("the PDF endpoint repeats session, permission and completion checks on the server", async () => {
  const route = await read("app/api/exams/document/route.ts");

  assert.match(route, /getSessionContext\(\)/);
  assert.match(route, /permissions\.has\("exams\.view"\)/);
  assert.match(route, /exam\.status !== "completed" \|\| !exam\.final_report_snapshot/);
  assert.match(route, /getClinicalExamDetail\(context\.accessToken, examId\)/);
  assert.match(route, /getClinicalExamImageGallery\(context\.accessToken, examId\)/);
  assert.match(route, /content-disposition/);
  assert.match(route, /url\.searchParams\.get\("view"\) === "1" \? "inline" : "attachment"/);
  assert.match(route, /content-type": "application\/pdf"/);
  assert.match(route, /private, no-store/);
  assert.doesNotMatch(route, /createSignedUrl|signedURL|signed_url/);
});

test("the final document is snapshot-first and excludes administrative patient data", async () => {
  const [model, documentComponent] = await Promise.all([
    read("app/lib/final-exam-document.ts"),
    read("app/components/final-exam-document.tsx"),
  ]);

  assert.match(model, /const snapshot = exam\.final_report_snapshot/);
  assert.match(model, /snapshot\?\.patient \?\? exam\.patient/);
  assert.match(model, /snapshot\?\.content/);
  assert.match(model, /snapshot\?\.dates/);
  assert.match(model, /orderSnapshotImages\(snapshot\?\.images/);
  assert.doesNotMatch(documentComponent, /telefone|contato de emergência|discord|e-mail/i);
  assert.equal(documentComponent.match(/Documento gerado exclusivamente para uso em RP\./g)?.length, 1);
  assert.doesNotMatch(documentComponent.replace("Documento gerado exclusivamente para uso em RP.", ""), /\bRP\b|GTA|roleplay|fictíci|simulação|personagem/i);
  assert.doesNotMatch(documentComponent, /Revisado por|Médico aprovador/);
});

test("A4 renderer supports clinical sections, tables, images and page numbering", async () => {
  const pdf = await read("app/lib/final-exam-pdf.ts");

  assert.match(pdf, /PDFDocument, PageSizes, StandardFonts/);
  assert.match(pdf, /this\.pdf\.addPage\(PageSizes\.A4\)/);
  assert.match(pdf, /finalExamLaboratoryResult/);
  assert.match(pdf, /finalExamImagingResult/);
  assert.match(pdf, /finalExamBloodType/);
  assert.match(pdf, /genericStructuredFacts/);
  assert.match(pdf, /drawTableRow/);
  assert.match(pdf, /embedPng|embedJpg/);
  assert.match(pdf, /Página \$\{index \+ 1\} de \$\{pages\.length\}/);
  assert.doesNotMatch(pdf, /Imagem gerada por IA\./);
  assert.equal(pdf.match(/Documento gerado exclusivamente para uso em RP\./g)?.length, 1);
  assert.doesNotMatch(pdf.replace("Documento gerado exclusivamente para uso em RP.", ""), /\bRP\b|GTA|roleplay|fictíci|simulação|personagem/i);
  assert.doesNotMatch(pdf, /reviewedBy|Médico aprovador|Revisado por/);
});

test("exam cards open details and completed results expose page links", async () => {
  const [center, pages, css] = await Promise.all([
    read("app/components/exam-center.tsx"),
    read("app/components/exam-page-actions.tsx"),
    read("app/brand.css"),
  ]);
  assert.match(center, /className="exam-hub-card"/);
  assert.match(center, /aria-label=\{`Abrir exame/);
  assert.match(center, /void openDetail\(exam\.id\)/);
  assert.match(center, /exam\.status === "completed" \? <ExamPageActions/);
  assert.match(pages, /Copiar link da página/);
  assert.match(pages, /navigator\.clipboard\.write/);
  assert.match(pages, /<DocumentImageViewer/);
  assert.match(css, /\.exam-hub-card/);
});

test("patient exam history exposes second-copy actions only for completed exams", async () => {
  const patientTab = await read("app/components/patient-exams-tab.tsx");

  assert.match(patientTab, /exam\.status === "completed" \? "Ver documento" : "Ver exame/);
  assert.match(patientTab, /exam\.status === "completed" \? <ExamPngListAction/);
  assert.match(patientTab, /initialDocumentOpen=\{detailDocumentOpen\}/);
  assert.match(patientTab, /pageSize: "10"/);
  assert.doesNotMatch(patientTab.slice(0, patientTab.indexOf("async function openDetail")), /\/api\/exams\/images/);
});

test("print rules isolate a light A4 document from application chrome", async () => {
  const css = await read("app/brand.css");

  assert.match(css, /@page \{ size: A4 portrait/);
  assert.match(css, /html\.printing-final-exam body \* \{ visibility: hidden/);
  assert.match(css, /html\.printing-final-exam \.final-exam-document/);
  assert.match(css, /\.final-document-toolbar \{ display: none !important/);
  assert.match(css, /background: #fff !important/);
  assert.match(css, /break-inside: avoid/);
});
