import { getSupabaseAdminConfig } from "./supabase-server";
import { SessionProfile } from "./session";
import { callSupabaseUserRpc } from "./supabase-user";

export type ManagedProfile = SessionProfile & {
  created_at: string;
};

export type AuditEntry = {
  action: string;
  actor_passport: string | null;
  actor_position: string | null;
  created_at: string;
  entity_id: string | null;
  entity_name: string;
  id: string;
};

export type AuditPage = {
  items: AuditEntry[];
  page: number;
  pageSize: number;
  total: number;
};

export type AuditFilters = {
  action?: string;
  entity?: string;
  page?: number;
  search?: string;
};

export function isDirector(profile: SessionProfile) {
  return ["diretor_geral", "diretoria"].includes(profile.role_code);
}

export async function getManagedProfiles(): Promise<ManagedProfile[]> {
  const { url, serviceRoleKey } = getSupabaseAdminConfig();
  const response = await fetch(
    `${url}/rest/v1/profiles?select=user_id,passport,display_name,role_code,status,must_change_password,position_id,created_at&order=display_name.asc`,
    { headers: adminHeaders(serviceRoleKey), cache: "no-store" },
  );
  if (!response.ok) throw new Error("Não foi possível consultar a equipe.");
  return (await response.json()) as ManagedProfile[];
}

export async function getAuditEntries(accessToken: string, filters: AuditFilters = {}): Promise<AuditPage> {
  const page = Math.max(1, Math.trunc(filters.page ?? 1));
  const pageSize = 25;
  return callSupabaseUserRpc<AuditPage>(accessToken, "hpsm_audit_page", {
    p_action: filters.action?.trim() || null,
    p_entity: filters.entity?.trim() || null,
    p_limit: pageSize,
    p_offset: (page - 1) * pageSize,
    p_search: filters.search?.trim() || null,
  });
}

export function adminHeaders(serviceRoleKey: string) {
  return {
    apikey: serviceRoleKey,
    authorization: `Bearer ${serviceRoleKey}`,
    "content-type": "application/json",
  };
}
