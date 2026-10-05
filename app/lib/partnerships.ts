import { callSupabaseUserRpc } from "./supabase-user";
import { normalizePatientSearch } from "./passport";

export type PartnershipStatus = "active" | "inactive";
export type PartnershipMemberStatus = "linked" | "pending_registration" | "name_review";

export type PartnershipPatient = {
  id: number;
  name: string;
  passport: string;
  portal_ready: boolean;
};

export type PartnershipSummary = {
  created_at: string;
  id: number;
  linked: number;
  name: string;
  name_review: number;
  pending_registration: number;
  responsible: Omit<PartnershipPatient, "portal_ready"> | null;
  secondary_responsible: Omit<PartnershipPatient, "portal_ready"> | null;
  status: PartnershipStatus;
  total_informed: number;
  updated_at: string;
};

export type PartnershipPage = {
  items: PartnershipSummary[];
  limit: number;
  offset: number;
  total: number;
};

export type PartnershipDetail = {
  deactivated_at: string | null;
  deactivation_reason: string | null;
  created_at: string;
  id: number;
  name: string;
  notes: string | null;
  responsible: PartnershipPatient | null;
  secondary_responsible: PartnershipPatient | null;
  status: PartnershipStatus;
  updated_at: string;
};

export type PartnershipDetailPage = {
  found: boolean;
  metrics?: { linked: number; name_review: number; pending_registration: number };
  partnership?: PartnershipDetail;
};

export type PartnershipMember = {
  canonical_name: string | null;
  id: number;
  name: string;
  occurred_at: string;
  origin: "partnership_responsible" | "professional" | "system";
  passport: string;
  patient_id: number | null;
  record_type: "membership" | "pending";
  status: PartnershipMemberStatus;
};

export type PartnershipMemberPage = {
  items: PartnershipMember[];
  limit: number;
  offset: number;
  total: number;
};

export type PartnershipImportResult = {
  items: Array<{ line: number; name: string; passport: string; result: "already_linked" | "invalid" | "linked" | "name_review" | "pending_registration" }>;
  summary: { already_linked: number; invalid: number; linked: number; name_review: number; pending_registration: number; total: number };
};

export async function getPartnershipPage(accessToken: string, options: { limit?: number; offset?: number; search?: string; status?: PartnershipStatus } = {}) {
  return callSupabaseUserRpc<PartnershipPage>(accessToken, "hpsm_partnership_page", {
    p_limit: options.limit ?? 24,
    p_offset: options.offset ?? 0,
    p_search: normalizePatientSearch(options.search) ?? "",
    p_status: options.status ?? "active",
  });
}

export async function getPartnershipDetail(accessToken: string, partnershipId: number) {
  return callSupabaseUserRpc<PartnershipDetailPage>(accessToken, "hpsm_partnership_detail", { p_partnership_id: partnershipId });
}

export async function getPartnershipMemberPage(accessToken: string, partnershipId: number, options: { filter?: string; limit?: number; offset?: number; search?: string } = {}) {
  return callSupabaseUserRpc<PartnershipMemberPage>(accessToken, "hpsm_partnership_member_page", {
    p_filter: options.filter ?? "all",
    p_limit: options.limit ?? 20,
    p_offset: options.offset ?? 0,
    p_partnership_id: partnershipId,
    p_search: normalizePatientSearch(options.search) ?? "",
  });
}

export async function searchPartnershipPatients(accessToken: string, search: string) {
  return callSupabaseUserRpc<PartnershipPatient[]>(accessToken, "hpsm_partnership_patient_lookup", { p_limit: 8, p_search: normalizePatientSearch(search) ?? "" });
}
