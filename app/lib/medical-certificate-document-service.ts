import { buildFinalMedicalCertificateDocument } from "./medical-certificate-document";
import { publishDocumentImage, recordDocumentImageEvent } from "./document-media";
import { MEDICAL_CERTIFICATE_PNG_RENDER_VERSION, renderMedicalCertificatePng } from "./medical-certificate-png";
import {
  getMedicalCertificateDocumentState,
  registerMedicalCertificateDocument,
  type MedicalCertificateDocumentState,
} from "./medical-certificates";
import {
  deleteStoredMedicalCertificate,
  downloadStoredMedicalCertificate,
  loadMedicalCertificateIdentity,
  medicalCertificateStoragePath,
  uploadStoredMedicalCertificate,
} from "./medical-certificate-storage";

export async function ensureMedicalCertificateDocument(accessToken: string, certificateId: number, uploadedBy: string | null): Promise<MedicalCertificateDocumentState> {
  const initial = await getMedicalCertificateDocumentState(accessToken, certificateId);
  if (initial.document?.render_version === MEDICAL_CERTIFICATE_PNG_RENDER_VERSION) {
    await publishStoredCertificate(initial, certificateId, uploadedBy);
    return initial;
  }
  if (initial.status !== "finalized" || !initial.snapshot) {
    throw new Error("O resultado está disponível somente para atestados finalizados.");
  }
  const document = buildFinalMedicalCertificateDocument(initial.snapshot);
  const identity = await loadMedicalCertificateIdentity(document.professional.signature_image_path, document.professional.id);
  const png = await renderMedicalCertificatePng(document, identity);
  const storagePath = medicalCertificateStoragePath(certificateId, crypto.randomUUID());
  await uploadStoredMedicalCertificate(storagePath, png.bytes);
  let state: MedicalCertificateDocumentState;
  try {
    state = await registerMedicalCertificateDocument(accessToken, {
      certificateId,
      fileSize: png.bytes.byteLength,
      height: png.height,
      renderVersion: MEDICAL_CERTIFICATE_PNG_RENDER_VERSION,
      storagePath,
      width: png.width,
    });
    if (state.document?.path !== storagePath) await deleteStoredMedicalCertificate(storagePath).catch(() => undefined);
    if (initial.document?.path && state.document?.path === storagePath && initial.document.path !== storagePath) {
      await deleteStoredMedicalCertificate(initial.document.path).catch(() => undefined);
    }
  } catch (error) {
    await deleteStoredMedicalCertificate(storagePath).catch(() => undefined);
    throw error;
  }
  try {
    await publishDocumentImage({
      bytes: state.document?.path === storagePath ? png.bytes : await storedCertificateBytes(state),
      documentId: certificateId,
      documentType: "MEDICAL_CERTIFICATE",
      filename: document.filename,
      renderVersion: MEDICAL_CERTIFICATE_PNG_RENDER_VERSION,
      uploadedBy,
    });
  } finally {
    await recordDocumentImageEvent("MEDICAL_CERTIFICATE", certificateId, uploadedBy, "DOCUMENT_IMAGE_RENDERED").catch(() => undefined);
  }
  return state;
}

async function publishStoredCertificate(state: MedicalCertificateDocumentState, certificateId: number, uploadedBy: string | null) {
  if (!state.document || !state.snapshot) return;
  const stored = await downloadStoredMedicalCertificate(state.document.path);
  if (!stored.ok) throw new Error("A imagem do atestado não está disponível.");
  const document = buildFinalMedicalCertificateDocument(state.snapshot);
  await publishDocumentImage({
    bytes: new Uint8Array(await stored.arrayBuffer()),
    documentId: certificateId,
    documentType: "MEDICAL_CERTIFICATE",
    filename: document.filename,
    renderVersion: state.document.render_version,
    uploadedBy,
  });
}

async function storedCertificateBytes(state: MedicalCertificateDocumentState) {
  if (!state.document) throw new Error("A imagem do atestado não está disponível.");
  const stored = await downloadStoredMedicalCertificate(state.document.path);
  if (!stored.ok) throw new Error("A imagem do atestado não está disponível.");
  return new Uint8Array(await stored.arrayBuffer());
}
