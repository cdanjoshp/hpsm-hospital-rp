import { redirect } from "next/navigation";
import { PatientPortalMedicalCertificates } from "../../components/patient-portal-medical-certificates";
import { PatientPortalError, PatientPortalFrame, PatientPortalShell } from "../../components/patient-portal-shell";
import { getPatientPortalMedicalCertificatePage, type PatientPortalMedicalCertificatePage } from "../../lib/patient-portal";

export const dynamic = "force-dynamic";

export default async function PatientPortalMedicalCertificatesPage() {
  let certificates: PatientPortalMedicalCertificatePage | null = null;
  try {
    certificates = await getPatientPortalMedicalCertificatePage();
  } catch {
    return <PatientPortalFrame><PatientPortalError /></PatientPortalFrame>;
  }
  if (!certificates) redirect("/portal-paciente");
  return <PatientPortalFrame><PatientPortalShell active="certificates" description="Consulte e baixe seus atestados médicos finalizados." patient={certificates.patient} title="Atestados Médicos"><PatientPortalMedicalCertificates initialPage={certificates} /></PatientPortalShell></PatientPortalFrame>;
}
