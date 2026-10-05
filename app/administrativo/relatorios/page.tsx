import { AdministrativeBreadcrumb } from "../../components/administrative-breadcrumb";
import { AdministrativeReports } from "../../components/administrative-reports";
import { currentSaoPauloDate } from "../../lib/administrative-reports";
import { requireAdministrativeContext } from "../../lib/administrative-server";

export const dynamic = "force-dynamic";

export default async function AdministrativeReportsPage() {
  const { permissionCodes } = await requireAdministrativeContext("reports");

  return <div className="administrative-domain">
    <AdministrativeBreadcrumb current="reports" />
    <AdministrativeReports canViewFinancial={permissionCodes.includes("attendances.manage") || permissionCodes.includes("sr.directors.view")} referenceDate={currentSaoPauloDate()} />
  </div>;
}
