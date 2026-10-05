import { adminHeaders } from "./admin-data";
import { getSupabaseAdminConfig } from "./supabase-server";

export type HrProfile = {
  display_name: string;
  passport: string;
  position_id: number | null;
  role_code: string;
  status: string;
  user_id: string;
};

export type HrHourSnapshot = {
  created_at: string;
  created_by: string;
  employee_id: string;
  id: number;
  note: string | null;
  reading_date: string;
  reference_month: string;
  total_minutes: number;
  updated_at: string;
  updated_by: string;
};

export type HrAbsenceRequest = {
  approval_effect: "record_only" | "weekly_exemption" | "weekly_adjustment" | null;
  cancelled_at: string | null;
  cancelled_by: string | null;
  employee_id: string;
  end_date: string;
  id: number;
  observation: string | null;
  reason: string;
  requested_at: string;
  review_note: string | null;
  reviewed_at: string | null;
  reviewed_by: string | null;
  start_date: string;
  status: "pending" | "approved" | "rejected" | "cancelled";
  updated_at: string;
};

export type HrLeaveWeekAdjustment = {
  approved_at: string;
  approved_by: string;
  deducted_minutes: number;
  employee_id: string;
  id: number;
  leave_request_id: number;
  updated_at: string;
  week_start: string;
};

export type HrWeekClosure = {
  closed_at: string | null;
  closed_by: string | null;
  id: number;
  started_at: string;
  started_by: string;
  status: "open" | "closed" | "reopened";
  updated_at: string;
  week_end: string;
  week_start: string;
};

export type HrWeekReopenEvent = {
  closure_id: number;
  id: number;
  reason: string;
  reopened_at: string;
  reopened_by: string;
};

export type HrWeeklyRecord = {
  absence_request_id: number | null;
  base_required_minutes: number;
  calculation_details: Record<string, unknown>;
  closed_at: string | null;
  closed_by: string | null;
  closure_id: number;
  closure_note: string | null;
  closure_status: "awaiting_justification" | "justification_pending" | "ready" | "closed";
  cycle_month: string;
  deficit_minutes: number;
  employee_id: string;
  id: number;
  justification_minutes: number;
  leave_deduction_minutes: number;
  remaining_deficit_minutes: number;
  required_minutes: number;
  status: "met" | "justified" | "deficit" | "warning_issued" | "warning_annulled";
  warning_suggestion_dismissed_at?: string | null;
  updated_at: string;
  week_end: string;
  week_start: string;
  worked_minutes: number;
};

export type HrHourJustification = {
  credited_minutes: number | null;
  deficit_minutes: number;
  employee_id: string;
  id: number;
  reason: string;
  review_note: string | null;
  reviewed_at: string | null;
  reviewed_by: string | null;
  status: "pending" | "approved" | "rejected";
  submitted_at: string;
  updated_at: string;
  weekly_record_id: number;
};

export type HrWarning = {
  annulled_at: string | null;
  annulled_by: string | null;
  annulment_reason: string | null;
  cycle_month: string;
  employee_id: string;
  id: number;
  impacts_progression: boolean;
  category: "weekly_goal" | "attendance" | "conduct" | "internal_rules" | "other";
  origin: "weekly_closure" | "manual";
  issued_at: string;
  issued_by: string;
  reason: string;
  progression_flagged_at: string | null;
  progression_flagged_by: string | null;
  progression_impact_note: string | null;
  sequence_in_cycle: number;
  status: "active" | "annulled";
  updated_at: string;
  weekly_record_id: number | null;
};

export type HrDisciplinaryReview = {
  cycle_month: string;
  decided_at: string | null;
  decided_by: string | null;
  decision_note: string | null;
  employee_id: string;
  id: number;
  status: "pending" | "suspension_maintained" | "dismissed" | "reactivated";
  triggered_at: string;
  triggered_by: string;
  triggered_by_warning_id: number;
  updated_at: string;
};

export type WeeklyProgress = {
  baseRequiredMinutes: number;
  baselineMinutes: number | null;
  complete: boolean;
  counterBaselineMinutes: number | null;
  counterTargetMinutes: number | null;
  cycleMonth: string;
  justificationMinutes: number;
  latestUpdate: string | null;
  leaveDeductionMinutes: number;
  monthlyAccumulated: number | null;
  monthlyTarget: number | null;
  remainingDeficitMinutes: number;
  requiredMinutes: number;
  status: "met" | "justified" | "awaiting_justification" | "justification_pending" | "deficit" | "awaiting_hours" | "in_progress";
  warningCount: number;
  weekEnd: string;
  weekStart: string;
  workedMinutes: number;
};

export type HrSelfData = {
  absences: HrAbsenceRequest[];
  hourJustifications: HrHourJustification[];
  leaveAdjustments: HrLeaveWeekAdjustment[];
  progress: WeeklyProgress;
  snapshots: HrHourSnapshot[];
  warnings: HrWarning[];
  weeklyRecords: HrWeeklyRecord[];
};

export type HrAdminData = {
  absences: HrAbsenceRequest[];
  closures: HrWeekClosure[];
  hourJustifications: HrHourJustification[];
  leaveAdjustments: HrLeaveWeekAdjustment[];
  profiles: HrProfile[];
  progressByEmployee: Record<string, WeeklyProgress>;
  reviews: HrDisciplinaryReview[];
  reopenEvents: HrWeekReopenEvent[];
  snapshots: HrHourSnapshot[];
  warnings: HrWarning[];
  weeklyRecords: HrWeeklyRecord[];
};

export const HR_HOUR_SNAPSHOT_SELECT = "id,employee_id,reading_date,reference_month,total_minutes,note,created_by,updated_by,created_at,updated_at";
const ABSENCE_SELECT = "id,employee_id,start_date,end_date,reason,observation,status,requested_at,reviewed_by,reviewed_at,review_note,approval_effect,cancelled_by,cancelled_at,updated_at";
const LEAVE_ADJUSTMENT_SELECT = "id,employee_id,leave_request_id,week_start,deducted_minutes,approved_by,approved_at,updated_at";
const CLOSURE_SELECT = "id,week_start,week_end,status,started_by,started_at,closed_by,closed_at,updated_at";
const WEEKLY_RECORD_SELECT = "id,employee_id,closure_id,week_start,week_end,cycle_month,base_required_minutes,leave_deduction_minutes,required_minutes,worked_minutes,justification_minutes,deficit_minutes,remaining_deficit_minutes,status,closure_status,absence_request_id,closed_by,closed_at,closure_note,calculation_details,updated_at";
const WEEKLY_RECORD_ADMIN_SELECT = `${WEEKLY_RECORD_SELECT},warning_suggestion_dismissed_at`;
const JUSTIFICATION_SELECT = "id,employee_id,weekly_record_id,deficit_minutes,reason,status,submitted_at,reviewed_by,reviewed_at,review_note,credited_minutes,updated_at";
const WARNING_SELECT = "id,employee_id,weekly_record_id,cycle_month,category,origin,reason,status,sequence_in_cycle,issued_by,issued_at,annulled_by,annulled_at,annulment_reason,impacts_progression,progression_flagged_by,progression_flagged_at,progression_impact_note,updated_at";
const DISCIPLINARY_REVIEW_SELECT = "id,employee_id,triggered_by_warning_id,cycle_month,status,triggered_by,triggered_at,decided_by,decided_at,decision_note,updated_at";
const REOPEN_EVENT_SELECT = "id,closure_id,reopened_by,reopened_at,reason";

export async function getHrSelfData(employeeId: string): Promise<HrSelfData> {
  const employeeFilter = encodeURIComponent(employeeId);
  const [snapshots, absences, leaveAdjustments, weeklyRecords, hourJustifications, warnings] = await Promise.all([
    getAdminRows<HrHourSnapshot>(`rh_hour_snapshots?select=${HR_HOUR_SNAPSHOT_SELECT}&employee_id=eq.${employeeFilter}&order=reading_date.asc`),
    getAdminRows<HrAbsenceRequest>(`rh_absence_requests?select=${ABSENCE_SELECT}&employee_id=eq.${employeeFilter}&order=requested_at.desc&limit=100`),
    getAdminRows<HrLeaveWeekAdjustment>(`rh_leave_week_adjustments?select=${LEAVE_ADJUSTMENT_SELECT}&employee_id=eq.${employeeFilter}&order=week_start.desc&limit=250`),
    getAdminRows<HrWeeklyRecord>(`rh_weekly_records?select=${WEEKLY_RECORD_SELECT}&employee_id=eq.${employeeFilter}&order=week_start.desc&limit=100`),
    getAdminRows<HrHourJustification>(`rh_hour_justifications?select=${JUSTIFICATION_SELECT}&employee_id=eq.${employeeFilter}&order=submitted_at.desc&limit=100`),
    getAdminRows<HrWarning>(`rh_warnings?select=${WARNING_SELECT}&employee_id=eq.${employeeFilter}&order=issued_at.desc&limit=100`),
  ]);

  return {
    absences,
    hourJustifications,
    leaveAdjustments,
    progress: buildWeeklyProgress(snapshots, leaveAdjustments, warnings, weeklyRecords),
    snapshots,
    warnings,
    weeklyRecords,
  };
}

export async function getHrWeeklyProgress(employeeId: string): Promise<WeeklyProgress> {
  const employeeFilter = encodeURIComponent(employeeId);
  const [snapshots, leaveAdjustments, weeklyRecords, warnings] = await Promise.all([
    getAdminRows<HrHourSnapshot>(`rh_hour_snapshots?select=${HR_HOUR_SNAPSHOT_SELECT}&employee_id=eq.${employeeFilter}&order=reading_date.asc`),
    getAdminRows<HrLeaveWeekAdjustment>(`rh_leave_week_adjustments?select=${LEAVE_ADJUSTMENT_SELECT}&employee_id=eq.${employeeFilter}&order=week_start.desc&limit=100`),
    getAdminRows<HrWeeklyRecord>(`rh_weekly_records?select=${WEEKLY_RECORD_SELECT}&employee_id=eq.${employeeFilter}&order=week_start.desc&limit=20`),
    getAdminRows<HrWarning>(`rh_warnings?select=${WARNING_SELECT}&employee_id=eq.${employeeFilter}&order=issued_at.desc&limit=100`),
  ]);
  return buildWeeklyProgress(snapshots, leaveAdjustments, warnings, weeklyRecords);
}

export async function getHrAdminData(permissionCodes?: readonly string[]): Promise<HrAdminData> {
  const can = (code: string) => !permissionCodes || permissionCodes.includes(code);
  const canViewReports = can("hr.reports.view");
  const canManageHours = ["hr.hours.manage", "hr.hours.import", "hr.weeks.close", "hr.weeks.reopen"].some(can);
  const canReviewAbsences = can("hr.absences.review");
  const canReviewJustifications = can("hr.justifications.review");
  const canManageDiscipline = ["hr.discipline.manage", "hr.discipline.review", "hr.warnings.issue", "hr.warnings.annul", "hr.warnings.progression"].some(can);
  const needsTeamProgress = can("hr.team.view") || canManageHours || canViewReports;
  const [profiles, staffPositions, rawSnapshots, rawAbsences, rawLeaveAdjustments, closures, rawWeeklyRecords, rawHourJustifications, rawWarnings, rawReviews, reopenEvents] = await Promise.all([
    getAdminRows<HrProfile>("profiles?select=user_id,passport,display_name,position_id,role_code,status&order=display_name.asc"),
    getAdminRows<{ id: number; official: boolean }>("staff_positions?select=id,official"),
    needsTeamProgress || canViewReports ? getAdminRows<HrHourSnapshot>(`rh_hour_snapshots?select=${HR_HOUR_SNAPSHOT_SELECT}&order=reading_date.desc&limit=1000`) : Promise.resolve([]),
    canReviewAbsences || canViewReports ? getAdminRows<HrAbsenceRequest>(`rh_absence_requests?select=${ABSENCE_SELECT}&order=requested_at.desc&limit=500`) : Promise.resolve([]),
    needsTeamProgress || canReviewAbsences || canReviewJustifications || canViewReports ? getAdminRows<HrLeaveWeekAdjustment>(`rh_leave_week_adjustments?select=${LEAVE_ADJUSTMENT_SELECT}&order=week_start.desc&limit=1000`) : Promise.resolve([]),
    canManageHours || canViewReports ? getAdminRows<HrWeekClosure>(`rh_week_closures?select=${CLOSURE_SELECT}&order=week_start.desc&limit=250`) : Promise.resolve([]),
    needsTeamProgress || canReviewJustifications || canManageDiscipline || canViewReports ? getAdminRows<HrWeeklyRecord>(`rh_weekly_records?select=${WEEKLY_RECORD_ADMIN_SELECT}&order=week_start.desc&limit=500`) : Promise.resolve([]),
    canReviewJustifications || canViewReports ? getAdminRows<HrHourJustification>(`rh_hour_justifications?select=${JUSTIFICATION_SELECT}&order=submitted_at.desc&limit=500`) : Promise.resolve([]),
    needsTeamProgress || canManageDiscipline || canViewReports ? getAdminRows<HrWarning>(`rh_warnings?select=${WARNING_SELECT}&order=issued_at.desc&limit=500`) : Promise.resolve([]),
    canManageDiscipline || canViewReports ? getAdminRows<HrDisciplinaryReview>(`rh_disciplinary_reviews?select=${DISCIPLINARY_REVIEW_SELECT}&order=triggered_at.desc&limit=250`) : Promise.resolve([]),
    canManageHours || canViewReports ? getAdminRows<HrWeekReopenEvent>(`rh_week_reopen_events?select=${REOPEN_EVENT_SELECT}&order=reopened_at.desc&limit=250`) : Promise.resolve([]),
  ]);

  const officialPositionIds = new Set(staffPositions.filter((position) => position.official).map((position) => position.id));
  const workforceProfiles = profiles.filter((profile) => profile.position_id !== null && officialPositionIds.has(profile.position_id));
  const workforceIds = new Set(workforceProfiles.map((profile) => profile.user_id));
  const workforceRows = <T extends { employee_id: string }>(rows: T[]) => rows.filter((row) => workforceIds.has(row.employee_id));
  const snapshots = workforceRows(rawSnapshots);
  const absences = workforceRows(rawAbsences);
  const leaveAdjustments = workforceRows(rawLeaveAdjustments);
  const weeklyRecords = workforceRows(rawWeeklyRecords);
  const hourJustifications = workforceRows(rawHourJustifications);
  const warnings = workforceRows(rawWarnings);
  const reviews = workforceRows(rawReviews);

  const snapshotsByEmployee = groupByEmployee(snapshots);
  const adjustmentsByEmployee = groupByEmployee(leaveAdjustments);
  const warningsByEmployee = groupByEmployee(warnings);
  const recordsByEmployee = groupByEmployee(weeklyRecords);
  const progressByEmployee = Object.fromEntries(
    workforceProfiles
      .filter((profile) => profile.role_code !== "diretor_geral")
      .map((profile) => [
        profile.user_id,
        buildWeeklyProgress(
          snapshotsByEmployee.get(profile.user_id) ?? [],
          adjustmentsByEmployee.get(profile.user_id) ?? [],
          warningsByEmployee.get(profile.user_id) ?? [],
          recordsByEmployee.get(profile.user_id) ?? [],
        ),
      ]),
  );

  return { absences, closures, hourJustifications, leaveAdjustments, profiles: workforceProfiles, progressByEmployee, reopenEvents, reviews, snapshots, warnings, weeklyRecords };
}

function groupByEmployee<T extends { employee_id: string }>(rows: T[]) {
  const grouped = new Map<string, T[]>();
  rows.forEach((row) => {
    const current = grouped.get(row.employee_id);
    if (current) current.push(row);
    else grouped.set(row.employee_id, [row]);
  });
  return grouped;
}

export async function getDirectorHrNotificationCount(): Promise<number> {
  try {
    const [absences, reviews, justifications] = await Promise.all([
      getAdminRows<{ id: number }>("rh_absence_requests?select=id&status=eq.pending&limit=100"),
      getAdminRows<{ id: number }>("rh_disciplinary_reviews?select=id&status=eq.pending&limit=100"),
      getAdminRows<{ id: number }>("rh_hour_justifications?select=id&status=eq.pending&limit=100"),
    ]);
    return absences.length + justifications.length + reviews.length;
  } catch {
    return 0;
  }
}

export function buildWeeklyProgress(
  snapshots: HrHourSnapshot[],
  leaveAdjustments: HrLeaveWeekAdjustment[],
  warnings: HrWarning[],
  weeklyRecords: HrWeeklyRecord[] = [],
  today = todayInSaoPaulo(),
): WeeklyProgress {
  const { weekStart, weekEnd } = weekRange(today);
  const cycleMonth = monthStart(weekEnd);
  const calculation = calculateWorkedMinutes(snapshots, weekStart, minIso(today, weekEnd));
  const record = weeklyRecords.find((item) => item.week_start === weekStart) ?? null;
  const leaveDeductionMinutes = Math.min(600, leaveAdjustments
    .filter((adjustment) => adjustment.week_start === weekStart)
    .reduce((total, adjustment) => total + adjustment.deducted_minutes, 0));
  const requiredMinutes = record?.required_minutes ?? Math.max(0, 600 - leaveDeductionMinutes);
  const workedMinutes = record?.worked_minutes ?? calculation.workedMinutes;
  const justificationMinutes = record?.justification_minutes ?? 0;
  const remainingDeficitMinutes = record?.remaining_deficit_minutes ?? Math.max(0, requiredMinutes - workedMinutes);
  const warningCount = warnings.filter(
    (warning) => warning.cycle_month === cycleMonth && warning.status === "active",
  ).length;
  const monthlySnapshots = snapshots
    .filter((snapshot) => snapshot.reference_month === monthStart(today) && snapshot.reading_date <= today)
    .sort(compareSnapshots);
  const latestMonthly = monthlySnapshots.at(-1) ?? null;
  const counterObjective = calculateCounterObjective(snapshots, weekStart, today, requiredMinutes, calculation.baselineMinutes);
  let status: WeeklyProgress["status"] = "in_progress";
  if (record?.closure_status === "justification_pending") status = "justification_pending";
  else if (record?.closure_status === "awaiting_justification") status = "awaiting_justification";
  else if (record && remainingDeficitMinutes > 0) status = "deficit";
  else if (record?.status === "justified") status = "justified";
  else if (workedMinutes >= requiredMinutes) status = "met";
  else if (!calculation.complete) status = "awaiting_hours";

  return {
    baseRequiredMinutes: 600,
    baselineMinutes: calculation.baselineMinutes,
    complete: calculation.complete,
    counterBaselineMinutes: counterObjective.baselineMinutes,
    counterTargetMinutes: counterObjective.targetMinutes,
    cycleMonth,
    justificationMinutes,
    latestUpdate: latestMonthly?.updated_at ?? calculation.latestUpdate,
    leaveDeductionMinutes,
    monthlyAccumulated: latestMonthly?.total_minutes ?? null,
    monthlyTarget: counterObjective.targetMinutes,
    remainingDeficitMinutes,
    requiredMinutes,
    status,
    warningCount,
    weekEnd,
    weekStart,
    workedMinutes,
  };
}

export function calculateCounterObjective(
  snapshots: HrHourSnapshot[],
  weekStart: string,
  today: string,
  requiredMinutes: number,
  weekBaselineMinutes: number | null,
) {
  const currentMonth = monthStart(today);
  if (monthStart(weekStart) === currentMonth) {
    return {
      baselineMinutes: weekBaselineMinutes,
      targetMinutes: weekBaselineMinutes === null ? null : weekBaselineMinutes + requiredMinutes,
    };
  }

  const previousSegment = calculateWorkedMinutes(snapshots, weekStart, addDays(currentMonth, -1));
  if (!previousSegment.complete) return { baselineMinutes: 0, targetMinutes: null };
  return {
    baselineMinutes: 0,
    targetMinutes: Math.max(0, requiredMinutes - previousSegment.workedMinutes),
  };
}

export function calculateWorkedMinutes(
  snapshots: HrHourSnapshot[],
  weekStart: string,
  throughDate: string,
) {
  const weekEnd = addDays(weekStart, 6);
  const effectiveEnd = minIso(throughDate, weekEnd);
  const months = monthsBetween(weekStart, effectiveEnd);
  let workedMinutes = 0;
  let complete = true;
  let latestUpdate: string | null = null;
  let baselineMinutes: number | null = null;

  for (const referenceMonth of months) {
    const periodStart = maxIso(weekStart, referenceMonth);
    const periodEnd = minIso(effectiveEnd, addDays(addMonths(referenceMonth, 1), -1));
    const monthRows = snapshots
      .filter((snapshot) => snapshot.reference_month === referenceMonth)
      .sort(compareSnapshots);
    const endSnapshot = monthRows.filter((snapshot) => snapshot.reading_date <= periodEnd).at(-1) ?? null;
    const startsWithMonth = periodStart === referenceMonth;
    const baselineDate = addDays(periodStart, -1);
    const baselineSnapshot = startsWithMonth
      ? null
      : monthRows.find((snapshot) => snapshot.reading_date === baselineDate) ?? null;

    if (!endSnapshot) {
      complete = false;
      continue;
    }
    if (endSnapshot.reading_date !== periodEnd) complete = false;
    if (!startsWithMonth && !baselineSnapshot) {
      complete = false;
      continue;
    }

    const baseline = baselineSnapshot?.total_minutes ?? 0;
    if (referenceMonth === monthStart(weekStart)) baselineMinutes = baseline;
    workedMinutes += Math.max(0, endSnapshot.total_minutes - baseline);
    if (!latestUpdate || endSnapshot.updated_at > latestUpdate) latestUpdate = endSnapshot.updated_at;
  }

  return { baselineMinutes, complete, latestUpdate, workedMinutes };
}

export function todayInSaoPaulo() {
  const parts = new Intl.DateTimeFormat("en-US", {
    day: "2-digit",
    month: "2-digit",
    timeZone: "America/Sao_Paulo",
    year: "numeric",
  }).formatToParts(new Date());
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}`;
}

export function weekRange(date: string) {
  const parsed = parseIsoDate(date);
  const offset = (parsed.getUTCDay() + 6) % 7;
  const weekStart = addDays(date, -offset);
  return { weekEnd: addDays(weekStart, 6), weekStart };
}

export function monthStart(date: string) {
  return `${date.slice(0, 7)}-01`;
}

export function addDays(date: string, days: number) {
  const parsed = parseIsoDate(date);
  parsed.setUTCDate(parsed.getUTCDate() + days);
  return parsed.toISOString().slice(0, 10);
}

export function addMonths(date: string, months: number) {
  const parsed = parseIsoDate(monthStart(date));
  parsed.setUTCMonth(parsed.getUTCMonth() + months);
  return parsed.toISOString().slice(0, 10);
}

export function parseDuration(value: string) {
  const match = value.trim().match(/^([0-9]{1,3}):([0-5][0-9])$/);
  if (!match) throw new Error("Use o formato de horas 00:00.");
  const minutes = Number(match[1]) * 60 + Number(match[2]);
  if (minutes > 60000) throw new Error("O total informado é muito alto.");
  return minutes;
}

export function formatMinutes(total: number | null) {
  if (total === null || !Number.isFinite(total)) return "—";
  const safe = Math.max(0, Math.round(total));
  return `${Math.floor(safe / 60)}h${String(safe % 60).padStart(2, "0")}`;
}

function monthsBetween(start: string, end: string) {
  const months: string[] = [];
  let cursor = monthStart(start);
  const last = monthStart(end);
  while (cursor <= last) {
    months.push(cursor);
    cursor = addMonths(cursor, 1);
  }
  return months;
}

function compareSnapshots(a: HrHourSnapshot, b: HrHourSnapshot) {
  return a.reading_date.localeCompare(b.reading_date) || a.updated_at.localeCompare(b.updated_at);
}

function parseIsoDate(value: string) {
  return new Date(`${value}T00:00:00.000Z`);
}

function minIso(a: string, b: string) {
  return a < b ? a : b;
}

function maxIso(a: string, b: string) {
  return a > b ? a : b;
}

async function getAdminRows<T>(path: string): Promise<T[]> {
  const { url, serviceRoleKey } = getSupabaseAdminConfig();
  const response = await fetch(`${url}/rest/v1/${path}`, {
    headers: adminHeaders(serviceRoleKey),
    cache: "no-store",
  });
  if (!response.ok) throw new Error("Não foi possível consultar os dados do RH.");
  return (await response.json()) as T[];
}
