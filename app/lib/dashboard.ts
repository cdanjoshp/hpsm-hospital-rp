import {
  buildWeeklyProgress,
  type HrHourSnapshot,
  type HrLeaveWeekAdjustment,
  type HrWarning,
  type HrWeeklyRecord,
  type WeeklyProgress,
} from "./hr";
import { callSupabaseUserRpc } from "./supabase-user";
import type { DashboardPreference } from "./dashboard-customization";

export type DashboardAnnouncement = {
  action_url: string | null;
  author_name: string;
  created_at: string;
  id: number;
  priority: "normal" | "important" | "urgent";
  read_at: string | null;
  title: string;
};

export type DashboardAttentionItem = {
  count: number;
  href: string;
  kind: "absence" | "career" | "cast" | "discipline" | "health_plan" | "hour_justification" | "personal_absence" | "personal_hours" | "recruitment";
  label: string;
  tone: "important" | "normal" | "urgent";
};

export type DashboardCareer = {
  current_position: {
    advancement_mode: string | null;
    id: number | null;
    level: number | null;
    name: string;
  } | null;
  progression: {
    attendance_count?: number;
    blocked?: boolean;
    eligible?: boolean;
    elapsed_days?: number;
    flagged_warning_count?: number;
    next_position_id?: number;
    next_position_name?: string;
    reason?: string;
    required_attendances?: number;
    required_days?: number;
    required_worked_minutes?: number;
    worked_minutes?: number;
  };
};

export type DashboardHospital = null | {
  active_professionals: number;
  attendance_count?: number;
  below_professionals: number;
  financial_access: boolean;
  fully_excused_professionals: number;
  hours_minutes: number;
  met_professionals: number;
  pending_count: number;
  recruitment_pending?: number;
  total_amount?: number;
};

export type ProfessionalDashboardData = {
  announcements: DashboardAnnouncement[];
  attention: { items: DashboardAttentionItem[]; total: number };
  career: DashboardCareer;
  hospital: DashboardHospital;
  period: { end: string; start: string };
  production: { attendance_count: number; item_count: number; total_amount: number };
  preferences: DashboardPreference | null;
  weeklyProgress: WeeklyProgress | null;
};

type DashboardPayload = Omit<ProfessionalDashboardData, "weeklyProgress"> & {
  weekly_inputs: null | {
    leaveAdjustments: HrLeaveWeekAdjustment[];
    snapshots: HrHourSnapshot[];
    warnings: HrWarning[];
    weeklyRecords: HrWeeklyRecord[];
  };
};

export async function getProfessionalDashboard(accessToken: string): Promise<ProfessionalDashboardData> {
  const payload = await callSupabaseUserRpc<DashboardPayload>(accessToken, "hpsm_dashboard_bundle");
  return {
    announcements: payload.announcements ?? [],
    attention: payload.attention ?? { items: [], total: 0 },
    career: payload.career ?? { current_position: null, progression: {} },
    hospital: payload.hospital ?? null,
    period: payload.period,
    preferences: payload.preferences ?? null,
    production: payload.production ?? { attendance_count: 0, item_count: 0, total_amount: 0 },
    weeklyProgress: payload.weekly_inputs
      ? buildWeeklyProgress(
        payload.weekly_inputs.snapshots ?? [],
        payload.weekly_inputs.leaveAdjustments ?? [],
        payload.weekly_inputs.warnings ?? [],
        payload.weekly_inputs.weeklyRecords ?? [],
      )
      : null,
  };
}
