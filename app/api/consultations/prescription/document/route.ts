import { prescriptionDocumentFilename } from "../../../../lib/prescription-document";
import { ensurePrescriptionDocument, getPrescriptionDocumentState, recordPrescriptionDocumentAccess, revokePrescriptionDocumentShare, type PrescriptionDocumentState } from "../../../../lib/prescription-document-service";
import { downloadStoredPrescriptionDocument, prescriptionDocumentStoragePath } from "../../../../lib/prescription-document-storage";
import { currentDocumentImagePublication, getDocumentImagePublication, publicationClientState, recordDocumentImageEvent } from "../../../../lib/document-media";
import type { DocumentImagePublication } from "../../../../lib/document-media-types";
import { getSessionBootstrap } from "../../../../lib/session";

export async function GET(request: Request) {
  const session = await authorizedSession();
  if (session instanceof Response) return session;
  const params = new URL(request.url).searchParams;
  const consultationId = positiveInteger(params.get("id"));
  if (!consultationId) return errorResponse("Consulta inválida.", 400);
  try {
    const [state, publication] = await Promise.all([getPrescriptionDocumentState(session.accessToken, consultationId), getDocumentImagePublication("PRESCRIPTION", consultationId)]);
    if (params.get("download") === "1" || params.get("inline") === "1") {
      if (!state.document) return errorResponse("Gere a Receita antes de abrir o documento.", 409);
      const stored = await downloadStoredPrescriptionDocument(prescriptionDocumentStoragePath(consultationId, state.document.id));
      if (!stored.ok || !stored.body) return errorResponse("A imagem da Receita não está disponível.", 404);
      const downloading = params.get("download") === "1";
      await recordPrescriptionDocumentAccess(session.accessToken, consultationId, downloading ? "PRESCRIPTION_DOCUMENT_DOWNLOADED" : "PRESCRIPTION_DOCUMENT_VIEWED");
      await recordDocumentImageEvent("PRESCRIPTION", consultationId, session.profile.user_id, "DOCUMENT_IMAGE_DOWNLOAD");
      return new Response(stored.body, { headers: {
        "cache-control": "private, no-store, max-age=0", "content-disposition": `${downloading ? "attachment" : "inline"}; filename="${prescriptionDocumentFilename(consultationId)}"`,
        "content-length": stored.headers.get("content-length") ?? String(state.document.file_size), "content-type": "image/png", pragma: "no-cache", "x-content-type-options": "nosniff",
      } });
    }
    return Response.json(clientState(request, consultationId, state, publication), { headers: privateHeaders() });
  } catch (error) { return actionError(error); }
}

export async function POST(request: Request) {
  const session = await authorizedSession();
  if (session instanceof Response) return session;
  try {
    const body = await request.json() as Record<string, unknown>;
    const consultationId = positiveInteger(body.consultationId);
    if (!consultationId) return errorResponse("Consulta inválida.", 400);
    if (body.action === "link-copied") {
      await getPrescriptionDocumentState(session.accessToken, consultationId);
      await recordDocumentImageEvent("PRESCRIPTION", consultationId, session.profile.user_id, "DOCUMENT_IMAGE_LINK_COPIED");
      const [state, publication] = await Promise.all([getPrescriptionDocumentState(session.accessToken, consultationId), getDocumentImagePublication("PRESCRIPTION", consultationId)]);
      return Response.json(clientState(request, consultationId, state, publication), { headers: privateHeaders() });
    }
    const state = await ensurePrescriptionDocument(session.accessToken, consultationId, session.profile.user_id);
    return Response.json(clientState(request, consultationId, state, await getDocumentImagePublication("PRESCRIPTION", consultationId)), { headers: privateHeaders() });
  } catch (error) { return actionError(error); }
}

export async function DELETE(request: Request) {
  const session = await authorizedSession();
  if (session instanceof Response) return session;
  const consultationId = positiveInteger(new URL(request.url).searchParams.get("id"));
  if (!consultationId) return errorResponse("Consulta inválida.", 400);
  try { return Response.json(clientState(request, consultationId, await revokePrescriptionDocumentShare(session.accessToken, consultationId), await getDocumentImagePublication("PRESCRIPTION", consultationId)), { headers: privateHeaders() }); }
  catch (error) { return actionError(error); }
}

async function authorizedSession() { const session = await getSessionBootstrap(); if (!session) return errorResponse("Sessão expirada.", 401); if (!session.permissionCodes.includes("consultations.view")) return errorResponse("Acesso não autorizado.", 403); return session; }
function clientState(request: Request, consultationId: number, state: PrescriptionDocumentState, publication: DocumentImagePublication | null) { void request; const currentPublication = currentDocumentImagePublication(publication, state.document?.render_version); return { ...state, ...publicationClientState(currentPublication), downloadUrl: state.document ? `/api/consultations/prescription/document?id=${consultationId}&download=1` : null, inlineUrl: state.document ? `/api/consultations/prescription/document?id=${consultationId}&inline=1` : null, shareUrl: currentPublication?.publication_status === "PUBLISHED" ? currentPublication.cdn_url : null }; }
function positiveInteger(value: unknown) { const parsed = Number(value); return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null; }
function privateHeaders() { return { "cache-control": "private, no-store, max-age=0", pragma: "no-cache", "x-content-type-options": "nosniff" }; }
function actionError(error: unknown) { const message = error instanceof Error ? error.message : "Não foi possível preparar a Receita."; const forbidden = /acesso não autorizado/i.test(message); const conflict = /somente após a conclusão|gere a Receita/i.test(message); const unavailable = /publica|demorou além|FiveManage/i.test(message); return errorResponse(forbidden ? "Acesso não autorizado." : message, forbidden ? 403 : conflict ? 409 : unavailable ? 503 : 400); }
function errorResponse(error: string, status: number) { return Response.json({ error }, { status, headers: privateHeaders() }); }
