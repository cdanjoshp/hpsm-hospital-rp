import { redirect } from "next/navigation";
import { AppFrame } from "../components/app-frame";
import { AttendanceDesk } from "../components/attendance-desk";
import { AttendanceHistory } from "../components/attendance-history";
import { getEffectivePermissionCodes } from "../lib/access";
import { getQuickActionPatient } from "../lib/patient-center";
import { getSessionBootstrap } from "../lib/session";

export const dynamic = "force-dynamic";

export default async function AttendancesPage({ searchParams }: { searchParams: Promise<{ novo?: string; paciente?: string }> }) {
  const context = await getSessionBootstrap();
  if (!context) redirect("/");
  if (context.profile.must_change_password) redirect("/primeiro-acesso");

  const permissionCodes = await getEffectivePermissionCodes(context.profile.user_id);
  const canCreateAttendances = permissionCodes.includes("attendances.create");
  const canManageAttendances = permissionCodes.includes("attendances.manage");
  const canSimulateAttendances = permissionCodes.includes("sr.directors.view");
  const canViewAllAttendances = (context.positionLevel !== null && context.positionLevel >= 12 && context.positionLevel <= 14) || canSimulateAttendances;
  const canManagePatients = permissionCodes.includes("patients.manage");
  if (!canCreateAttendances && !canManageAttendances && !canSimulateAttendances) redirect("/painel");
  const params = await searchParams;
  const initialPatient = params.novo === "1" && canCreateAttendances
    ? await getQuickActionPatient(context.accessToken, params.paciente) : null;

  return (
    <AppFrame
      active="attendances"
      profile={context.profile}
      title="Vendas"
      description={canCreateAttendances ? "Selecione o paciente, adicione produtos e procedimentos e conclua o atendimento." : "Consulte preços, benefícios e descontos sem registrar uma venda."}
    >
      <AttendanceDesk key={initialPatient?.id ?? "regular"} services={[]} isDirector={canManageAttendances} canManagePatients={canManagePatients} canRecordAttendance={canCreateAttendances} initialPatient={initialPatient} />
      <AttendanceHistory canManage={canManageAttendances} scope={canViewAllAttendances ? "all" : "mine"} />
    </AppFrame>
  );
}
