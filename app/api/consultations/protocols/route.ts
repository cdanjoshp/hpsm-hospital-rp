import { getClinicalProtocolLibrary, runConsultationMutation } from "../../../lib/consultations";
import { getSessionBootstrap } from "../../../lib/session";

export async function GET() {
  const session = await getSessionBootstrap();
  if (!session) return response("Sessão expirada.", 401);
  if (!session.permissionCodes.includes("consultations.view")) return response("Acesso não autorizado.", 403);
  try { return Response.json(await getClinicalProtocolLibrary(session.accessToken), { headers: headers() }); }
  catch (error) { return actionError(error); }
}

export async function POST(request: Request) {
  const session = await getSessionBootstrap();
  if (!session) return response("Sessão expirada.", 401);
  if (!session.permissionCodes.includes("consultations.manage") || session.positionLevel === null || session.positionLevel < 11 || session.positionLevel > 14) return response("Acesso não autorizado.", 403);
  try {
    const body = await request.json() as Record<string, unknown>;
    const action = text(body.action);
    if (action === "moderate") await runConsultationMutation(session.accessToken, "moderate_clinical_protocol", { p_protocol_id: uuid(body.protocolId), p_status: status(body.status), p_reason: required(body.reason, 500) });
    else if (action === "medication") await runConsultationMutation(session.accessToken, "set_rp_medication_active", { p_medication_id: medicationId(body.medicationId), p_active: Boolean(body.active), p_reason: required(body.reason, 500) });
    else if (action === "settings") await runConsultationMutation(session.accessToken, "set_clinical_protocol_settings", {
      p_candidate_to_learned_count: integer(body.candidateToLearned, 2, 100), p_learned_to_consolidated_count: integer(body.learnedToConsolidated, 3, 500),
      p_merge_similarity_threshold: decimal(body.mergeSimilarity), p_related_similarity_threshold: decimal(body.relatedSimilarity),
      p_max_related_protocols: integer(body.maxRelated, 1, 5), p_reason: required(body.reason, 500),
    });
    else throw new Error("Ação inválida.");
    return Response.json(await getClinicalProtocolLibrary(session.accessToken), { headers: headers() });
  } catch (error) { return actionError(error); }
}
function text(value: unknown) { return typeof value === "string" ? value.trim() : ""; }
function required(value: unknown, max: number) { const result = text(value); if (result.length < 3 || result.length > max) throw new Error("Informe o motivo da alteração."); return result; }
function uuid(value: unknown) { const result = text(value); if (!/^[0-9a-f-]{36}$/i.test(result)) throw new Error("Protocolo inválido."); return result; }
function medicationId(value: unknown) { const result = text(value).toUpperCase(); if (!/^[A-Z0-9_]{3,40}$/.test(result)) throw new Error("Medicamento inválido."); return result; }
function status(value: unknown) { const result = text(value); if (!['active','inactive','quarantined'].includes(result)) throw new Error("Estado de moderação inválido."); return result; }
function integer(value: unknown, min: number, max: number) { const parsed = Number(value); if (!Number.isSafeInteger(parsed) || parsed < min || parsed > max) throw new Error("Limiar inválido."); return parsed; }
function decimal(value: unknown) { const parsed = Number(value); if (!Number.isFinite(parsed) || parsed < 0 || parsed > 1) throw new Error("Similaridade inválida."); return parsed; }
function headers() { return { "cache-control": "private, no-store", "x-content-type-options": "nosniff" }; }
function actionError(error: unknown) { const message = error instanceof Error ? error.message : "Não foi possível atualizar a biblioteca."; const forbidden = /acesso não autorizado/i.test(message); return response(forbidden ? "Acesso não autorizado." : message, forbidden ? 403 : 400); }
function response(error: string, status: number) { return Response.json({ error }, { status, headers: headers() }); }
