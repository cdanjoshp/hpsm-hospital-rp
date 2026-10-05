import { buildFinalMedicalCertificateDocument } from "../../../../../lib/medical-certificate-document";
import { publishDocumentImage, recordDocumentImageEvent } from "../../../../../lib/document-media";
import { MEDICAL_CERTIFICATE_PNG_RENDER_VERSION, renderMedicalCertificatePng } from "../../../../../lib/medical-certificate-png";
import {
  deleteStoredMedicalCertificate,
  downloadStoredMedicalCertificate,
  loadMedicalCertificateIdentity,
  medicalCertificateStoragePath,
  uploadStoredMedicalCertificate,
} from "../../../../../lib/medical-certificate-storage";
import {
  auditPatientPortalMedicalCertificateDownload,
  getPatientPortalMedicalCertificateDetail,
  registerPatientPortalMedicalCertificateDocument,
} from "../../../../../lib/patient-portal";

const HEADERS = { "cache-control": "private, no-store, max-age=0", pragma: "no-cache", vary: "Cookie", "x-content-type-options": "nosniff" };

export async function GET(_: Request, { params }: { params: Promise<{ id: string }> }) {
  const certificateId = Number((await params).id);
  if (!Number.isSafeInteger(certificateId) || certificateId <= 0) return error("Atestado não localizado.", 404);
  try {
    let detail = await getPatientPortalMedicalCertificateDetail(certificateId);
    if (!detail) return error("Sessão expirada.", 401);
    if (detail === "not_found") return error("Atestado não localizado.", 404);
    if (!detail.document || detail.document.renderVersion !== MEDICAL_CERTIFICATE_PNG_RENDER_VERSION) {
      const previousPath = detail.document?.path ?? null;
      const document = buildFinalMedicalCertificateDocument(detail.snapshot);
      const identity = await loadMedicalCertificateIdentity(document.professional.signature_image_path, document.professional.id);
      const png = await renderMedicalCertificatePng(document, identity);
      const storagePath = medicalCertificateStoragePath(certificateId, crypto.randomUUID());
      await uploadStoredMedicalCertificate(storagePath, png.bytes);
      try {
        const registered = await registerPatientPortalMedicalCertificateDocument(certificateId, { fileSize: png.bytes.byteLength, height: png.height, renderVersion: MEDICAL_CERTIFICATE_PNG_RENDER_VERSION, storagePath, width: png.width });
        if (!registered || registered === "not_found") throw new Error("Atestado não localizado.");
        if (registered.document?.path !== storagePath) await deleteStoredMedicalCertificate(storagePath).catch(() => undefined);
        if (previousPath && registered.document?.path === storagePath && previousPath !== storagePath) await deleteStoredMedicalCertificate(previousPath).catch(() => undefined);
        detail = registered;
      } catch (cause) {
        await deleteStoredMedicalCertificate(storagePath).catch(() => undefined);
        throw cause;
      }
    }
    if (!detail.document) return error("O resultado ainda não está disponível.", 409);
    const stored = await downloadStoredMedicalCertificate(detail.document.path);
    if (!stored.ok || !stored.body) return error("O resultado não está disponível.", 404);
    await auditPatientPortalMedicalCertificateDownload(certificateId);
    const document = buildFinalMedicalCertificateDocument(detail.snapshot);
    const bytes = new Uint8Array(await stored.arrayBuffer());
    await publishDocumentImage({ bytes, documentId: certificateId, documentType: "MEDICAL_CERTIFICATE", filename: document.filename, renderVersion: detail.document.renderVersion, uploadedBy: null }).catch(() => undefined);
    await recordDocumentImageEvent("MEDICAL_CERTIFICATE", certificateId, null, "DOCUMENT_IMAGE_DOWNLOAD");
    return new Response(bytes, { headers: { ...HEADERS, "content-disposition": `attachment; filename="${document.filename}"`, "content-length": String(bytes.byteLength), "content-type": "image/png" } });
  } catch {
    return error("Não foi possível preparar o resultado agora.", 503);
  }
}

function error(message: string, status: number) { return Response.json({ error: message }, { status, headers: HEADERS }); }
