import { authenticatedHeaders } from "./operational-data";
import { getSupabaseConfig } from "./supabase-server";
import type { ConsultationVitalRanges } from "./consultation-vitals";

export type AppointmentStatus = "scheduled" | "confirmed" | "in_progress" | "completed" | "cancelled" | "no_show";
export type ConsultationAiAction = "ANAMNESIS_REWRITE" | "EXAM_SUGGESTIONS" | "CLINICAL_SYNTHESIS";
export type ComplementaryAction = "NONE" | "CAST" | "HOSPITALIZATION";

export type ConsultationScheduleItem = {
  appointment_id: number | null;
  consultation_id: number | null;
  patient_id: number;
  patient_name: string;
  patient_passport: string;
  professional_id: string;
  professional_name: string;
  professional_position: string | null;
  starts_at: string;
  ends_at: string | null;
  duration_minutes: number | null;
  reason: string;
  notes: string | null;
  status: AppointmentStatus;
  walk_in: boolean;
  follow_up_of_consultation_id: number | null;
  created_at: string;
};

export type ConsultationPage = { items: ConsultationScheduleItem[]; total: number };
export type ConsultationProfessional = { id: string; name: string; position: string | null };
export type ConsultationExamType = { id: number; name: string; category: string };
export type ConsultationReferenceData = {
  professionals: ConsultationProfessional[];
  exam_types: ConsultationExamType[];
  vital_ranges: ConsultationVitalRanges;
  medications: RpMedication[];
};

export type RpMedication = {
  id: string;
  rp_name: string;
  reference_name: string;
  category: string;
  active: boolean;
  controlled: boolean;
  antibiotic: boolean;
  requires_justification: boolean;
  default_dose: string;
  default_frequency: string;
  default_duration: string;
  default_duration_days: number;
  default_route: string;
  default_instructions: string;
  default_doses_per_day: number;
  default_as_needed: boolean;
  version: number;
};

export type MedicationSuggestion = { medication_id: string; reason: string };
export type ConsultationPrescriptionItem = {
  id: string;
  medication_id: string;
  source: "ai" | "manual";
  catalog_version: number;
  rp_name_snapshot: string;
  reference_name_snapshot: string;
  dose_snapshot: string;
  frequency_snapshot: string;
  duration_snapshot: string;
  duration_days: number;
  route_snapshot: string;
  reason_snapshot: string;
  instructions_snapshot: string;
  justification_snapshot: string | null;
  calculated_quantity_snapshot: number;
  final_quantity_snapshot: number;
  quantity_override_snapshot: boolean;
  override_reason: string | null;
  created_at: string;
  updated_at: string;
};
export type ConsultationPrescription = {
  id: string;
  status: "draft" | "finalized";
  final_snapshot: Record<string, unknown> | null;
  created_at: string;
  finalized_at: string | null;
  items: ConsultationPrescriptionItem[];
};
export type MedicationDecision = {
  medication_id: string;
  source: "ai" | "manual";
  decision: "accepted" | "rejected" | "removed";
  reason: string | null;
  created_at: string;
};
export type RelatedClinicalProtocol = {
  id: string;
  display_name: string;
  state: "CANDIDATE" | "LEARNED" | "CONSOLIDATED";
  observed_count: number;
  similarity: number;
  body_system: string;
  case_tags: string[];
  vital_flags: string[];
  diagnoses: Array<{ name: string; count: number }>;
  exams: Array<{ name: string; count: number }>;
  medications: Array<{ id: string; name: string; count: number }>;
};
export type ClinicalProtocolLibraryData = {
  can_moderate: boolean;
  settings: {
    candidate_to_learned_count: number;
    learned_to_consolidated_count: number;
    merge_similarity_threshold: number;
    related_similarity_threshold: number;
    max_related_protocols: number;
  };
  protocols: Array<{
    id: string; display_name: string; state: "CANDIDATE" | "LEARNED" | "CONSOLIDATED";
    moderation_status: "active" | "inactive" | "quarantined"; version: number; observed_count: number;
    body_system: string; case_tags: string[]; vital_flags: string[]; primary_diagnosis: string;
    first_observed_at: string; last_observed_at: string;
  }>;
  medications: Array<RpMedication>;
};

export type ConsultationDiagnosis = {
  severity: "normal" | "grave" | "gravissimo";
  diagnosis?: string;
  reasoning_summary?: string;
  final_plan?: string;
  complementary_action?: ComplementaryAction;
  complementary_action_dismissed?: boolean;
  orientation?: string;
  medication_suggestions?: MedicationSuggestion[];
  title?: string;
  rationale?: string;
};
export type ConsultationAiGeneration = { action_type: ConsultationAiAction; status: "pending" | "completed" | "failed"; response: Record<string, unknown> | null; error: string | null; requested_at: string; completed_at: string | null };
export type ConsultationDetail = {
  id: number;
  status: "in_progress" | "completed";
  patient: { id: number; name: string; passport: string; allergies: string | null; plan_active: boolean; cast_active: boolean; hospitalization_active: boolean };
  professional: ConsultationProfessional;
  appointment: { id: number; scheduled_start: string; scheduled_end: string; reason: string; notes: string | null } | null;
  started_at: string;
  completed_at: string | null;
  vitals: {
    blood_pressure_systolic: number | null;
    blood_pressure_diastolic: number | null;
    blood_pressure_class: string | null;
    temperature_c: number | null;
    temperature_class: string | null;
    heart_rate_bpm: number | null;
    heart_rate_class: string | null;
    oxygen_saturation_percent: number | null;
    oxygen_saturation_class: string | null;
    pain_score: number | null;
  };
  anamnesis: string | null;
  selected_diagnosis: ConsultationDiagnosis | null;
  final_diagnosis_plan: string | null;
  complementary_action: ComplementaryAction;
  orientation_text: string | null;
  final_snapshot: Record<string, unknown> | null;
  ai_generations: ConsultationAiGeneration[];
  exams: Array<{ id: number; exam_type_id: number; type: string; status: string; conclusion: string | null; completed_at: string | null }>;
  casts: Array<{ id: number; body_region: string; status: string; applied_at: string }>;
  hospitalizations: Array<{ id: number; status: string; admitted_at: string }>;
  certificates: Array<{ id: number; status: string; leave_days: number; created_at: string }>;
  case_signature: { body_system: string; case_tags: string[]; vital_flags: string[] };
  related_protocols: RelatedClinicalProtocol[];
  prescription: ConsultationPrescription | null;
  medication_decisions: MedicationDecision[];
  can_edit: boolean;
};

export async function getConsultationReferences(accessToken: string) {
  const [base, rollup] = await Promise.all([
    callConsultationRpc<Omit<ConsultationReferenceData, "medications">>(accessToken, "consultation_reference_data", {}),
    callConsultationRpc<{ medications: RpMedication[] }>(accessToken, "consultation_rollup_reference_data", {}),
  ]);
  return { ...base, medications: rollup.medications };
}

export function getConsultationPage(accessToken: string, options: {
  search?: string; professionalId?: string | null; status?: AppointmentStatus | null;
  dateFrom?: string | null; dateTo?: string | null; mine?: boolean; page?: number; pageSize?: number;
} = {}) {
  const page = Math.max(1, options.page ?? 1);
  const pageSize = Math.min(100, Math.max(1, options.pageSize ?? 50));
  return callConsultationRpc<ConsultationPage>(accessToken, "consultation_schedule_page", {
    p_date_from: options.dateFrom || null,
    p_date_to: options.dateTo || null,
    p_limit: pageSize,
    p_mine: Boolean(options.mine),
    p_offset: (page - 1) * pageSize,
    p_professional_id: options.professionalId || null,
    p_search: options.search?.trim().slice(0, 120) || null,
    p_status: options.status || null,
  });
}

export async function getConsultationDetail(accessToken: string, consultationId: number) {
  const [base, rollup] = await Promise.all([
    callConsultationRpc<Omit<ConsultationDetail, "case_signature" | "related_protocols" | "prescription" | "medication_decisions">>(accessToken, "clinical_consultation_detail", { p_consultation_id: consultationId }),
    callConsultationRpc<Pick<ConsultationDetail, "case_signature" | "related_protocols" | "prescription" | "medication_decisions">>(accessToken, "consultation_rollup_detail", { p_consultation_id: consultationId }),
  ]);
  return { ...base, ...rollup };
}

export function runConsultationMutation<T>(accessToken: string, name: string, payload: Record<string, unknown>) {
  return callConsultationRpc<T>(accessToken, name, payload);
}

export function getClinicalProtocolLibrary(accessToken: string) {
  return callConsultationRpc<ClinicalProtocolLibraryData>(accessToken, "clinical_protocol_library", {});
}

async function callConsultationRpc<T>(accessToken: string, name: string, payload: Record<string, unknown>): Promise<T> {
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
    if (error instanceof DOMException && (error.name === "AbortError" || error.name === "TimeoutError")) throw new Error("O módulo de consultas demorou para responder. Tente novamente.");
    throw error;
  }
  if (!response.ok) {
    const problem = await response.json().catch(() => null) as { code?: string; message?: string } | null;
    throw new ConsultationRpcError(problem?.message || "Não foi possível concluir a operação.", problem?.code || null);
  }
  if (response.status === 204) return undefined as T;
  const text = await response.text();
  return (text ? JSON.parse(text) : undefined) as T;
}

export class ConsultationRpcError extends Error {
  constructor(message: string, public code: string | null) { super(message); }
}
