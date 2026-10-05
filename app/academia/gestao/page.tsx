import { redirect } from "next/navigation";
import { AppFrame } from "../../components/app-frame";
import { AcademyManagement } from "../../components/academy-management";
import { readAcademy, type AcademyAdminList } from "../../lib/academy";
import { getSessionBootstrap } from "../../lib/session";
import "../academy.css";

export const dynamic = "force-dynamic";
export default async function AcademyManagementPage() {
  const context = await getSessionBootstrap();
  if (!context) redirect("/");
  if (context.profile.must_change_password) redirect("/primeiro-acesso");
  if (!context.permissionCodes.includes("courses.academy.manage") || !context.permissionCodes.includes("courses.manage") || context.positionLevel === null || context.positionLevel < 12 || context.positionLevel > 14) redirect("/painel");
  const data = await readAcademy<AcademyAdminList>(context.accessToken,"admin");
  return <AppFrame active="hr" profile={context.profile} title="Gestão da Academia" description="Cursos, aulas, avaliações e resultados.">
    <AcademyManagement initial={data} canViewResults={context.permissionCodes.includes("courses.results.viewall")}
      canAdjust={context.permissionCodes.includes("courses.results.manage")}
      canReopen={context.permissionCodes.includes("courses.attempts.reopen")} />
  </AppFrame>;
}
