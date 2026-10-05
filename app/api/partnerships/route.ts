import { hasPermission } from "../../lib/access";
import {
  getPartnershipDetail,
  getPartnershipMemberPage,
  getPartnershipPage,
  searchPartnershipPatients,
  type PartnershipImportResult,
  type PartnershipStatus,
} from "../../lib/partnerships";
import { getSessionContext } from "../../lib/session";
import { callSupabaseUserRpc, SupabaseUserRpcError } from "../../lib/supabase-user";

export async function GET(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(context.profile, "partnerships.view")) return Response.json({ error: "Acesso não autorizado." }, { status: 403 });

  try {
    const params = new URL(request.url).searchParams;
    const view = params.get("view") ?? "list";
    if (view === "list") {
      const status = params.get("status") === "inactive" ? "inactive" : "active";
      return Response.json(await getPartnershipPage(context.accessToken, {
        limit: positive(params.get("limit"), 24, 50),
        offset: nonNegative(params.get("offset")),
        search: params.get("search") ?? "",
        status,
      }));
    }
    if (view === "patients") {
      if (!await hasPermission(context.profile, "partnerships.manage")) return Response.json({ error: "Acesso não autorizado." }, { status: 403 });
      return Response.json({ items: await searchPartnershipPatients(context.accessToken, params.get("search") ?? "") });
    }
    const partnershipId = positive(params.get("partnershipId"), 0);
    if (!partnershipId) return Response.json({ error: "Parceria inválida." }, { status: 400 });
    if (view === "detail") return Response.json(await getPartnershipDetail(context.accessToken, partnershipId));
    if (view === "members") return Response.json(await getPartnershipMemberPage(context.accessToken, partnershipId, {
      filter: params.get("filter") ?? "all",
      limit: positive(params.get("limit"), 20, 50),
      offset: nonNegative(params.get("offset")),
      search: params.get("search") ?? "",
    }));
    return Response.json({ error: "Consulta inválida." }, { status: 400 });
  } catch (error) {
    return rpcFailure(error, "Não foi possível consultar as parcerias.");
  }
}

export async function POST(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(context.profile, "partnerships.manage")) return Response.json({ error: "Acesso não autorizado." }, { status: 403 });

  try {
    const body = await request.json() as Record<string, unknown>;
    const action = stringValue(body.action);
    if (action === "create") {
      const id = await callSupabaseUserRpc<number>(context.accessToken, "create_partnership", {
        p_name: stringValue(body.name),
        p_notes: nullableString(body.notes),
        p_responsible_patient_id: nullableId(body.responsiblePatientId),
      });
      return Response.json({ id }, { status: 201 });
    }
    const partnershipId = positiveValue(body.partnershipId);
    if (action === "update") {
      await callSupabaseUserRpc<boolean>(context.accessToken, "update_partnership_v2", {
        p_name: stringValue(body.name),
        p_notes: nullableString(body.notes),
        p_partnership_id: partnershipId,
        p_responsible_patient_id: nullableId(body.responsiblePatientId),
        p_secondary_responsible_patient_id: nullableId(body.secondaryResponsiblePatientId),
      });
      return Response.json({ ok: true });
    }
    if (action === "status") {
      const status = stringValue(body.status) as PartnershipStatus;
      if (!(["active", "inactive"] as string[]).includes(status)) throw new InputError("Situação de parceria inválida.");
      await callSupabaseUserRpc<boolean>(context.accessToken, "set_partnership_status", {
        p_partnership_id: partnershipId,
        p_reason: nullableString(body.reason),
        p_status: status,
      });
      return Response.json({ ok: true });
    }
    if (action === "import") {
      if (!Array.isArray(body.people)) throw new InputError("Informe ao menos uma pessoa.");
      const result = await callSupabaseUserRpc<PartnershipImportResult>(context.accessToken, "import_partnership_people", {
        p_partnership_id: partnershipId,
        p_people: body.people,
        p_source: body.people.length === 1 ? "individual" : "batch",
      });
      return Response.json(result);
    }
    if (action === "unlink") {
      await callSupabaseUserRpc<boolean>(context.accessToken, "unlink_patient_partnership", {
        p_membership_id: positiveValue(body.recordId),
        p_reason: stringValue(body.reason),
      });
      return Response.json({ ok: true });
    }
    if (action === "cancel") {
      await callSupabaseUserRpc<boolean>(context.accessToken, "cancel_partnership_pending", {
        p_pending_id: positiveValue(body.recordId),
        p_reason: stringValue(body.reason),
      });
      return Response.json({ ok: true });
    }
    if (action === "review") {
      const decision = stringValue(body.decision);
      if (!(["confirm", "reject"] as string[]).includes(decision)) throw new InputError("Decisão inválida.");
      await callSupabaseUserRpc<boolean>(context.accessToken, "review_partnership_pending", {
        p_decision: decision,
        p_pending_id: positiveValue(body.recordId),
        p_reason: nullableString(body.reason),
      });
      return Response.json({ ok: true });
    }
    throw new InputError("Operação inválida.");
  } catch (error) {
    return rpcFailure(error, "Não foi possível concluir a operação.");
  }
}

function positive(value: string | null, fallback: number, max = Number.MAX_SAFE_INTEGER) {
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed > 0 ? Math.min(parsed, max) : fallback;
}

function nonNegative(value: string | null) {
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed >= 0 ? parsed : 0;
}

function positiveValue(value: unknown) {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 1) throw new InputError("Registro inválido.");
  return parsed;
}

function nullableId(value: unknown) {
  return value === null || value === undefined || value === "" ? null : positiveValue(value);
}

function stringValue(value: unknown) {
  if (typeof value !== "string") throw new InputError("Preencha os campos obrigatórios.");
  return value.trim();
}

function nullableString(value: unknown) {
  const result = typeof value === "string" ? value.trim() : "";
  return result || null;
}

function rpcFailure(error: unknown, fallback: string) {
  if (error instanceof InputError) return Response.json({ error: error.message }, { status: 400 });
  if (error instanceof SupabaseUserRpcError) {
    const status = error.status === 401 || error.status === 403 ? error.status : 400;
    return Response.json({ error: error.rpcMessage ?? fallback }, { status });
  }
  return Response.json({ error: fallback }, { status: 500 });
}

class InputError extends Error {}
