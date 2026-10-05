import type {
  CastAttendanceOption,
  ClinicalCastReference,
  ClinicalCastDetail,
  ClinicalCastPage,
  ClinicalCastPatientPage,
  ClinicalCastStatus,
  OverdueClinicalCast,
  PatientActiveClinicalCast,
} from "./cast-types";
import { authenticatedHeaders } from "./operational-data";
import { normalizePatientSearch } from "./passport";
import { getSupabaseConfig } from "./supabase-server";

type CastPagePayload = Omit<ClinicalCastPage, "page" | "pageSize">;
type CastPatientPagePayload = Omit<ClinicalCastPage, "page" | "pageSize"> & { cast_total: number };

export async function getClinicalCastPatientPage(
  accessToken: string,
  options: { page?: number; pageSize?: number; search?: string; status?: ClinicalCastStatus | null } = {},
): Promise<ClinicalCastPatientPage> {
  const page = positiveInteger(options.page, 1);
  const pageSize = Math.min(positiveInteger(options.pageSize, 20), 50);
  const payload = await callCastRpc<CastPatientPagePayload>(accessToken, "clinical_cast_patient_page", {
    p_limit: pageSize,
    p_offset: (page - 1) * pageSize,
    p_search: normalizePatientSearch(clean(options.search)),
    p_status: options.status ?? null,
  });
  return { items: payload.items, total: payload.total, castTotal: payload.cast_total, page, pageSize };
}

export async function getClinicalCastPage(
  accessToken: string,
  options: { page?: number; pageSize?: number; search?: string; status?: ClinicalCastStatus | null } = {},
): Promise<ClinicalCastPage> {
  const page = positiveInteger(options.page, 1);
  const pageSize = Math.min(positiveInteger(options.pageSize, 20), 50);
  const payload = await callCastRpc<CastPagePayload>(accessToken, "clinical_cast_page", {
    p_limit: pageSize,
    p_offset: (page - 1) * pageSize,
    p_search: normalizePatientSearch(clean(options.search)),
    p_status: options.status ?? null,
  });
  return { ...payload, page, pageSize };
}

export function getClinicalCastDetail(accessToken: string, castId: number) {
  return callCastRpc<ClinicalCastDetail>(accessToken, "clinical_cast_detail", { p_cast_id: castId });
}

export function getClinicalCastAttendanceOptions(accessToken: string, patientId: number) {
  return callCastRpc<CastAttendanceOption[]>(accessToken, "clinical_cast_attendance_options", { p_patient_id: patientId });
}

export function getClinicalCastReferences(accessToken: string, includeInactive = false) {
  return callCastRpc<ClinicalCastReference[]>(accessToken, "clinical_cast_reference_catalog", {
    p_include_inactive: includeInactive,
  });
}

export function getPatientActiveClinicalCasts(accessToken: string, patientId: number) {
  return callCastRpc<PatientActiveClinicalCast[]>(accessToken, "patient_active_clinical_casts", {
    p_patient_id: patientId,
  });
}

export function getOverdueClinicalCasts(accessToken: string, limit = 250) {
  return callCastRpc<OverdueClinicalCast[]>(accessToken, "clinical_cast_overdue_page", {
    p_limit: limit,
  });
}

export function runClinicalCastMutation<T>(accessToken: string, name: string, payload: Record<string, unknown>) {
  return callCastRpc<T>(accessToken, name, payload);
}

async function callCastRpc<T>(accessToken: string, name: string, payload: Record<string, unknown>): Promise<T> {
  const { url } = getSupabaseConfig();
  let response: Response;
  try {
    response = await fetch(`${url}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers: authenticatedHeaders(accessToken),
      body: JSON.stringify(payload),
      cache: "no-store",
      signal: AbortSignal.timeout(20_000),
    });
  } catch (error) {
    if (error instanceof DOMException && (error.name === "AbortError" || error.name === "TimeoutError")) {
      throw new Error("O Controle de Gesso demorou para responder. Tente novamente.");
    }
    throw error;
  }
  if (!response.ok) {
    const problem = await response.json().catch(() => null) as { code?: string; details?: string; message?: string } | null;
    const duplicate = problem?.details === "HPSM_ACTIVE_CAST_DUPLICATE";
    if (duplicate) throw new ActiveCastDuplicateError(problem?.message);
    throw new Error(problem?.message || "Não foi possível concluir a operação de gesso.");
  }
  if (response.status === 204) return undefined as T;
  const text = await response.text();
  return (text ? JSON.parse(text) : undefined) as T;
}

export class ActiveCastDuplicateError extends Error {}

function positiveInteger(value: number | undefined, fallback: number) {
  return Number.isInteger(value) && Number(value) > 0 ? Number(value) : fallback;
}

function clean(value: string | undefined) {
  const result = value?.trim();
  return result ? result.slice(0, 120) : null;
}
