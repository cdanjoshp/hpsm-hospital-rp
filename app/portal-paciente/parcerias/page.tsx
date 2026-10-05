import { redirect } from "next/navigation";
import { PatientPortalPartnerships } from "../../components/patient-portal-partnerships";
import { PatientPortalError, PatientPortalFrame, PatientPortalShell } from "../../components/patient-portal-shell";
import { getPatientPortalPartnershipMemberPage, getPatientPortalPartnershipPage } from "../../lib/patient-portal";

export const dynamic = "force-dynamic";

export default async function PatientPortalPartnershipsPage() {
  let page = null;
  let initialMembers = null;
  let failed = false;
  try {
    page = await getPatientPortalPartnershipPage();
    if (page?.items[0]) initialMembers = await getPatientPortalPartnershipMemberPage(page.items[0].id);
  } catch {
    failed = true;
  }
  if (!page || !page.items.length) redirect("/portal-paciente");
  if (failed || !initialMembers) return <PatientPortalFrame><PatientPortalError message="Atualize a página para tentar novamente. Nenhum dado foi alterado." title="Não foi possível carregar suas parcerias." /></PatientPortalFrame>;
  return <PatientPortalFrame><PatientPortalShell active="partnerships" description="Administre somente a lista de pessoas das parcerias sob sua responsabilidade." managesPartnerships partnershipArea patient={page.patient} title="Minhas parcerias"><PatientPortalPartnerships initialMembers={initialMembers} initialPage={page} /></PatientPortalShell></PatientPortalFrame>;
}
