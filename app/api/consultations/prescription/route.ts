import { runConsultationMutation } from "../../../lib/consultations";
import { hasOptionalMedicationUse } from "../../../lib/rp-medications";
import { getSessionBootstrap } from "../../../lib/session";

export async function POST(request: Request) {
  const session = await getSessionBootstrap();
  if (!session) return response("Sessão expirada.", 401);
  if (!session.permissionCodes.includes("consultations.complete")) return response("Acesso não autorizado.", 403);
  try {
    const body = await request.json() as Record<string, unknown>;
    const action = string(body.action);
    const consultationId = integer(body.consultationId, "Consulta inválida.");
    if (action === "upsert") {
      const source = string(body.source);
      if (source !== "ai" && source !== "manual") throw new Error("Origem da medicação inválida.");
      const frequency = required(body.frequency, 120, "Informe a frequência.");
      const instructions = required(body.instructions, 500, "Informe as orientações.");
      if (hasOptionalMedicationUse(`${frequency} ${instructions}`)) throw new Error("A prescrição deve definir uso regular, sem termos condicionais como ‘se necessário’.");
      await runConsultationMutation(session.accessToken, "upsert_consultation_prescription_item", {
        p_consultation_id: consultationId,
        p_item_id: optionalUuid(body.itemId),
        p_medication_id: medicationId(body.medicationId),
        p_source: source,
        p_reason: required(body.reason, 1_000, "Informe o motivo da prescrição."),
        p_dose: required(body.dose, 80, "Informe a dose."),
        p_frequency: frequency,
        p_duration_days: rangedInteger(body.durationDays, 1, 365, "A duração deve ficar entre 1 e 365 dias."),
        p_route: required(body.route, 120, "Informe a via."),
        p_instructions: instructions,
        p_justification: optional(body.justification, 1_000),
        p_final_quantity: optionalRangedInteger(body.finalQuantity, 1, 1_000),
        p_override_reason: optional(body.overrideReason, 500),
      });
    } else if (action === "reject") {
      await runConsultationMutation(session.accessToken, "reject_consultation_medication_suggestion", { p_consultation_id: consultationId, p_medication_id: medicationId(body.medicationId), p_reason: optional(body.reason, 500) });
    } else if (action === "remove") {
      await runConsultationMutation(session.accessToken, "remove_consultation_prescription_item", { p_consultation_id: consultationId, p_item_id: uuid(body.itemId), p_reason: optional(body.reason, 500) });
    } else throw new Error("Ação inválida.");
    return Response.json({ ok: true }, { headers: headers() });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Não foi possível atualizar a prescrição.";
    const forbidden = /acesso não autorizado|somente o profissional/i.test(message);
    return response(forbidden ? "Acesso não autorizado." : message, forbidden ? 403 : 400);
  }
}

function string(value: unknown) { return typeof value === "string" ? value.trim() : ""; }
function required(value: unknown, max: number, message: string) { const result = string(value); if (!result || result.length > max) throw new Error(message); return result; }
function optional(value: unknown, max: number) { const result = string(value); if (result.length > max) throw new Error("Texto muito extenso."); return result || null; }
function integer(value: unknown, message: string) { const parsed = Number(value); if (!Number.isSafeInteger(parsed) || parsed < 1) throw new Error(message); return parsed; }
function rangedInteger(value: unknown, min: number, max: number, message: string) { const parsed = integer(value, message); if (parsed < min || parsed > max) throw new Error(message); return parsed; }
function optionalRangedInteger(value: unknown, min: number, max: number) { if (value === null || value === undefined || value === "") return null; return rangedInteger(value, min, max, "Quantidade final inválida."); }
function uuid(value: unknown) { const result = string(value); if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(result)) throw new Error("Item da prescrição inválido."); return result; }
function optionalUuid(value: unknown) { return value ? uuid(value) : null; }
function medicationId(value: unknown) { const result = string(value).toUpperCase(); if (!/^[A-Z0-9_]{3,40}$/.test(result)) throw new Error("Medicamento inválido."); return result; }
function headers() { return { "cache-control": "private, no-store", "x-content-type-options": "nosniff" }; }
function response(error: string, status: number) { return Response.json({ error }, { status, headers: headers() }); }
