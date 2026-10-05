import { deleteStoredExamDocument, downloadStoredExamDocument, uploadStoredExamDocument } from "./exam-document-storage";

export function prescriptionDocumentStoragePath(consultationId: number, documentId: string) {
  return `prescriptions/${consultationId}/documents/${documentId}.png`;
}
export function downloadStoredPrescriptionDocument(path: string) { assertPath(path); return downloadStoredExamDocument(path); }
export function uploadStoredPrescriptionDocument(path: string, bytes: Uint8Array) { assertPath(path); return uploadStoredExamDocument(path, bytes); }
export function deleteStoredPrescriptionDocument(path: string) { assertPath(path); return deleteStoredExamDocument(path); }
function assertPath(path: string) { if (!/^prescriptions\/[0-9]+\/documents\/[0-9a-f-]{36}\.png$/i.test(path)) throw new Error("Caminho de Receita inválido."); }
