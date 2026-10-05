import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("imaging request data is captured before execution and stays read only afterwards", async () => {
  const [center, migration] = await Promise.all([
    read("app/components/exam-center.tsx"),
    read("supabase/migrations/20260901150000_exam_request_data_ai_sync_and_deletion.sql"),
  ]);
  const createPanel = center.slice(center.indexOf("export function ExamCreatePanel"), center.indexOf("export function ExamDetailPanel"));
  const execution = center.slice(center.indexOf('exam.status === "in_progress"'), center.indexOf('exam.status === "awaiting_review"'));
  assert.match(createPanel, /initialResultData: isBetaHcg \? \{ beta_hcg_outcome: betaHcgOutcome, \.\.\.\(betaHcgOutcome === "positive" \? \{ gestational_weeks: Number\(gestationalWeeks\) \} : \{\}\) \} : imagingRequest/);
  assert.match(createPanel, /<ImagingResultEditor result=\{imagingRequest\}/);
  assert.match(center, /<ImagingResultView result=\{imagingResult\}/);
  assert.doesNotMatch(execution, /<ImagingResultEditor result=\{imagingResult\}/);
  assert.match(migration, /'result_config', exam_type\.result_config/);
  assert.match(migration, /p_initial_result_data jsonb default null/);
  assert.match(migration, /Preencha as informações básicas do exame de imagem na solicitação/);
});

test("the Luna clinical report v3 replaces Observacao RP with a complete report", async () => {
  const [assistant, edge, requestMigration, reportMigration] = await Promise.all([
    read("app/components/exam-ai-assistant.tsx"),
    read("supabase/functions/exam-ai-generate/index.ts"),
    read("supabase/migrations/20260901150000_exam_request_data_ai_sync_and_deletion.sql"),
    read("supabase/migrations/20260901180425_luna_clinical_report_v3.sql"),
  ]);
  assert.doesNotMatch(assistant, /Observação RP/);
  assert.match(edge, /hpsm\.ai\.clinical_report\.v3/);
  const schema = edge.slice(edge.indexOf("function reportSchema"), edge.indexOf("function validateLaboratorySuggestion"));
  assert.doesNotMatch(schema, /rp_note/);
  for (const field of ["technique", "findings", "conclusion", "conduct"]) assert.match(schema, new RegExp(field));
  assert.doesNotMatch(edge, /observação RP opcional/i);
  assert.match(requestMigration, /v_exam\.result_data->>'schema' = 'hpsm\.image_result\.v1' then v_exam\.result_data/);
  assert.match(reportMigration, /jsonb_set\(v_exam\.result_data, '\{notes\}', to_jsonb\(v_conduct\), true\)/);
});

test("AI image application refreshes the gallery and recovers a late response", async () => {
  const [flow, gallery] = await Promise.all([
    read("app/lib/exam-ai-flow.ts"),
    read("app/components/imaging-results.tsx"),
  ]);
  assert.match(flow, /recoverCompletedExam/);
  assert.match(flow, /await callImage\(examId, "status"\)/);
  assert.match(flow, /\["awaiting_review", "completed"\]/);
  assert.match(gallery, /refreshToken = 0/);
  assert.match(gallery, /\[examId, refreshToken\]/);
  const center = await read("app/components/exam-center.tsx");
  assert.match(center, /setGalleryRevision\(\(current\) => current \+ 1\)/);
  assert.match(center, /Não foi possível confirmar as imagens do exame/);
  assert.doesNotMatch(center, /Aguarde o carregamento da galeria antes de enviar para revisão/);
});

test("directors can delete completed exams with dependent records and private files", async () => {
  const [page, center, edge, migration] = await Promise.all([
    read("app/exames/page.tsx"),
    read("app/components/exam-center.tsx"),
    read("supabase/functions/exam-delete/index.ts"),
    read("supabase/migrations/20260930220336_director_delete_completed_exams.sql"),
  ]);
  assert.match(center, /deleteConfirmation !== `EXCLUIR \$\{exam\.id\}`/);
  assert.match(page, /canDeleteCompleted=\{permissions\.includes\("exams\.delete"\) && context\.positionLevel !== null && context\.positionLevel >= 12 && context\.positionLevel <= 14\}/);
  assert.match(center, /exam\.status === "completed" \? canDeleteCompleted : canDeleteAny \|\| exam\.responsible_professional\.id === currentUserId/);
  assert.match(migration, /position\.official and position\.active and position\.level between 12 and 14/);
  assert.match(migration, /Somente diretores podem excluir exames concluídos/);
  assert.match(migration, /elsif v_exam\.responsible_professional_id is distinct from v_actor/);
  assert.match(migration, /delete from public\.medical_certificate_exams where exam_id = p_exam_id/);
  assert.match(migration, /delete from public\.clinical_exam_document_shares where exam_id = p_exam_id/);
  assert.match(migration, /delete from public\.clinical_exam_page_publications where exam_id = p_exam_id/);
  assert.match(migration, /delete from public\.clinical_exam_documents where exam_id = p_exam_id/);
  assert.match(migration, /delete from public\.document_media_publications where document_type = 'EXAM' and document_id = p_exam_id/);
  assert.match(migration, /delete from public\.exam_result_choices where exam_id = p_exam_id/);
  assert.match(migration, /delete from public\.exam_ai_generations/);
  assert.match(migration, /delete from public\.clinical_exam_images/);
  assert.match(migration, /delete from public\.clinical_exam_report_versions/);
  assert.match(edge, /storage\/v1\/object\/\$\{bucket\}/);
  assert.match(edge, /DOCUMENT_BUCKET = "clinical-exam-documents"/);
  assert.match(edge, /result\.document_storage_paths/);
  assert.match(edge, /prefixes: paths\.slice/);
});
