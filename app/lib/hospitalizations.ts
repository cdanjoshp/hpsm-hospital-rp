import { authenticatedHeaders } from "./operational-data";
import { normalizePatientSearch } from "./passport";
import { getSupabaseConfig } from "./supabase-server";

export type HospitalizationSource = "hpsm" | "hp_norte";
export type HospitalizationStatus = "active" | "discharged" | "cancelled";

export type HospitalBed = {
  admitted_at: string | null;
  admitted_by: string | null;
  admitted_by_name: string | null;
  code: string;
  hospitalization_id: number | null;
  id: number;
  label: string;
  notes: string | null;
  number: number;
  patient_id: number | null;
  patient_name: string | null;
  patient_passport: string | null;
  reason: string | null;
  source: HospitalizationSource | null;
};

export type HospitalBedBoard = {
  available: number;
  beds: HospitalBed[];
  hp_norte: number;
  hpsm: number;
  occupied: number;
  total: number;
};

export type HospitalizationRecord = {
  admitted_at: string;
  admitted_by: string;
  admitted_by_name: string;
  bed_id: number;
  bed_label: string;
  bed_number: number;
  cancellation_reason: string | null;
  cancelled_at: string | null;
  cancelled_by: string | null;
  cancelled_by_name: string | null;
  created_at: string;
  discharged_at: string | null;
  discharged_by: string | null;
  discharged_by_name: string | null;
  id: number;
  notes: string | null;
  patient_id: number | null;
  patient_name: string;
  patient_passport: string | null;
  reason: string;
  source: HospitalizationSource;
  status: HospitalizationStatus;
  updated_at: string;
};

export type HospitalizationPage = {
  items: HospitalizationRecord[];
  page: number;
  pageSize: number;
  total: number;
};

export function getHospitalBedBoard(accessToken: string) {
  return callHospitalizationRpc<HospitalBedBoard>(accessToken, "hospital_bed_board", {});
}

export async function getHospitalizationHistory(accessToken: string, options: {
  bedId?: number | null;
  dateFrom?: string | null;
  dateTo?: string | null;
  page?: number;
  pageSize?: number;
  search?: string;
  source?: HospitalizationSource | null;
  status?: HospitalizationStatus | null;
} = {}): Promise<HospitalizationPage> {
  const page = positiveInteger(options.page, 1);
  const pageSize = Math.min(positiveInteger(options.pageSize, 20), 50);
  const result = await callHospitalizationRpc<Omit<HospitalizationPage, "page" | "pageSize">>(accessToken, "hospitalization_history_page", {
    p_bed_id: options.bedId ?? null,
    p_date_from: options.dateFrom || null,
    p_date_to: options.dateTo || null,
    p_limit: pageSize,
    p_offset: (page - 1) * pageSize,
    p_search: normalizePatientSearch(clean(options.search)),
    p_source: options.source ?? null,
    p_status: options.status ?? null,
  });
  return { ...result, page, pageSize };
}

export async function getPatientHospitalizationHistory(accessToken: string, patientId: number, page = 1, pageSize = 10) {
  const normalizedPage = positiveInteger(page, 1);
  const normalizedPageSize = Math.min(positiveInteger(pageSize, 10), 25);
  const result = await callHospitalizationRpc<{ items: Array<Pick<HospitalizationRecord, "admitted_at" | "admitted_by_name" | "bed_id" | "bed_label" | "cancellation_reason" | "cancelled_at" | "discharged_at" | "discharged_by_name" | "id" | "notes" | "reason" | "source" | "status">>; total: number }>(accessToken, "patient_hospitalization_page", {
    p_limit: normalizedPageSize,
    p_offset: (normalizedPage - 1) * normalizedPageSize,
    p_patient_id: patientId,
  });
  return { ...result, page: normalizedPage, pageSize: normalizedPageSize };
}

export function runHospitalizationMutation<T>(accessToken: string, name: string, payload: Record<string, unknown>) {
  return callHospitalizationRpc<T>(accessToken, name, payload);
}

async function callHospitalizationRpc<T>(accessToken: string, name: string, payload: Record<string, unknown>): Promise<T> {
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
      throw new Error("O Controle de Leitos demorou para responder. Tente novamente.");
    }
    throw error;
  }
  if (!response.ok) {
    const problem = await response.json().catch(() => null) as { code?: string; details?: string; message?: string } | null;
    const conflict = problem?.code === "23505" || problem?.details?.startsWith("HPSM_");
    if (conflict) throw new HospitalizationConflictError(problem?.message);
    throw new Error(problem?.message || "Não foi possível concluir a operação de internação.");
  }
  if (response.status === 204) return undefined as T;
  const text = await response.text();
  return (text ? JSON.parse(text) : undefined) as T;
}

export class HospitalizationConflictError extends Error {}

function positiveInteger(value: number | undefined, fallback: number) {
  return Number.isSafeInteger(value) && Number(value) > 0 ? Number(value) : fallback;
}

function clean(value: string | undefined) {
  const result = value?.trim();
  return result ? result.slice(0, 120) : null;
}
