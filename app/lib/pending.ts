import { adminCount, adminRest } from "./hr-server";
import { staffIdentity } from "./staff-identity";
import { getOverdueClinicalCasts } from "./casts";
import { castBodyRegionLabel, castLateralityLabel } from "./cast-types";

export type PendingCategory = "absence" | "health_plan" | "hour_justification" | "career" | "discipline" | "recruitment" | "cast";

export type PendingItem = {
  category: PendingCategory;
  createdAt: string;
  href: string;
  id: string;
  priority: "important" | "normal" | "urgent";
  subtitle: string;
  title: string;
  actionLabel?: string;
};

export type PendingCenterData = {
  absences: PendingItem[];
  career: PendingItem[];
  casts: PendingItem[];
  counts: PendingCounts;
  discipline: PendingItem[];
  healthPlans: HealthPlanPending[];
  recruitment: PendingItem[];
  total: number;
};

export type PendingCounts = {
  absences: number;
  casts: number;
  discipline: number;
  healthPlans: number;
  justifications: number;
  promotions: number;
  recruitment: number;
};

export type HealthPlanPending = {
  attendanceId: number;
  createdAt: string;
  patientName: string;
  patientPassport: string;
  planValue: number;
  requestId: number;
  sellerIdentity: string;
  sellerName: string;
};

type RecruitmentPending = {
  created_at: string;
  full_name: string;
  id: string;
  passport: string;
};
type AbsencePending = {
  employee_id: string;
  end_date: string;
  id: number;
  reason: string;
  requested_at: string;
  start_date: string;
};
type DisciplinePending = {
  cycle_month: string;
  employee_id: string;
  id: number;
  triggered_at: string;
};
type HourJustificationPending = {
  deficit_minutes: number;
  employee_id: string;
  id: number;
  reason: string;
  submitted_at: string;
};
type ProfileName = { display_name: string; passport: string; position_id: number | null; user_id: string };
type PromotionPending = { created_at: string; employee_id: string; id: number };
type HealthPlanRequestPending = { attendance_id: number; id: number; patient_id: number; requested_at: string };
type AttendancePending = { created_at: string; id: number; patient_name: string; patient_passport: string; performed_by: string };
type PlanAttendanceItem = { attendance_id: number; line_total: number };

export async function getPendingCenterData(accessToken: string, permissionCodes?: string[]): Promise<PendingCenterData> {
  const can = (code: string) => !permissionCodes || permissionCodes.includes(code);
  const canObserve = can("sr.directors.view");
  const canRecruit = canObserve || can("recruitment.manage");
  const canReviewAbsences = canObserve || can("hr.absences.review");
  const canReviewJustifications = canObserve || can("hr.justifications.review");
  const canReviewDiscipline = canObserve || can("hr.discipline.manage") || can("hr.discipline.review");
  const canReviewPromotions = canObserve || can("progression.review");
  const canReviewHealthPlans = canObserve || can("healthplans.review");
  const canManageCasts = can("casts.view") && (canObserve || can("casts.manage"));
  const needsStaffReferences = canReviewAbsences || canReviewJustifications || canReviewDiscipline || canReviewPromotions || canReviewHealthPlans;
  const [applications, absences, justifications, reviews, promotionReviews, profiles, positions, healthPlanRequests, planServices, overdueCasts] = await Promise.all([
    canRecruit
      ? adminRest<RecruitmentPending[]>(
        "recruitment_applications?select=id,full_name,passport,created_at&status=in.(submitted,under_review,interview)&order=created_at.asc&limit=250",
      )
      : Promise.resolve([]),
    canReviewAbsences
      ? adminRest<AbsencePending[]>(
        "rh_absence_requests?select=id,employee_id,start_date,end_date,reason,requested_at&status=eq.pending&order=requested_at.asc&limit=250",
      )
      : Promise.resolve([]),
    canReviewJustifications
      ? adminRest<HourJustificationPending[]>(
        "rh_hour_justifications?select=id,employee_id,deficit_minutes,reason,submitted_at&status=eq.pending&order=submitted_at.asc&limit=250",
      )
      : Promise.resolve([]),
    canReviewDiscipline
      ? adminRest<DisciplinePending[]>(
        "rh_disciplinary_reviews?select=id,employee_id,cycle_month,triggered_at&status=eq.pending&order=triggered_at.asc&limit=250",
      )
      : Promise.resolve([]),
    canReviewPromotions
      ? adminRest<PromotionPending[]>("staff_promotion_reviews?select=id,employee_id,created_at&status=eq.pending&order=created_at.asc&limit=250").catch(() => [])
      : Promise.resolve([]),
    needsStaffReferences
      ? adminRest<ProfileName[]>("profiles?select=user_id,display_name,passport,position_id&limit=500")
      : Promise.resolve([]),
    needsStaffReferences
      ? adminRest<Array<{ id: number; name: string; official: boolean }>>("staff_positions?select=id,name,official&limit=50")
      : Promise.resolve([]),
    canReviewHealthPlans
      ? adminRest<HealthPlanRequestPending[]>(
        "patient_health_plan_requests?select=id,patient_id,attendance_id,requested_at&status=eq.pending&order=requested_at.asc&limit=250",
      ).catch(() => [])
      : Promise.resolve([]),
    canReviewHealthPlans
      ? adminRest<Array<{ id: number }>>("service_catalog?select=id&code=eq.plano_saude_convenio&limit=1")
      : Promise.resolve([]),
    canManageCasts ? getOverdueClinicalCasts(accessToken) : Promise.resolve([]),
  ]);
  const officialPositionIds = new Set(positions.filter((position) => position.official).map((position) => position.id));
  const workforceProfiles = profiles.filter((profile) => profile.position_id !== null && officialPositionIds.has(profile.position_id));
  const workforceIds = new Set(workforceProfiles.map((profile) => profile.user_id));
  const profileById = new Map(workforceProfiles.map((profile) => [profile.user_id, profile]));
  const positionById = new Map(positions.map((position) => [position.id, position.name]));
  const identityOf = (profile: ProfileName | undefined) => profile
    ? staffIdentity(profile.passport, positionById.get(profile.position_id ?? -1))
    : "Cargo não identificado";

  const recruitment: PendingItem[] = applications.map((application) => ({
    category: "recruitment",
    createdAt: application.created_at,
    href: `/administrativo/recrutamento?selecionar=${application.id}`,
    id: `recruitment-${application.id}`,
    priority: "normal",
    subtitle: `Passaporte ${application.passport} · candidatura aguardando decisão`,
    title: application.full_name,
  }));
  const absenceItems: PendingItem[] = absences.filter((absence) => workforceIds.has(absence.employee_id)).map((absence) => {
    const employee = profileById.get(absence.employee_id);
    return {
      category: "absence",
      createdAt: absence.requested_at,
      href: "/administrativo/rh?aba=absences",
      id: `absence-${absence.id}`,
      priority: "important",
      subtitle: `${identityOf(employee)} · afastamento ${formatPeriod(absence.start_date, absence.end_date)} · ${truncate(absence.reason, 80)}`,
      title: employee?.display_name ?? "Colaborador",
    };
  });
  absenceItems.push(...justifications.filter((justification) => workforceIds.has(justification.employee_id)).map((justification) => {
    const employee = profileById.get(justification.employee_id);
    return {
      category: "hour_justification" as const,
      createdAt: justification.submitted_at,
      href: "/administrativo/rh?aba=absences",
      id: `hour-justification-${justification.id}`,
      priority: "important" as const,
      subtitle: `${identityOf(employee)} · déficit de ${formatMinutes(justification.deficit_minutes)} · ${truncate(justification.reason, 80)}`,
      title: employee?.display_name ?? "Colaborador",
    };
  }));
  absenceItems.sort((a, b) => a.createdAt.localeCompare(b.createdAt));
  const discipline: PendingItem[] = reviews.filter((review) => workforceIds.has(review.employee_id)).map((review) => {
    const employee = profileById.get(review.employee_id);
    return {
      category: "discipline",
      createdAt: review.triggered_at,
      href: "/administrativo/rh?aba=discipline",
      id: `discipline-${review.id}`,
      priority: "urgent",
      subtitle: `${identityOf(employee)} · ciclo ${formatMonth(review.cycle_month)} · suspensão aguardando análise`,
      title: employee?.display_name ?? "Colaborador",
    };
  });
  const career: PendingItem[] = [];
  career.push(...promotionReviews.filter((review) => workforceIds.has(review.employee_id)).map((review) => ({
    category: "career" as const,
    createdAt: review.created_at,
    href: "/administrativo/carreira",
    id: `promotion-${review.id}`,
    priority: "important" as const,
    subtitle: `${identityOf(profileById.get(review.employee_id))} · requisitos mínimos atingidos · promoção depende de análise humana`,
    title: profileById.get(review.employee_id)?.display_name ?? "Colaborador",
  })));
  career.sort((a, b) => a.createdAt.localeCompare(b.createdAt));
  const castItems: PendingItem[] = overdueCasts.map((cast) => ({
    actionLabel: can("casts.remove") ? "Registrar retirada" : "Ver registro",
    category: "cast",
    createdAt: cast.expected_removal_at,
    href: `/gessos?registro=${cast.id}${can("casts.remove") ? "&acao=retirar" : ""}`,
    id: `cast-${cast.id}`,
    priority: "urgent",
    subtitle: `Passaporte ${cast.patient_passport} · ${castBodyRegionLabel(cast.body_region)} · ${castLateralityLabel(cast.laterality)} · previsão ${formatCastDate(cast.expected_removal_at)} · aplicado por ${cast.applied_by_name}`,
    title: cast.patient_name,
  }));

  let healthPlans: HealthPlanPending[] = [];
  if (canReviewHealthPlans && healthPlanRequests.length) {
    const attendanceIds = healthPlanRequests.map((request) => request.attendance_id);
    const attendanceFilter = attendanceIds.join(",");
    const planServiceId = planServices[0]?.id;
    const [attendances, planItems] = await Promise.all([
      adminRest<AttendancePending[]>(
        `attendances?select=id,patient_name,patient_passport,performed_by,created_at&id=in.(${attendanceFilter})&limit=250`,
      ),
      planServiceId
        ? adminRest<PlanAttendanceItem[]>(
          `attendance_items?select=attendance_id,line_total&attendance_id=in.(${attendanceFilter})&service_id=eq.${planServiceId}&limit=250`,
        )
        : Promise.resolve([]),
    ]);
    const attendanceById = new Map(attendances.map((attendance) => [attendance.id, attendance]));
    const planValueByAttendance = new Map(planItems.map((item) => [item.attendance_id, Number(item.line_total)]));
    healthPlans = healthPlanRequests.flatMap((request) => {
      const attendance = attendanceById.get(request.attendance_id);
      if (!attendance) return [];
      const seller = profileById.get(attendance.performed_by);
      return [{
        attendanceId: attendance.id,
        createdAt: request.requested_at,
        patientName: attendance.patient_name,
        patientPassport: attendance.patient_passport,
        planValue: planValueByAttendance.get(attendance.id) ?? 0,
        requestId: request.id,
        sellerIdentity: identityOf(seller),
        sellerName: seller?.display_name ?? "Profissional",
      }];
    });
  }

  const counts: PendingCounts = {
    absences: absenceItems.filter((item) => item.category === "absence").length,
    casts: castItems.length,
    discipline: discipline.length,
    healthPlans: healthPlans.length,
    justifications: absenceItems.filter((item) => item.category === "hour_justification").length,
    promotions: career.filter((item) => item.category === "career").length,
    recruitment: recruitment.length,
  };
  const total = Object.values(counts).reduce((sum, count) => sum + count, 0);

  return {
    absences: absenceItems,
    career,
    casts: castItems,
    counts,
    discipline,
    healthPlans,
    recruitment,
    total,
  };
}

export async function getDirectorPendingCount(permissionCodes?: string[]) {
  try {
    const can = (code: string) => !permissionCodes || permissionCodes.includes(code);
    const canObserve = can("sr.directors.view");
    const [applications, absences, justifications, reviews, promotions, healthPlans] = await Promise.all([
      canObserve || can("recruitment.manage")
        ? adminCount("recruitment_applications?select=id&status=in.(submitted,under_review,interview)")
        : Promise.resolve(0),
      canObserve || can("hr.absences.review")
        ? adminCount("rh_absence_requests?select=id&status=eq.pending")
        : Promise.resolve(0),
      canObserve || can("hr.justifications.review")
        ? adminCount("rh_hour_justifications?select=id&status=eq.pending")
        : Promise.resolve(0),
      canObserve || can("hr.discipline.manage") || can("hr.discipline.review")
        ? adminCount("rh_disciplinary_reviews?select=id&status=eq.pending")
        : Promise.resolve(0),
      canObserve || can("progression.review")
        ? adminCount("staff_promotion_reviews?select=id&status=eq.pending").catch(() => 0)
        : Promise.resolve(0),
      canObserve || can("healthplans.review")
        ? adminCount("patient_health_plan_requests?select=id&status=eq.pending").catch(() => 0)
        : Promise.resolve(0),
    ]);
    return applications + absences + justifications + reviews + promotions + healthPlans;
  } catch {
    return 0;
  }
}

function formatMinutes(total: number) {
  return `${Math.floor(total / 60)}h${String(total % 60).padStart(2, "0")}`;
}

function formatPeriod(start: string, end: string) {
  const format = (value: string) => value.split("-").reverse().join("/");
  return start === end ? format(start) : `${format(start)} a ${format(end)}`;
}

function formatMonth(value: string) {
  return new Intl.DateTimeFormat("pt-BR", { month: "long", timeZone: "UTC", year: "numeric" })
    .format(new Date(`${value.slice(0, 10)}T00:00:00.000Z`));
}

function truncate(value: string, maxLength: number) {
  const normalized = value.trim();
  return normalized.length <= maxLength ? normalized : `${normalized.slice(0, maxLength - 1)}…`;
}

function formatCastDate(value: string) {
  return new Intl.DateTimeFormat("pt-BR", {
    dateStyle: "short",
    timeStyle: "short",
    timeZone: "America/Sao_Paulo",
  }).format(new Date(value));
}
