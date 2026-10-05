import { redirect } from "next/navigation";
import { PatientPortalLegacyHistory } from "../../components/patient-portal-legacy-history";
import { PatientPortalError, PatientPortalFrame, PatientPortalShell } from "../../components/patient-portal-shell";
import { getPatientPortalLegacyHistoryPage } from "../../lib/patient-portal";

export const dynamic = "force-dynamic";
export default async function PatientPortalLegacyHistoryPage() {
  let page;
  try { page = await getPatientPortalLegacyHistoryPage(); }
  catch { return <PatientPortalFrame><PatientPortalError /></PatientPortalFrame>; }
  if (!page) redirect("/portal-paciente");
  return <PatientPortalFrame><PatientPortalShell active="legacy" description="Consulte os registros preservados do HP Norte vinculados ao seu cadastro." patient={page.patient} title="Histórico HP Norte"><PatientPortalLegacyHistory initialPage={page} /></PatientPortalShell></PatientPortalFrame>;
}
