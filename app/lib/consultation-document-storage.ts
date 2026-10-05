import {
  deleteStoredExamDocument,
  downloadStoredExamDocument,
  uploadStoredExamDocument,
} from "./exam-document-storage";

export function consultationDocumentStoragePath(consultationId: number, documentId: string) {
  return `consultations/${consultationId}/documents/${documentId}.png`;
}

export function downloadStoredConsultationDocument(path: string) {
  if (!isConsultationDocumentPath(path)) throw new Error("Caminho de prontuário inválido.");
  return downloadStoredExamDocument(path);
}

export function uploadStoredConsultationDocument(path: string, bytes: Uint8Array) {
  if (!isConsultationDocumentPath(path)) throw new Error("Caminho de prontuário inválido.");
  return uploadStoredExamDocument(path, bytes);
}

export function deleteStoredConsultationDocument(path: string) {
  if (!isConsultationDocumentPath(path)) throw new Error("Caminho de prontuário inválido.");
  return deleteStoredExamDocument(path);
}

function isConsultationDocumentPath(path: string) {
  return /^consultations\/[0-9]+\/documents\/[0-9a-f-]{36}\.png$/i.test(path);
}
