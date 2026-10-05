import { redirect } from "next/navigation";
import { AppFrame } from "../../components/app-frame";
import { ClinicalProtocolLibrary } from "../../components/clinical-protocol-library";
import { getClinicalProtocolLibrary } from "../../lib/consultations";
import { getSessionBootstrap } from "../../lib/session";

export const dynamic = "force-dynamic";
export default async function ClinicalProtocolsPage() {
  const context = await getSessionBootstrap();
  if (!context) redirect("/");
  if (context.profile.must_change_password) redirect("/primeiro-acesso");
  if (!context.permissionCodes.includes("consultations.view")) redirect("/painel");
  return <AppFrame active="consultations" profile={context.profile} title="Biblioteca de Protocolos" description="Padrões clínicos RP autoalimentados e catálogo canônico Anjos Pharma."><ClinicalProtocolLibrary initialData={await getClinicalProtocolLibrary(context.accessToken)} /></AppFrame>;
}
