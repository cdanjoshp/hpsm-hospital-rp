import { notFound, redirect } from "next/navigation";
import { PatientPortalAttendanceDetailView } from "../../../components/patient-portal-attendances";
import { PatientPortalError, PatientPortalFrame, PatientPortalShell } from "../../../components/patient-portal-shell";
import { getPatientPortalAttendanceDetail, type PatientPortalAttendanceDetail } from "../../../lib/patient-portal";

export const dynamic = "force-dynamic";

export default async function PatientPortalAttendanceDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!/^\d+$/.test(id)) notFound();
  const attendanceId = Number(id);
  if (!Number.isSafeInteger(attendanceId) || attendanceId < 1) notFound();

  let detail: PatientPortalAttendanceDetail | null | "not_found";
  try {
    detail = await getPatientPortalAttendanceDetail(attendanceId);
  } catch {
    return <PatientPortalFrame><PatientPortalError /></PatientPortalFrame>;
  }
  if (!detail) redirect("/portal-paciente");
  if (detail === "not_found") notFound();

  return (
    <PatientPortalFrame>
      <PatientPortalShell
        active="attendances"
        description="Confira os itens e os valores registrados no momento deste atendimento."
        patient={detail.patient}
        title="Detalhes do atendimento"
      >
        <PatientPortalAttendanceDetailView data={detail} />
      </PatientPortalShell>
    </PatientPortalFrame>
  );
}
