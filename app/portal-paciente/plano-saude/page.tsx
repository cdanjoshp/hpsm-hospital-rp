import { redirect } from "next/navigation";
import { PatientPortalHealthPlan } from "../../components/patient-portal-health-plan";
import { PatientPortalError, PatientPortalFrame, PatientPortalShell } from "../../components/patient-portal-shell";
import { getPatientPortalHealthPlanPage, type PatientPortalHealthPlanPage } from "../../lib/patient-portal";

export const dynamic = "force-dynamic";

export default async function PatientPortalHealthPlanPage() {
  let plan: PatientPortalHealthPlanPage | null = null;
  try {
    plan = await getPatientPortalHealthPlanPage();
  } catch {
    return <PatientPortalFrame><PatientPortalError /></PatientPortalFrame>;
  }
  if (!plan) redirect("/portal-paciente");

  return (
    <PatientPortalFrame>
      <PatientPortalShell
        active="health-plan"
        description="Consulte a situação atual e o histórico do seu Plano de Saúde HPSM."
        patient={plan.patient}
        title="Plano de Saúde"
      >
        <PatientPortalHealthPlan initialPage={plan} />
      </PatientPortalShell>
    </PatientPortalFrame>
  );
}
