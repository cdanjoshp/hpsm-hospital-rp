import { redirect } from "next/navigation";
import { PatientPortalExamList } from "../../components/patient-portal-exams";
import { PatientPortalError, PatientPortalFrame, PatientPortalShell } from "../../components/patient-portal-shell";
import { getPatientPortalExamPage, type PatientPortalExamPage } from "../../lib/patient-portal";

export const dynamic = "force-dynamic";

export default async function PatientPortalExamsPage() {
  let exams: PatientPortalExamPage | null = null;
  try {
    exams = await getPatientPortalExamPage();
  } catch {
    return <PatientPortalFrame><PatientPortalError /></PatientPortalFrame>;
  }
  if (!exams) redirect("/portal-paciente");

  return (
    <PatientPortalFrame>
      <PatientPortalShell
        active="exams"
        description="Acompanhe seus exames e consulte os resultados finais aprovados."
        patient={exams.patient}
        title="Exames"
      >
        <PatientPortalExamList initialPage={exams} />
      </PatientPortalShell>
    </PatientPortalFrame>
  );
}
