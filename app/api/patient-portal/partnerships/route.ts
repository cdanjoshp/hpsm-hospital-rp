import {
  getPatientPortalPartnershipMemberPage,
  getPatientPortalPartnershipPage,
  mutatePatientPortalPartnership,
  PatientPortalRpcError,
} from "../../../lib/patient-portal";

export async function GET(request: Request) {
  try {
    const params = new URL(request.url).searchParams;
    const partnershipId = positive(params.get("partnershipId"));
    if (!partnershipId) {
      const page = await getPatientPortalPartnershipPage();
      return page ? Response.json(page) : Response.json({ error: "Sessão expirada." }, { status: 401 });
    }
    const page = await getPatientPortalPartnershipMemberPage(partnershipId, {
      filter: params.get("filter") ?? "all",
      offset: nonNegative(params.get("offset")),
      search: params.get("search") ?? "",
    });
    return page ? Response.json(page) : Response.json({ error: "Sessão expirada." }, { status: 401 });
  } catch (error) { return failure(error, "Não foi possível consultar esta parceria."); }
}

export async function POST(request: Request) {
  try {
    const body = await request.json() as Record<string, unknown>;
    const action = typeof body.action === "string" ? body.action : "";
    const partnershipId = positiveValue(body.partnershipId);
    if (action === "import") {
      if (!Array.isArray(body.people)) return Response.json({ error: "Informe ao menos uma pessoa." }, { status: 400 });
      const result = await mutatePatientPortalPartnership("patient_portal_import_partnership_people", {
        p_partnership_id: partnershipId,
        p_people: body.people,
        p_source: body.people.length === 1 ? "individual" : "batch",
      });
      return result === null ? Response.json({ error: "Sessão expirada." }, { status: 401 }) : Response.json(result);
    }
    if (action === "unlink" || action === "cancel") {
      if (typeof body.recordKey !== "string") return Response.json({ error: "Registro inválido." }, { status: 400 });
      const result = await mutatePatientPortalPartnership(action === "unlink" ? "patient_portal_unlink_partnership_member" : "patient_portal_cancel_partnership_pending", {
        p_partnership_id: partnershipId,
        p_record_key: body.recordKey,
      });
      return result === null ? Response.json({ error: "Sessão expirada." }, { status: 401 }) : Response.json({ ok: true });
    }
    return Response.json({ error: "Operação inválida." }, { status: 400 });
  } catch (error) { return failure(error, "Não foi possível concluir a operação."); }
}

function failure(error: unknown, fallback: string) {
  if (error instanceof PatientPortalRpcError) return Response.json({ error: error.rpcMessage ?? fallback }, { status: error.status === 401 ? 401 : 400 });
  return Response.json({ error: fallback }, { status: 400 });
}
function positive(value: string | null) { const parsed = Number(value); return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : 0; }
function nonNegative(value: string | null) { const parsed = Number(value); return Number.isSafeInteger(parsed) && parsed >= 0 ? parsed : 0; }
function positiveValue(value: unknown) { const parsed = Number(value); if (!Number.isSafeInteger(parsed) || parsed < 1) throw new Error("invalid"); return parsed; }
