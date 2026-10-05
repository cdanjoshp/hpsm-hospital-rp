import { redirect } from "next/navigation";
import { AppFrame } from "../components/app-frame";
import { MyHrPanel } from "../components/my-hr-panel";
import { getMyHrData } from "../lib/my-hr";
import { hasPermission } from "../lib/access";
import { getSessionContext } from "../lib/session";

export const dynamic = "force-dynamic";

export default async function MyHrPage() {
  const context = await getSessionContext();
  if (!context) redirect("/");
  if (context.profile.must_change_password) redirect("/primeiro-acesso");
  if (!await hasPermission(context.profile, "hr.self.view")) redirect("/painel");
  const { data, careerData } = await getMyHrData(context.accessToken);
  return (
    <AppFrame
      active="my-hr"
      profile={context.profile}
      title="Meu RH"
      description="Acompanhe sua meta semanal, justificativas e histórico funcional."
    >
      <MyHrPanel initialData={data} initialCareerData={careerData} />
    </AppFrame>
  );
}
