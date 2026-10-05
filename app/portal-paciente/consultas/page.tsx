import { redirect } from "next/navigation";
import { PatientPortalConsultationList } from "../../components/patient-portal-consultations";
import { PatientPortalError, PatientPortalFrame, PatientPortalShell } from "../../components/patient-portal-shell";
import { getPatientPortalConsultationPage, type PatientPortalConsultationPage } from "../../lib/patient-portal";

export const dynamic = "force-dynamic";

export default async function PatientPortalConsultationsPage() {
  let page: PatientPortalConsultationPage | null;
  try { page = await getPatientPortalConsultationPage(); }
  catch { return <PatientPortalFrame><PatientPortalError /></PatientPortalFrame>; }
  if (!page) redirect("/portal-paciente");
  return <PatientPortalFrame>
    <PatientPortalShell active="consultations" description="Acompanhe seus agendamentos e consulte as informações das consultas concluídas." patient={page.patient} title="Consultas">
      <PatientPortalConsultationList initialPage={page} />
    </PatientPortalShell>
  </PatientPortalFrame>;
}
