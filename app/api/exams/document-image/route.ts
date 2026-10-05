import {
  downloadStoredExamDocument,
  examDocumentStoragePath,
} from "../../../lib/exam-document-storage";
import {
  getClinicalExamDocumentState,
  revokeClinicalExamDocumentShare,
  type ClinicalExamDocumentState,
} from "../../../lib/exams";
import { ensureExamDocumentImage, getCompletedClinicalExam } from "../../../lib/exam-document-image-service";
import { currentDocumentImagePublication, getDocumentImagePublication, publicationClientState, recordDocumentImageEvent } from "../../../lib/document-media";
import type { DocumentImagePublication } from "../../../lib/document-media-types";
import { finalExamPngFilename } from "../../../lib/final-exam-document";
import { getSessionBootstrap } from "../../../lib/session";

export async function GET(request: Request) {
  const session = await authorizedSession();
  if (session instanceof Response) return session;
  const params = new URL(request.url).searchParams;
  const examId = positiveInteger(params.get("id"));
  if (!examId) return documentError("Exame inválido.", 400);

  try {
    const [exam, state, publication] = await Promise.all([
      getCompletedClinicalExam(session.accessToken, examId),
      getClinicalExamDocumentState(session.accessToken, examId),
      getDocumentImagePublication("EXAM", examId),
    ]);
    if (params.get("download") === "1" || params.get("inline") === "1") {
      if (!state.document) return documentError("Gere a imagem compartilhável antes de baixar.", 409);
      const path = examDocumentStoragePath(examId, state.document.id);
      const stored = await downloadStoredExamDocument(path);
      if (!stored.ok || !stored.body) return documentError("A imagem do documento não está disponível.", 404);
      await recordDocumentImageEvent("EXAM", examId, session.profile.user_id, "DOCUMENT_IMAGE_DOWNLOAD");
      const downloading = params.get("download") === "1";
      return new Response(stored.body, {
        headers: {
          "cache-control": "private, no-store, max-age=0",
          "content-disposition": `${downloading ? "attachment" : "inline"}; filename="${finalExamPngFilename(exam.id, exam.exam_type.name)}"`,
          "content-length": stored.headers.get("content-length") ?? String(state.document.file_size),
          "content-type": "image/png",
          pragma: "no-cache",
          "x-content-type-options": "nosniff",
        },
      });
    }
    return Response.json(clientState(request, examId, state, publication), { headers: privateHeaders() });
  } catch (error) {
    return actionError(error);
  }
}

export async function POST(request: Request) {
  const session = await authorizedSession();
  if (session instanceof Response) return session;

  try {
    const body = await request.json() as Record<string, unknown>;
    const examId = positiveInteger(body.examId);
    if (!examId) return documentError("Exame inválido.", 400);
    const action = body.action === "link-copied" ? "link-copied" : body.action === "create-link" ? "create-link" : "ensure";
    if (action === "link-copied") {
      await getCompletedClinicalExam(session.accessToken, examId);
      const state = await getClinicalExamDocumentState(session.accessToken, examId);
      await recordDocumentImageEvent("EXAM", examId, session.profile.user_id, "DOCUMENT_IMAGE_LINK_COPIED");
      const publication = await getDocumentImagePublication("EXAM", examId);
      return Response.json(clientState(request, examId, state, publication), { headers: privateHeaders() });
    }
    const { publication, state } = await ensureExamDocumentImage(session.accessToken, examId, session.profile.user_id);
    return Response.json(clientState(request, examId, state, publication), { headers: privateHeaders() });
  } catch (error) {
    return actionError(error);
  }
}

export async function DELETE(request: Request) {
  const session = await authorizedSession();
  if (session instanceof Response) return session;
  const examId = positiveInteger(new URL(request.url).searchParams.get("id"));
  if (!examId) return documentError("Exame inválido.", 400);

  try {
    await getCompletedClinicalExam(session.accessToken, examId);
    const state = await revokeClinicalExamDocumentShare(session.accessToken, examId);
    return Response.json(clientState(request, examId, state, await getDocumentImagePublication("EXAM", examId)), { headers: privateHeaders() });
  } catch (error) {
    return actionError(error);
  }
}

async function authorizedSession() {
  const session = await getSessionBootstrap();
  if (!session) return documentError("Sessão expirada.", 401);
  if (!session.permissionCodes.includes("exams.view")) return documentError("Acesso não autorizado.", 403);
  return session;
}

function clientState(request: Request, examId: number, state: ClinicalExamDocumentState, publication: DocumentImagePublication | null) {
  void request;
  const currentPublication = currentDocumentImagePublication(publication, state.document?.render_version);
  return {
    ...state,
    ...publicationClientState(currentPublication),
    downloadUrl: state.document ? `/api/exams/document-image?id=${examId}&download=1` : null,
    inlineUrl: state.document ? `/api/exams/document-image?id=${examId}&inline=1` : null,
    shareUrl: currentPublication?.publication_status === "PUBLISHED" ? currentPublication.cdn_url : null,
  };
}

function positiveInteger(value: unknown) {
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null;
}

function privateHeaders() {
  return { "cache-control": "private, no-store, max-age=0", pragma: "no-cache", "x-content-type-options": "nosniff" };
}

function actionError(error: unknown) {
  const message = error instanceof Error ? error.message : "Não foi possível preparar a imagem compartilhável.";
  const forbidden = /acesso não autorizado/i.test(message);
  const conflict = /somente para exames concluídos|gere a imagem/i.test(message);
  const unavailable = /publica|demorou além|FiveManage/i.test(message);
  return documentError(forbidden ? "Acesso não autorizado." : message, forbidden ? 403 : conflict ? 409 : unavailable ? 503 : 400);
}

function documentError(error: string, status: number) {
  return Response.json({ error }, { status, headers: privateHeaders() });
}
