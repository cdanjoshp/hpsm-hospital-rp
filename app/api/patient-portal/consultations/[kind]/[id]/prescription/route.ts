import { getPatientPortalConsultationDetail, getPatientPortalPrescriptionSnapshot } from "../../../../../../lib/patient-portal";
import { prescriptionDocumentFilename } from "../../../../../../lib/prescription-document";
import { renderPrescriptionDocumentPng } from "../../../../../../lib/prescription-document-png";
import { loadMedicalCertificateIdentity } from "../../../../../../lib/medical-certificate-storage";

const HEADERS = { "cache-control": "private, no-store", pragma: "no-cache", vary: "Cookie", "x-content-type-options": "nosniff" };
export async function GET(_request: Request, { params }: { params: Promise<{ kind: string; id: string }> }) {
  const { kind, id } = await params;
  if ((kind !== "appointment" && kind !== "consultation") || !/^[1-9]\d*$/.test(id) || !Number.isSafeInteger(Number(id))) return error("Consulta não localizada.", 404);
  try {
    const detail = await getPatientPortalConsultationDetail(kind, Number(id));
    if (!detail) return error("Sessão expirada.", 401);
    if (detail === "not_found" || !detail.snapshot || !detail.consultation.consultationId) return error("Receita indisponível.", 404);
    const consultationId = detail.consultation.consultationId;
    const snapshot = await getPatientPortalPrescriptionSnapshot(consultationId);
    if (snapshot === "unauthenticated") return error("Sessão expirada.", 401);
    if (!snapshot || snapshot.patient.passport !== detail.patient.passport) return error("Receita indisponível.", 404);
    const identity = await loadMedicalCertificateIdentity(snapshot.professional.signature_image_path, snapshot.professional.id);
    const png = await renderPrescriptionDocumentPng(snapshot, identity);
    return new Response(png.bytes.slice().buffer, { headers: {
      ...HEADERS, "content-disposition": `attachment; filename="${prescriptionDocumentFilename(consultationId)}"`,
      "content-length": String(png.bytes.byteLength), "content-type": "image/png",
    } });
  } catch { return error("Não foi possível preparar a Receita agora.", 503); }
}
function error(message: string, status: number) { return Response.json({ error: message }, { status, headers: HEADERS }); }
