import { redirect } from "next/navigation";
import { AppFrame } from "../components/app-frame";
import { MedicalCertificateCenter } from "../components/medical-certificate-center";
import { getMedicalCertificatePage } from "../lib/medical-certificates";
import { getSessionBootstrap } from "../lib/session";

export const dynamic = "force-dynamic";

export default async function MedicalCertificatesPage() {
  const context = await getSessionBootstrap();
  if (!context) redirect("/");
  if (context.profile.must_change_password) redirect("/primeiro-acesso");
  const permissions = context.permissionCodes;
  if (!permissions.includes("atestados.view")) redirect("/painel");
  const initialData = await getMedicalCertificatePage(context.accessToken, { page: 1, pageSize: 20 });
  return (
    <AppFrame active="certificates" profile={context.profile} title="Atestados Médicos" description="Crie, revise, finalize e consulte atestados vinculados a atendimentos ou consultas clínicas.">
      <MedicalCertificateCenter
        canCancel={permissions.includes("atestados.cancel")}
        canCreate={permissions.includes("atestados.create") && permissions.includes("patients.view")}
        canFinalize={permissions.includes("atestados.finalize")}
        currentProfessional={{ id: context.profile.user_id, name: context.profile.display_name, position: context.positionDisplayName }}
        initialData={initialData}
      />
    </AppFrame>
  );
}
