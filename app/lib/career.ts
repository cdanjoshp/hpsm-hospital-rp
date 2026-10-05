import type { ManagedProfile } from "./admin-data";
import type { StaffPosition } from "./access";
import { adminRest, callHrRpc } from "./hr-server";

export type ProgressionStatus = {
  attendance_count?: number;
  blocked?: boolean;
  eligible: boolean;
  elapsed_days?: number;
  employee_id: string;
  flagged_warning_count?: number;
  level?: number;
  next_position_id?: number;
  next_position_name?: string;
  position_id?: number;
  position_name?: string;
  reason?: string;
  required_attendances?: number;
  required_days?: number;
  required_worked_minutes?: number;
  since?: string;
  worked_minutes?: number;
};

export type PositionHistory = {
  created_at: string;
  decided_by: string;
  effective_at: string;
  employee_id: string;
  event_type: "initial_assignment" | "promotion" | "appointment" | "succession" | "override";
  from_position_id: number | null;
  id: number;
  note: string | null;
  to_position_id: number;
};

export type PromotionReview = {
  attendance_count: number;
  created_at: string;
  decided_at: string | null;
  decided_by: string | null;
  decision_note: string | null;
  elapsed_days: number;
  employee_id: string;
  flagged_warning_count: number;
  from_position_id: number;
  id: number;
  required_days: number;
  status: "pending" | "promoted" | "deferred" | "cancelled";
  to_position_id: number;
  updated_at: string;
  worked_minutes: number;
};

export type Course = {
  active: boolean;
  created_at: string;
  created_by: string;
  description: string;
  id: number;
  name: string;
  updated_at: string;
  updated_by: string;
};

export type StaffCourseRecord = {
  assigned_at: string;
  assigned_by: string;
  completed_at: string | null;
  completed_by: string | null;
  course_id: number;
  employee_id: string;
  id: number;
  status: "pending" | "completed";
  updated_at: string;
};

export type CareerAdminData = {
  courseRecords: StaffCourseRecord[];
  courses: Course[];
  history: PositionHistory[];
  positions: StaffPosition[];
  profiles: ManagedProfile[];
  progression: Record<string, ProgressionStatus>;
  reviews: PromotionReview[];
};

export type CareerSelfData = {
  courseRecords: StaffCourseRecord[];
  courses: Course[];
  history: PositionHistory[];
  position: StaffPosition | null;
  positions: StaffPosition[];
  progression: ProgressionStatus;
};

export const EMPTY_CAREER_ADMIN_DATA: CareerAdminData = {
  courseRecords: [], courses: [], history: [], positions: [], profiles: [],
  progression: {}, reviews: [],
};

const POSITION_SELECT = "id,code,name,level,sort_order,official,active,advancement_mode,created_at,updated_at";
const HISTORY_SELECT = "id,employee_id,from_position_id,to_position_id,event_type,effective_at,decided_by,note,created_at";
const REVIEW_SELECT = "id,employee_id,from_position_id,to_position_id,status,required_days,elapsed_days,worked_minutes,attendance_count,flagged_warning_count,created_at,decided_by,decided_at,decision_note,updated_at";
const COURSE_SELECT = "id,name,description,active,created_by,updated_by,created_at,updated_at";
const COURSE_RECORD_SELECT = "id,employee_id,course_id,status,assigned_by,assigned_at,completed_by,completed_at,updated_at";

export async function getCareerAdminData(actorId: string, permissionCodes?: readonly string[]): Promise<CareerAdminData> {
  const can = (code: string) => !permissionCodes || permissionCodes.includes(code);
  const canManageProgression = can("progression.review") || can("appointments.manage") || can("succession.manage");
  const canManageCourses = can("courses.manage") || can("courses.completions.manage");
  const canObserve = can("sr.directors.view");
  if (canManageProgression) await callHrRpc("refresh_staff_promotion_reviews", { p_actor_id: actorId }).catch(() => null);
  const [positions, profiles, history, reviews, courses, courseRecords, progressionByEmployee] = await Promise.all([
    adminRest<StaffPosition[]>(`staff_positions?select=${POSITION_SELECT}&order=level.asc`),
    adminRest<ManagedProfile[]>("profiles?select=user_id,passport,display_name,role_code,status,must_change_password,position_id,created_at&order=display_name.asc"),
    canManageProgression || canObserve ? adminRest<PositionHistory[]>(`staff_position_history?select=${HISTORY_SELECT}&order=effective_at.desc&limit=250`) : Promise.resolve([]),
    canManageProgression || canObserve ? adminRest<PromotionReview[]>(`staff_promotion_reviews?select=${REVIEW_SELECT}&order=created_at.desc&limit=500`) : Promise.resolve([]),
    can("courses.academy.manage") ? adminRest<Course[]>(`courses?select=${COURSE_SELECT}&order=active.desc,name.asc`) : Promise.resolve([]),
    canManageCourses || canObserve ? adminRest<StaffCourseRecord[]>(`staff_course_records?select=${COURSE_RECORD_SELECT}&order=assigned_at.desc&limit=100`) : Promise.resolve([]),
    canManageProgression ? callHrRpc<Record<string, ProgressionStatus>>("get_staff_progression_statuses", { p_actor_id: actorId }).catch((): Record<string, ProgressionStatus> => ({})) : Promise.resolve<Record<string, ProgressionStatus>>({}),
  ]);
  const levelByPosition = new Map(positions.map((position) => [position.id, position.level]));
  const progressiveProfiles = canManageProgression ? profiles.filter((profile) => {
    const level = levelByPosition.get(profile.position_id ?? -1);
    return level !== undefined && level !== null && level <= 10;
  }) : [];
  const statuses = progressiveProfiles.map((profile) => [
    profile.user_id,
    progressionByEmployee[profile.user_id] ?? { employee_id: profile.user_id, eligible: false },
  ] as const);
  const officialPositionIds = new Set(positions.filter((position) => position.official).map((position) => position.id));
  const officialProfiles = profiles.filter((profile) => profile.position_id !== null && officialPositionIds.has(profile.position_id));
  const officialUserIds = new Set(officialProfiles.map((profile) => profile.user_id));
  return {
    courseRecords: courseRecords.filter((record) => officialUserIds.has(record.employee_id)),
    courses,
    history: history.filter((record) => officialUserIds.has(record.employee_id)),
    positions: positions.filter((position) => position.official),
    profiles: officialProfiles,
    progression: Object.fromEntries(statuses),
    reviews: reviews.filter((review) => officialUserIds.has(review.employee_id)),
  };
}

export async function getCareerSelfData(employeeId: string): Promise<CareerSelfData> {
  const filter = encodeURIComponent(employeeId);
  const [positions, history, progression, courseRecords] = await Promise.all([
    adminRest<StaffPosition[]>(`staff_positions?select=${POSITION_SELECT}&order=level.asc`),
    adminRest<PositionHistory[]>(`staff_position_history?select=${HISTORY_SELECT}&employee_id=eq.${filter}&order=effective_at.desc&limit=100`),
    callHrRpc<ProgressionStatus>("get_staff_progression_status", { p_actor_id: employeeId, p_employee_id: employeeId }),
    adminRest<StaffCourseRecord[]>(`staff_course_records?select=${COURSE_RECORD_SELECT}&employee_id=eq.${filter}&order=assigned_at.desc&limit=200`),
  ]);
  const legacyCourseIds = [...new Set(courseRecords.map((record) => record.course_id))];
  const courses = legacyCourseIds.length ? await adminRest<Course[]>(`courses?select=${COURSE_SELECT}&id=in.(${legacyCourseIds.join(",")})`) : [];
  const currentPositionId = history[0]?.to_position_id ?? progression.position_id ?? null;
  return {
    courseRecords,
    courses,
    history,
    position: positions.find((position) => position.id === currentPositionId) ?? null,
    positions,
    progression,
  };
}
