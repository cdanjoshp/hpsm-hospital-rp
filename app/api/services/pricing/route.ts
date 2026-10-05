import { hasPermission } from "../../../lib/access";
import { authenticatedHeaders } from "../../../lib/operational-data";
import { getSessionContext } from "../../../lib/session";
import { getSupabaseConfig } from "../../../lib/supabase-server";
import { BENEFIT_PLANS, type PlanCode } from "../../../lib/benefit-plans";

type DiscountInput = {
  discountPercent?: unknown;
  planCode?: unknown;
};

type PricingRequest = {
  action?: unknown;
  discounts?: unknown;
  serviceId?: unknown;
  unitPrice?: unknown;
};

type BulkDiscountResult = {
  discounts: Record<PlanCode, number>;
  service_count: number;
  updated_rows: number;
};

type UnitPriceResult = {
  service_id: number;
  unit_price: number;
};

const PLAN_CODES = new Set<PlanCode>(BENEFIT_PLANS.map((plan) => plan.code));

export async function PATCH(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(context.profile, "catalog.manage")) {
    return Response.json({ error: "Acesso não autorizado." }, { status: 403 });
  }

  try {
    const body = (await request.json()) as PricingRequest;
    if (body.action === "unit_price") return updateUnitPrice(context.accessToken, body);
    if (body.action === "bulk_discounts") return updateBulkDiscounts(context.accessToken, body);
    return Response.json({ error: "Escolha uma alteração de preço válida." }, { status: 400 });
  } catch {
    return Response.json({ error: "Não foi possível interpretar os valores informados." }, { status: 400 });
  }
}

async function updateUnitPrice(accessToken: string, body: PricingRequest) {
  const serviceId = Number(body.serviceId);
  const unitPrice = parseDecimal(body.unitPrice);
  if (!Number.isSafeInteger(serviceId) || serviceId < 1) {
    return Response.json({ error: "Selecione um item válido." }, { status: 400 });
  }
  if (unitPrice === null || unitPrice < 0) {
    return Response.json({ error: "Informe um preço unitário válido, igual ou maior que zero." }, { status: 400 });
  }

  const response = await callPricingRpc<UnitPriceResult>(accessToken, "update_catalog_unit_price", {
    p_service_id: serviceId,
    p_unit_price: unitPrice,
  });
  if (!response.ok) return rpcFailure(response);
  const result = response.value;
  return Response.json(
    { serviceId: Number(result.service_id), unitPrice: Number(result.unit_price) },
    { headers: { "cache-control": "private, no-store" } },
  );
}

async function updateBulkDiscounts(accessToken: string, body: PricingRequest) {
  const discounts = parseDiscounts(body.discounts);
  if (!discounts) {
    return Response.json({ error: "Informe uma porcentagem entre 0% e 100% para cada um dos três benefícios." }, { status: 400 });
  }

  const response = await callPricingRpc<BulkDiscountResult>(accessToken, "update_catalog_discounts_bulk", {
    p_discounts: discounts.map((discount) => ({
      plan_code: discount.planCode,
      discount_percent: discount.discountPercent,
    })),
  });
  if (!response.ok) return rpcFailure(response);
  const result = response.value;
  return Response.json(
    {
      discounts: result.discounts,
      serviceCount: Number(result.service_count),
      updatedRows: Number(result.updated_rows),
    },
    { headers: { "cache-control": "private, no-store" } },
  );
}

async function callPricingRpc<T>(accessToken: string, rpc: string, body: Record<string, unknown>) {
  const { url } = getSupabaseConfig();
  const response = await fetch(`${url}/rest/v1/rpc/${rpc}`, {
    method: "POST",
    headers: authenticatedHeaders(accessToken),
    body: JSON.stringify(body),
    cache: "no-store",
  });
  if (!response.ok) {
    const payload = await response.json().catch(() => null) as { code?: string; message?: string } | null;
    return { ok: false as const, code: payload?.code, message: payload?.message };
  }
  return { ok: true as const, value: await response.json() as T };
}

function rpcFailure(failure: { code?: string; message?: string }) {
  const status = failure.code === "42501" ? 403 : failure.code === "P0002" ? 404 : 400;
  const fallback = status === 403 ? "Acesso não autorizado." : status === 404 ? "Item não localizado." : "Não foi possível salvar os valores.";
  return Response.json({ error: failure.message || fallback }, { status });
}

function parseDiscounts(value: unknown) {
  if (!Array.isArray(value) || value.length !== BENEFIT_PLANS.length) return null;
  const discounts = value.map((raw) => {
    const input = raw as DiscountInput;
    const planCode = input.planCode;
    const discountPercent = parseDecimal(input.discountPercent);
    if (typeof planCode !== "string" || !PLAN_CODES.has(planCode as PlanCode) || discountPercent === null || discountPercent < 0 || discountPercent > 100) return null;
    return { planCode: planCode as PlanCode, discountPercent };
  });
  if (discounts.some((discount) => !discount)) return null;
  const parsed = discounts as Array<{ discountPercent: number; planCode: PlanCode }>;
  if (new Set(parsed.map((discount) => discount.planCode)).size !== BENEFIT_PLANS.length) return null;
  return parsed;
}

function parseDecimal(value: unknown) {
  if (typeof value !== "number" && typeof value !== "string") return null;
  const number = Number(typeof value === "string" ? value.replace(",", ".") : value);
  return Number.isFinite(number) ? Math.round(number * 100) / 100 : null;
}
