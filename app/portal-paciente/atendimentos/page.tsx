import { redirect } from "next/navigation";
import { PatientPortalAttendanceList } from "../../components/patient-portal-attendances";
import { PatientPortalError, PatientPortalFrame, PatientPortalShell } from "../../components/patient-portal-shell";
import { getPatientPortalAttendancePage, type PatientPortalAttendancePage } from "../../lib/patient-portal";

export const dynamic = "force-dynamic";

export default async function PatientPortalAttendancesPage() {
  let attendances: PatientPortalAttendancePage | null = null;
  try {
    attendances = await getPatientPortalAttendancePage();
  } catch {
    return <PatientPortalFrame><PatientPortalError /></PatientPortalFrame>;
  }
  if (!attendances) redirect("/portal-paciente");

  return (
    <PatientPortalFrame>
      <PatientPortalShell
        active="attendances"
        description="Consulte os valores, benefícios e itens registrados em seus atendimentos."
        patient={attendances.patient}
        title="Atendimentos"
      >
        <PatientPortalAttendanceList initialPage={attendances} />
      </PatientPortalShell>
    </PatientPortalFrame>
  );
}
