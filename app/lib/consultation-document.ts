export type ConsultationSnapshot = {
  schema: "hpsm.clinical_consultation.v2" | "hpsm.clinical_consultation.v3";
  consultation_id: number;
  patient: {
    id: number;
    name: string;
    passport: string;
    birth_date: string | null;
    phone: string | null;
    emergency_contact_name: string | null;
    emergency_contact_phone: string | null;
    allergies: string | null;
    plan_code: string | null;
    health_plan: { status?: string; coverage_start?: string | null; coverage_end?: string | null } | null;
    partnerships: Array<{ id: number; name: string }>;
  };
  professional: {
    id: string;
    name: string;
    position: string | null;
    crm_code: string;
    signature_image_path: string;
  };
  appointment: { id: number; scheduled_start: string; scheduled_end: string; reason: string; notes: string | null } | null;
  started_at: string;
  completed_at: string;
  vitals: Record<string, string | number | null>;
  anamnesis: string;
  selected_diagnosis: Record<string, unknown>;
  final_diagnosis_plan: string;
  complementary_action: "NONE" | "CAST" | "HOSPITALIZATION";
  orientation_text: string;
  exam_analysis: Record<string, unknown> | null;
  exams: Array<Record<string, unknown>>;
  casts: Array<Record<string, unknown>>;
  hospitalizations: Array<Record<string, unknown>>;
  certificates: Array<Record<string, unknown>>;
  follow_ups: Array<Record<string, unknown>>;
  prescription?: null | {
    schema: "hpsm.rp_prescription.v1";
    items: Array<Record<string, unknown>>;
    rp_notice: string;
  };
};

export function buildConsultationDocument(value: unknown): ConsultationSnapshot {
  if (!isRecord(value) || !["hpsm.clinical_consultation.v2", "hpsm.clinical_consultation.v3"].includes(String(value.schema))) throw new Error("O snapshot clínico do prontuário é incompatível.");
  const snapshot = value as unknown as ConsultationSnapshot;
  if (!Number.isSafeInteger(snapshot.consultation_id) || snapshot.consultation_id < 1) throw new Error("Consulta inválida no snapshot clínico.");
  if (!snapshot.patient?.name || !snapshot.patient.passport || !snapshot.professional?.id || !snapshot.professional.name) throw new Error("O snapshot clínico está incompleto.");
  if (!/^\d{8}$/.test(snapshot.professional.crm_code ?? "") || !snapshot.professional.signature_image_path) throw new Error("A identidade profissional do prontuário está incompleta.");
  if (!snapshot.completed_at || !snapshot.anamnesis || !snapshot.final_diagnosis_plan || !snapshot.orientation_text) throw new Error("O conteúdo clínico do prontuário está incompleto.");
  for (const key of ["exams", "casts", "hospitalizations", "certificates", "follow_ups"] as const) {
    if (!Array.isArray(snapshot[key])) throw new Error("As dependências clínicas do prontuário estão incompletas.");
  }
  if (snapshot.prescription && (snapshot.prescription.schema !== "hpsm.rp_prescription.v1" || !Array.isArray(snapshot.prescription.items))) throw new Error("A prescrição do prontuário é incompatível.");
  return snapshot;
}

export function consultationDocumentFilename(consultationId: number) {
  return `HPSM_prontuario_consulta_${String(consultationId).padStart(6, "0")}.png`;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value && typeof value === "object" && !Array.isArray(value));
}
