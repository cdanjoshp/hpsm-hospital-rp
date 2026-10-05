import { AdministrativeBreadcrumb } from "../../components/administrative-breadcrumb";
import { PartnershipManagement } from "../../components/partnership-management";
import { requireAdministrativeContext } from "../../lib/administrative-server";
import { getPartnershipDetail, getPartnershipMemberPage, getPartnershipPage, type PartnershipPage } from "../../lib/partnerships";

export const dynamic = "force-dynamic";

const EMPTY_PARTNERSHIPS: PartnershipPage = { items: [], limit: 24, offset: 0, total: 0 };

export default async function AdministrativePartnershipsPage() {
  const { context, permissionCodes } = await requireAdministrativeContext("partnerships");
  const initialPage = await getPartnershipPage(context.accessToken).catch(() => EMPTY_PARTNERSHIPS);
  const selectedId = initialPage.items[0]?.id;
  const [initialDetail, initialMembers] = selectedId ? await Promise.all([
    getPartnershipDetail(context.accessToken, selectedId).catch(() => null),
    getPartnershipMemberPage(context.accessToken, selectedId).catch(() => undefined),
  ]) : [null, undefined];

  return <div className="administrative-domain">
    <AdministrativeBreadcrumb current="partnerships" />
    <PartnershipManagement canManage={permissionCodes.includes("partnerships.manage")} initialDetail={initialDetail} initialMembers={initialMembers} initialPage={initialPage} />
  </div>;
}
