import { AdministrativeBreadcrumb } from "../../components/administrative-breadcrumb";
import { RecruitmentManagement } from "../../components/recruitment-management";
import { requireAdministrativeContext } from "../../lib/administrative-server";
import { getRecruitmentManagementData } from "../../lib/recruitment-management";

export const dynamic = "force-dynamic";

export default async function AdministrativeRecruitmentPage({ searchParams }: { searchParams: Promise<{ selecionar?: string }> }) {
  const { context, permissionCodes } = await requireAdministrativeContext("recruitment");
  const [result, query] = await Promise.all([
    getRecruitmentManagementData(context.accessToken)
      .then((data) => ({ data, error: "" }))
      .catch(() => ({ data: { applications: [], decisions: [] }, error: "Não foi possível carregar as candidaturas. Atualize a página para tentar novamente." })),
    searchParams,
  ]);

  return <div className="administrative-domain">
    <AdministrativeBreadcrumb current="recruitment" />
    <RecruitmentManagement canDecide={permissionCodes.includes("recruitment.manage")} initialApplications={result.data.applications} initialDecisions={result.data.decisions} initialLoadError={result.error} initialSelectedId={query.selecionar} />
  </div>;
}
