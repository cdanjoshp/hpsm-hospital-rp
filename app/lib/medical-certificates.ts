import { authenticatedHeaders } from "./operational-data";
import type { CastBodyRegion, CastLaterality } from "./cast-types";
import { normalizePatientSearch } from "./passport";
import { getSupabaseConfig } from "./supabase-server";

export type MedicalCertificateStatus = "cancelled" | "draft" | "finalized";

export type MedicalCertificateListItem = {
  attendance_id: number | null;
  consultation_id?: number | null;
  cancelled_at: string | null;
  created_at: string;
  created_by: string;
  document_ready: boolean;
  finalized_at: string | null;
  id: number;
  leave_days: number;
  patient_id: number;
  patient_name: string;
  patient_passport: string;
  professional_name: string;
  professional_position: string | null;
  status: MedicalCertificateStatus;
};

export type MedicalCertificatePage = {
  items: MedicalCertificateListItem[];
  page: number;
  pageSize: number;
  total: number;
};

export type MedicalCertificateAttendanceOption = {
  created_at: string;
  id: number;
  professional_name: string;
  summary: string;
};

export type MedicalCertificateExamOption = {
  attendance_id: number | null;
  completed_at?: string | null;
  id: number;
  requested_at: string;
  status: string;
  type: string;
};

export type MedicalCertificateCastOption = {
  applied_at: string;
  attendance_id: number | null;
  body_region: CastBodyRegion;
  id: number;
  laterality: CastLaterality;
  status: string;
};

export type MedicalCertificateReferenceOptions = {
  attendances: MedicalCertificateAttendanceOption[];
  casts: MedicalCertificateCastOption[];
  cids: MedicalCid10[];
  exams: MedicalCertificateExamOption[];
};

export type MedicalCid10 = { code: string; description: string };

export type MedicalCertificateSnapshot = {
  attendance: { created_at: string; id: number };
  certificate_id: number;
  issued_at: string;
  leave_days: number;
  patient: { id: number; name: string; passport: string };
  professional: {
    crm_code: string;
    id: string;
    name: string;
    position: string | null;
    registration_date: string;
    signature_image_path: string;
  };
  schema: "hpsm.medical_certificate_snapshot.v1" | "hpsm.medical_certificate_snapshot.v2";
  text: string;
  diagnosis?: { text: string; cid_code: string; cid_description: string };
  origin_type?: "attendance" | "consultation";
  consultation_id?: number | null;
};

export type MedicalCertificateDetail = {
  ai_generated_at: string | null;
  ai_model: string | null;
  ai_prompt_version: string | null;
  attendance_created_at: string;
  attendance_id: number | null;
  consultation_id: number | null;
  origin_type: "attendance" | "consultation";
  attendance_summary: string;
  cancelled_at: string | null;
  cancellation_reason: string | null;
  casts: MedicalCertificateCastOption[];
  created_at: string;
  created_by: string;
  document_ready: boolean;
  exams: MedicalCertificateExamOption[];
  final_text: string | null;
  finalized_at: string | null;
  generated_text: string | null;
  id: number;
  leave_days: number;
  medical_context: string;
  diagnosis_text: string | null;
  cid_code: string | null;
  cid_description: string | null;
  patient_id: number;
  patient_name: string;
  patient_passport: string;
  professional_name: string;
  professional_position: string | null;
  professional_snapshot: MedicalCertificateSnapshot | null;
  status: MedicalCertificateStatus;
  updated_at: string;
};

export type MedicalCertificateDocumentState = {
  document: null | {
    file_size: number;
    height: number;
    path: string;
    render_version: string;
    width: number;
  };
  id: number;
  snapshot: MedicalCertificateSnapshot | null;
  status: MedicalCertificateStatus;
};

export async function getMedicalCertificatePage(
  accessToken: string,
  options: { createdBy?: string | null; dateFrom?: string | null; dateTo?: string | null; page?: number; pageSize?: number; search?: string; status?: MedicalCertificateStatus | null } = {},
): Promise<MedicalCertificatePage> {
  const page = positiveInteger(options.page, 1);
  const pageSize = Math.min(positiveInteger(options.pageSize, 20), 50);
  const payload = await callMedicalCertificateRpc<Omit<MedicalCertificatePage, "page" | "pageSize">>(accessToken, "medical_certificate_page", {
    p_created_by: options.createdBy ?? null,
    p_date_from: options.dateFrom ?? null,
    p_date_to: options.dateTo ?? null,
    p_limit: pageSize,
    p_offset: (page - 1) * pageSize,
    p_search: normalizePatientSearch(clean(options.search)),
    p_status: options.status ?? null,
  });
  return { ...payload, page, pageSize };
}

export function getMedicalCertificateDetail(accessToken: string, certificateId: number) {
  return callMedicalCertificateRpc<MedicalCertificateDetail>(accessToken, "medical_certificate_detail", { p_certificate_id: certificateId });
}

export function getMedicalCertificateReferenceOptions(accessToken: string, patientId: number) {
  return callMedicalCertificateRpc<MedicalCertificateReferenceOptions>(accessToken, "medical_certificate_reference_options", { p_patient_id: patientId });
}

export function getMedicalCertificateCidCatalog(accessToken: string, search?: string) {
  return callMedicalCertificateRpc<MedicalCid10[]>(accessToken, "medical_certificate_cid_catalog", { p_search: search?.trim() || null });
}

export async function getPatientMedicalCertificatePage(accessToken: string, patientId: number, page = 1, pageSize = 10) {
  const normalizedPage = positiveInteger(page, 1);
  const normalizedSize = Math.min(positiveInteger(pageSize, 10), 25);
  const payload = await callMedicalCertificateRpc<{ items: Omit<MedicalCertificateListItem, "patient_id" | "patient_name" | "patient_passport" | "created_by">[]; total: number }>(accessToken, "patient_medical_certificate_page", {
    p_limit: normalizedSize,
    p_offset: (normalizedPage - 1) * normalizedSize,
    p_patient_id: patientId,
  });
  return { ...payload, page: normalizedPage, pageSize: normalizedSize };
}

export function getMedicalCertificateDocumentState(accessToken: string, certificateId: number) {
  return callMedicalCertificateRpc<MedicalCertificateDocumentState>(accessToken, "medical_certificate_document_state", { p_certificate_id: certificateId });
}

export function registerMedicalCertificateDocument(accessToken: string, input: {
  certificateId: number;
  fileSize: number;
  height: number;
  renderVersion: string;
  storagePath: string;
  width: number;
}) {
  return callMedicalCertificateRpc<MedicalCertificateDocumentState>(accessToken, "register_medical_certificate_document", {
    p_certificate_id: input.certificateId,
    p_file_size: input.fileSize,
    p_height: input.height,
    p_render_version: input.renderVersion,
    p_storage_path: input.storagePath,
    p_width: input.width,
  });
}

export function runMedicalCertificateMutation<T>(accessToken: string, name: string, payload: Record<string, unknown>) {
  return callMedicalCertificateRpc<T>(accessToken, name, payload);
}

async function callMedicalCertificateRpc<T>(accessToken: string, name: string, payload: Record<string, unknown>): Promise<T> {
  const { url } = getSupabaseConfig();
  let response: Response;
  try {
    response = await fetch(`${url}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers: authenticatedHeaders(accessToken),
      body: JSON.stringify(payload),
      cache: "no-store",
      signal: AbortSignal.timeout(25_000),
    });
  } catch (error) {
    if (error instanceof DOMException && (error.name === "AbortError" || error.name === "TimeoutError")) {
      throw new Error("O módulo de Atestados demorou para responder. Tente novamente.");
    }
    throw error;
  }
  if (!response.ok) {
    const problem = await response.json().catch(() => null) as { message?: string } | null;
    throw new Error(problem?.message || "Não foi possível concluir a operação de atestado.");
  }
  if (response.status === 204) return undefined as T;
  const text = await response.text();
  return (text ? JSON.parse(text) : undefined) as T;
}

function positiveInteger(value: number | undefined, fallback: number) {
  return Number.isInteger(value) && Number(value) > 0 ? Number(value) : fallback;
}

function clean(value: string | undefined) {
  const result = value?.trim();
  return result ? result.slice(0, 120) : null;
}
