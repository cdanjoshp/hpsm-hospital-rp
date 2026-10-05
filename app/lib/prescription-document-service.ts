import { buildPrescriptionDocument, prescriptionDocumentFilename } from "./prescription-document";
import { publishDocumentImage, recordDocumentImageEvent } from "./document-media";
import { PRESCRIPTION_DOCUMENT_RENDER_VERSION, renderPrescriptionDocumentPng } from "./prescription-document-png";
import { deleteStoredPrescriptionDocument, downloadStoredPrescriptionDocument, prescriptionDocumentStoragePath, uploadStoredPrescriptionDocument } from "./prescription-document-storage";
import { runConsultationMutation } from "./consultations";
import { loadMedicalCertificateIdentity } from "./medical-certificate-storage";

export type PrescriptionDocumentState = {
  document: null | { id: string; created_at: string; completed_at: string; file_size: number; pixel_width: number; pixel_height: number; render_version: string };
  share: null | { id: string; created_at: string };
};
type Preparation = { document_id: string; status: "pending" | "completed"; source_snapshot: unknown };

export function getPrescriptionDocumentState(accessToken: string, consultationId: number) { return runConsultationMutation<PrescriptionDocumentState>(accessToken, "prescription_document_state", { p_consultation_id: consultationId }); }
export function createPrescriptionDocumentShare(accessToken: string, consultationId: number) { return runConsultationMutation<PrescriptionDocumentState>(accessToken, "create_prescription_document_share", { p_consultation_id: consultationId }); }
export function revokePrescriptionDocumentShare(accessToken: string, consultationId: number) { return runConsultationMutation<PrescriptionDocumentState>(accessToken, "revoke_prescription_document_share", { p_consultation_id: consultationId }); }
export function recordPrescriptionDocumentAccess(accessToken: string, consultationId: number, action: "PRESCRIPTION_DOCUMENT_VIEWED" | "PRESCRIPTION_DOCUMENT_DOWNLOADED") { return runConsultationMutation<void>(accessToken, "record_prescription_document_access", { p_action: action, p_consultation_id: consultationId }); }

export async function ensurePrescriptionDocument(accessToken: string, consultationId: number, uploadedBy: string | null) {
  const preparation = await runConsultationMutation<Preparation>(accessToken, "begin_prescription_document", { p_consultation_id: consultationId });
  if (preparation.status === "completed") {
    const state = await getPrescriptionDocumentState(accessToken, consultationId);
    await publishStoredPrescriptionDocument(state, consultationId, uploadedBy);
    return state;
  }
  const snapshot = buildPrescriptionDocument(preparation.source_snapshot);
  const identity = await loadMedicalCertificateIdentity(snapshot.professional.signature_image_path, snapshot.professional.id);
  const png = await renderPrescriptionDocumentPng(snapshot, identity);
  const storagePath = prescriptionDocumentStoragePath(consultationId, preparation.document_id);
  await uploadStoredPrescriptionDocument(storagePath, png.bytes);
  let state: PrescriptionDocumentState;
  try {
    state = await runConsultationMutation<PrescriptionDocumentState>(accessToken, "complete_prescription_document", {
      p_consultation_id: consultationId, p_document_id: preparation.document_id, p_file_size: png.bytes.byteLength,
      p_pixel_height: png.height, p_pixel_width: png.width, p_render_version: PRESCRIPTION_DOCUMENT_RENDER_VERSION, p_storage_path: storagePath,
    });
  } catch (error) {
    await deleteStoredPrescriptionDocument(storagePath).catch(() => undefined);
    throw error;
  }
  try {
    await publishDocumentImage({ bytes: png.bytes, documentId: consultationId, documentType: "PRESCRIPTION", filename: prescriptionDocumentFilename(consultationId), renderVersion: PRESCRIPTION_DOCUMENT_RENDER_VERSION, uploadedBy });
  } finally {
    await recordDocumentImageEvent("PRESCRIPTION", consultationId, uploadedBy, "DOCUMENT_IMAGE_RENDERED").catch(() => undefined);
  }
  return state;
}

async function publishStoredPrescriptionDocument(state: PrescriptionDocumentState, consultationId: number, uploadedBy: string | null) {
  if (!state.document) return;
  const stored = await downloadStoredPrescriptionDocument(prescriptionDocumentStoragePath(consultationId, state.document.id));
  if (!stored.ok) throw new Error("A imagem da Receita não está disponível.");
  await publishDocumentImage({ bytes: new Uint8Array(await stored.arrayBuffer()), documentId: consultationId, documentType: "PRESCRIPTION", filename: prescriptionDocumentFilename(consultationId), renderVersion: state.document.render_version, uploadedBy });
}
