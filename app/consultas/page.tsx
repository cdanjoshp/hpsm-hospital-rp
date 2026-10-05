import { redirect } from "next/navigation";
import { AppFrame } from "../components/app-frame";
import { ConsultationCenter } from "../components/consultation-center";
import { getConsultationPage, getConsultationReferences } from "../lib/consultations";
import { getQuickActionPatient } from "../lib/patient-center";
import { getSessionBootstrap } from "../lib/session";

export const dynamic = "force-dynamic";

export default async function ConsultationsPage({ searchParams }: { searchParams: Promise<{ agendamento?: string; novo?: string; paciente?: string; situacao?: string }> }) {
  const context = await getSessionBootstrap();
  if (!context) redirect("/");
  if (context.profile.must_change_password) redirect("/primeiro-acesso");
  if (!context.permissionCodes.includes("consultations.view")) redirect("/painel");
  const params = await searchParams;
  const targetAppointmentId = /^[1-9]\d*$/.test(params.agendamento ?? "") ? Number(params.agendamento) : null;
  const patientSearch = targetAppointmentId && /^\d{4}$/.test(params.paciente ?? "") ? params.paciente : undefined;
  const initialStatus = targetAppointmentId && (params.situacao === "scheduled" || params.situacao === "confirmed") ? params.situacao : undefined;
  const openWalkIn = params.novo === "1" && context.permissionCodes.includes("consultations.create");
  const [initialData, references, initialWalkInPatient] = await Promise.all([
    getConsultationPage(context.accessToken, { pageSize: 100, search: patientSearch, status: initialStatus }),
    getConsultationReferences(context.accessToken),
    openWalkIn ? getQuickActionPatient(context.accessToken, params.paciente) : Promise.resolve(null),
  ]);
  return <AppFrame active="consultations" profile={context.profile} title="Consultas e Agendamentos" description="Organize a agenda e registre consultas clínicas sem vínculo com vendas.">
    <ConsultationCenter
      key={openWalkIn ? `walk-in-${initialWalkInPatient?.id ?? params.paciente ?? "new"}` : "regular"}
      canCreate={context.permissionCodes.includes("consultations.create")}
      canDeleteAppointment={context.positionLevel === 14 && context.permissionCodes.includes("consultations.delete")}
      canManage={context.permissionCodes.includes("consultations.manage")}
      currentUserId={context.profile.user_id}
      initialData={initialData}
      initialSearch={patientSearch ?? ""}
      initialStatus={initialStatus ?? "all"}
      initialWalkInPatient={initialWalkInPatient}
      openWalkIn={openWalkIn}
      focusAppointmentId={targetAppointmentId}
      references={references}
    />
  </AppFrame>;
}
