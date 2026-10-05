import { formatMedicalCertificateDateTime, type FinalMedicalCertificateDocument } from "./medical-certificate-document";
import {
  institutionalCardBlocks,
  institutionalFactsBlock,
  institutionalTextBlocks,
  renderOfficialInstitutionalDocument,
  type InstitutionalIdentityAssets,
} from "./institutional-document-png";
import { formatPatientPassport } from "./passport";

export const MEDICAL_CERTIFICATE_PNG_RENDER_VERSION = "medical-certificate-png-v7";

export function renderMedicalCertificatePng(document: FinalMedicalCertificateDocument, identity: InstitutionalIdentityAssets) {
  const patient = document.patient as FinalMedicalCertificateDocument["patient"] & { birth_date?: string | null; sex?: string | null };
  const blocks = [
    ...institutionalTextBlocks("Atestado", document.text),
    institutionalFactsBlock("Período de afastamento", [
      { label: "Período", value: `${document.leaveDays} ${document.leaveDays === 1 ? "dia" : "dias"}` },
      { label: "Origem", value: document.originType === "consultation" ? "Consulta clínica" : "Atendimento" },
      { label: "Emissão", value: formatMedicalCertificateDateTime(document.issuedAt) },
    ]),
    ...(document.diagnosis ? institutionalCardBlocks("Diagnóstico e classificação", [
      document.diagnosis.text,
      `CID-10 ${document.diagnosis.cid_code} · ${document.diagnosis.cid_description}`,
    ]) : []),
  ];
  return renderOfficialInstitutionalDocument({
    attendanceDate: formatMedicalCertificateDateTime(document.attendance.created_at),
    attendanceLabel: `${document.originType === "consultation" ? "Consulta" : "Atendimento"} #${document.attendance.id}`,
    documentNumber: document.certificateCode,
    documentTitle: "Atestado Médico",
    issuedAt: formatMedicalCertificateDateTime(document.issuedAt),
    patient: {
      birthDate: patient.birth_date ? formatDate(patient.birth_date) : null,
      name: document.patient.name,
      passport: formatPatientPassport(document.patient.passport),
      sex: patient.sex ?? null,
    },
    professional: {
      crmCode: document.professional.crm_code,
      id: document.professional.id,
      name: document.professional.name,
      role: document.professional.position ?? "Cargo não informado",
    },
    recordNumber: formatPatientPassport(document.patient.passport),
    subtitle: "Atestado médico",
  }, blocks, identity, "atestado");
}

function formatDate(value: string) {
  const parsed = new Date(`${value}T12:00:00`);
  return Number.isNaN(parsed.getTime()) ? "Não informado" : new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeZone: "America/Sao_Paulo" }).format(parsed);
}
