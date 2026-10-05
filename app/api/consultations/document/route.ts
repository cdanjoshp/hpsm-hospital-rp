import { consultationDocumentFilename } from "../../../lib/consultation-document";
import {
  ensureConsultationDocument,
  getConsultationDocumentState,
  revokeConsultationDocumentShare,
  type ConsultationDocumentState,
} from "../../../lib/consultation-document-service";
import { consultationDocumentStoragePath, downloadStoredConsultationDocument } from "../../../lib/consultation-document-storage";
import { currentDocumentImagePublication, getDocumentImagePublication, publicationClientState, recordDocumentImageEvent } from "../../../lib/document-media";
import type { DocumentImagePublication } from "../../../lib/document-media-types";
import { getSessionBootstrap } from "../../../lib/session";

export async function GET(request: Request) {
  const session = await authorizedSession();
  if (session instanceof Response) return session;
  const params = new URL(request.url).searchParams;
  const consultationId = positiveInteger(params.get("id"));
  if (!consultationId) return errorResponse("Consulta inválida.", 400);
  try {
    const [state, publication] = await Promise.all([
      getConsultationDocumentState(session.accessToken, consultationId),
      getDocumentImagePublication("CONSULTATION_RECORD", consultationId),
    ]);
    if (params.get("download") === "1" || params.get("inline") === "1") {
      if (!state.document) return errorResponse("Gere o prontuário antes de abrir o documento.", 409);
      const path = consultationDocumentStoragePath(consultationId, state.document.id);
      const stored = await downloadStoredConsultationDocument(path);
      if (!stored.ok || !stored.body) return errorResponse("A imagem do prontuário não está disponível.", 404);
      const disposition = params.get("download") === "1" ? "attachment" : "inline";
      await recordDocumentImageEvent("CONSULTATION_RECORD", consultationId, session.profile.user_id, "DOCUMENT_IMAGE_DOWNLOAD");
      return new Response(stored.body, { headers: {
        "cache-control": "private, no-store, max-age=0",
        "content-disposition": `${disposition}; filename="${consultationDocumentFilename(consultationId)}"`,
        "content-length": stored.headers.get("content-length") ?? String(state.document.file_size),
        "content-type": "image/png",
        pragma: "no-cache",
        "x-content-type-options": "nosniff",
      } });
    }
    return Response.json(clientState(request, consultationId, state, publication), { headers: privateHeaders() });
  } catch (error) {
    return actionError(error);
  }
}

export async function POST(request: Request) {
  const session = await authorizedSession();
  if (session instanceof Response) return session;
  try {
    const body = await request.json() as Record<string, unknown>;
    const consultationId = positiveInteger(body.consultationId);
    if (!consultationId) return errorResponse("Consulta inválida.", 400);
    if (body.action === "link-copied") {
      await getConsultationDocumentState(session.accessToken, consultationId);
      await recordDocumentImageEvent("CONSULTATION_RECORD", consultationId, session.profile.user_id, "DOCUMENT_IMAGE_LINK_COPIED");
      const [state, publication] = await Promise.all([getConsultationDocumentState(session.accessToken, consultationId), getDocumentImagePublication("CONSULTATION_RECORD", consultationId)]);
      return Response.json(clientState(request, consultationId, state, publication), { headers: privateHeaders() });
    }
    const state = await ensureConsultationDocument(session.accessToken, consultationId, session.profile.user_id);
    const publication = await getDocumentImagePublication("CONSULTATION_RECORD", consultationId);
    return Response.json(clientState(request, consultationId, state, publication), { headers: privateHeaders() });
  } catch (error) {
    return actionError(error);
  }
}

export async function DELETE(request: Request) {
  const session = await authorizedSession();
  if (session instanceof Response) return session;
  const consultationId = positiveInteger(new URL(request.url).searchParams.get("id"));
  if (!consultationId) return errorResponse("Consulta inválida.", 400);
  try {
    const state = await revokeConsultationDocumentShare(session.accessToken, consultationId);
    return Response.json(clientState(request, consultationId, state, await getDocumentImagePublication("CONSULTATION_RECORD", consultationId)), { headers: privateHeaders() });
  } catch (error) {
    return actionError(error);
  }
}

async function authorizedSession() {
  const session = await getSessionBootstrap();
  if (!session) return errorResponse("Sessão expirada.", 401);
  if (!session.permissionCodes.includes("consultations.view")) return errorResponse("Acesso não autorizado.", 403);
  return session;
}

function clientState(request: Request, consultationId: number, state: ConsultationDocumentState, publication: DocumentImagePublication | null) {
  void request;
  const currentPublication = currentDocumentImagePublication(publication, state.document?.render_version);
  return {
    ...state,
    ...publicationClientState(currentPublication),
    downloadUrl: state.document ? `/api/consultations/document?id=${consultationId}&download=1` : null,
    inlineUrl: state.document ? `/api/consultations/document?id=${consultationId}&inline=1` : null,
    shareUrl: currentPublication?.publication_status === "PUBLISHED" ? currentPublication.cdn_url : null,
  };
}

function positiveInteger(value: unknown) { const parsed = Number(value); return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null; }
function privateHeaders() { return { "cache-control": "private, no-store, max-age=0", pragma: "no-cache", "x-content-type-options": "nosniff" }; }
function actionError(error: unknown) {
  const message = error instanceof Error ? error.message : "Não foi possível preparar o prontuário.";
  const forbidden = /acesso não autorizado/i.test(message);
  const conflict = /somente para consultas concluídas|gere o prontuário/i.test(message);
  const unavailable = /publica|demorou além|FiveManage/i.test(message);
  return errorResponse(forbidden ? "Acesso não autorizado." : message, forbidden ? 403 : conflict ? 409 : unavailable ? 503 : 400);
}
function errorResponse(error: string, status: number) { return Response.json({ error }, { status, headers: privateHeaders() }); }
