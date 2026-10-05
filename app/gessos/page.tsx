import { redirect } from "next/navigation";
import { AppFrame } from "../components/app-frame";
import { CastControl } from "../components/cast-control";
import { getClinicalCastPatientPage } from "../lib/casts";
import { getQuickActionPatient } from "../lib/patient-center";
import { getSessionBootstrap } from "../lib/session";

export const dynamic = "force-dynamic";

export default async function CastsPage({ searchParams }: { searchParams: Promise<{ acao?: string; consulta?: string; nova?: string; novo?: string; paciente?: string; registro?: string }> }) {
  const context = await getSessionBootstrap();
  if (!context) redirect("/");
  if (context.profile.must_change_password) redirect("/primeiro-acesso");
  const permissions = context.permissionCodes;
  if (!permissions.includes("casts.view")) redirect("/painel");

  const initialData = await getClinicalCastPatientPage(context.accessToken, { page: 1, pageSize: 20, status: "in_use" });
  const params = await searchParams;
  const initialCastId = /^[1-9]\d*$/.test(params.registro ?? "") ? Number(params.registro) : null;
  const canCreate = permissions.includes("casts.create") && permissions.includes("patients.view");
  const initialPatient = params.novo === "1" && canCreate ? await getQuickActionPatient(context.accessToken, params.paciente) : null;
  return (
    <AppFrame
      active="casts"
      profile={context.profile}
      title="Controle de Gesso"
      description="Registre aplicações, acompanhe previsões e documente retiradas com segurança clínica."
    >
      <CastControl
        key={initialPatient?.id ?? "regular"}
        canCreate={canCreate}
        canManage={permissions.includes("casts.manage")}
        canRemove={permissions.includes("casts.remove")}
        currentProfessional={{
          id: context.profile.user_id,
          name: context.profile.display_name,
          position: context.positionDisplayName,
        }}
        initialData={initialData}
        initialPatient={initialPatient}
        initialCastId={initialCastId && Number.isSafeInteger(initialCastId) ? initialCastId : null}
        initialCastAction={params.acao === "retirar" ? "remove" : null}
      />
    </AppFrame>
  );
}
