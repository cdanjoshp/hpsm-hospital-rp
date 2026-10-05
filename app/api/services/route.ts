import { hasPermission } from "../../lib/access";
import { adminHeaders } from "../../lib/admin-data";
import { authenticatedHeaders, BENEFIT_PLANS, getServiceCatalogMetadata } from "../../lib/operational-data";
import type { CatalogService, PlanCode } from "../../lib/operational-data";
import { getSessionAccessToken, getSessionContext } from "../../lib/session";
import { getSupabaseAdminConfig } from "../../lib/supabase-server";
import { SupabaseUserRpcError } from "../../lib/supabase-user";

type DiscountInput = {
  discountPercent?: unknown;
  planCode?: unknown;
};

type PricingInput = {
  active?: unknown;
  category?: unknown;
  discounts?: unknown;
  id?: unknown;
  icon?: unknown;
  name?: unknown;
  sortOrder?: unknown;
  unitPrice?: unknown;
};

const PLAN_CODES = new Set<PlanCode>(BENEFIT_PLANS.map((plan) => plan.code));

export async function GET() {
  const accessToken = await getSessionAccessToken();
  if (!accessToken) return Response.json({ error: "Sessão expirada." }, { status: 401 });

  try {
    const services = await getServiceCatalogMetadata(accessToken);
    return Response.json(
      { services },
      { headers: { "cache-control": "private, max-age=30" } },
    );
  } catch (cause) {
    if (cause instanceof SupabaseUserRpcError && (cause.status === 401 || cause.status === 403)) {
      return Response.json({ error: cause.status === 401 ? "Sessão expirada." : "Acesso não autorizado." }, { status: cause.status });
    }
    return Response.json({ error: "Não foi possível consultar a tabela de preços." }, { status: 503 });
  }
}

export async function PATCH(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(context.profile, "catalog.manage")) return Response.json({ error: "Acesso não autorizado." }, { status: 403 });

  try {
    const input = parsePricingInput((await request.json()) as PricingInput);
    const { url, serviceRoleKey } = getSupabaseAdminConfig();
    const headers = authenticatedHeaders(context.accessToken);
    const updateResponse = await fetch(`${url}/rest/v1/rpc/update_catalog_pricing`, {
      method: "POST",
      headers,
      body: JSON.stringify({
        p_service_id: input.id,
        p_unit_price: input.unitPrice,
        p_discounts: input.discounts.map((discount) => ({
          plan_code: discount.planCode,
          discount_percent: discount.discountPercent,
        })),
      }),
    });

    if (!updateResponse.ok) {
      return Response.json({ error: "Não foi possível salvar os valores." }, { status: 400 });
    }

    const detailsResponse = await fetch(`${url}/rest/v1/service_catalog?id=eq.${input.id}`, {
      method: "PATCH",
      headers: { ...adminHeaders(serviceRoleKey), Prefer: "return=minimal" },
      body: JSON.stringify({
        active: input.active,
        category: input.category,
        icon: input.icon,
        name: input.name,
        sort_order: input.sortOrder,
        updated_by: context.profile.user_id,
      }),
    });
    if (!detailsResponse.ok) {
      return Response.json({ error: "Os valores foram atualizados, mas os dados do item não puderam ser salvos." }, { status: 400 });
    }

    const serviceResponse = await fetch(
      `${url}/rest/v1/service_catalog?select=id,code,icon,image_path,name,category,unit_price,active,sort_order,created_at,updated_at,plan_discounts(plan_code,discount_percent)&id=eq.${input.id}`,
      { headers, cache: "no-store" },
    );
    if (!serviceResponse.ok) throw new Error("read");
    const services = (await serviceResponse.json()) as CatalogService[];
    if (!services[0]) return Response.json({ error: "Item não localizado." }, { status: 404 });
    return Response.json({ service: services[0] });
  } catch {
    return Response.json({ error: "Confira o preço e os percentuais informados." }, { status: 400 });
  }
}

function parsePricingInput(body: PricingInput) {
  const id = Number(body.id);
  const unitPrice = Number(body.unitPrice);
  const name = typeof body.name === "string" ? body.name.trim() : "";
  const category = typeof body.category === "string" ? body.category.trim() : "";
  const icon = typeof body.icon === "string" ? body.icon.trim() : "";
  const sortOrder = Number(body.sortOrder);
  if (
    !Number.isSafeInteger(id) || id < 1 || !Number.isFinite(unitPrice) || unitPrice < 0
    || name.length < 2 || name.length > 100
    || category.length < 2 || category.length > 60
    || icon.length < 1 || icon.length > 12
    || !Number.isSafeInteger(sortOrder) || sortOrder < -10000 || sortOrder > 10000
    || typeof body.active !== "boolean"
  ) {
    throw new Error("pricing");
  }
  if (!Array.isArray(body.discounts) || body.discounts.length !== BENEFIT_PLANS.length) {
    throw new Error("discounts");
  }

  const discounts = body.discounts.map((raw) => {
    const discount = raw as DiscountInput;
    const planCode = discount.planCode;
    const discountPercent = Number(discount.discountPercent);
    if (
      typeof planCode !== "string" ||
      !PLAN_CODES.has(planCode as PlanCode) ||
      !Number.isFinite(discountPercent) ||
      discountPercent < 0 ||
      discountPercent > 100
    ) {
      throw new Error("discount");
    }
    return {
      planCode: planCode as PlanCode,
      discountPercent: Math.round(discountPercent * 100) / 100,
    };
  });

  if (new Set(discounts.map((discount) => discount.planCode)).size !== BENEFIT_PLANS.length) {
    throw new Error("duplicate");
  }

  return {
    active: body.active,
    category,
    discounts,
    id,
    icon,
    name,
    sortOrder,
    unitPrice: Math.round(unitPrice * 100) / 100,
  };
}
