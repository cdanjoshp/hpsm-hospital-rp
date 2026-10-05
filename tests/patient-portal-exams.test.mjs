import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("phase 6.4 exam RPCs are session-derived, patient-scoped and service-only", async () => {
  const migration = await read("supabase/migrations/20260910164016_phase64_patient_portal_exams.sql");
  for (const name of [
    "patient_portal_exam_page",
    "patient_portal_exam_detail",
    "patient_portal_exam_image",
    "patient_portal_exam_document_state",
    "patient_portal_register_clinical_exam_document",
    "patient_portal_create_clinical_exam_document_share",
  ]) {
    assert.match(migration, new RegExp(`create or replace function public\\.${name}\\(`));
  }
  assert.match(migration, /private\.patient_portal_session_record\(p_token_hash\)/g);
  assert.match(migration, /exam\.patient_id = v_session\.patient_id/g);
  assert.match(migration, /exam\.status = 'completed'/g);
  assert.match(migration, /v_target\.status = 'completed' then v_target\.final_report_snapshot else null/);
  assert.match(migration, /limit v_limit \+ 1/);
  assert.match(migration, /order by exam\.requested_at desc, exam\.id desc/);
  assert.doesNotMatch(migration, /patient_portal_exam_page\([\s\S]{0,180}p_patient_id/);
  assert.doesNotMatch(migration, /grant execute[\s\S]{0,180}to (?:anon|authenticated)/i);
  assert.match(migration, /created_by_patient_id/);
  assert.match(migration, /clinical_exam_documents_creator_check/);
  assert.match(migration, /clinical_exam_document_shares_creator_check/);
});

test("portal exams expose metadata first and the approved canonical document only on detail", async () => {
  const [service, listRoute, detailRoute, imageRoute, documentRoute, list, detail, shell, summary, history] = await Promise.all([
    read("app/lib/patient-portal.ts"),
    read("app/api/patient-portal/exams/route.ts"),
    read("app/api/patient-portal/exams/[id]/route.ts"),
    read("app/api/patient-portal/exams/[id]/images/[imageId]/route.ts"),
    read("app/api/patient-portal/exams/[id]/document/route.ts"),
    read("app/components/patient-portal-exams.tsx"),
    read("app/components/patient-portal-exam-detail.tsx"),
    read("app/components/patient-portal-shell.tsx"),
    read("app/components/patient-portal-summary.tsx"),
    read("app/components/patient-portal-history.tsx"),
  ]);

  assert.match(service, /patient_portal_exam_page/);
  assert.match(service, /p_limit: 15/);
  assert.match(service, /buildFinalExamDocument/);
  assert.match(shell, /href: "\/portal-paciente\/exames", key: "exams", label: "Exames"/);
  assert.match(list, /Todos/);
  assert.match(list, /Em andamento/);
  assert.match(list, /Concluídos/);
  assert.match(list, /Ver resultado/);
  assert.match(detail, /FinalExamDocument/);
  assert.match(detail, /Resultado ainda não disponível/);
  assert.match(summary, /\/portal-paciente\/exames\/\$\{exam\.id\}/);
  assert.match(history, /\/portal-paciente\/exames\/\$\{item\.examId\}/);
  for (const route of [listRoute, detailRoute, imageRoute, documentRoute]) {
    assert.match(route, /no-store/);
  }
  assert.doesNotMatch(detailRoute, /storage_path|final_report_snapshot|ai_generations|patient\.id/);
  assert.match(imageRoute, /getPatientPortalExamImage/);
  assert.match(imageRoute, /clinical-exam-images/);
});

test("patient second copy reuses the canonical PNG, private storage and public direct share route", async () => {
  const [patientRoute, professionalRoute, professionalService, storage, actions, publicRoute, styles, rendererCoverage] = await Promise.all([
    read("app/api/patient-portal/exams/[id]/document/route.ts"),
    read("app/api/exams/document-image/route.ts"),
    read("app/lib/exam-document-image-service.ts"),
    read("app/lib/exam-document-storage.ts"),
    read("app/components/patient-portal-exam-actions.tsx"),
    read("app/api/exam-share/[file]/route.ts"),
    read("app/brand.css"),
    read("tests/final-exam-pdf-render.test.mjs"),
  ]);

  for (const source of [patientRoute, professionalService]) {
    assert.match(source, /renderFinalExamPng/);
    assert.match(source, /examDocumentStoragePath/);
    assert.match(source, /loadPrivateExamImages/);
  }
  assert.match(professionalRoute, /ensureExamDocumentImage/);
  assert.match(storage, /clinical-exam-documents/);
  assert.match(storage, /clinical-exam-images/);
  assert.match(actions, /Baixar imagem/);
  assert.match(actions, /Copiar link/);
  assert.match(actions, /Qualquer pessoa com este link poderá visualizar este exame\./);
  assert.doesNotMatch(actions, /Revogar/);
  assert.match(publicRoute, /content-type": "image\/png"/);
  assert.match(publicRoute, /status: 200/);
  assert.match(publicRoute, /\.png\$/);
  assert.match(styles, /html\[data-theme="dark"\][\s\S]*?\.patient-portal-exam-list/);
  assert.match(styles, /@media \(max-width: 520px\)[\s\S]*?\.patient-portal-exam-actions/);
  assert.match(rendererCoverage, /Raio-X[\s\S]*Tomografia[\s\S]*Ressonância Magnética[\s\S]*Ultrassom[\s\S]*Hemograma[\s\S]*Bioquímica[\s\S]*Tipagem Sanguínea[\s\S]*Toxicologia[\s\S]*Biópsia[\s\S]*Citologia[\s\S]*Eletrocardiograma/);
});
