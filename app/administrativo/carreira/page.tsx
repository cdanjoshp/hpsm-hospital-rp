import { AdministrativeBreadcrumb } from "../../components/administrative-breadcrumb";
import { CareerManagement } from "../../components/career-management";
import { requireAdministrativeContext } from "../../lib/administrative-server";
import { EMPTY_CAREER_ADMIN_DATA, getCareerAdminData } from "../../lib/career";

export const dynamic = "force-dynamic";

export default async function AdministrativeCareerPage() {
  const { context, permissionCodes } = await requireAdministrativeContext("career");
  const data = await getCareerAdminData(context.profile.user_id, permissionCodes).catch(() => EMPTY_CAREER_ADMIN_DATA);
  const canManageProgression = ["progression.review", "appointments.manage", "succession.manage"].some((code) => permissionCodes.includes(code));
  const canManageCourses = permissionCodes.includes("courses.manage") || permissionCodes.includes("courses.completions.manage");
  const canManageAcademy = permissionCodes.includes("courses.academy.manage");
  const canObserve = permissionCodes.includes("sr.directors.view");
  const visibleData = {
    ...data,
    courseRecords: canManageCourses || canObserve ? data.courseRecords : [],
    courses: canManageAcademy ? data.courses : [],
    history: canManageProgression || canObserve ? data.history : [],
    progression: canManageProgression ? data.progression : {},
    reviews: canManageProgression || canObserve ? data.reviews : [],
  };

  return <div className="administrative-domain">
    <AdministrativeBreadcrumb current="career" />
    <CareerManagement actorId={context.profile.user_id} initialData={visibleData} permissionCodes={permissionCodes} />
  </div>;
}
