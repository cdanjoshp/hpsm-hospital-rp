import type { PlanCode } from "./benefit-plans";

export type AttendanceLimitGroup = "no_benefit" | "police" | "partner_plan";

export const ATTENDANCE_ITEM_LIMITS = {
  kitmed: { no_benefit: 2, police: 2, partner_plan: 2 },
  bandagem: { no_benefit: 5, police: 5, partner_plan: 5 },
  atadura: { no_benefit: 10, police: 20, partner_plan: 15 },
  analgesico: { no_benefit: 10, police: 10, partner_plan: 15 },
  ritmoneury: { no_benefit: 5, police: 5, partner_plan: 5 },
  sinkalmy: { no_benefit: 5, police: 5, partner_plan: 5 },
  adrenalina: { no_benefit: 3, police: 5, partner_plan: 5 },
} as const;

export type ControlledAttendanceItemCode = keyof typeof ATTENDANCE_ITEM_LIMITS;

export function attendanceLimitGroup(benefitCode: PlanCode | null): AttendanceLimitGroup {
  if (benefitCode === "policiais_arcanjos") return "police";
  if (benefitCode === "parceiros_hp" || benefitCode === "plano_saude") return "partner_plan";
  return "no_benefit";
}

export function getAttendanceItemLimit(serviceCode: string, benefitCode: PlanCode | null): number | null {
  if (!isControlledAttendanceItemCode(serviceCode)) return null;
  return ATTENDANCE_ITEM_LIMITS[serviceCode][attendanceLimitGroup(benefitCode)];
}

export function isControlledAttendanceItemCode(serviceCode: string): serviceCode is ControlledAttendanceItemCode {
  return Object.prototype.hasOwnProperty.call(ATTENDANCE_ITEM_LIMITS, serviceCode);
}
