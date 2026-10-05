import { notFound, redirect } from "next/navigation";
import { PatientPortalExamDetailView } from "../../../components/patient-portal-exam-detail";
import { PatientPortalError, PatientPortalFrame, PatientPortalShell } from "../../../components/patient-portal-shell";
import { getPatientPortalExamDetail, type PatientPortalExamDetail } from "../../../lib/patient-portal";

export const dynamic = "force-dynamic";

export default async function PatientPortalExamDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!/^\d+$/.test(id)) notFound();
  const examId = Number(id);
  if (!Number.isSafeInteger(examId) || examId < 1) notFound();

  let detail: PatientPortalExamDetail | null | "not_found";
  try {
    detail = await getPatientPortalExamDetail(examId);
  } catch {
    return <PatientPortalFrame><PatientPortalError /></PatientPortalFrame>;
  }
  if (!detail) redirect("/portal-paciente");
  if (detail === "not_found") notFound();

  return (
    <PatientPortalFrame>
      <PatientPortalShell
        active="exams"
        description="Consulte o andamento e, quando concluído, o resultado final aprovado."
        patient={detail.patient}
        title="Detalhes do exame"
      >
        <PatientPortalExamDetailView data={detail} />
      </PatientPortalShell>
    </PatientPortalFrame>
  );
}
