import { cookies } from "next/headers";
import {
  isCastBodyRegion,
  isCastLaterality,
  isClinicalCastStatus,
  type CastBodyRegion,
  type CastLaterality,
  type ClinicalCastStatus,
} from "./cast-types";
import { buildFinalExamDocument, type FinalExamDocumentImage, type FinalExamDocumentModel } from "./final-exam-document";
import type { ClinicalExamDetail, ClinicalExamDocumentState, ClinicalExamReportSnapshot } from "./exams";
import type { MedicalCertificateSnapshot } from "./medical-certificates";
import { buildPrescriptionDocument, type PrescriptionSnapshot } from "./prescription-document";
import { normalizePatientSearch } from "./passport";
import { getSupabaseAdminConfig } from "./supabase-server";
import { enrichClinicalExamIdentities } from "./professional-identity";
import { persistentSessionCookieExpires } from "./session-cookie-policy";

export const PATIENT_PORTAL_COOKIE = "hp_patient_portal_session";
export const PATIENT_PORTAL_COOKIE_EXPIRES = persistentSessionCookieExpires;

const HEX_256_PATTERN = /^[0-9a-f]{64}$/;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const PORTAL_RPC_TIMEOUT_MS = 10_000;

export type PatientPortalSession = {
  expiresAt: string | null;
  managesPartnerships: boolean;
  name: string;
  passport: string;
};

export type PatientPortalIdentity = {
  name: string;
  passport: string;
};

export type PatientPortalPartnershipSummary = {
  id: number;
  role: "primary" | "secondary";
  linked: number;
  name: string;
  nameReview: number;
  pendingRegistration: number;
  status: "active" | "inactive";
  totalInformed: number;
};

export type PatientPortalPartnershipPage = {
  items: PatientPortalPartnershipSummary[];
  patient: PatientPortalIdentity;
};

export type PatientPortalPartnershipMember = {
  name: string;
  occurredAt: string;
  passport: string;
  recordKey: string;
  status: "linked" | "name_review" | "pending_registration";
};

export type PatientPortalPartnershipMemberPage = {
  items: PatientPortalPartnershipMember[];
  limit: number;
  offset: number;
  partnership: { id: number; name: string; status: "active" | "inactive" };
  patient: PatientPortalIdentity;
  total: number;
};

export type PatientPortalPartnershipImportResult = {
  items: Array<{ line: number; name: string; passport: string; result: string }>;
  summary: { already_linked: number; invalid: number; linked: number; name_review: number; pending_registration: number; total: number };
};

export type PatientPortalHealthPlanStatus = "active" | "awaiting_confirmation" | "expired" | "none";
export type PatientPortalHealthPlanEvent = "activated" | "not_approved" | "renewed" | "requested";

export type PatientPortalHealthPlanHistoryItem = {
  coverageEnd: string | null;
  coverageStart: string | null;
  event: PatientPortalHealthPlanEvent;
  key: string;
  occurredAt: string;
  requestedAt: string;
  reviewedAt: string | null;
  status: "approved" | "pending" | "rejected";
};

export type PatientPortalHealthPlanPage = {
  current: {
    activatedAt: string | null;
    pendingRequestedAt: string | null;
    status: PatientPortalHealthPlanStatus;
    validUntil: string | null;
  };
  items: PatientPortalHealthPlanHistoryItem[];
  nextCursor: { id: number; occurredAt: string } | null;
  patient: PatientPortalIdentity;
};

export type PatientPortalCastItem = {
  appliedAt: string;
  appliedByName: string | null;
  appliedByPosition: string | null;
  bodyRegion: CastBodyRegion;
  cancelledAt: string | null;
  expectedRemovalAt: string;
  key: string;
  laterality: CastLaterality;
  occurredAt: string | null;
  removedAt: string | null;
  removedByName: string | null;
  removedByPosition: string | null;
  status: ClinicalCastStatus;
};

export type PatientPortalCastPage = {
  activeCasts: PatientPortalCastItem[];
  history: PatientPortalCastItem[];
  nextCursor: { id: number; occurredAt: string } | null;
  patient: PatientPortalIdentity;
  referenceTime: string;
};

export type PatientPortalMedicalCertificateItem = {
  attendanceId: number | null;
  createdAt: string;
  documentReady: boolean;
  finalizedAt: string;
  id: number;
  leaveDays: number;
  professionalName: string;
  professionalPosition: string | null;
};

export type PatientPortalMedicalCertificatePage = {
  items: PatientPortalMedicalCertificateItem[];
  page: number;
  pageSize: number;
  patient: PatientPortalIdentity;
  total: number;
};

export type PatientPortalMedicalCertificateDetail = {
  document: null | { fileSize: number; height: number; path: string; renderVersion: string; width: number };
  id: number;
  patient: PatientPortalIdentity;
  snapshot: MedicalCertificateSnapshot;
};

export type PatientPortalHistoryItem = {
  amount: number | null;
  attendanceId: number | null;
  description: string;
  examId: number | null;
  key: string;
  occurredAt: string;
  professionalName: string | null;
  professionalPosition: string | null;
  title: string;
  type: "attendance" | "cast" | "exam" | "health_plan" | "consultation" | "certificate" | "hospitalization" | "legacy";
};

export type PatientPortalHospitalizationPage = {
  items: Array<{ id: number; admittedAt: string; dischargedAt: string | null; reason: string; status: "active" | "discharged"; bedLabel: string; admittedByName: string | null; dischargedByName: string | null }>;
  total: number; page: number; pageSize: number; patient: PatientPortalIdentity;
};

export type PatientPortalLegacyRecordType = "registration" | "attendance" | "exam" | "vaccine" | "appointment" | "health_plan";
export type PatientPortalLegacyHistoryPage = {
  items: Array<{ id: number; recordType: PatientPortalLegacyRecordType; occurredAt: string | null; occurredPrecision: string; title: string; status: string | null; professionalName: string | null; professionalRegistration: string | null; summary: string | null; details: Record<string, unknown>; referenceLinks: unknown[] }>;
  total: number; page: number; pageSize: number; patient: PatientPortalIdentity; summary: Record<string, number>;
};

export type PatientPortalExamStatus = "awaiting_review" | "completed" | "in_progress" | "requested";
export type PatientPortalExamFilter = "all" | "completed" | "in_progress";

export type PatientPortalExamListItem = {
  category: string;
  completedAt: string | null;
  id: number;
  occurredAt: string;
  status: PatientPortalExamStatus;
  type: string;
};

export type PatientPortalExamPage = {
  items: PatientPortalExamListItem[];
  nextCursor: { id: number; occurredAt: string } | null;
  patient: PatientPortalIdentity;
};

export type PatientPortalExamDetail = {
  document: FinalExamDocumentModel | null;
  exam: PatientPortalExamListItem;
  patient: PatientPortalIdentity;
};

export type PatientPortalConsultationItem = {
  completedAt: string | null;
  consultationId: number | null;
  id: number;
  kind: "appointment" | "consultation";
  occurredAt: string;
  professionalName: string | null;
  professionalPosition: string | null;
  reason: string | null;
  status: "scheduled" | "confirmed" | "in_progress" | "completed" | "cancelled" | "no_show";
};

export type PatientPortalConsultationPage = {
  items: PatientPortalConsultationItem[];
  nextCursor: { key: string; occurredAt: string } | null;
  patient: PatientPortalIdentity;
};

export type PatientPortalConsultationDetail = {
  consultation: PatientPortalConsultationItem;
  patient: PatientPortalIdentity;
  snapshot: import("./consultation-document").ConsultationSnapshot | null;
};

export type PatientPortalExamImageSource = {
  fileSize: number;
  mimeType: string;
  storagePath: string;
};

export type PatientPortalHistoryPage = {
  items: PatientPortalHistoryItem[];
  nextCursor: { key: string; occurredAt: string } | null;
  patient: PatientPortalIdentity;
};

export type PatientPortalAttendanceListItem = {
  benefitCode: string | null;
  benefitName: string | null;
  id: number;
  itemCount: number;
  occurredAt: string;
  professionalName: string | null;
  professionalPosition: string | null;
  total: number;
};

export type PatientPortalAttendancePage = {
  items: PatientPortalAttendanceListItem[];
  metrics: {
    lifetimeSpent: number;
    totalAttendances: number;
  };
  nextCursor: { id: number; occurredAt: string } | null;
  patient: PatientPortalIdentity;
};

export type PatientPortalAttendanceDetail = {
  attendance: PatientPortalAttendanceListItem & {
    discount: number;
    items: Array<{
      discountAmount: number;
      discountPercent: number;
      lineTotal: number;
      name: string;
      quantity: number;
      unitPrice: number;
    }>;
    subtotal: number;
  };
  patient: PatientPortalIdentity;
};

export type PatientPortalSummary = {
  activeCasts: Array<{
    appliedAt: string;
    bodyRegion: string;
    expectedRemovalAt: string;
    laterality: string;
  }>;
  healthPlan: {
    status: PatientPortalHealthPlanStatus;
    validUntil: string | null;
  };
  metrics: {
    lastAttendance: {
      occurredAt: string;
      professionalName: string | null;
      total: number;
    } | null;
    lifetimeSpent: number;
    totalAttendances: number;
  };
  patient: {
    name: string;
    passport: string;
  };
  recentExams: Array<{
    id: number;
    occurredAt: string;
    status: "awaiting_review" | "completed" | "in_progress" | "requested";
    type: string;
  }>;
  referenceTime: string;
};

type PatientPortalMePayload = {
  authenticated?: boolean;
  expires_at?: unknown;
  manages_partnerships?: unknown;
  name?: unknown;
  passport?: unknown;
};

type PatientPortalPartnershipPayload = {
  authenticated?: boolean;
  items?: unknown;
  limit?: unknown;
  offset?: unknown;
  partnership?: unknown;
  patient?: unknown;
  total?: unknown;
};

type PatientPortalSummaryPayload = {
  active_casts?: unknown;
  authenticated?: boolean;
  health_plan?: unknown;
  patient?: unknown;
  recent_exams?: unknown;
  summary?: unknown;
};

type PatientPortalPagePayload = {
  authenticated?: boolean;
  items?: unknown;
  next_cursor?: unknown;
  patient?: unknown;
  summary?: unknown;
};

type PatientPortalHealthPlanPagePayload = PatientPortalPagePayload & {
  current?: unknown;
};

type PatientPortalCastPagePayload = PatientPortalPagePayload & {
  active_casts?: unknown;
  history?: unknown;
  reference_time?: unknown;
};

type PatientPortalMedicalCertificatePayload = {
  authenticated?: boolean;
  certificate?: unknown;
  document?: unknown;
  found?: boolean;
  items?: unknown;
  patient?: unknown;
  total?: unknown;
};

type PatientPortalAttendanceDetailPayload = {
  attendance?: unknown;
  authenticated?: boolean;
  found?: boolean;
  patient?: unknown;
};

type PatientPortalExamDetailPayload = {
  authenticated?: boolean;
  exam?: unknown;
  final_report_snapshot?: unknown;
  found?: boolean;
  images?: unknown;
  patient?: unknown;
};

type PatientPortalExamImagePayload = {
  authenticated?: boolean;
  found?: boolean;
  image?: unknown;
};

type PatientPortalExamDocumentPayload = {
  authenticated?: boolean;
  found?: boolean;
  state?: unknown;
};

export type PatientPortalLoginResult = {
  blocked?: boolean;
  code?: "first_access" | "invalid_pin" | "invalid_pin_format" | "patient_not_found" | "pin_exists" | "pin_mismatch" | "rate_limited";
  expires_at?: string;
  ok?: boolean;
};

export type PatientPortalAccessResult = {
  blocked?: boolean;
  found?: boolean;
  has_pin?: boolean;
};

export type PatientPortalProfile = {
  allergies: string | null;
  birthDate: string | null;
  emergencyContactName: string | null;
  emergencyContactPhone: string | null;
  name: string;
  passport: string;
  phone: string | null;
};

type PatientPortalProfilePayload = {
  authenticated?: boolean;
  patient?: unknown;
};

export async function getPatientPortalSession(): Promise<PatientPortalSession | null> {
  const cookieStore = await cookies();
  const token = cookieStore.get(PATIENT_PORTAL_COOKIE)?.value ?? "";
  return resolvePatientPortalSession(token);
}

export async function getPatientPortalSummary(): Promise<PatientPortalSummary | null> {
  const cookieStore = await cookies();
  const token = cookieStore.get(PATIENT_PORTAL_COOKIE)?.value ?? "";
  return resolvePatientPortalSummary(token);
}

export async function getPatientPortalProfile(): Promise<PatientPortalProfile | null> {
  const token = await patientPortalCookieToken();
  return resolvePatientPortalProfile(token);
}

export async function updatePatientPortalProfile(input: Omit<PatientPortalProfile, "passport">): Promise<PatientPortalProfile | null> {
  const token = await patientPortalCookieToken();
  if (!isPatientPortalToken(token)) return null;
  const payload = await callPatientPortalRpc<PatientPortalProfilePayload>("patient_portal_update_profile", {
    p_allergies: input.allergies,
    p_birth_date: input.birthDate,
    p_emergency_contact_name: input.emergencyContactName,
    p_emergency_contact_phone: input.emergencyContactPhone,
    p_name: input.name,
    p_phone: input.phone,
    p_token_hash: await hashPatientPortalValue(token),
  });
  if (payload.authenticated !== true) return null;
  return parsePatientPortalProfile(payload.patient);
}

export async function getPatientPortalHistoryPage(cursor?: { key: string; occurredAt: string } | null) {
  const token = await patientPortalCookieToken();
  return resolvePatientPortalHistoryPage(token, cursor);
}

export async function getPatientPortalHospitalizationPage(page = 1): Promise<PatientPortalHospitalizationPage | null> {
  const token = await patientPortalCookieToken();
  if (!isPatientPortalToken(token)) return null;
  const pageSize = 15;
  const payload = await callPatientPortalRpc<PatientPortalPagePayload & { total?: unknown }>("patient_portal_hospitalization_page", {
    p_token_hash: await hashPatientPortalValue(token), p_limit: pageSize, p_offset: (page - 1) * pageSize,
  });
  if (payload.authenticated !== true) return null;
  return { patient: parsePortalIdentity(payload.patient), page, pageSize, total: positiveIntegerOf(payload.total, true),
    items: arrayOf(payload.items).map((value) => { const item = recordOf(value); const status = stringOf(item.status);
      if (status !== "active" && status !== "discharged") throw new Error("patient_portal_invalid_hospitalization_status");
      return { id: positiveIntegerOf(item.id), admittedAt: stringOf(item.admitted_at), dischargedAt: nullableStringOf(item.discharged_at), reason: stringOf(item.reason), status, bedLabel: stringOf(item.bed_label), admittedByName: nullableStringOf(item.admitted_by_name), dischargedByName: nullableStringOf(item.discharged_by_name) }; }),
  };
}

const LEGACY_TYPES = ["registration", "attendance", "exam", "vaccine", "appointment", "health_plan"];
export async function getPatientPortalLegacyHistoryPage(page = 1, recordType: PatientPortalLegacyRecordType | null = null): Promise<PatientPortalLegacyHistoryPage | null> {
  const token = await patientPortalCookieToken();
  if (!isPatientPortalToken(token)) return null;
  const pageSize = 20;
  const payload = await callPatientPortalRpc<PatientPortalPagePayload & { total?: unknown }>("patient_portal_legacy_history_page", {
    p_token_hash: await hashPatientPortalValue(token), p_record_type: recordType, p_limit: pageSize, p_offset: (page - 1) * pageSize,
  });
  if (payload.authenticated !== true) return null;
  const summary = recordOf(payload.summary);
  return { patient: parsePortalIdentity(payload.patient), page, pageSize, total: positiveIntegerOf(payload.total, true),
    summary: Object.fromEntries(LEGACY_TYPES.map((type) => [type, positiveIntegerOf(summary[type] ?? 0, true)])),
    items: arrayOf(payload.items).map((value) => { const item = recordOf(value); const type = stringOf(item.record_type);
      if (!LEGACY_TYPES.includes(type)) throw new Error("patient_portal_invalid_legacy_type");
      return { id: positiveIntegerOf(item.id), recordType: type as PatientPortalLegacyRecordType,
        occurredAt: nullableStringOf(item.occurred_at), occurredPrecision: stringOf(item.occurred_precision), title: stringOf(item.title), status: nullableStringOf(item.status), professionalName: nullableStringOf(item.professional_name), professionalRegistration: nullableStringOf(item.professional_registration), summary: nullableStringOf(item.summary), details: recordOf(item.details), referenceLinks: arrayOf(item.reference_links) }; }),
  };
}

export async function getPatientPortalPrescriptionSnapshot(consultationId: number): Promise<PrescriptionSnapshot | null | "unauthenticated"> {
  const token = await patientPortalCookieToken();
  if (!isPatientPortalToken(token)) return "unauthenticated";
  const payload = await callPatientPortalRpc<{ authenticated?: boolean; found?: boolean; snapshot?: unknown }>("patient_portal_prescription_snapshot", {
    p_token_hash: await hashPatientPortalValue(token), p_consultation_id: consultationId,
  });
  if (payload.authenticated !== true) return "unauthenticated";
  if (payload.found !== true) return null;
  const snapshot = buildPrescriptionDocument(payload.snapshot);
  if (snapshot.consultation_id !== consultationId) throw new Error("patient_portal_prescription_mismatch");
  return snapshot;
}

export async function getPatientPortalHealthPlanPage(cursor?: { id: number; occurredAt: string } | null) {
  const token = await patientPortalCookieToken();
  return resolvePatientPortalHealthPlanPage(token, cursor);
}

export async function getPatientPortalCastPage(cursor?: { id: number; occurredAt: string } | null) {
  const token = await patientPortalCookieToken();
  return resolvePatientPortalCastPage(token, cursor);
}

export async function getPatientPortalMedicalCertificatePage(page = 1, pageSize = 15) {
  const token = await patientPortalCookieToken();
  return resolvePatientPortalMedicalCertificatePage(token, page, pageSize);
}

export async function getPatientPortalMedicalCertificateDetail(certificateId: number) {
  const token = await patientPortalCookieToken();
  return resolvePatientPortalMedicalCertificateDetail(token, certificateId);
}

export async function registerPatientPortalMedicalCertificateDocument(certificateId: number, input: { fileSize: number; height: number; renderVersion: string; storagePath: string; width: number }) {
  const token = await patientPortalCookieToken();
  if (!isPatientPortalToken(token)) return null;
  const payload = await callPatientPortalRpc<PatientPortalMedicalCertificatePayload>("patient_portal_register_medical_certificate_document", {
    p_certificate_id: certificateId,
    p_file_size: input.fileSize,
    p_height: input.height,
    p_render_version: input.renderVersion,
    p_storage_path: input.storagePath,
    p_token_hash: await hashPatientPortalValue(token),
    p_width: input.width,
  });
  if (payload.authenticated !== true) return null;
  if (payload.found !== true) return "not_found" as const;
  return parsePatientPortalMedicalCertificateDetail(payload);
}

export async function auditPatientPortalMedicalCertificateDownload(certificateId: number) {
  const token = await patientPortalCookieToken();
  if (!isPatientPortalToken(token)) return false;
  return callPatientPortalRpc<boolean>("patient_portal_audit_medical_certificate_download", {
    p_certificate_id: certificateId,
    p_token_hash: await hashPatientPortalValue(token),
  });
}

export async function getPatientPortalAttendancePage(cursor?: { id: number; occurredAt: string } | null) {
  const token = await patientPortalCookieToken();
  return resolvePatientPortalAttendancePage(token, cursor);
}

export async function getPatientPortalAttendanceDetail(attendanceId: number) {
  const token = await patientPortalCookieToken();
  return resolvePatientPortalAttendanceDetail(token, attendanceId);
}

export async function getPatientPortalExamPage(
  filter: PatientPortalExamFilter = "all",
  cursor?: { id: number; occurredAt: string } | null,
) {
  const token = await patientPortalCookieToken();
  return resolvePatientPortalExamPage(token, filter, cursor);
}

export async function getPatientPortalExamDetail(examId: number) {
  const token = await patientPortalCookieToken();
  return resolvePatientPortalExamDetail(token, examId);
}

export async function getPatientPortalConsultationPage(cursor?: { key: string; occurredAt: string } | null) {
  const token = await patientPortalCookieToken();
  return resolvePatientPortalConsultationPage(token, cursor);
}

export async function getPatientPortalConsultationDetail(kind: "appointment" | "consultation", id: number) {
  const token = await patientPortalCookieToken();
  return resolvePatientPortalConsultationDetail(token, kind, id);
}

export async function getPatientPortalPartnershipPage(): Promise<PatientPortalPartnershipPage | null> {
  const token = await patientPortalCookieToken();
  if (!isPatientPortalToken(token)) return null;
  const payload = await callPatientPortalRpc<PatientPortalPartnershipPayload>("patient_portal_partnership_page", {
    p_token_hash: await hashPatientPortalValue(token),
  });
  if (payload.authenticated !== true) return null;
  return parsePatientPortalPartnershipPage(payload);
}

export async function getPatientPortalPartnershipMemberPage(partnershipId: number, options: { filter?: string; offset?: number; search?: string } = {}): Promise<PatientPortalPartnershipMemberPage | null> {
  const token = await patientPortalCookieToken();
  if (!isPatientPortalToken(token)) return null;
  const payload = await callPatientPortalRpc<PatientPortalPartnershipPayload>("patient_portal_partnership_member_page", {
    p_filter: options.filter ?? "all",
    p_limit: 20,
    p_offset: options.offset ?? 0,
    p_partnership_id: partnershipId,
    p_search: normalizePatientSearch(options.search) ?? "",
    p_token_hash: await hashPatientPortalValue(token),
  });
  if (payload.authenticated !== true) return null;
  return parsePatientPortalPartnershipMemberPage(payload);
}

export async function mutatePatientPortalPartnership(name: "patient_portal_cancel_partnership_pending" | "patient_portal_import_partnership_people" | "patient_portal_unlink_partnership_member", body: Record<string, unknown>) {
  const token = await patientPortalCookieToken();
  if (!isPatientPortalToken(token)) return null;
  return callPatientPortalRpc<PatientPortalPartnershipImportResult | boolean>(name, {
    ...body,
    p_token_hash: await hashPatientPortalValue(token),
  });
}

export async function getPatientPortalExamImage(examId: number, imageId: string) {
  const token = await patientPortalCookieToken();
  if (!isPatientPortalToken(token) || !UUID_PATTERN.test(imageId)) return null;
  const payload = await callPatientPortalRpc<PatientPortalExamImagePayload>("patient_portal_exam_image", {
    p_exam_id: examId,
    p_image_id: imageId,
    p_token_hash: await hashPatientPortalValue(token),
  });
  if (payload.authenticated !== true) return null;
  if (payload.found !== true) return "not_found" as const;
  const image = recordOf(payload.image);
  return {
    fileSize: positiveIntegerOf(image.file_size),
    mimeType: stringOf(image.mime_type),
    storagePath: stringOf(image.storage_path),
  } satisfies PatientPortalExamImageSource;
}

export async function getPatientPortalExamDocumentState(examId: number) {
  return patientPortalDocumentRpc("patient_portal_exam_document_state", { p_exam_id: examId });
}

export async function registerPatientPortalExamDocument(examId: number, input: {
  documentId: string;
  fileSize: number;
  pixelHeight: number;
  pixelWidth: number;
  renderVersion: string;
  storagePath: string;
}) {
  return patientPortalDocumentRpc("patient_portal_register_clinical_exam_document", {
    p_document_id: input.documentId,
    p_exam_id: examId,
    p_file_size: input.fileSize,
    p_pixel_height: input.pixelHeight,
    p_pixel_width: input.pixelWidth,
    p_render_version: input.renderVersion,
    p_storage_path: input.storagePath,
  });
}

export async function createPatientPortalExamShare(examId: number) {
  return patientPortalDocumentRpc("patient_portal_create_clinical_exam_document_share", { p_exam_id: examId });
}

export async function resolvePatientPortalExamPage(
  token: string,
  filter: PatientPortalExamFilter = "all",
  cursor?: { id: number; occurredAt: string } | null,
): Promise<PatientPortalExamPage | null> {
  if (!isPatientPortalToken(token)) return null;
  const payload = await callPatientPortalRpc<PatientPortalPagePayload>("patient_portal_exam_page", {
    p_cursor_at: cursor?.occurredAt ?? null,
    p_cursor_id: cursor?.id ?? null,
    p_limit: 15,
    p_status_group: filter,
    p_token_hash: await hashPatientPortalValue(token),
  });
  if (payload.authenticated !== true) return null;
  return parsePatientPortalExamPage(payload);
}

export async function resolvePatientPortalExamDetail(
  token: string,
  examId: number,
): Promise<PatientPortalExamDetail | null | "not_found"> {
  if (!isPatientPortalToken(token)) return null;
  const payload = await callPatientPortalRpc<PatientPortalExamDetailPayload>("patient_portal_exam_detail", {
    p_exam_id: examId,
    p_token_hash: await hashPatientPortalValue(token),
  });
  if (payload.authenticated !== true) return null;
  if (payload.found !== true) return "not_found";
  return await parsePatientPortalExamDetail(payload);
}

export async function resolvePatientPortalConsultationPage(token: string, cursor?: { key: string; occurredAt: string } | null): Promise<PatientPortalConsultationPage | null> {
  if (!isPatientPortalToken(token)) return null;
  const payload = await callPatientPortalRpc<PatientPortalPagePayload>("patient_portal_consultation_page", {
    p_cursor_at: cursor?.occurredAt ?? null,
    p_cursor_key: cursor?.key ?? null,
    p_limit: 15,
    p_token_hash: await hashPatientPortalValue(token),
  });
  if (payload.authenticated !== true) return null;
  return {
    items: arrayOf(payload.items).map(parsePatientPortalConsultationItem),
    nextCursor: parseHistoryCursor(payload.next_cursor),
    patient: parsePortalIdentity(payload.patient),
  };
}

export async function resolvePatientPortalConsultationDetail(token: string, kind: "appointment" | "consultation", id: number): Promise<PatientPortalConsultationDetail | null | "not_found"> {
  if (!isPatientPortalToken(token)) return null;
  const payload = await callPatientPortalRpc<PatientPortalPagePayload & { found?: boolean; consultation?: unknown; final_snapshot?: unknown }>("patient_portal_consultation_detail", {
    p_kind: kind,
    p_record_id: id,
    p_token_hash: await hashPatientPortalValue(token),
  });
  if (payload.authenticated !== true) return null;
  if (payload.found !== true) return "not_found";
  const consultation = parsePatientPortalConsultationItem(payload.consultation);
  const snapshot = consultation.status === "completed" && payload.final_snapshot
    ? (await import("./consultation-document")).buildConsultationDocument(payload.final_snapshot)
    : null;
  return { consultation, patient: parsePortalIdentity(payload.patient), snapshot };
}

export async function resolvePatientPortalHistoryPage(
  token: string,
  cursor?: { key: string; occurredAt: string } | null,
): Promise<PatientPortalHistoryPage | null> {
  if (!isPatientPortalToken(token)) return null;
  const payload = await callPatientPortalRpc<PatientPortalPagePayload>("patient_portal_history_page_v2", {
    p_cursor_at: cursor?.occurredAt ?? null,
    p_cursor_key: cursor?.key ?? null,
    p_limit: 20,
    p_token_hash: await hashPatientPortalValue(token),
  });
  if (payload.authenticated !== true) return null;
  return parsePatientPortalHistoryPage(payload);
}

export async function resolvePatientPortalHealthPlanPage(
  token: string,
  cursor?: { id: number; occurredAt: string } | null,
): Promise<PatientPortalHealthPlanPage | null> {
  if (!isPatientPortalToken(token)) return null;
  const payload = await callPatientPortalRpc<PatientPortalHealthPlanPagePayload>("patient_portal_health_plan_page", {
    p_cursor_at: cursor?.occurredAt ?? null,
    p_cursor_id: cursor?.id ?? null,
    p_limit: 12,
    p_token_hash: await hashPatientPortalValue(token),
  });
  if (payload.authenticated !== true) return null;
  return parsePatientPortalHealthPlanPage(payload);
}

export async function resolvePatientPortalCastPage(
  token: string,
  cursor?: { id: number; occurredAt: string } | null,
): Promise<PatientPortalCastPage | null> {
  if (!isPatientPortalToken(token)) return null;
  const payload = await callPatientPortalRpc<PatientPortalCastPagePayload>("patient_portal_cast_page", {
    p_cursor_at: cursor?.occurredAt ?? null,
    p_cursor_id: cursor?.id ?? null,
    p_limit: 15,
    p_token_hash: await hashPatientPortalValue(token),
  });
  if (payload.authenticated !== true) return null;
  return parsePatientPortalCastPage(payload);
}

export async function resolvePatientPortalMedicalCertificatePage(token: string, page = 1, pageSize = 15): Promise<PatientPortalMedicalCertificatePage | null> {
  if (!isPatientPortalToken(token)) return null;
  const normalizedPage = Number.isSafeInteger(page) && page > 0 ? page : 1;
  const normalizedSize = Number.isSafeInteger(pageSize) && pageSize > 0 ? Math.min(pageSize, 30) : 15;
  const payload = await callPatientPortalRpc<PatientPortalMedicalCertificatePayload>("patient_portal_medical_certificate_page", {
    p_limit: normalizedSize,
    p_offset: (normalizedPage - 1) * normalizedSize,
    p_token_hash: await hashPatientPortalValue(token),
  });
  if (payload.authenticated !== true) return null;
  return parsePatientPortalMedicalCertificatePage(payload, normalizedPage, normalizedSize);
}

export async function resolvePatientPortalMedicalCertificateDetail(token: string, certificateId: number): Promise<PatientPortalMedicalCertificateDetail | null | "not_found"> {
  if (!isPatientPortalToken(token)) return null;
  const payload = await callPatientPortalRpc<PatientPortalMedicalCertificatePayload>("patient_portal_medical_certificate_detail", {
    p_certificate_id: certificateId,
    p_token_hash: await hashPatientPortalValue(token),
  });
  if (payload.authenticated !== true) return null;
  if (payload.found !== true) return "not_found";
  return parsePatientPortalMedicalCertificateDetail(payload);
}

export async function resolvePatientPortalAttendancePage(
  token: string,
  cursor?: { id: number; occurredAt: string } | null,
): Promise<PatientPortalAttendancePage | null> {
  if (!isPatientPortalToken(token)) return null;
  const payload = await callPatientPortalRpc<PatientPortalPagePayload>("patient_portal_attendance_page", {
    p_cursor_at: cursor?.occurredAt ?? null,
    p_cursor_id: cursor?.id ?? null,
    p_limit: 20,
    p_token_hash: await hashPatientPortalValue(token),
  });
  if (payload.authenticated !== true) return null;
  return parsePatientPortalAttendancePage(payload);
}

export async function resolvePatientPortalAttendanceDetail(
  token: string,
  attendanceId: number,
): Promise<PatientPortalAttendanceDetail | null | "not_found"> {
  if (!isPatientPortalToken(token)) return null;
  const payload = await callPatientPortalRpc<PatientPortalAttendanceDetailPayload>("patient_portal_attendance_detail", {
    p_attendance_id: attendanceId,
    p_token_hash: await hashPatientPortalValue(token),
  });
  if (payload.authenticated !== true) return null;
  if (payload.found !== true) return "not_found";
  return parsePatientPortalAttendanceDetail(payload);
}

export async function resolvePatientPortalSummary(token: string): Promise<PatientPortalSummary | null> {
  if (!isPatientPortalToken(token)) return null;
  const payload = await callPatientPortalRpc<PatientPortalSummaryPayload>("patient_portal_summary", {
    p_token_hash: await hashPatientPortalValue(token),
  });
  if (payload.authenticated !== true) return null;
  return parsePatientPortalSummary(payload, new Date().toISOString());
}

export async function resolvePatientPortalSession(token: string): Promise<PatientPortalSession | null> {
  if (!isPatientPortalToken(token)) return null;
  try {
    const payload = await callPatientPortalRpc<PatientPortalMePayload>("patient_portal_session_me", {
      p_token_hash: await hashPatientPortalValue(token),
    });
    if (
      payload.authenticated !== true ||
      (payload.expires_at !== null && typeof payload.expires_at !== "string") ||
      typeof payload.name !== "string" ||
      typeof payload.passport !== "string"
    ) return null;
    return { expiresAt: payload.expires_at, managesPartnerships: payload.manages_partnerships === true, name: payload.name, passport: payload.passport };
  } catch {
    return null;
  }
}

export async function resolvePatientPortalProfile(token: string): Promise<PatientPortalProfile | null> {
  if (!isPatientPortalToken(token)) return null;
  const payload = await callPatientPortalRpc<PatientPortalProfilePayload>("patient_portal_profile", {
    p_token_hash: await hashPatientPortalValue(token),
  });
  if (payload.authenticated !== true) return null;
  return parsePatientPortalProfile(payload.patient);
}

export async function callPatientPortalRpc<T>(name: string, body: Record<string, unknown>): Promise<T> {
  const { serviceRoleKey, url } = getSupabaseAdminConfig();
  const response = await fetch(`${url}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: serviceRoleKey,
      authorization: `Bearer ${serviceRoleKey}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
    cache: "no-store",
    signal: AbortSignal.timeout(PORTAL_RPC_TIMEOUT_MS),
  });
  if (!response.ok) {
    const payload = await response.json().catch(() => null) as { message?: unknown } | null;
    throw new PatientPortalRpcError(response.status, typeof payload?.message === "string" ? payload.message : null);
  }
  return await response.json() as T;
}

export class PatientPortalRpcError extends Error {
  constructor(public status: number, public rpcMessage: string | null) {
    super("Não foi possível concluir a operação no Portal.");
  }
}

export function createPatientPortalToken() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export function isPatientPortalToken(value: string) {
  return HEX_256_PATTERN.test(value);
}

export async function hashPatientPortalValue(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export async function patientPortalRequestHashes(request: Request) {
  const forwarded = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  const address = (
    request.headers.get("cf-connecting-ip") ||
    forwarded ||
    request.headers.get("x-real-ip") ||
    "unknown"
  ).slice(0, 128);
  const userAgent = (request.headers.get("user-agent") || "unknown").slice(0, 512);
  const [originHash, clientHash] = await Promise.all([
    hashPatientPortalValue(`origin:${address}`),
    hashPatientPortalValue(`client:${userAgent}`),
  ]);
  return { clientHash, originHash };
}

function parsePatientPortalSummary(payload: PatientPortalSummaryPayload, referenceTime: string): PatientPortalSummary {
  const patient = recordOf(payload.patient);
  const metrics = recordOf(payload.summary);
  const plan = recordOf(payload.health_plan);
  const lastAttendance = metrics.last_attendance === null ? null : recordOf(metrics.last_attendance);
  const planStatus = stringOf(plan.status);
  if (!["active", "awaiting_confirmation", "expired", "none"].includes(planStatus)) {
    throw new Error("patient_portal_summary_invalid_plan");
  }

  return {
    activeCasts: arrayOf(payload.active_casts).map((item) => {
      const cast = recordOf(item);
      return {
        appliedAt: stringOf(cast.applied_at),
        bodyRegion: stringOf(cast.body_region),
        expectedRemovalAt: stringOf(cast.expected_removal_at),
        laterality: stringOf(cast.laterality),
      };
    }),
    healthPlan: {
      status: planStatus as PatientPortalSummary["healthPlan"]["status"],
      validUntil: nullableStringOf(plan.valid_until),
    },
    metrics: {
      lastAttendance: lastAttendance ? {
        occurredAt: stringOf(lastAttendance.occurred_at),
        professionalName: nullableStringOf(lastAttendance.professional_name),
        total: numberOf(lastAttendance.total),
      } : null,
      lifetimeSpent: numberOf(metrics.lifetime_spent),
      totalAttendances: Math.max(0, Math.trunc(numberOf(metrics.total_attendances))),
    },
    patient: {
      name: stringOf(patient.name),
      passport: stringOf(patient.passport),
    },
    recentExams: arrayOf(payload.recent_exams).map((item) => {
      const exam = recordOf(item);
      const status = stringOf(exam.status);
      if (!["requested", "in_progress", "awaiting_review", "completed"].includes(status)) {
        throw new Error("patient_portal_summary_invalid_exam");
      }
      return {
        id: positiveIntegerOf(exam.id),
        occurredAt: stringOf(exam.occurred_at),
        status: status as PatientPortalSummary["recentExams"][number]["status"],
        type: stringOf(exam.type),
      };
    }),
    referenceTime,
  };
}

function parsePatientPortalProfile(value: unknown): PatientPortalProfile {
  const patient = recordOf(value);
  return {
    allergies: nullableStringOf(patient.allergies),
    birthDate: nullableStringOf(patient.birth_date),
    emergencyContactName: nullableStringOf(patient.emergency_contact_name),
    emergencyContactPhone: nullableStringOf(patient.emergency_contact_phone),
    name: stringOf(patient.name),
    passport: stringOf(patient.passport),
    phone: nullableStringOf(patient.phone),
  };
}

function parsePatientPortalPartnershipPage(payload: PatientPortalPartnershipPayload): PatientPortalPartnershipPage {
  return {
    items: arrayOf(payload.items).map((value) => {
      const item = recordOf(value);
      const status = stringOf(item.status);
      if (status !== "active" && status !== "inactive") throw new Error("patient_portal_partnership_invalid_status");
      const role = stringOf(item.role);
      if (role !== "primary" && role !== "secondary") throw new Error("patient_portal_partnership_invalid_role");
      return {
        id: positiveIntegerOf(item.id),
        role,
        linked: positiveIntegerOf(item.linked, true),
        name: stringOf(item.name),
        nameReview: positiveIntegerOf(item.name_review, true),
        pendingRegistration: positiveIntegerOf(item.pending_registration, true),
        status,
        totalInformed: positiveIntegerOf(item.total_informed, true),
      };
    }),
    patient: parsePortalIdentity(payload.patient),
  };
}

function parsePatientPortalPartnershipMemberPage(payload: PatientPortalPartnershipPayload): PatientPortalPartnershipMemberPage {
  const partnership = recordOf(payload.partnership);
  const status = stringOf(partnership.status);
  if (status !== "active" && status !== "inactive") throw new Error("patient_portal_partnership_invalid_status");
  return {
    items: arrayOf(payload.items).map((value) => {
      const item = recordOf(value);
      const itemStatus = stringOf(item.status);
      if (!["linked", "name_review", "pending_registration"].includes(itemStatus)) throw new Error("patient_portal_partnership_member_invalid_status");
      return {
        name: stringOf(item.name),
        occurredAt: stringOf(item.occurred_at),
        passport: stringOf(item.passport),
        recordKey: stringOf(item.record_key),
        status: itemStatus as PatientPortalPartnershipMember["status"],
      };
    }),
    limit: positiveIntegerOf(payload.limit),
    offset: positiveIntegerOf(payload.offset, true),
    partnership: { id: positiveIntegerOf(partnership.id), name: stringOf(partnership.name), status },
    patient: parsePortalIdentity(payload.patient),
    total: positiveIntegerOf(payload.total, true),
  };
}

function parsePatientPortalHealthPlanPage(payload: PatientPortalHealthPlanPagePayload): PatientPortalHealthPlanPage {
  const current = recordOf(payload.current);
  const currentStatus = stringOf(current.status);
  if (!isPatientPortalHealthPlanStatus(currentStatus)) {
    throw new Error("patient_portal_health_plan_invalid_status");
  }
  return {
    current: {
      activatedAt: nullableStringOf(current.activated_at),
      pendingRequestedAt: nullableStringOf(current.pending_requested_at),
      status: currentStatus,
      validUntil: nullableStringOf(current.valid_until),
    },
    items: arrayOf(payload.items).map((value) => {
      const item = recordOf(value);
      const event = stringOf(item.event);
      const status = stringOf(item.status);
      if (!isPatientPortalHealthPlanEvent(event) || !["approved", "pending", "rejected"].includes(status)) {
        throw new Error("patient_portal_health_plan_invalid_history");
      }
      return {
        coverageEnd: nullableStringOf(item.coverage_end),
        coverageStart: nullableStringOf(item.coverage_start),
        event,
        key: stringOf(item.key),
        occurredAt: stringOf(item.occurred_at),
        requestedAt: stringOf(item.requested_at),
        reviewedAt: nullableStringOf(item.reviewed_at),
        status: status as PatientPortalHealthPlanHistoryItem["status"],
      };
    }),
    nextCursor: parseIdCursor(payload.next_cursor),
    patient: parsePortalIdentity(payload.patient),
  };
}

function parsePatientPortalCastPage(payload: PatientPortalCastPagePayload): PatientPortalCastPage {
  return {
    activeCasts: arrayOf(payload.active_casts).map(parsePatientPortalCastItem),
    history: arrayOf(payload.history).map(parsePatientPortalCastItem),
    nextCursor: parseIdCursor(payload.next_cursor),
    patient: parsePortalIdentity(payload.patient),
    referenceTime: stringOf(payload.reference_time),
  };
}

function parsePatientPortalCastItem(value: unknown): PatientPortalCastItem {
  const item = recordOf(value);
  const bodyRegion = stringOf(item.body_region);
  const laterality = stringOf(item.laterality);
  const status = stringOf(item.status);
  if (!isCastBodyRegion(bodyRegion) || !isCastLaterality(laterality) || !isClinicalCastStatus(status)) {
    throw new Error("patient_portal_cast_invalid_item");
  }
  return {
    appliedAt: stringOf(item.applied_at),
    appliedByName: nullableStringOf(item.applied_by_name),
    appliedByPosition: nullableStringOf(item.applied_by_position),
    bodyRegion,
    cancelledAt: nullableStringOf(item.cancelled_at),
    expectedRemovalAt: stringOf(item.expected_removal_at),
    key: stringOf(item.key),
    laterality,
    occurredAt: nullableStringOf(item.occurred_at),
    removedAt: nullableStringOf(item.removed_at),
    removedByName: nullableStringOf(item.removed_by_name),
    removedByPosition: nullableStringOf(item.removed_by_position),
    status,
  };
}

function parsePatientPortalMedicalCertificatePage(payload: PatientPortalMedicalCertificatePayload, page: number, pageSize: number): PatientPortalMedicalCertificatePage {
  return {
    items: arrayOf(payload.items).map((value) => {
      const item = recordOf(value);
      return {
        attendanceId: nullablePositiveIntegerOf(item.attendance_id),
        createdAt: stringOf(item.created_at),
        documentReady: item.document_ready === true,
        finalizedAt: stringOf(item.finalized_at),
        id: positiveIntegerOf(item.id),
        leaveDays: positiveIntegerOf(item.leave_days),
        professionalName: stringOf(item.professional_name),
        professionalPosition: nullableStringOf(item.professional_position),
      };
    }),
    page,
    pageSize,
    patient: parsePortalIdentity(payload.patient),
    total: positiveIntegerOf(payload.total, true),
  };
}

function parsePatientPortalMedicalCertificateDetail(payload: PatientPortalMedicalCertificatePayload): PatientPortalMedicalCertificateDetail {
  const certificate = recordOf(payload.certificate);
  const snapshot = parseMedicalCertificateSnapshot(certificate.snapshot);
  const document = payload.document === null || payload.document === undefined ? null : recordOf(payload.document);
  return {
    document: document ? {
      fileSize: positiveIntegerOf(document.file_size),
      height: positiveIntegerOf(document.height),
      path: stringOf(document.path),
      renderVersion: stringOf(document.render_version),
      width: positiveIntegerOf(document.width),
    } : null,
    id: positiveIntegerOf(certificate.id),
    patient: parsePortalIdentity(payload.patient),
    snapshot,
  };
}

function parseMedicalCertificateSnapshot(value: unknown): MedicalCertificateSnapshot {
  const snapshot = recordOf(value);
  const patient = recordOf(snapshot.patient);
  const attendance = recordOf(snapshot.attendance);
  const professional = recordOf(snapshot.professional);
  if (snapshot.schema !== "hpsm.medical_certificate_snapshot.v1" && snapshot.schema !== "hpsm.medical_certificate_snapshot.v2") throw new Error("patient_portal_invalid_medical_certificate_snapshot");
  return {
    attendance: { created_at: stringOf(attendance.created_at), id: positiveIntegerOf(attendance.id) },
    certificate_id: positiveIntegerOf(snapshot.certificate_id),
    issued_at: stringOf(snapshot.issued_at),
    leave_days: positiveIntegerOf(snapshot.leave_days),
    patient: { id: positiveIntegerOf(patient.id), name: stringOf(patient.name), passport: stringOf(patient.passport) },
    professional: {
      crm_code: stringOf(professional.crm_code),
      id: stringOf(professional.id),
      name: stringOf(professional.name),
      position: nullableStringOf(professional.position),
      registration_date: stringOf(professional.registration_date),
      signature_image_path: stringOf(professional.signature_image_path),
    },
    schema: snapshot.schema,
    origin_type: snapshot.origin_type === "consultation" ? "consultation" : "attendance",
    consultation_id: nullablePositiveIntegerOf(snapshot.consultation_id),
    diagnosis: snapshot.schema === "hpsm.medical_certificate_snapshot.v2" ? (() => { const diagnosis = recordOf(snapshot.diagnosis); return { text: stringOf(diagnosis.text), cid_code: stringOf(diagnosis.cid_code), cid_description: stringOf(diagnosis.cid_description) }; })() : undefined,
    text: stringOf(snapshot.text),
  };
}

function parsePatientPortalHistoryPage(payload: PatientPortalPagePayload): PatientPortalHistoryPage {
  return {
    items: arrayOf(payload.items).map((item) => {
      const event = recordOf(item);
      const type = stringOf(event.type);
      if (!["attendance", "cast", "exam", "health_plan", "consultation", "certificate", "hospitalization", "legacy"].includes(type)) {
        throw new Error("patient_portal_history_invalid_type");
      }
      return {
        amount: nullableNumberOf(event.amount),
        attendanceId: nullablePositiveIntegerOf(event.attendance_id),
        description: nullableStringOf(event.description) ?? "",
        examId: type === "exam" ? historyExamId(stringOf(event.key)) : null,
        key: stringOf(event.key),
        occurredAt: stringOf(event.occurred_at),
        professionalName: nullableStringOf(event.professional_name),
        professionalPosition: nullableStringOf(event.professional_position),
        title: stringOf(event.title),
        type: type as PatientPortalHistoryItem["type"],
      };
    }),
    nextCursor: parseHistoryCursor(payload.next_cursor),
    patient: parsePortalIdentity(payload.patient),
  };
}

function parsePatientPortalAttendancePage(payload: PatientPortalPagePayload): PatientPortalAttendancePage {
  const summary = recordOf(payload.summary);
  return {
    items: arrayOf(payload.items).map((item) => parseAttendanceListItem(item)),
    metrics: {
      lifetimeSpent: numberOf(summary.lifetime_spent),
      totalAttendances: positiveIntegerOf(summary.total_attendances, true),
    },
    nextCursor: parseAttendanceCursor(payload.next_cursor),
    patient: parsePortalIdentity(payload.patient),
  };
}

function parsePatientPortalExamPage(payload: PatientPortalPagePayload): PatientPortalExamPage {
  return {
    items: arrayOf(payload.items).map(parsePatientPortalExamListItem),
    nextCursor: parseExamCursor(payload.next_cursor),
    patient: parsePortalIdentity(payload.patient),
  };
}

async function parsePatientPortalExamDetail(payload: PatientPortalExamDetailPayload): Promise<PatientPortalExamDetail> {
  const exam = parsePatientPortalExamListItem(payload.exam);
  const patient = parsePortalIdentity(payload.patient);
  let document: FinalExamDocumentModel | null = null;

  if (exam.status === "completed" && payload.final_report_snapshot) {
    const snapshot = parseFinalReportSnapshot(payload.final_report_snapshot);
    const images = arrayOf(payload.images).map((value): FinalExamDocumentImage => {
      const image = recordOf(value);
      const id = stringOf(image.id);
      return {
        caption: nullableStringOf(image.caption),
        created_at: stringOf(image.created_at),
        id,
        mime_type: stringOf(image.mime_type),
        original_filename: stringOf(image.original_filename),
        signed_url: `/api/patient-portal/exams/${exam.id}/images/${id}`,
        sort_order: positiveIntegerOf(image.sort_order, true),
        source: stringOf(image.source) as FinalExamDocumentImage["source"],
        storage_path: stringOf(image.storage_path),
      };
    });
    const enriched = await enrichClinicalExamIdentities(clinicalExamFromSnapshot(exam, snapshot));
    document = buildFinalExamDocument(enriched, images);
  }

  return { document, exam, patient };
}

function parsePatientPortalExamListItem(value: unknown): PatientPortalExamListItem {
  const exam = recordOf(value);
  const status = stringOf(exam.status);
  if (!isPatientPortalExamStatus(status)) throw new Error("patient_portal_exam_invalid_status");
  return {
    category: stringOf(exam.category),
    completedAt: nullableStringOf(exam.completed_at),
    id: positiveIntegerOf(exam.id),
    occurredAt: stringOf(exam.occurred_at),
    status,
    type: stringOf(exam.type),
  };
}

function parseFinalReportSnapshot(value: unknown) {
  const snapshot = recordOf(value);
  if (snapshot.schema !== "hpsm.exam_report_snapshot.v1" && snapshot.schema !== "hpsm.exam_report_snapshot.v2") {
    throw new Error("patient_portal_exam_invalid_snapshot");
  }
  return value as ClinicalExamReportSnapshot;
}

function parsePatientPortalConsultationItem(value: unknown): PatientPortalConsultationItem {
  const item = recordOf(value);
  const kind = stringOf(item.kind);
  const status = stringOf(item.status);
  if ((kind !== "appointment" && kind !== "consultation") || !["scheduled", "confirmed", "in_progress", "completed", "cancelled", "no_show"].includes(status)) {
    throw new Error("patient_portal_consultation_invalid_status");
  }
  return {
    completedAt: nullableStringOf(item.completed_at),
    consultationId: nullablePositiveIntegerOf(item.consultation_id),
    id: positiveIntegerOf(item.id),
    kind,
    occurredAt: stringOf(item.occurred_at),
    professionalName: nullableStringOf(item.professional_name),
    professionalPosition: nullableStringOf(item.professional_position),
    reason: nullableStringOf(item.reason),
    status: status as PatientPortalConsultationItem["status"],
  };
}

function clinicalExamFromSnapshot(exam: PatientPortalExamListItem, snapshot: ClinicalExamReportSnapshot): ClinicalExamDetail {
  const completedAt = snapshot.dates.completed_at ?? exam.completedAt;
  return {
    ai_generations: [],
    attendance_id: null,
    clinical_context: snapshot.clinical_context,
    completed_at: completedAt,
    conclusion: snapshot.content.conclusion,
    correction_reason: null,
    created_at: snapshot.dates.requested_at,
    exam_type: {
      category_id: snapshot.exam.category_id,
      category_name: snapshot.exam.category_name,
      id: snapshot.exam.id,
      name: snapshot.exam.name,
    },
    final_report_snapshot: snapshot,
    findings: snapshot.content.findings,
    history: [],
    id: exam.id,
    indication: snapshot.indication,
    patient: snapshot.patient,
    report_config: snapshot.report_config,
    report_versions: [],
    requested_at: snapshot.dates.requested_at,
    requested_by: snapshot.requested_by,
    responsible_professional: snapshot.executed_by,
    result_data: snapshot.content.result_data,
    reviewed_by: snapshot.reviewed_by,
    started_at: snapshot.dates.started_at,
    status: "completed",
    submitted_for_review_at: snapshot.dates.submitted_for_review_at,
    technique: snapshot.content.technique,
    updated_at: completedAt ?? snapshot.dates.requested_at,
  };
}

function parsePatientPortalAttendanceDetail(payload: PatientPortalAttendanceDetailPayload): PatientPortalAttendanceDetail {
  const attendance = recordOf(payload.attendance);
  return {
    attendance: {
      ...parseAttendanceListItem(attendance, false),
      discount: numberOf(attendance.discount),
      items: arrayOf(attendance.items).map((item) => {
        const row = recordOf(item);
        return {
          discountAmount: numberOf(row.discount_amount),
          discountPercent: numberOf(row.discount_percent),
          lineTotal: numberOf(row.line_total),
          name: stringOf(row.name),
          quantity: positiveIntegerOf(row.quantity),
          unitPrice: numberOf(row.unit_price),
        };
      }),
      subtotal: numberOf(attendance.subtotal),
    },
    patient: parsePortalIdentity(payload.patient),
  };
}

function parseAttendanceListItem(value: unknown, requireItemCount = true): PatientPortalAttendanceListItem {
  const item = recordOf(value);
  return {
    benefitCode: nullableStringOf(item.benefit_code),
    benefitName: nullableStringOf(item.benefit_name),
    id: positiveIntegerOf(item.id),
    itemCount: requireItemCount ? positiveIntegerOf(item.item_count, true) : arrayOf(item.items).reduce<number>((total, entry) => {
      const quantity = positiveIntegerOf(recordOf(entry).quantity);
      return total + quantity;
    }, 0),
    occurredAt: stringOf(item.occurred_at),
    professionalName: nullableStringOf(item.professional_name),
    professionalPosition: nullableStringOf(item.professional_position),
    total: numberOf(item.total),
  };
}

function parsePortalIdentity(value: unknown): PatientPortalIdentity {
  const patient = recordOf(value);
  return { name: stringOf(patient.name), passport: stringOf(patient.passport) };
}

function parseHistoryCursor(value: unknown): PatientPortalHistoryPage["nextCursor"] {
  if (value === null || value === undefined) return null;
  const cursor = recordOf(value);
  return { key: stringOf(cursor.key), occurredAt: stringOf(cursor.occurred_at) };
}

function parseAttendanceCursor(value: unknown): PatientPortalAttendancePage["nextCursor"] {
  if (value === null || value === undefined) return null;
  const cursor = recordOf(value);
  return { id: positiveIntegerOf(cursor.id), occurredAt: stringOf(cursor.occurred_at) };
}

function parseExamCursor(value: unknown): PatientPortalExamPage["nextCursor"] {
  if (value === null || value === undefined) return null;
  const cursor = recordOf(value);
  return { id: positiveIntegerOf(cursor.id), occurredAt: stringOf(cursor.occurred_at) };
}

function parseIdCursor(value: unknown): { id: number; occurredAt: string } | null {
  if (value === null || value === undefined) return null;
  const cursor = recordOf(value);
  return { id: positiveIntegerOf(cursor.id), occurredAt: stringOf(cursor.occurred_at) };
}

async function patientPortalDocumentRpc(name: string, body: Record<string, unknown>) {
  const token = await patientPortalCookieToken();
  if (!isPatientPortalToken(token)) return null;
  const payload = await callPatientPortalRpc<PatientPortalExamDocumentPayload>(name, {
    ...body,
    p_token_hash: await hashPatientPortalValue(token),
  });
  if (payload.authenticated !== true) return null;
  if (payload.found !== true) return "not_found" as const;
  return parseClinicalExamDocumentState(payload.state);
}

function parseClinicalExamDocumentState(value: unknown): ClinicalExamDocumentState {
  const state = recordOf(value);
  const rawDocument = state.document === null ? null : recordOf(state.document);
  const rawShare = state.share === null ? null : recordOf(state.share);
  return {
    document: rawDocument ? {
      created_at: stringOf(rawDocument.created_at),
      file_size: positiveIntegerOf(rawDocument.file_size),
      id: stringOf(rawDocument.id),
      pixel_height: positiveIntegerOf(rawDocument.pixel_height),
      pixel_width: positiveIntegerOf(rawDocument.pixel_width),
      render_version: stringOf(rawDocument.render_version) as NonNullable<ClinicalExamDocumentState["document"]>["render_version"],
    } : null,
    share: rawShare ? { created_at: stringOf(rawShare.created_at), id: stringOf(rawShare.id) } : null,
  };
}

function historyExamId(key: string) {
  const match = /^exam:(\d+)$/.exec(key);
  return match ? positiveIntegerOf(match[1]) : null;
}

function isPatientPortalExamStatus(value: string): value is PatientPortalExamStatus {
  return ["requested", "in_progress", "awaiting_review", "completed"].includes(value);
}

function isPatientPortalHealthPlanStatus(value: string): value is PatientPortalHealthPlanStatus {
  return ["active", "awaiting_confirmation", "expired", "none"].includes(value);
}

function isPatientPortalHealthPlanEvent(value: string): value is PatientPortalHealthPlanEvent {
  return ["activated", "not_approved", "renewed", "requested"].includes(value);
}

async function patientPortalCookieToken() {
  const cookieStore = await cookies();
  return cookieStore.get(PATIENT_PORTAL_COOKIE)?.value ?? "";
}

function arrayOf(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function nullableStringOf(value: unknown): string | null {
  return value === null || value === undefined ? null : stringOf(value);
}

function numberOf(value: unknown): number {
  const parsed = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(parsed)) throw new Error("patient_portal_summary_invalid_number");
  return parsed;
}

function nullableNumberOf(value: unknown): number | null {
  return value === null || value === undefined ? null : numberOf(value);
}

function nullablePositiveIntegerOf(value: unknown): number | null {
  return value === null || value === undefined ? null : positiveIntegerOf(value);
}

function positiveIntegerOf(value: unknown, allowZero = false): number {
  const parsed = numberOf(value);
  if (!Number.isInteger(parsed) || parsed < (allowZero ? 0 : 1)) {
    throw new Error("patient_portal_invalid_integer");
  }
  return parsed;
}

function recordOf(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("patient_portal_summary_invalid_object");
  }
  return value as Record<string, unknown>;
}

function stringOf(value: unknown): string {
  if (typeof value !== "string" || !value) throw new Error("patient_portal_summary_invalid_string");
  return value;
}
