import { redirect } from "next/navigation";
import { PatientPortalHospitalizations } from "../../components/patient-portal-hospitalizations";
import { PatientPortalError, PatientPortalFrame, PatientPortalShell } from "../../components/patient-portal-shell";
import { getPatientPortalHospitalizationPage } from "../../lib/patient-portal";

export const dynamic = "force-dynamic";
export default async function PatientPortalHospitalizationsPage() {
  let page;
  try { page = await getPatientPortalHospitalizationPage(); }
  catch { return <PatientPortalFrame><PatientPortalError /></PatientPortalFrame>; }
  if (!page) redirect("/portal-paciente");
  return <PatientPortalFrame><PatientPortalShell active="hospitalizations" description="Acompanhe suas internações no HPSM e as altas registradas." patient={page.patient} title="Internações"><PatientPortalHospitalizations initialPage={page} /></PatientPortalShell></PatientPortalFrame>;
}
