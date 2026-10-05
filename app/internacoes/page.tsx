import { redirect } from "next/navigation";
import { AppFrame } from "../components/app-frame";
import { HospitalizationCenter } from "../components/hospitalization-center";
import { getHospitalBedBoard } from "../lib/hospitalizations";
import { getQuickActionPatient } from "../lib/patient-center";
import { getSessionBootstrap } from "../lib/session";

export const dynamic = "force-dynamic";

export default async function HospitalizationsPage({ searchParams }: { searchParams: Promise<{ acao?: string; novo?: string; paciente?: string; registro?: string }> }) {
  const context = await getSessionBootstrap();
  if (!context) redirect("/");
  if (context.profile.must_change_password) redirect("/primeiro-acesso");
  const permissions = context.permissionCodes;
  if (!permissions.includes("hospitalizations.view")) redirect("/painel");
  const initialBoard = await getHospitalBedBoard(context.accessToken);
  const params = await searchParams;
  const canCreate = permissions.includes("hospitalizations.create") && permissions.includes("patients.view");
  const initialPatient = params.novo === "1" && canCreate ? await getQuickActionPatient(context.accessToken, params.paciente) : null;
  return (
    <AppFrame active="hospitalizations" profile={context.profile} title="Internações e Leitos" description="Acompanhe os dez leitos compartilhados pelo HPSM e HP Norte.">
      <HospitalizationCenter
        key={initialPatient?.id ?? "regular"}
        canCreate={permissions.includes("hospitalizations.create")}
        canDischarge={permissions.includes("hospitalizations.discharge")}
        canSearchPatients={permissions.includes("patients.view")}
        canUpdate={permissions.includes("hospitalizations.update")}
        canViewHistory={permissions.includes("hospitalizations.history")}
        initialBoard={initialBoard}
        initialPatient={initialPatient}
        initialHospitalizationId={/^[1-9]\d*$/.test(params.registro ?? "") ? Number(params.registro) : null}
        initialDischarge={params.acao === "alta"}
      />
    </AppFrame>
  );
}
