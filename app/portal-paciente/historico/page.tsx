import { redirect } from "next/navigation";
import { PatientPortalHistoryList } from "../../components/patient-portal-history";
import { PatientPortalError, PatientPortalFrame, PatientPortalShell } from "../../components/patient-portal-shell";
import { getPatientPortalHistoryPage, type PatientPortalHistoryPage as PatientPortalHistoryPageData } from "../../lib/patient-portal";

export const dynamic = "force-dynamic";

export default async function PatientPortalHistoryPage() {
  let history: PatientPortalHistoryPageData | null = null;
  try {
    history = await getPatientPortalHistoryPage();
  } catch {
    return <PatientPortalFrame><PatientPortalError /></PatientPortalFrame>;
  }
  if (!history) redirect("/portal-paciente");

  return (
    <PatientPortalFrame>
      <PatientPortalShell
        active="history"
        description="Acompanhe os principais acontecimentos registrados durante seus cuidados."
        patient={history.patient}
        title="Histórico"
      >
        <PatientPortalHistoryList initialPage={history} />
      </PatientPortalShell>
    </PatientPortalFrame>
  );
}
