import { notFound, redirect } from "next/navigation";
import { PatientPortalConsultationDetailView } from "../../../../components/patient-portal-consultation-detail";
import { PatientPortalError, PatientPortalFrame, PatientPortalShell } from "../../../../components/patient-portal-shell";
import { getPatientPortalConsultationDetail, getPatientPortalPrescriptionSnapshot, type PatientPortalConsultationDetail } from "../../../../lib/patient-portal";

export const dynamic = "force-dynamic";

export default async function PatientPortalConsultationDetailPage({ params }: { params: Promise<{ kind: string; id: string }> }) {
  const { kind, id } = await params;
  if ((kind !== "appointment" && kind !== "consultation") || !/^[1-9]\d*$/.test(id) || !Number.isSafeInteger(Number(id))) notFound();
  let detail: PatientPortalConsultationDetail | null | "not_found";
  try { detail = await getPatientPortalConsultationDetail(kind, Number(id)); }
  catch { return <PatientPortalFrame><PatientPortalError /></PatientPortalFrame>; }
  if (!detail) redirect("/portal-paciente");
  if (detail === "not_found") notFound();
  let prescriptionReady = false;
  if (detail.consultation.consultationId && detail.snapshot?.prescription?.items.length) {
    try { prescriptionReady = Boolean(await getPatientPortalPrescriptionSnapshot(detail.consultation.consultationId)); }
    catch { /* O prontuário continua disponível se a Receita estiver temporariamente indisponível. */ }
  }
  return <PatientPortalFrame>
    <PatientPortalShell active="consultations" description="Veja o acompanhamento da consulta e as orientações registradas para você." patient={detail.patient} title="Detalhes da consulta">
      <PatientPortalConsultationDetailView data={detail} prescriptionReady={prescriptionReady} />
    </PatientPortalShell>
  </PatientPortalFrame>;
}
