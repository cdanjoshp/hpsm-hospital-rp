import {
  deleteStoredExamDocument,
  downloadStoredExamDocument,
  examDocumentStoragePath,
  loadPrivateExamImages,
  uploadStoredExamDocument,
} from "../../../../../lib/exam-document-storage";
import { finalExamPngFilename } from "../../../../../lib/final-exam-document";
import { currentDocumentImagePublication, getDocumentImagePublication, publishDocumentImage, recordDocumentImageEvent } from "../../../../../lib/document-media";
import { FINAL_EXAM_PNG_RENDER_VERSION, renderFinalExamPng } from "../../../../../lib/final-exam-png";
import type { ClinicalExamDocumentState } from "../../../../../lib/exams";
import { loadProfessionalDocumentIdentity } from "../../../../../lib/professional-identity";
import {
  getPatientPortalExamDetail,
  getPatientPortalExamDocumentState,
  registerPatientPortalExamDocument,
  type PatientPortalExamDetail,
} from "../../../../../lib/patient-portal";

export async function GET(_request: Request, context: { params: Promise<{ id: string }> }) {
  const examId = await examIdFromParams(context.params);
  if (!examId) return notFound();
  try {
    const [detail, state] = await Promise.all([
      getPatientPortalExamDetail(examId),
      getPatientPortalExamDocumentState(examId),
    ]);
    if (!detail || !state) return unauthorized();
    if (detail === "not_found" || state === "not_found" || !detail.document || !state.document) return notFound();
    const stored = await downloadStoredExamDocument(examDocumentStoragePath(examId, state.document.id));
    if (!stored.ok || !stored.body) return notFound();
    await recordDocumentImageEvent("EXAM", examId, null, "DOCUMENT_IMAGE_DOWNLOAD");
    return new Response(stored.body, { headers: {
      ...privateHeaders(),
      "content-disposition": `attachment; filename="${finalExamPngFilename(examId, detail.document.exam.name)}"`,
      "content-length": stored.headers.get("content-length") ?? String(state.document.file_size),
      "content-type": "image/png",
    } });
  } catch {
    return documentError("Não foi possível baixar o resultado agora.", 503);
  }
}

export async function POST(request: Request, context: { params: Promise<{ id: string }> }) {
  const examId = await examIdFromParams(context.params);
  if (!examId) return notFound();
  let action: "download" | "share";
  try {
    const body = await request.json() as Record<string, unknown>;
    if (body.action !== "download" && body.action !== "share") return documentError("Ação inválida.", 400);
    action = body.action;
  } catch {
    return documentError("Ação inválida.", 400);
  }

  try {
    const [detail, initialState] = await Promise.all([
      getPatientPortalExamDetail(examId),
      getPatientPortalExamDocumentState(examId),
    ]);
    if (!detail || !initialState) return unauthorized();
    if (detail === "not_found" || initialState === "not_found" || !detail.document) return notFound();

    let state: ClinicalExamDocumentState = initialState;
    if (!state.document) {
      const prepared = await prepareDocument(examId, detail);
      if (!prepared || prepared === "not_found") return notFound();
      state = prepared;
    }
    if (!state.document) return notFound();
    const stored = await downloadStoredExamDocument(examDocumentStoragePath(examId, state.document.id));
    if (!stored.ok) return notFound();
    let publication = await getDocumentImagePublication("EXAM", examId);
    try {
      publication = await publishDocumentImage({
        bytes: new Uint8Array(await stored.arrayBuffer()),
        documentId: examId,
        documentType: "EXAM",
        filename: finalExamPngFilename(examId, detail.document.exam.name),
        renderVersion: state.document.render_version,
        uploadedBy: null,
      });
    } catch (cause) {
      if (action === "share") throw cause;
    }
    publication = currentDocumentImagePublication(publication, state.document.render_version);
    if (action === "share") await recordDocumentImageEvent("EXAM", examId, null, "DOCUMENT_IMAGE_LINK_COPIED");
    return Response.json({
      downloadUrl: `/api/patient-portal/exams/${examId}/document`,
      shareUrl: publication?.publication_status === "PUBLISHED" ? publication.cdn_url : null,
    }, { headers: privateHeaders() });
  } catch {
    return documentError("Não foi possível preparar o resultado agora.", 503);
  }
}

async function prepareDocument(examId: number, detail: PatientPortalExamDetail) {
  if (!detail.document) return "not_found" as const;
  const expectedImages = detail.document.images.length;
  const assets = expectedImages ? await loadPrivateExamImages(detail.document.images) : [];
  const identity = await loadProfessionalDocumentIdentity(detail.document.executedBy);
  const png = await renderFinalExamPng(detail.document, assets, identity);
  const documentId = crypto.randomUUID();
  const storagePath = examDocumentStoragePath(examId, documentId);
  await uploadStoredExamDocument(storagePath, png.bytes);
  try {
    const state = await registerPatientPortalExamDocument(examId, {
      documentId,
      fileSize: png.bytes.byteLength,
      pixelHeight: png.height,
      pixelWidth: png.width,
      renderVersion: FINAL_EXAM_PNG_RENDER_VERSION,
      storagePath,
    });
    if (!state || state === "not_found") {
      await deleteStoredExamDocument(storagePath).catch(() => undefined);
      return state;
    }
    if (state.document?.id !== documentId) await deleteStoredExamDocument(storagePath).catch(() => undefined);
    return state;
  } catch (error) {
    await deleteStoredExamDocument(storagePath).catch(() => undefined);
    throw error;
  }
}

async function examIdFromParams(params: Promise<{ id: string }>) {
  const { id } = await params;
  if (!/^\d+$/.test(id)) return null;
  const value = Number(id);
  return Number.isSafeInteger(value) && value > 0 ? value : null;
}

function privateHeaders() {
  return { "cache-control": "private, no-store, max-age=0", pragma: "no-cache", vary: "Cookie", "x-content-type-options": "nosniff" };
}
function notFound() {
  return documentError("Exame não localizado.", 404);
}
function unauthorized() {
  return Response.json({ authenticated: false }, { status: 401, headers: privateHeaders() });
}
function documentError(error: string, status: number) {
  return Response.json({ error }, { status, headers: privateHeaders() });
}
