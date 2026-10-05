import { redirect } from "next/navigation";
import { AppFrame } from "../components/app-frame";
import { ProfessionalDashboard } from "../components/professional-dashboard";
import { getProfessionalDashboard } from "../lib/dashboard";
import { getSessionBootstrap } from "../lib/session";

export const dynamic = "force-dynamic";

export default async function DashboardPage() {
  const bootstrap = await getSessionBootstrap();
  if (!bootstrap) redirect("/");
  const { accessToken, permissionCodes, profile } = bootstrap;
  if (profile.must_change_password) redirect("/primeiro-acesso");

  const dashboard = await getProfessionalDashboard(accessToken).catch(() => null);
  return (
    <AppFrame
      active="dashboard"
      profile={profile}
      title="Página Inicial"
      description="Acesse os módulos do hospital."
    >
      <ProfessionalDashboard
        data={dashboard}
        dateLabel={new Intl.DateTimeFormat("pt-BR", { dateStyle: "long", timeZone: "America/Sao_Paulo" }).format(new Date())}
        firstName={profile.display_name.trim().split(/\s+/)[0] || "profissional"}
        permissionCodes={permissionCodes}
      />
    </AppFrame>
  );
}
