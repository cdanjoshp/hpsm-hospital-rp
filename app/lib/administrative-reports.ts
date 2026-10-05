import { callSupabaseUserRpc } from "./supabase-user";

export type ReportPeriod = { end: string; start: string };
export type ReportPosition = { id: number; name: string };
export type ReportStaffOption = {
  id: string;
  name: string;
  passport: string;
  position: string;
  position_id: number | null;
  status: "active" | "suspended";
};

export type ReportOverview = {
  active_professionals: number;
  attendance_count?: number;
  below_professionals: number;
  financial_access: boolean;
  fully_excused_professionals: number;
  hours_minutes: number;
  met_professionals: number;
  participating_professionals?: number;
  period: ReportPeriod;
  ticket_average?: number;
  total_amount?: number;
  unique_patients?: number;
};

export type ReportHrRow = {
  active_warnings: number;
  base_target_minutes: number;
  below_weeks: number;
  difference_minutes: number;
  effective_target_minutes: number;
  excused_weeks: number;
  goal_status: "below" | "fully_excused" | "met" | "no_data";
  has_absence: boolean;
  has_justification: boolean;
  id: string;
  leave_minutes: number;
  met_weeks: number;
  name: string;
  passport: string;
  position: string;
  position_id: number | null;
  profile_status: "active" | "suspended";
  recorded_weeks: number;
  worked_minutes: number;
};

export type ReportHrData = {
  items: ReportHrRow[];
  page: number;
  page_size: number;
  positions: ReportPosition[];
  total: number;
};

export type ReportProductionRow = {
  attendance_count: number;
  employee_id: string;
  item_count: number;
  name: string;
  passport: string;
  position: string;
  position_id: number | null;
  ticket_average: number;
  total_amount: number;
};

export type ReportFinancialData = {
  benefits: Array<{
    attendance_count: number;
    code: string;
    discount_amount: number;
    name: string;
    total_amount: number;
  }>;
  partnerships: Array<{
    attendance_count: number;
    discount_amount: number;
    name: string;
    partnership_id: number | null;
    total_amount: number;
  }>;
  page: number;
  page_size: number;
  positions: ReportPosition[];
  production: ReportProductionRow[];
  production_total: number;
  summary: {
    attendance_count: number;
    item_count: number;
    professional_count: number;
    ticket_average: number;
    total_amount: number;
    unique_patients: number;
  };
  top_items: Array<{
    category: string;
    name: string;
    quantity: number;
    service_id: number;
    total_amount: number;
  }>;
};

export type ReportTeamData = {
  absences: Array<{
    deducted_minutes: number;
    employee_id: string;
    end_date: string;
    name: string;
    passport: string;
    position: string;
    start_date: string;
  }>;
  admissions: Array<{
    date: string;
    employee_id: string;
    name: string;
    passport: string;
    position: string;
  }>;
  promotions: Array<{
    date: string;
    employee_id: string;
    from_position: string;
    name: string;
    passport: string;
    to_position: string;
  }>;
  summary: {
    active_professionals: number;
    admissions: number;
    approved_absences: number;
    promotions: number;
    suspensions: number;
  };
};

export type ReportIndividualData = {
  career: {
    completed_courses: number | null;
    promotions: Array<{ date: string; from_position: string; to_position: string }>;
  };
  financial_access: boolean;
  found: boolean;
  journey: {
    base_target_minutes: number;
    below_weeks: number;
    difference_minutes: number;
    effective_target_minutes: number;
    excused_weeks: number;
    leave_minutes: number;
    met_weeks: number;
    recorded_weeks: number;
    worked_minutes: number;
  };
  period: ReportPeriod;
  production: null | {
    attendance_count: number;
    item_count: number;
    ticket_average: number;
    total_amount: number;
  };
  profile: null | {
    id: string;
    name: string;
    passport: string;
    position: string;
    position_id: number | null;
    status: "active" | "suspended";
  };
  rh: { absences: number; active_warnings: number; justifications: number };
};

export type ReportFilters = {
  direction?: string;
  employeeId?: string | null;
  end: string;
  page?: number;
  pageSize?: number;
  positionId?: number | null;
  search?: string;
  sort?: string;
  start: string;
  status?: string;
};

export async function getReportOverview(accessToken: string, filters: ReportFilters) {
  return callSupabaseUserRpc<ReportOverview>(accessToken, "hpsm_report_overview", {
    p_end_date: filters.end,
    p_start_date: filters.start,
  });
}

export async function getReportHr(accessToken: string, filters: ReportFilters) {
  return callSupabaseUserRpc<ReportHrData>(accessToken, "hpsm_report_hr", {
    p_direction: filters.direction ?? "asc",
    p_end_date: filters.end,
    p_page: filters.page ?? 1,
    p_page_size: filters.pageSize ?? 25,
    p_position_id: filters.positionId ?? null,
    p_search: filters.search ?? "",
    p_sort: filters.sort ?? "name",
    p_start_date: filters.start,
    p_status: filters.status ?? "active",
  });
}

export async function getReportFinancial(accessToken: string, filters: ReportFilters) {
  const [financial, partnerships] = await Promise.all([callSupabaseUserRpc<Omit<ReportFinancialData, "partnerships">>(accessToken, "hpsm_report_financial", {
    p_direction: filters.direction ?? "desc",
    p_employee_id: filters.employeeId ?? null,
    p_end_date: filters.end,
    p_page: filters.page ?? 1,
    p_page_size: filters.pageSize ?? 25,
    p_position_id: filters.positionId ?? null,
    p_sort: filters.sort ?? "value",
    p_start_date: filters.start,
  }), callSupabaseUserRpc<ReportFinancialData["partnerships"]>(accessToken, "hpsm_report_partnerships", {
    p_end_date: filters.end,
    p_start_date: filters.start,
  })]);
  return { ...financial, partnerships };
}

export async function getReportTeam(accessToken: string, filters: ReportFilters) {
  return callSupabaseUserRpc<ReportTeamData>(accessToken, "hpsm_report_team", {
    p_end_date: filters.end,
    p_start_date: filters.start,
  });
}

export async function getReportIndividual(accessToken: string, filters: ReportFilters) {
  return callSupabaseUserRpc<ReportIndividualData>(accessToken, "hpsm_report_individual", {
    p_employee_id: filters.employeeId,
    p_end_date: filters.end,
    p_start_date: filters.start,
  });
}

export async function searchReportStaff(accessToken: string, query: string) {
  return callSupabaseUserRpc<{ items: ReportStaffOption[] }>(accessToken, "hpsm_report_staff_search", {
    p_limit: 8,
    p_query: query,
  });
}

export function currentSaoPauloDate() {
  const parts = new Intl.DateTimeFormat("en-CA", {
    day: "2-digit",
    month: "2-digit",
    timeZone: "America/Sao_Paulo",
    year: "numeric",
  }).formatToParts(new Date());
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}`;
}
