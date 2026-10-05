import { redirect } from "next/navigation";
import { AppFrame } from "../components/app-frame";
import { ExamCenter } from "../components/exam-center";
import { getClinicalExamPage, getClinicalExamReferenceData } from "../lib/exams";
import { getExamCardContexts } from "../lib/exam-card-context";
import { getQuickActionPatient } from "../lib/patient-center";
import { getSessionBootstrap } from "../lib/session";

export const dynamic = "force-dynamic";

export default async function ExamsPage({ searchParams }: { searchParams: Promise<{ novo?: string; paciente?: string }> }) {
  const context = await getSessionBootstrap();
  if (!context) redirect("/");
  if (context.profile.must_change_password) redirect("/primeiro-acesso");

  const permissions = context.permissionCodes;
  if (!permissions.includes("exams.view")) redirect("/painel");
  const [initialData, referenceData] = await Promise.all([
    getClinicalExamPage(context.accessToken, { page: 1, pageSize: 20 }),
    getClinicalExamReferenceData(context.accessToken),
  ]);
  const initialContexts = await getExamCardContexts(initialData.items, new Set(permissions));
  const params = await searchParams;
  const canCreate = permissions.includes("exams.create") && permissions.includes("patients.view");
  const initialPatient = params.novo === "1" && canCreate ? await getQuickActionPatient(context.accessToken, params.paciente) : null;

  return (
    <AppFrame
      active="exams"
      profile={context.profile}
      title="Central de Exames"
      description="Solicite, execute, revise e consulte exames clínicos com rastreabilidade completa."
    >
      <ExamCenter
        key={initialPatient?.id ?? "regular"}
        canCatalogManage={permissions.includes("exams.catalog.manage")}
        canCreate={canCreate}
        canDeleteAny={permissions.includes("exams.delete")}
        canDeleteCompleted={permissions.includes("exams.delete") && context.positionLevel !== null && context.positionLevel >= 12 && context.positionLevel <= 14}
        canPerform={permissions.includes("exams.perform")}
        canReview={permissions.includes("exams.review") && context.positionLevel !== null && context.positionLevel >= 11 && context.positionLevel <= 14}
        currentUserId={context.profile.user_id}
        initialData={initialData}
        initialContexts={initialContexts}
        permissionCodes={permissions}
        initialReferenceData={referenceData}
        initialPatient={initialPatient}
      />
    </AppFrame>
  );
}
