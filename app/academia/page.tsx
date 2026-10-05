import { redirect } from "next/navigation";
import { AppFrame } from "../components/app-frame";
import { AcademyCatalogView } from "../components/academy-catalog";
import { readAcademy, type AcademyCatalog } from "../lib/academy";
import { getSessionBootstrap } from "../lib/session";
import "./academy.css";

export const dynamic = "force-dynamic";
export default async function AcademyPage() {
  const context = await getSessionBootstrap();
  if (!context) redirect("/");
  if (context.profile.must_change_password) redirect("/primeiro-acesso");
  if (!context.permissionCodes.includes("courses.study")) redirect("/painel");
  const catalog = await readAcademy<AcademyCatalog>(context.accessToken, "catalog");
  return <AppFrame active="my-hr" profile={context.profile} title="Academia HPSM" description="Cursos e avaliações da equipe.">
    <AcademyCatalogView initial={catalog} canManage={context.permissionCodes.includes("courses.academy.manage") && context.permissionCodes.includes("courses.manage") && context.positionLevel !== null && context.positionLevel >= 12 && context.positionLevel <= 14} />
  </AppFrame>;
}
