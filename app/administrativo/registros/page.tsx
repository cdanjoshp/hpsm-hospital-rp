import { AdministrativeBreadcrumb } from "../../components/administrative-breadcrumb";
import { AttendanceHistory } from "../../components/attendance-history";
import { requireAdministrativeContext } from "../../lib/administrative-server";

export const dynamic = "force-dynamic";

export default async function AdministrativeRecordsPage() {
  const { permissionCodes } = await requireAdministrativeContext("records");
  return <div className="administrative-domain">
    <AdministrativeBreadcrumb current="records" />
    <AttendanceHistory canManage={permissionCodes.includes("attendances.manage")} />
  </div>;
}
