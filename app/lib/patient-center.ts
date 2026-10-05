import type { Patient, PatientHealthPlan, PlanCode } from "./operational-data";
import type { ClinicalExamStatus } from "./exam-status";
import type { PatientActiveClinicalCast } from "./cast-types";
import { getPatientActiveClinicalCasts } from "./casts";
import { authenticatedHeaders } from "./operational-data";
import { getSupabaseConfig } from "./supabase-server";
import { normalizePatientSearch } from "./passport";
import { callSupabaseUserRpc } from "./supabase-user";

export type PatientPlanStatus = PatientHealthPlan["status"];
export type PatientPlanFilter = "all" | PatientPlanStatus;

export type PatientCardFilter = "all" | "active" | "expired" | "partner" | "police" | "none";
export type PatientCard = {
  id: number;
  passport: string;
  name: string;
  allergies: string | null;
  benefit: Exclude<PatientCardFilter, "all">;
  alerts: {
    casts?: { count: number; latest: { id: number; location: string; appliedAt: string; expectedRemovalAt: string } };
    hospitalization?: { id: number; bed: string; reason: string; admittedAt: string };
    appointments?: { count: number; next: { id: number; reason: string; scheduledStart: string; status: "scheduled" | "confirmed" } };
  };
};
export type PatientCardPage = { page: number; pageSize: number; patients: PatientCard[]; total: number };

export async function getPatientCardPage(
  accessToken: string,
  options: { filter?: PatientCardFilter; page?: number; pageSize?: number; search?: string } = {},
): Promise<PatientCardPage> {
  return callSupabaseUserRpc<PatientCardPage>(accessToken, "hpsm_patient_card_page", {
    p_filter: options.filter ?? "all",
    p_page: options.page ?? 1,
    p_page_size: options.pageSize ?? 20,
    p_search: options.search ?? "",
  });
}

export async function getQuickActionPatient(accessToken: string, passport: string | undefined): Promise<Patient | null> {
  if (!passport || !/^[0-9]{4}$/.test(passport)) return null;
  const patients = await callSupabaseUserRpc<Patient[]>(accessToken, "hpsm_patient_quick_lookup", {
    p_passport: passport,
    p_limit: 1,
  });
  return patients.find((patient) => patient.passport === passport) ?? null;
}

export type PatientDirectoryEntry = Patient & {
  last_attendance_at: string | null;
};

type PatientDirectoryRow = {
  allergies: string | null;
  birth_date: string | null;
  created_at: string;
  emergency_contact_name: string | null;
  emergency_contact_phone: string | null;
  id: number;
  last_attendance_at: string | null;
  name: string;
  passport: string;
  pending_request_id: number | null;
  pending_requested_at: string | null;
  phone: string | null;
  plan_activated_at: string | null;
  plan_authorized_by: string | null;
  plan_authorized_by_name: string | null;
  plan_status: PatientPlanStatus;
  plan_valid_until: string | null;
  updated_at: string;
};

export type PatientDirectoryPage = {
  page: number;
  pageSize: number;
  patients: PatientDirectoryEntry[];
  total: number;
};

export type PatientSummary = {
  active_casts: PatientActiveClinicalCast[];
  last_attendance_at: string | null;
  recent_procedures: Array<{
    attendance_id: number;
    category: string;
    date: string;
    id: number;
    name: string;
  }>;
  total_attendances: number;
  total_purchases: number;
};

export type PatientActivityItem = {
  category: string;
  code: string;
  discount_amount: number;
  discount_percent: number;
  id: number;
  line_total: number;
  quantity: number;
  service_id: number;
  service_name: string;
  source: "attendance" | "exam";
  unit_price: number;
};

export type PatientActivityRecord = {
  created_at: string;
  discount: number;
  id: number;
  items: PatientActivityItem[];
  notes: string | null;
  patient_name: string;
  patient_passport: string;
  plan_code: PlanCode | null;
  plan_name: string | null;
  professional_name: string;
  professional_passport: string;
  professional_position: string;
  status: "completed" | "cancelled";
  subtotal: number;
  total: number;
};

export type PatientActivityPage = {
  availableMonths: Array<{ count: number; month: string; total: number }>;
  monthlyCount: number;
  monthlyTotal: number;
  page: number;
  pageSize: number;
  records: PatientActivityRecord[];
  selectedMonth: string;
  total: number;
};

export type PatientPlanHistoryRecord = {
  administrative_action: "expiry_adjustment" | "grant" | null;
  attendance_id: number | null;
  attendance_total: number | null;
  authorized_by_name: string | null;
  coverage_end: string | null;
  coverage_start: string | null;
  id: number;
  origin: "administrative" | "sale";
  plan_value: number;
  rejection_reason: string | null;
  requested_at: string;
  reviewed_at: string | null;
  seller_name: string | null;
  seller_passport: string | null;
  status: "approved" | "pending" | "rejected";
};

export type PatientPlanHistoryPage = {
  page: number;
  pageSize: number;
  records: PatientPlanHistoryRecord[];
  total: number;
};

export type PatientPartnershipPage = {
  items: Array<{ id: number; linked_at: string; name: string; status: "active" | "inactive" }>;
};

export const PATIENT_LEGACY_RECORD_TYPES = ["registration", "attendance", "exam", "vaccine", "appointment", "health_plan"] as const;

export type PatientLegacyRecordType = typeof PATIENT_LEGACY_RECORD_TYPES[number];

export type PatientLegacyHistoryItem = {
  details: Record<string, unknown>;
  id: number;
  occurred_at: string | null;
  occurred_precision: "date" | "datetime" | "unknown";
  professional_name: string | null;
  professional_registration: string | null;
  record_type: PatientLegacyRecordType;
  reference_links: unknown[];
  status: string | null;
  summary: string | null;
  title: string;
};

export type PatientLegacyHistoryPage = {
  items: PatientLegacyHistoryItem[];
  page: number;
  pageSize: number;
  source: "HP Norte";
  sourceProfiles: number;
  summary: Partial<Record<PatientLegacyRecordType, number>>;
  total: number;
};

export type PatientTimelineEvent = {
  cast_id: number | null;
  date: string;
  description: string;
  exam_id: number | null;
  id: string;
  title: string;
  type: string;
};

export type PatientRecord = {
  id: string;
  date: string;
  category: "attendance" | "procedure" | "purchase" | "exam" | "cast" | "hospitalization" | "plan" | "certificate" | "prescription" | "record";
  title: string;
  description: string;
  resource_id: string;
  resource_kind: string;
  status: string;
  document: boolean;
};
export type PatientRecordPage = { items: PatientRecord[]; page: number; pageSize: number; total: number };
export type PatientRecordFilter = PatientRecord["category"] | "all";
export type PatientActiveHospitalization = { id: number; admitted_at: string; reason: string | null };
export async function getPatientActiveHospitalization(accessToken: string, patientId: number): Promise<PatientActiveHospitalization | null> {
  return callPatientRpc<PatientActiveHospitalization | null>(accessToken, "hpsm_patient_active_hospitalization", { p_patient_id: patientId });
}

export async function getPatientRecordPage(accessToken: string, patientId: number, mode: "timeline" | "documents", filter: PatientRecordFilter, page = 1, pageSize = 10): Promise<PatientRecordPage> {
  const safePage = positiveInteger(page, 1);
  const safeSize = Math.min(50, positiveInteger(pageSize, 10));
  const payload = await callPatientRpc<{ items: PatientRecord[]; total: number }>(accessToken, "hpsm_patient_record_page", {
    p_patient_id: patientId, p_mode: mode, p_filter: filter, p_limit: safeSize, p_offset: (safePage - 1) * safeSize,
  });
  return { items: payload.items ?? [], total: Number(payload.total ?? 0), page: safePage, pageSize: safeSize };
}

export type PatientClinicalExamListItem = {
  category_id: number;
  category_name: string;
  completed_at: string | null;
  exam_type_id: number;
  exam_type_name: string;
  id: number;
  image_count: number;
  indication: string;
  patient_id: number;
  relevant_at: string;
  requested_at: string;
  responsible_name: string;
  responsible_position: string | null;
  responsible_professional_id: string;
  reviewer_name: string | null;
  reviewer_position: string | null;
  status: ClinicalExamStatus;
};

export type PatientClinicalExamPage = {
  items: PatientClinicalExamListItem[];
  page: number;
  pageSize: number;
  summary: { awaitingReview: number; completed: number; total: number };
  total: number;
};

export type PatientClinicalExamFilters = {
  categoryId?: number;
  dateFrom?: string;
  dateTo?: string;
  examTypeId?: number;
  status?: ClinicalExamStatus;
};

export async function getPatientDirectoryPage(
  accessToken: string,
  options: { filter?: PatientPlanFilter; page?: number; pageSize?: number; search?: string } = {},
): Promise<PatientDirectoryPage> {
  const page = positiveInteger(options.page, 1);
  const pageSize = Math.min(50, positiveInteger(options.pageSize, 20));
  const filter = validFilter(options.filter) ? options.filter : "all";
  const search = normalizePatientSearch(cleanSearch(options.search));
  const offset = (page - 1) * pageSize;
  const { url } = getSupabaseConfig();
  const endpoint = new URL(`${url}/rest/v1/patient_directory`);
  endpoint.searchParams.set("select", "id,passport,name,phone,birth_date,emergency_contact_name,emergency_contact_phone,allergies,created_at,updated_at,last_attendance_at,plan_status,plan_activated_at,plan_valid_until,plan_authorized_by,plan_authorized_by_name,pending_request_id,pending_requested_at");
  endpoint.searchParams.set("order", "passport.asc,name.asc");
  endpoint.searchParams.set("limit", String(pageSize));
  endpoint.searchParams.set("offset", String(offset));
  if (filter !== "all") endpoint.searchParams.set("plan_status", `eq.${filter}`);
  if (search) {
    if (/^[0-9]{4}$/.test(search)) endpoint.searchParams.set("passport", `eq.${search}`);
    else endpoint.searchParams.set("name", `ilike.*${search}*`);
  }

  const response = await fetch(endpoint, {
    headers: {
      ...authenticatedHeaders(accessToken),
      prefer: "count=exact",
    },
    cache: "no-store",
  });
  if (!response.ok) throw new Error("Não foi possível consultar os pacientes.");
  const rows = (await response.json()) as PatientDirectoryRow[];
  return {
    page,
    pageSize,
    patients: rows.map(toDirectoryEntry),
    total: totalFromContentRange(response.headers.get("content-range"), rows.length),
  };
}

export async function getPatientDirectoryEntry(accessToken: string, patientId: number) {
  const { url } = getSupabaseConfig();
  const endpoint = new URL(`${url}/rest/v1/patient_directory`);
  endpoint.searchParams.set("select", "id,passport,name,phone,birth_date,emergency_contact_name,emergency_contact_phone,allergies,created_at,updated_at,last_attendance_at,plan_status,plan_activated_at,plan_valid_until,plan_authorized_by,plan_authorized_by_name,pending_request_id,pending_requested_at");
  endpoint.searchParams.set("id", `eq.${patientId}`);
  endpoint.searchParams.set("limit", "1");
  const response = await fetch(endpoint, { headers: authenticatedHeaders(accessToken), cache: "no-store" });
  if (!response.ok) throw new Error("Não foi possível consultar o paciente.");
  const rows = (await response.json()) as PatientDirectoryRow[];
  return rows[0] ? toDirectoryEntry(rows[0]) : null;
}

export async function getPatientSummary(
  accessToken: string,
  patientId: number,
  includeCasts = false,
): Promise<PatientSummary> {
  const [rows, activeCasts] = await Promise.all([
    callPatientRpc<Array<Omit<PatientSummary, "active_casts">>>(accessToken, "patient_profile_summary", {
      p_patient_id: patientId,
    }),
    includeCasts ? getPatientActiveClinicalCasts(accessToken, patientId) : Promise.resolve([]),
  ]);
  return {
    ...(rows[0] ?? { last_attendance_at: null, recent_procedures: [], total_attendances: 0, total_purchases: 0 }),
    active_casts: activeCasts,
  };
}

export async function getPatientActivityPage(
  accessToken: string,
  patientId: number,
  kind: "all" | "procedures" | "purchases",
  page = 1,
  pageSize = 10,
  month?: string,
): Promise<PatientActivityPage> {
  const safePage = positiveInteger(page, 1);
  const safePageSize = Math.min(50, positiveInteger(pageSize, 10));
  const rows = await callPatientRpc<Array<{ available_months: Array<{ count: number; month: string; total: number }>; monthly_count: number; monthly_total: number; records: PatientActivityRecord[]; selected_month: string; total_count: number }>>(
    accessToken,
    "patient_activity_page",
    { p_kind: kind, p_limit: safePageSize, p_month: validMonth(month) ? `${month}-01` : null, p_offset: (safePage - 1) * safePageSize, p_patient_id: patientId },
  );
  return {
    availableMonths: rows[0]?.available_months ?? [],
    monthlyCount: Number(rows[0]?.monthly_count ?? 0),
    monthlyTotal: Number(rows[0]?.monthly_total ?? 0),
    page: safePage,
    pageSize: safePageSize,
    records: (rows[0]?.records ?? []).map((record) => ({
      ...record,
      items: record.items.map((item) => ({ ...item, source: "attendance" as const })),
    })),
    selectedMonth: rows[0]?.selected_month ?? month ?? "",
    total: Number(rows[0]?.total_count ?? 0),
  };
}

export async function getPatientPlanHistoryPage(
  accessToken: string,
  patientId: number,
  page = 1,
  pageSize = 10,
): Promise<PatientPlanHistoryPage> {
  const safePage = positiveInteger(page, 1);
  const safePageSize = Math.min(50, positiveInteger(pageSize, 10));
  const rows = await callPatientRpc<Array<{ records: PatientPlanHistoryRecord[]; total_count: number }>>(
    accessToken,
    "patient_plan_history_page",
    { p_limit: safePageSize, p_offset: (safePage - 1) * safePageSize, p_patient_id: patientId },
  );
  return {
    page: safePage,
    pageSize: safePageSize,
    records: rows[0]?.records ?? [],
    total: Number(rows[0]?.total_count ?? 0),
  };
}

export async function getPatientPartnershipPage(accessToken: string, patientId: number): Promise<PatientPartnershipPage> {
  return callPatientRpc<PatientPartnershipPage>(accessToken, "patient_partnership_page", { p_patient_id: patientId });
}

export async function getPatientLegacyHistoryPage(
  accessToken: string,
  patientId: number,
  recordType?: PatientLegacyRecordType,
  page = 1,
  pageSize = 20,
): Promise<PatientLegacyHistoryPage> {
  const safePage = positiveInteger(page, 1);
  const safePageSize = Math.min(50, positiveInteger(pageSize, 20));
  const payload = await callPatientRpc<Omit<PatientLegacyHistoryPage, "page" | "pageSize">>(accessToken, "patient_legacy_history_page", {
    p_limit: safePageSize,
    p_offset: (safePage - 1) * safePageSize,
    p_patient_id: patientId,
    p_record_type: recordType ?? null,
  });
  return {
    ...payload,
    items: Array.isArray(payload.items) ? payload.items : [],
    page: safePage,
    pageSize: safePageSize,
    source: "HP Norte",
    sourceProfiles: Number(payload.sourceProfiles ?? 0),
    summary: payload.summary ?? {},
    total: Number(payload.total ?? 0),
  };
}

export function isPatientLegacyRecordType(value: string | null): value is PatientLegacyRecordType {
  return PATIENT_LEGACY_RECORD_TYPES.includes(value as PatientLegacyRecordType);
}

export async function getPatientTimeline(accessToken: string, patientId: number): Promise<PatientTimelineEvent[]> {
  const result = await callPatientRpc<PatientTimelineEvent[]>(accessToken, "patient_timeline", {
    p_limit: 50,
    p_patient_id: patientId,
  });
  return Array.isArray(result) ? result : [];
}

export async function getPatientClinicalExamPage(
  accessToken: string,
  patientId: number,
  filters: PatientClinicalExamFilters = {},
  page = 1,
  pageSize = 10,
): Promise<PatientClinicalExamPage> {
  const safePage = positiveInteger(page, 1);
  const safePageSize = Math.min(20, positiveInteger(pageSize, 10));
  const payload = await callPatientRpc<{
    items?: PatientClinicalExamListItem[];
    summary?: { awaiting_review?: number; completed?: number; total?: number };
    total?: number;
  }>(accessToken, "patient_clinical_exam_page", {
    p_category_id: positiveOrNull(filters.categoryId),
    p_date_from: validDate(filters.dateFrom) ? filters.dateFrom : null,
    p_date_to: validDate(filters.dateTo) ? filters.dateTo : null,
    p_exam_type_id: positiveOrNull(filters.examTypeId),
    p_limit: safePageSize,
    p_offset: (safePage - 1) * safePageSize,
    p_patient_id: patientId,
    p_status: filters.status ?? null,
  });
  return {
    items: payload.items ?? [],
    page: safePage,
    pageSize: safePageSize,
    summary: {
      awaitingReview: Number(payload.summary?.awaiting_review ?? 0),
      completed: Number(payload.summary?.completed ?? 0),
      total: Number(payload.summary?.total ?? 0),
    },
    total: Number(payload.total ?? 0),
  };
}

async function callPatientRpc<T>(accessToken: string, name: string, payload: Record<string, unknown>): Promise<T> {
  const { url } = getSupabaseConfig();
  const response = await fetch(`${url}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: authenticatedHeaders(accessToken),
    body: JSON.stringify(payload),
    cache: "no-store",
  });
  if (!response.ok) throw new Error("Não foi possível consultar o histórico do paciente.");
  return (await response.json()) as T;
}

function toDirectoryEntry(row: PatientDirectoryRow): PatientDirectoryEntry {
  return {
    allergies: row.allergies,
    birth_date: row.birth_date,
    created_at: row.created_at,
    emergency_contact_name: row.emergency_contact_name,
    emergency_contact_phone: row.emergency_contact_phone,
    health_plan: {
      activated_at: row.plan_activated_at,
      authorized_by: row.plan_authorized_by,
      authorized_by_name: row.plan_authorized_by_name,
      pending_request_id: row.pending_request_id,
      pending_requested_at: row.pending_requested_at,
      status: row.plan_status,
      valid_until: row.plan_valid_until,
    },
    id: row.id,
    last_attendance_at: row.last_attendance_at,
    name: row.name,
    passport: row.passport,
    phone: row.phone,
    updated_at: row.updated_at,
  };
}

function positiveInteger(value: number | undefined, fallback: number) {
  return Number.isInteger(value) && Number(value) > 0 ? Number(value) : fallback;
}

function validFilter(value: unknown): value is PatientPlanFilter {
  return ["all", "active", "awaiting_confirmation", "expired", "none"].includes(String(value));
}

function cleanSearch(value: string | undefined) {
  return (value ?? "").trim().replace(/[,*()]/g, "").slice(0, 100);
}

function validMonth(value: string | undefined) {
  return /^\d{4}-(0[1-9]|1[0-2])$/.test(value ?? "");
}

function validDate(value: string | undefined) {
  return /^\d{4}-\d{2}-\d{2}$/.test(value ?? "");
}

function positiveOrNull(value: number | undefined) {
  return Number.isInteger(value) && Number(value) > 0 ? Number(value) : null;
}

function totalFromContentRange(contentRange: string | null, fallback: number) {
  const total = Number(contentRange?.split("/")[1]);
  return Number.isFinite(total) ? total : fallback;
}
