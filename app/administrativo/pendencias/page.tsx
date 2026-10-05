import { AdministrativeBreadcrumb } from "../../components/administrative-breadcrumb";
import { PendingCenter } from "../../components/pending-center";
import { EMPTY_PENDING_CENTER_DATA } from "../../lib/administrative";
import { requireAdministrativeContext } from "../../lib/administrative-server";
import { getPendingCenterData } from "../../lib/pending";

export const dynamic = "force-dynamic";

export default async function AdministrativePendingPage() {
  const { context, permissionCodes } = await requireAdministrativeContext("pending");
  const data = await getPendingCenterData(context.accessToken, permissionCodes).catch(() => EMPTY_PENDING_CENTER_DATA);

  return <div className="administrative-domain">
    <AdministrativeBreadcrumb current="pending" />
    <PendingCenter data={data} readOnly={permissionCodes.includes("sr.directors.view") && !permissionCodes.includes("admin.pending.manage")} />
  </div>;
}
