import { buildConsultationDocument } from "./consultation-document";
import { consultationDocumentFilename } from "./consultation-document";
import { CONSULTATION_DOCUMENT_RENDER_VERSION, renderConsultationDocumentPng } from "./consultation-document-png";
import { publishDocumentImage, recordDocumentImageEvent } from "./document-media";
import {
  consultationDocumentStoragePath,
  deleteStoredConsultationDocument,
  downloadStoredConsultationDocument,
  uploadStoredConsultationDocument,
} from "./consultation-document-storage";
import { runConsultationMutation } from "./consultations";
import { loadMedicalCertificateIdentity } from "./medical-certificate-storage";

export type ConsultationDocumentState = {
  document: null | {
    id: string;
    created_at: string;
    completed_at: string;
    file_size: number;
    pixel_width: number;
    pixel_height: number;
    render_version: string;
  };
  share: null | { id: string; created_at: string };
};

type ConsultationDocumentPreparation = {
  document_id: string;
  status: "pending" | "completed";
  source_snapshot: unknown;
};

export function getConsultationDocumentState(accessToken: string, consultationId: number) {
  return runConsultationMutation<ConsultationDocumentState>(accessToken, "consultation_document_state", { p_consultation_id: consultationId });
}

export function createConsultationDocumentShare(accessToken: string, consultationId: number) {
  return runConsultationMutation<ConsultationDocumentState>(accessToken, "create_consultation_document_share", { p_consultation_id: consultationId });
}

export function revokeConsultationDocumentShare(accessToken: string, consultationId: number) {
  return runConsultationMutation<ConsultationDocumentState>(accessToken, "revoke_consultation_document_share", { p_consultation_id: consultationId });
}

export async function ensureConsultationDocument(accessToken: string, consultationId: number, uploadedBy: string | null) {
  const preparation = await runConsultationMutation<ConsultationDocumentPreparation>(accessToken, "begin_consultation_document", { p_consultation_id: consultationId });
  if (preparation.status === "completed") {
    const state = await getConsultationDocumentState(accessToken, consultationId);
    await publishStoredConsultationDocument(state, consultationId, uploadedBy);
    return state;
  }

  const snapshot = buildConsultationDocument(preparation.source_snapshot);
  const identity = await loadMedicalCertificateIdentity(snapshot.professional.signature_image_path, snapshot.professional.id);
  const png = await renderConsultationDocumentPng(snapshot, identity);
  const storagePath = consultationDocumentStoragePath(consultationId, preparation.document_id);
  await uploadStoredConsultationDocument(storagePath, png.bytes);
  let state: ConsultationDocumentState;
  try {
    state = await runConsultationMutation<ConsultationDocumentState>(accessToken, "complete_consultation_document", {
      p_consultation_id: consultationId,
      p_document_id: preparation.document_id,
      p_file_size: png.bytes.byteLength,
      p_pixel_height: png.height,
      p_pixel_width: png.width,
      p_render_version: CONSULTATION_DOCUMENT_RENDER_VERSION,
      p_storage_path: storagePath,
    });
  } catch (error) {
    await deleteStoredConsultationDocument(storagePath).catch(() => undefined);
    throw error;
  }
  try {
    await publishDocumentImage({ bytes: png.bytes, documentId: consultationId, documentType: "CONSULTATION_RECORD", filename: consultationDocumentFilename(consultationId), renderVersion: CONSULTATION_DOCUMENT_RENDER_VERSION, uploadedBy });
  } finally {
    await recordDocumentImageEvent("CONSULTATION_RECORD", consultationId, uploadedBy, "DOCUMENT_IMAGE_RENDERED").catch(() => undefined);
  }
  return state;
}

async function publishStoredConsultationDocument(state: ConsultationDocumentState, consultationId: number, uploadedBy: string | null) {
  if (!state.document) return;
  const stored = await downloadStoredConsultationDocument(consultationDocumentStoragePath(consultationId, state.document.id));
  if (!stored.ok) throw new Error("A imagem do prontuário não está disponível.");
  await publishDocumentImage({ bytes: new Uint8Array(await stored.arrayBuffer()), documentId: consultationId, documentType: "CONSULTATION_RECORD", filename: consultationDocumentFilename(consultationId), renderVersion: state.document.render_version, uploadedBy });
}
