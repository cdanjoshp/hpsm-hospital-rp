import { ensureMedicalCertificateDocument } from "../../../lib/medical-certificate-document-service";
import { buildFinalMedicalCertificateDocument } from "../../../lib/medical-certificate-document";
import { currentDocumentImagePublication, getDocumentImagePublication, publicationClientState, recordDocumentImageEvent } from "../../../lib/document-media";
import { downloadStoredMedicalCertificate } from "../../../lib/medical-certificate-storage";
import { getMedicalCertificateDocumentState, runMedicalCertificateMutation, type MedicalCertificateDocumentState } from "../../../lib/medical-certificates";
import { getSessionBootstrap } from "../../../lib/session";

export async function POST(request: Request) {
  const session = await authorizedSession();
  if (session instanceof Response) return session;
  try {
    const body = await request.json() as Record<string, unknown>;
    const certificateId = positiveInteger(body.certificateId);
    if (!certificateId) return responseError("Atestado inválido.", 400);
    if (body.action === "link-copied") {
      const state = await getMedicalCertificateDocumentState(session.accessToken, certificateId);
      await recordDocumentImageEvent("MEDICAL_CERTIFICATE", certificateId, session.profile.user_id, "DOCUMENT_IMAGE_LINK_COPIED");
      return Response.json(await clientState(certificateId, state), { headers: privateHeaders() });
    }
    const state = await ensureMedicalCertificateDocument(session.accessToken, certificateId, session.profile.user_id);
    return Response.json(await clientState(certificateId, state), { headers: privateHeaders() });
  } catch (error) {
    return actionError(error);
  }
}

export async function GET(request: Request) {
  const session = await authorizedSession();
  if (session instanceof Response) return session;
  const params = new URL(request.url).searchParams;
  const certificateId = positiveInteger(params.get("id"));
  const download = params.get("download") === "1";
  if (!certificateId) return responseError("Atestado inválido.", 400);
  try {
    let state: MedicalCertificateDocumentState;
    try {
      state = await ensureMedicalCertificateDocument(session.accessToken, certificateId, session.profile.user_id);
    } catch (cause) {
      state = await getMedicalCertificateDocumentState(session.accessToken, certificateId);
      if (!state.document) throw cause;
    }
    if (!state.document || !state.snapshot) return responseError("O resultado ainda não está disponível.", 409);
    const stored = await downloadStoredMedicalCertificate(state.document.path);
    if (!stored.ok || !stored.body) return responseError("A imagem do atestado não está disponível.", 404);
    await runMedicalCertificateMutation(session.accessToken, "audit_medical_certificate_download", { p_certificate_id: certificateId });
    await recordDocumentImageEvent("MEDICAL_CERTIFICATE", certificateId, session.profile.user_id, "DOCUMENT_IMAGE_DOWNLOAD");
    const document = buildFinalMedicalCertificateDocument(state.snapshot);
    return new Response(stored.body, {
      headers: {
        "cache-control": "private, no-store, max-age=0",
        "content-disposition": `${download ? "attachment" : "inline"}; filename="${document.filename}"`,
        "content-length": stored.headers.get("content-length") ?? String(state.document.file_size),
        "content-type": "image/png",
        pragma: "no-cache",
        "x-content-type-options": "nosniff",
      },
    });
  } catch (error) {
    return actionError(error);
  }
}

async function clientState(certificateId: number, state: MedicalCertificateDocumentState) {
  const publication = currentDocumentImagePublication(await getDocumentImagePublication("MEDICAL_CERTIFICATE", certificateId), state.document?.render_version);
  return {
    ...publicationClientState(publication),
    documentReady: Boolean(state.document),
    previewUrl: state.document ? `/api/medical-certificates/document?id=${certificateId}` : null,
    downloadUrl: state.document ? `/api/medical-certificates/document?id=${certificateId}&download=1` : null,
    shareUrl: publication?.publication_status === "PUBLISHED" ? publication.cdn_url : null,
  };
}

async function authorizedSession() { const session = await getSessionBootstrap(); if (!session) return responseError("Sessão expirada.", 401); if (!session.permissionCodes.includes("atestados.view")) return responseError("Acesso não autorizado.", 403); return session; }
function positiveInteger(value: unknown) { const parsed = Number(value); return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null; }
function privateHeaders() { return { "cache-control": "private, no-store, max-age=0", pragma: "no-cache", "x-content-type-options": "nosniff" }; }
function responseError(error: string, status: number) { return Response.json({ error }, { status, headers: privateHeaders() }); }
function actionError(error: unknown) { const message = error instanceof Error ? error.message : "Não foi possível preparar o resultado."; const forbidden = /acesso não autorizado/i.test(message); const conflict = /somente para atestados finalizados|resultado está disponível/i.test(message); const unavailable = /publica|demorou além|FiveManage/i.test(message); return responseError(forbidden ? "Acesso não autorizado." : message, forbidden ? 403 : conflict ? 409 : unavailable ? 503 : 400); }
