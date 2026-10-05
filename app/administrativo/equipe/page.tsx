import { AccessManagement } from "../../components/access-management";
import { AdministrativeBreadcrumb } from "../../components/administrative-breadcrumb";
import { UserManagement } from "../../components/user-management";
import { getAccessManagementData, getStaffPositions, type AccessManagementData } from "../../lib/access";
import { getManagedProfiles } from "../../lib/admin-data";
import { requireAdministrativeContext } from "../../lib/administrative-server";

export const dynamic = "force-dynamic";

export default async function AdministrativeTeamPage() {
  const { context, permissionCodes } = await requireAdministrativeContext("team");
  const canManageTeam = permissionCodes.includes("team.manage");
  const canManageAccess = permissionCodes.includes("access.manage");
  const canViewAll = permissionCodes.includes("sr.directors.view");
  const [profiles, accessData, standalonePositions] = await Promise.all([
    getManagedProfiles().catch(() => []),
    canManageAccess || canViewAll ? getAccessManagementData().catch(() => null) : Promise.resolve(null),
    canManageAccess || canViewAll ? Promise.resolve([]) : getStaffPositions().catch(() => []),
  ]);
  const positions = accessData?.positions ?? standalonePositions;
  const resolvedAccessData: AccessManagementData = accessData ?? { grants: [], permissions: [], positionPermissions: [], positions };

  return <div className="administrative-domain">
    <AdministrativeBreadcrumb current="team" />
    <div className="access-team-stack">
      {canManageTeam || canViewAll ? <UserManagement canManage={canManageTeam} canOverridePosition={canManageTeam && context.profile.role_code === "diretor_geral" && permissionCodes.includes("succession.manage")} initialProfiles={profiles} positions={positions} /> : null}
      {canManageAccess || canViewAll ? <AccessManagement canManage={canManageAccess} initialData={resolvedAccessData} profiles={profiles} referenceTime={new Date().toISOString()} /> : null}
    </div>
  </div>;
}
