import { redirect } from "next/navigation";
import { PatientPortalProfileForm } from "../../components/patient-portal-profile";
import { PatientPortalError, PatientPortalFrame, PatientPortalShell } from "../../components/patient-portal-shell";
import { getPatientPortalProfile } from "../../lib/patient-portal";

export const dynamic = "force-dynamic";

export default async function PatientPortalProfilePage() {
  let patient = null;
  let failed = false;
  try {
    patient = await getPatientPortalProfile();
  } catch {
    failed = true;
  }
  if (!patient && !failed) redirect("/?access=patient");

  return (
    <PatientPortalFrame>
      {patient ? (
        <PatientPortalShell
          active="profile"
          description="Mantenha seus dados de contato e saúde atualizados."
          patient={patient}
          title="Meus Dados"
        >
          <PatientPortalProfileForm initialPatient={patient} />
        </PatientPortalShell>
      ) : <PatientPortalError />}
    </PatientPortalFrame>
  );
}
