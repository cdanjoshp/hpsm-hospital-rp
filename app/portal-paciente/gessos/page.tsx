import { redirect } from "next/navigation";
import { PatientPortalCasts } from "../../components/patient-portal-casts";
import { PatientPortalError, PatientPortalFrame, PatientPortalShell } from "../../components/patient-portal-shell";
import { getPatientPortalCastPage, type PatientPortalCastPage } from "../../lib/patient-portal";

export const dynamic = "force-dynamic";

export default async function PatientPortalCastsPage() {
  let casts: PatientPortalCastPage | null = null;
  try {
    casts = await getPatientPortalCastPage();
  } catch {
    return <PatientPortalFrame><PatientPortalError /></PatientPortalFrame>;
  }
  if (!casts) redirect("/portal-paciente");

  return (
    <PatientPortalFrame>
      <PatientPortalShell
        active="casts"
        description="Acompanhe os gessos em uso e consulte registros anteriores."
        patient={casts.patient}
        title="Gessos"
      >
        <PatientPortalCasts initialPage={casts} />
      </PatientPortalShell>
    </PatientPortalFrame>
  );
}
