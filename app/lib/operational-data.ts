import { getSupabaseAdminConfig, getSupabaseConfig } from "./supabase-server";
import { callSupabaseUserRpc } from "./supabase-user";
import type { PlanCode } from "./benefit-plans";

export { BENEFIT_PLANS, type PlanCode } from "./benefit-plans";

export type CatalogService = {
  active: boolean;
  category: string;
  code: string;
  created_at: string;
  id: number;
  icon: string;
  image_path: string | null;
  image_url?: string | null;
  name: string;
  plan_discounts: PlanDiscount[];
  sort_order: number;
  unit_price: number;
  updated_at: string;
};

export type PlanDiscount = {
  discount_percent: number;
  plan_code: PlanCode;
};

export type PatientHealthPlan = {
  activated_at: string | null;
  authorized_by: string | null;
  authorized_by_name: string | null;
  pending_request_id: number | null;
  pending_requested_at: string | null;
  status: "active" | "awaiting_confirmation" | "expired" | "none";
  valid_until: string | null;
};

export type Patient = {
  allergies: string | null;
  birth_date: string | null;
  created_at: string;
  emergency_contact_name: string | null;
  emergency_contact_phone: string | null;
  health_plan: PatientHealthPlan;
  id: number;
  name: string;
  passport: string;
  partnerships?: Array<{ id: number; linked_at: string; name: string; status: "active" | "inactive" }>;
  phone: string | null;
  updated_at: string;
};

export type AttendanceItem = {
  discount_amount: number;
  discount_percent: number;
  id: number;
  line_total: number;
  quantity: number;
  service_id: number;
  service_name: string;
  unit_price: number;
};

export type AttendanceRecord = {
  attendance_items: AttendanceItem[];
  created_at: string;
  discount: number;
  id: number;
  notes: string | null;
  patient_id: number | null;
  patient_name: string;
  patient_passport: string;
  partnership_id: number | null;
  partnership_name: string | null;
  plan_code: PlanCode | null;
  plan_name: string | null;
  performed_by: string;
  professional_name: string;
  professional_passport: string;
  professional_position: string;
  status: "completed" | "cancelled";
  subtotal: number;
  total: number;
};

export type AttendanceHistoryPage = {
  items: AttendanceRecord[];
  page: number;
  pageSize: number;
  total: number;
};

export function authenticatedHeaders(accessToken: string) {
  const { anonKey } = getSupabaseConfig();
  return {
    apikey: anonKey,
    authorization: `Bearer ${accessToken}`,
    "content-type": "application/json",
  };
}

export async function getServiceCatalog(accessToken: string): Promise<CatalogService[]> {
  return attachCatalogImageUrls(await getServiceCatalogMetadata(accessToken));
}

export async function getServiceCatalogMetadata(accessToken: string): Promise<CatalogService[]> {
  return callSupabaseUserRpc<CatalogService[]>(accessToken, "hpsm_operational_catalog");
}

export async function attachCatalogImageUrls(services: CatalogService[]): Promise<CatalogService[]> {
  const withImages = services.filter((service) => service.image_path);
  if (!withImages.length) return services;

  try {
    const { url, serviceRoleKey } = getSupabaseAdminConfig();
    const response = await fetch(`${url}/storage/v1/object/sign/catalog-images`, {
      method: "POST",
      headers: {
        apikey: serviceRoleKey,
        authorization: `Bearer ${serviceRoleKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        expiresIn: 600,
        paths: withImages.map((service) => service.image_path),
      }),
      cache: "no-store",
    });
    if (!response.ok) return markCatalogImagesForFallback(services);
    const signedItems = (await response.json()) as Array<{
      path?: string | null;
      signedURL?: string | null;
      signedUrl?: string | null;
    }>;
    const signedByPath = new Map<string, string>();
    withImages.forEach((service, index) => {
      const path = service.image_path;
      const item = signedItems[index];
      const signed = item?.signedURL ?? item?.signedUrl;
      if (!path || !signed) return;
      const signedUrl = signed.startsWith("http")
        ? signed
        : `${url}/storage/v1${signed.startsWith("/") ? "" : "/"}${signed}`;
      signedByPath.set(path, signedUrl);
      if (item.path) signedByPath.set(item.path, signedUrl);
    });
    return services.map((service) => ({
      ...service,
      image_url: service.image_path ? signedByPath.get(service.image_path) ?? null : null,
    }));
  } catch {
    // A rota autenticada individual permanece como fallback seguro.
    return markCatalogImagesForFallback(services);
  }
}

function markCatalogImagesForFallback(services: CatalogService[]): CatalogService[] {
  return services.map((service) => service.image_path ? { ...service, image_url: null } : service);
}

export async function getAttendanceHistory(accessToken: string, page = 1, pageSize = 20, focusId: number | null = null): Promise<AttendanceHistoryPage> {
  const safePage = Math.max(1, Math.trunc(page));
  const safePageSize = Math.min(50, Math.max(1, Math.trunc(pageSize)));
  return callSupabaseUserRpc<AttendanceHistoryPage>(accessToken, "hpsm_attendance_history_page", {
    p_limit: safePageSize,
    p_offset: (safePage - 1) * safePageSize,
    p_focus_id: focusId,
  });
}
