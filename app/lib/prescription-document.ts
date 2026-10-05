export type PrescriptionSnapshot = {
  schema: "hpsm.rp_prescription.v1";
  prescription_id: string;
  consultation_id: number;
  patient: { name: string; passport: string };
  professional: { id: string; name: string; crm_code: string; role: string; signature_image_path: string };
  created_at: string;
  finalized_at: string;
  items: Array<{
    id: string;
    medication_id: string;
    rp_name_snapshot: string;
    reference_name_snapshot: string;
    dose_snapshot: string;
    frequency_snapshot: string;
    duration_snapshot: string;
    route_snapshot: string;
    reason_snapshot: string;
    instructions_snapshot: string;
    justification_snapshot: string | null;
    calculated_quantity_snapshot: number;
    final_quantity_snapshot: number;
    quantity_override_snapshot: boolean;
    override_reason: string | null;
  }>;
  rp_notice: string;
};

export function buildPrescriptionDocument(value: unknown): PrescriptionSnapshot {
  if (!isRecord(value) || value.schema !== "hpsm.rp_prescription.v1") throw new Error("O snapshot da Receita é incompatível.");
  const snapshot = value as unknown as PrescriptionSnapshot;
  if (!Number.isSafeInteger(snapshot.consultation_id) || snapshot.consultation_id < 1 || !snapshot.prescription_id) throw new Error("A Receita possui identificação inválida.");
  if (!snapshot.patient?.name || !snapshot.patient.passport || !snapshot.professional?.id || !snapshot.professional.name) throw new Error("A Receita possui identificação incompleta.");
  if (!/^\d{8}$/.test(snapshot.professional.crm_code ?? "") || !snapshot.professional.signature_image_path) throw new Error("A identidade profissional da Receita está incompleta.");
  if (!snapshot.finalized_at || !Array.isArray(snapshot.items) || !snapshot.items.length) throw new Error("A Receita não possui itens finalizados.");
  if (!snapshot.rp_notice?.includes("exclusivamente ao uso em RP")) throw new Error("O aviso obrigatório da Receita está ausente.");
  for (const item of snapshot.items) {
    if (!item.id || !item.medication_id || !item.rp_name_snapshot || !item.dose_snapshot || !item.frequency_snapshot || !item.duration_snapshot || !item.route_snapshot || !item.instructions_snapshot || !Number.isSafeInteger(item.final_quantity_snapshot) || item.final_quantity_snapshot < 1) throw new Error("Um item da Receita está incompleto.");
  }
  return snapshot;
}

export function prescriptionDocumentFilename(consultationId: number) {
  return `HPSM_receita_consulta_${String(consultationId).padStart(6, "0")}.png`;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value && typeof value === "object" && !Array.isArray(value));
}
