import { hasAnyPermission, hasPermission } from "../../lib/access";
import { authenticatedHeaders, getAttendanceHistory } from "../../lib/operational-data";
import { getSessionContext } from "../../lib/session";
import { getSupabaseConfig } from "../../lib/supabase-server";
import { callSupabaseUserRpc, SupabaseUserRpcError } from "../../lib/supabase-user";

type AttendanceInput = {
  benefitCode?: unknown;
  items?: unknown;
  notes?: unknown;
  patientId?: unknown;
  partnershipId?: unknown;
};

export async function GET(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasAnyPermission(context.profile, ["attendances.create", "attendances.manage", "patients.view", "sr.directors.view"])) {
    return Response.json({ error: "Acesso não autorizado." }, { status: 403 });
  }

  try {
    const searchParams = new URL(request.url).searchParams;
    const page = positiveInteger(searchParams.get("page"), 1, 10_000);
    const pageSize = positiveInteger(searchParams.get("pageSize"), 20, 50);
    const focusId = optionalPositiveInteger(searchParams.get("focusId"));
    return Response.json({ history: await getAttendanceHistory(context.accessToken, page, pageSize, focusId) });
  } catch {
    return Response.json({ error: "Não foi possível consultar o histórico." }, { status: 503 });
  }
}

function positiveInteger(value: string | null, fallback: number, maximum: number) {
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed > 0 ? Math.min(parsed, maximum) : fallback;
}

function optionalPositiveInteger(value: string | null) {
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null;
}

export async function POST(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(context.profile, "attendances.create")) return Response.json({ error: "Acesso não autorizado." }, { status: 403 });

  try {
    const body = (await request.json()) as AttendanceInput;
    if (!Array.isArray(body.items)) {
      return Response.json({ error: "Preencha os dados do atendimento." }, { status: 400 });
    }

    const patientId = body.patientId === null || body.patientId === undefined || body.patientId === ""
      ? null
      : Number(body.patientId);
    const benefitCode = body.benefitCode === null || body.benefitCode === ""
      ? null
      : typeof body.benefitCode === "string" ? body.benefitCode : undefined;
    const notes = typeof body.notes === "string" ? body.notes.trim() : "";
    const partnershipId = body.partnershipId === null || body.partnershipId === undefined || body.partnershipId === ""
      ? null
      : Number(body.partnershipId);
    const items = body.items.map((item) => {
      const value = item as { serviceId?: unknown; quantity?: unknown };
      return {
        service_id: Number(value.serviceId),
        quantity: Number(value.quantity),
      };
    });

    if (
      (patientId !== null && (!Number.isSafeInteger(patientId) || patientId < 1)) ||
      (partnershipId !== null && (!Number.isSafeInteger(partnershipId) || partnershipId < 1)) ||
      notes.length > 1000 ||
      benefitCode === undefined ||
      (benefitCode !== null && !["plano_saude", "parceiros_hp", "policiais_arcanjos"].includes(benefitCode)) ||
      items.length < 1 ||
      items.length > 50 ||
      items.some((item) => !Number.isSafeInteger(item.service_id) || !Number.isInteger(item.quantity) || item.quantity < 1 || item.quantity > 99)
    ) {
      return Response.json({ error: "Os dados informados não são válidos." }, { status: 400 });
    }

    const id = Number(await callSupabaseUserRpc<number>(context.accessToken, "create_attendance", {
      p_benefit_code: benefitCode,
      p_items: items,
      p_notes: notes || null,
      p_partnership_id: partnershipId,
      p_patient_id: patientId,
    }));
    if (!Number.isSafeInteger(id)) throw new Error("Identificador inválido.");
    return Response.json({ id }, { status: 201 });
  } catch (error) {
    if (error instanceof SupabaseUserRpcError) {
      return Response.json({ error: error.rpcMessage ?? "Não foi possível registrar a venda. Revise o paciente, os itens e os valores." }, { status: 400 });
    }
    return Response.json({ error: "Não foi possível concluir o atendimento." }, { status: 500 });
  }
}

export async function PATCH(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(context.profile, "attendances.manage")) return Response.json({ error: "Acesso não autorizado." }, { status: 403 });

  try {
    const body = (await request.json()) as { attendanceId?: unknown };
    const attendanceId = Number(body.attendanceId);
    if (!Number.isSafeInteger(attendanceId) || attendanceId < 1) {
      return Response.json({ error: "Atendimento inválido." }, { status: 400 });
    }

    const { url } = getSupabaseConfig();
    const response = await fetch(`${url}/rest/v1/rpc/cancel_attendance`, {
      method: "POST",
      headers: authenticatedHeaders(context.accessToken),
      body: JSON.stringify({ p_attendance_id: attendanceId }),
    });
    if (!response.ok) throw new Error("cancel");
    const cancelled = Boolean(await response.json());
    if (!cancelled) return Response.json({ error: "O atendimento já foi cancelado ou não existe." }, { status: 409 });
    return Response.json({ ok: true });
  } catch {
    return Response.json({ error: "Não foi possível cancelar o atendimento." }, { status: 500 });
  }
}
