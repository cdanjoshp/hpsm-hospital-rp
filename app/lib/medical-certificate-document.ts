import type { MedicalCertificateSnapshot } from "./medical-certificates";

export type FinalMedicalCertificateDocument = {
  attendance: MedicalCertificateSnapshot["attendance"];
  certificateCode: string;
  certificateId: number;
  diagnosis: MedicalCertificateSnapshot["diagnosis"] | null;
  filename: string;
  issuedAt: string;
  leaveDays: number;
  originType: "attendance" | "consultation";
  patient: MedicalCertificateSnapshot["patient"];
  professional: MedicalCertificateSnapshot["professional"];
  text: string;
};

export function buildFinalMedicalCertificateDocument(snapshot: MedicalCertificateSnapshot): FinalMedicalCertificateDocument {
  if (
    (snapshot.schema !== "hpsm.medical_certificate_snapshot.v1" && snapshot.schema !== "hpsm.medical_certificate_snapshot.v2")
    || !Number.isSafeInteger(snapshot.certificate_id)
    || snapshot.certificate_id <= 0
    || !Number.isInteger(snapshot.leave_days)
    || snapshot.leave_days <= 0
    || !snapshot.text?.trim()
    || !snapshot.patient?.name
    || !snapshot.patient?.passport
    || !snapshot.professional?.name
    || !/^\d{8}$/.test(snapshot.professional.crm_code)
    || !snapshot.professional.signature_image_path
    || (snapshot.schema === "hpsm.medical_certificate_snapshot.v2" && (!snapshot.diagnosis?.text || !snapshot.diagnosis.cid_code || !snapshot.diagnosis.cid_description))
  ) throw new Error("O snapshot final do atestado está incompleto.");
  const certificateCode = formatMedicalCertificateCode(snapshot.certificate_id);
  return {
    attendance: snapshot.attendance,
    certificateCode,
    certificateId: snapshot.certificate_id,
    diagnosis: snapshot.diagnosis ?? null,
    filename: `HPSM_${certificateCode}_Atestado-Medico.png`,
    issuedAt: snapshot.issued_at,
    leaveDays: snapshot.leave_days,
    originType: snapshot.origin_type ?? "attendance",
    patient: snapshot.patient,
    professional: snapshot.professional,
    text: snapshot.text.trim(),
  };
}

export function formatMedicalCertificateCode(certificateId: number) {
  return `AT-${String(certificateId).padStart(6, "0")}`;
}

export function formatMedicalCertificateDateTime(value: string) {
  return new Intl.DateTimeFormat("pt-BR", {
    day: "2-digit",
    hour: "2-digit",
    hour12: false,
    minute: "2-digit",
    month: "2-digit",
    timeZone: "America/Sao_Paulo",
    year: "numeric",
  }).format(new Date(value));
}
