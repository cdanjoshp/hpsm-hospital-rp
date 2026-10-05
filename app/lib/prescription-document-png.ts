import type { PrescriptionSnapshot } from "./prescription-document";
import {
  institutionalCardBlocks,
  renderOfficialInstitutionalDocument,
  type InstitutionalDocumentBlock,
  type InstitutionalIdentityAssets,
} from "./institutional-document-png";
import { formatPatientPassport } from "./passport";

export const PRESCRIPTION_DOCUMENT_RENDER_VERSION = "prescription-document-png-v6";

export function renderPrescriptionDocumentPng(snapshot: PrescriptionSnapshot, identity: InstitutionalIdentityAssets) {
  const blocks: InstitutionalDocumentBlock[] = snapshot.items.flatMap((item, index) => institutionalCardBlocks(
    `${index + 1}. ${item.rp_name_snapshot} · ${item.final_quantity_snapshot} item(ns)`,
    [
      `Referência: ${item.reference_name_snapshot}`,
      `Posologia: ${item.dose_snapshot} · ${item.frequency_snapshot} · ${item.duration_snapshot} · ${item.route_snapshot}`,
      `Orientações: ${item.instructions_snapshot}`,
      `Indicação RP: ${item.reason_snapshot}`,
      ...(item.justification_snapshot ? [`Justificativa clínica: ${item.justification_snapshot}`] : []),
      ...(item.quantity_override_snapshot ? [`Quantidade ajustada: ${item.calculated_quantity_snapshot} → ${item.final_quantity_snapshot} · ${item.override_reason ?? "Motivo não informado"}`] : []),
    ],
  ));
  blocks.push(...institutionalCardBlocks("Orientação da prescrição", [snapshot.rp_notice], { tone: "warning" }));
  return renderOfficialInstitutionalDocument({
    attendanceDate: formatDateTime(snapshot.finalized_at),
    attendanceLabel: `Consulta #${snapshot.consultation_id}`,
    documentNumber: prescriptionCode(snapshot.consultation_id),
    documentTitle: "Receita",
    issuedAt: formatDateTime(snapshot.finalized_at),
    patient: { name: snapshot.patient.name, passport: formatPatientPassport(snapshot.patient.passport) },
    professional: {
      crmCode: snapshot.professional.crm_code,
      id: snapshot.professional.id,
      name: snapshot.professional.name,
      role: snapshot.professional.role,
    },
    recordNumber: formatPatientPassport(snapshot.patient.passport),
    subtitle: "Prescrição e orientações",
  }, blocks, identity, "receita");
}

function formatDateTime(input: string) {
  const date = new Date(input);
  return Number.isNaN(date.getTime()) ? "Não informado" : new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" }).format(date);
}
function prescriptionCode(id: number) { return `REC-${String(id).padStart(6, "0")}`; }
