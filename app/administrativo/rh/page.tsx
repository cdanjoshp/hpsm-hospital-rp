import { AdministrativeBreadcrumb } from "../../components/administrative-breadcrumb";
import { HrManagement, type HrManagementTab } from "../../components/hr-management";
import { getStaffPositions } from "../../lib/access";
import { EMPTY_PENDING_CENTER_DATA } from "../../lib/administrative";
import { requireAdministrativeContext } from "../../lib/administrative-server";
import { EMPTY_CAREER_ADMIN_DATA } from "../../lib/career";
import { getHrAdminData } from "../../lib/hr";
import { currentSaoPauloMonth } from "../../lib/hr-production";

export const dynamic = "force-dynamic";

export default async function AdministrativeHrPage({ searchParams }: { searchParams: Promise<{ aba?: string }> }) {
  const { context, permissionCodes } = await requireAdministrativeContext("rh");
  const [rawData, positions, query] = await Promise.all([getHrAdminData(permissionCodes), getStaffPositions(), searchParams]);
  const has = (code: string) => permissionCodes.includes(code);
  const canObserve = has("sr.directors.view");
  const canViewOverview = has("hr.team.view") || has("hr.hours.manage") || has("hr.weeks.close");
  const data = {
    ...rawData,
    absences: canObserve || has("hr.absences.review") ? rawData.absences : [],
    closures: canObserve || has("hr.hours.manage") || has("hr.weeks.close") || has("hr.weeks.reopen") ? rawData.closures : [],
    hourJustifications: canObserve || has("hr.justifications.review") ? rawData.hourJustifications : [],
    leaveAdjustments: canObserve || has("hr.absences.review") || has("hr.hours.manage") || has("hr.justifications.review") ? rawData.leaveAdjustments : [],
    progressByEmployee: canViewOverview ? rawData.progressByEmployee : {},
    reopenEvents: canObserve || has("hr.hours.manage") || has("hr.weeks.reopen") ? rawData.reopenEvents : [],
    reviews: canObserve || has("hr.discipline.manage") || has("hr.discipline.review") ? rawData.reviews : [],
    snapshots: has("hr.team.view") || has("hr.hours.manage") || has("hr.hours.import") || has("hr.weeks.close") ? rawData.snapshots : [],
    warnings: canObserve || has("hr.discipline.manage") || has("hr.warnings.issue") || has("hr.warnings.annul") || has("hr.warnings.progression") ? rawData.warnings : [],
    weeklyRecords: has("hr.team.view") || has("hr.hours.manage") || has("hr.weeks.close") || has("hr.justifications.review") || has("hr.discipline.manage") || has("hr.warnings.issue") ? rawData.weeklyRecords : [],
  };
  const requestedTab: HrManagementTab = query.aba === "hours" || query.aba === "absences" || query.aba === "discipline" ? query.aba : "overview";

  return <div className="administrative-domain">
    <AdministrativeBreadcrumb current="rh" />
    <HrManagement
      actorId={context.profile.user_id}
      initialAccessData={{ grants: [], permissions: [], positionPermissions: [], positions }}
      initialApplications={[]}
      initialCareerData={{ ...EMPTY_CAREER_ADMIN_DATA, positions }}
      initialData={data}
      initialDecisions={[]}
      initialPendingData={EMPTY_PENDING_CENTER_DATA}
      initialProductionData={{ days: [], month: currentSaoPauloMonth() }}
      initialProfiles={[]}
      initialTab={requestedTab}
      permissionCodes={permissionCodes}
      referenceTime={new Date().toISOString()}
      visibleTabs={["overview", "hours", "absences", "discipline"]}
    />
  </div>;
}
