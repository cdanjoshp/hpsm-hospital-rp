import { redirect } from "next/navigation";
import { AppFrame } from "../components/app-frame";
import { HpsmAssist } from "../components/hpsm-assist";
import { getSessionBootstrap } from "../lib/session";

export const dynamic = "force-dynamic";

export default async function HpsmAssistPage() {
  const context = await getSessionBootstrap();
  if (!context) redirect("/");
  if (context.profile.must_change_password) redirect("/primeiro-acesso");
  if (!context.permissionCodes.includes("hpsm.assist.use")) redirect("/painel");
  return <AppFrame active="assist" profile={context.profile} title="HPSM Assist" description="Descreva o caso e receba sugestões rápidas de avaliação, exames, medicamentos e conduta.">
    <HpsmAssist />
  </AppFrame>;
}
