import {
  deleteStoredExamDocument,
  downloadStoredExamDocument,
  examDocumentStoragePath,
  loadPrivateExamImages,
  uploadStoredExamDocument,
} from "./exam-document-storage";
import {
  getClinicalExamDetail,
  getClinicalExamDocumentState,
  getClinicalExamImageGallery,
  registerClinicalExamDocument,
  type ClinicalExamDocumentState,
} from "./exams";
import { publishDocumentImage, recordDocumentImageEvent } from "./document-media";
import { buildFinalExamDocument, finalExamPngFilename } from "./final-exam-document";
import { FINAL_EXAM_PNG_RENDER_VERSION, renderFinalExamPng } from "./final-exam-png";
import { enrichClinicalExamIdentities, loadProfessionalDocumentIdentity } from "./professional-identity";

export async function getCompletedClinicalExam(accessToken: string, examId: number) {
  const exam = await enrichClinicalExamIdentities(await getClinicalExamDetail(accessToken, examId));
  if (exam.status !== "completed" || !exam.final_report_snapshot) {
    throw new Error("A imagem compartilhável está disponível somente para exames concluídos.");
  }
  return exam;
}

export async function ensureExamDocumentImage(accessToken: string, examId: number, uploadedBy: string | null, publishComplete = true) {
  const [exam, initialState] = await Promise.all([
    getCompletedClinicalExam(accessToken, examId),
    getClinicalExamDocumentState(accessToken, examId),
  ]);
  let state = initialState;
  let rendered = false;
  if (!exam.final_report_snapshot) throw new Error("A imagem compartilhável está disponível somente para exames concluídos.");

  if (!state.document) {
    const expectedImages = exam.final_report_snapshot.images.length;
    const gallery = expectedImages ? await getClinicalExamImageGallery(accessToken, examId) : [];
    const finalDocument = buildFinalExamDocument(exam, gallery);
    if (finalDocument.images.length !== expectedImages) throw new Error("Uma das imagens finais do exame não está disponível.");
    const imageAssets = await loadPrivateExamImages(finalDocument.images);
    const identity = await loadProfessionalDocumentIdentity(finalDocument.executedBy);
    const png = await renderFinalExamPng(finalDocument, imageAssets, identity);
    const documentId = crypto.randomUUID();
    const storagePath = examDocumentStoragePath(examId, documentId);
    await uploadStoredExamDocument(storagePath, png.bytes);
    try {
      state = await registerClinicalExamDocument(accessToken, {
        documentId,
        examId,
        fileSize: png.bytes.byteLength,
        pixelHeight: png.height,
        pixelWidth: png.width,
        renderVersion: FINAL_EXAM_PNG_RENDER_VERSION,
        storagePath,
      });
    } catch (error) {
      await deleteStoredExamDocument(storagePath).catch(() => undefined);
      throw error;
    }
    if (state.document?.id !== documentId) await deleteStoredExamDocument(storagePath).catch(() => undefined);
    rendered = true;
  }

  try {
    const publication = publishComplete ? await publishStoredExamDocument(examId, exam.exam_type.name, state, uploadedBy) : null;
    return { exam, publication, state };
  } finally {
    if (rendered) await recordDocumentImageEvent("EXAM", examId, uploadedBy, "DOCUMENT_IMAGE_RENDERED").catch(() => undefined);
  }
}

async function publishStoredExamDocument(examId: number, examTypeName: string, state: ClinicalExamDocumentState, uploadedBy: string | null) {
  if (!state.document) throw new Error("A imagem final do exame não está disponível.");
  const stored = await downloadStoredExamDocument(examDocumentStoragePath(examId, state.document.id));
  if (!stored.ok) throw new Error("A imagem do documento não está disponível.");
  return publishDocumentImage({
    bytes: new Uint8Array(await stored.arrayBuffer()),
    documentId: examId,
    documentType: "EXAM",
    filename: finalExamPngFilename(examId, examTypeName),
    renderVersion: state.document.render_version,
    uploadedBy,
  });
}
