import { redirect } from "next/navigation";
import { AppFrame } from "../../components/app-frame";
import { ConsultationWorkspace } from "../../components/consultation-workspace";
import { getConsultationDetail, getConsultationReferences } from "../../lib/consultations";
import { getClinicalExamReferenceData } from "../../lib/exams";
import { getSessionBootstrap } from "../../lib/session";

export const dynamic = "force-dynamic";

export default async function ConsultationPage({ params }: { params: Promise<{ id: string }> }) {
  const context = await getSessionBootstrap();
  if (!context) redirect("/");
  if (context.profile.must_change_password) redirect("/primeiro-acesso");
  if (!context.permissionCodes.includes("consultations.view")) redirect("/painel");
  const consultationId = Number((await params).id);
  if (!Number.isSafeInteger(consultationId) || consultationId < 1) redirect("/consultas");
  const canCreateExam = context.permissionCodes.includes("exams.create");
  const [consultation, references, examReferences] = await Promise.all([
    getConsultationDetail(context.accessToken, consultationId),
    getConsultationReferences(context.accessToken),
    canCreateExam ? getClinicalExamReferenceData(context.accessToken) : Promise.resolve(null),
  ]);
  return <AppFrame active="consultations" profile={context.profile} title="Consulta clínica" description="Evolução clínica contínua, auditável e independente do fluxo financeiro.">
    <ConsultationWorkspace
      canCreateCast={context.permissionCodes.includes("casts.create")}
      canCreateCertificate={context.permissionCodes.includes("atestados.create")}
      canFinalizeCertificate={context.permissionCodes.includes("atestados.finalize")}
      canCreateExam={canCreateExam}
      canPerformExam={context.permissionCodes.includes("exams.perform")}
      canReviewExam={context.permissionCodes.includes("exams.review")}
      canViewExam={context.permissionCodes.includes("exams.view")}
      canCreateHospitalization={context.permissionCodes.includes("hospitalizations.create")}
      canDeleteConsultation={context.permissionCodes.includes("consultations.delete") && (context.positionLevel === 13 || context.positionLevel === 14)}
      consultation={consultation}
      currentUserId={context.profile.user_id}
      examReferences={examReferences}
      references={references}
    />
  </AppFrame>;
}
