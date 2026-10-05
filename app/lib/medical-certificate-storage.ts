import {
  deleteStoredExamDocument,
  downloadStorageObject,
  downloadStoredExamDocument,
  uploadStoredExamDocument,
} from "./exam-document-storage";

export function medicalCertificateStoragePath(certificateId: number, documentId: string) {
  return `medical-certificates/${certificateId}/documents/${documentId}.png`;
}

export function downloadStoredMedicalCertificate(path: string) {
  if (!isMedicalCertificatePath(path)) throw new Error("Caminho de atestado inválido.");
  return downloadStoredExamDocument(path);
}

export function uploadStoredMedicalCertificate(path: string, bytes: Uint8Array) {
  if (!isMedicalCertificatePath(path)) throw new Error("Caminho de atestado inválido.");
  return uploadStoredExamDocument(path, bytes);
}

export function deleteStoredMedicalCertificate(path: string) {
  if (!isMedicalCertificatePath(path)) throw new Error("Caminho de atestado inválido.");
  return deleteStoredExamDocument(path);
}

export async function loadMedicalCertificateSignature(path: string, personId: string) {
  if (!/^professionals\/[0-9a-f-]{36}\/[0-9a-f-]{36}\/signature\.png$/i.test(path)) {
    throw new Error("A assinatura profissional do atestado é inválida.");
  }
  const response = await downloadStorageObject("professional-identities", path);
  if (!response.ok) throw new Error("A assinatura profissional não pôde ser carregada.");
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.byteLength < 32 || bytes.byteLength > 5 * 1024 * 1024 || bytes[0] !== 0x89 || bytes[1] !== 0x50 || bytes[2] !== 0x4e || bytes[3] !== 0x47) {
    throw new Error("A assinatura profissional armazenada é inválida.");
  }
  return { bytes, personId };
}

export async function loadMedicalCertificateIdentity(path: string, personId: string) {
  const signature = await loadMedicalCertificateSignature(path, personId);
  const rubricPath = path.replace(/\/signature[.]png$/i, "/rubric.png");
  if (rubricPath === path || !/^professionals\/[0-9a-f-]{36}\/[0-9a-f-]{36}\/rubric[.]png$/i.test(rubricPath)) {
    throw new Error("A rubrica profissional do documento é inválida.");
  }
  const response = await downloadStorageObject("professional-identities", rubricPath);
  if (!response.ok) throw new Error("A rubrica profissional não pôde ser carregada.");
  const rubricBytes = new Uint8Array(await response.arrayBuffer());
  if (rubricBytes.byteLength < 32 || rubricBytes.byteLength > 5 * 1024 * 1024 || rubricBytes[0] !== 0x89 || rubricBytes[1] !== 0x50 || rubricBytes[2] !== 0x4e || rubricBytes[3] !== 0x47) {
    throw new Error("A rubrica profissional armazenada é inválida.");
  }
  return { personId, rubricBytes, signatureBytes: signature.bytes };
}

function isMedicalCertificatePath(path: string) {
  return /^medical-certificates\/[0-9]+\/documents\/[0-9a-f-]{36}\.png$/i.test(path);
}
