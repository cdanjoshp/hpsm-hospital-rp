import { getEffectivePermissionCodes } from "../../../lib/access";
import { runClinicalExamMutation } from "../../../lib/exams";
import { getSessionContext } from "../../../lib/session";
import { ConfigurationError, getSupabaseConfig } from "../../../lib/supabase-server";

const EDGE_TIMEOUT_MS = 70_000;

export async function POST(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });

  try {
    const permissions = new Set(await getEffectivePermissionCodes(context.profile.user_id));
    if (!permissions.has("exams.perform") && !permissions.has("exams.review")) {
      return Response.json({ error: "Acesso não autorizado." }, { status: 403 });
    }

    const body = await request.json() as Record<string, unknown>;
    const action = textValue(body.action);
    if (action === "select_result") {
      const examId = positiveInteger(body.examId, "Exame inválido.");
      const optionId = textValue(body.optionId);
      if (!/^(option_[1-3]|manual)$/.test(optionId)) throw new Error("Selecione uma possibilidade válida.");
      const result = await runClinicalExamMutation(context.accessToken, "select_clinical_exam_result", {
        p_exam_id: examId, p_option_id: optionId,
        p_manual_title: optionId === "manual" ? textValue(body.manualTitle).slice(0, 120) : null,
        p_manual_context: optionId === "manual" ? textValue(body.manualContext).slice(0, 1000) : null,
      });
      return Response.json({ result });
    }
    if (action === "generate") {
      const examId = positiveInteger(body.examId, "Exame inválido.");
      const operation = body.operation === "result_options" ? "result_options" : generationType(body.operation);
      const idempotencyKey = uuidValue(body.idempotencyKey);
      const imageGenerationId = body.imageGenerationId === undefined || body.imageGenerationId === null
        ? null
        : uuidValue(body.imageGenerationId);
      if (!operation || !idempotencyKey) throw new Error("Solicitação de IA inválida.");
      if (body.imageGenerationId && !imageGenerationId) throw new Error("Rascunho de imagem inválido.");
      const { anonKey, url } = getSupabaseConfig();
      const response = await fetch(`${url}/functions/v1/exam-ai-generate`, {
        method: "POST",
        headers: {
          apikey: anonKey,
          authorization: `Bearer ${context.accessToken}`,
          "content-type": "application/json",
        },
      body: JSON.stringify({ examId, operation, idempotencyKey, imageGenerationId, reanalyze: body.reanalyze === true }),
        cache: "no-store",
        signal: AbortSignal.timeout(EDGE_TIMEOUT_MS),
      });
      const payload = await response.json().catch(() => null) as Record<string, unknown> | null;
      if (!payload) return Response.json({ error: "Assistente de IA temporariamente indisponível." }, { status: 503 });
      return Response.json(payload, { status: response.status, headers: { "cache-control": "private, no-store" } });
    }

    const generationId = uuidValue(body.generationId);
    if (!generationId) throw new Error("Sugestão de IA inválida.");
    if (action === "apply") {
      await runClinicalExamMutation(context.accessToken, "apply_clinical_exam_ai_generation", { p_generation_id: generationId });
      return Response.json({ ok: true });
    }
    if (action === "discard") {
      await runClinicalExamMutation(context.accessToken, "discard_clinical_exam_ai_generation", { p_generation_id: generationId });
      return Response.json({ ok: true });
    }
    return Response.json({ error: "Ação de IA inválida." }, { status: 400 });
  } catch (error) {
    if (error instanceof ConfigurationError) {
      return Response.json({ error: "Assistente de IA temporariamente indisponível." }, { status: 503 });
    }
    if (error instanceof Error && (error.name === "AbortError" || error.name === "TimeoutError")) {
      return Response.json({ error: "O assistente demorou para responder. Tente novamente." }, { status: 504 });
    }
    const message = error instanceof Error ? error.message : "Não foi possível concluir a operação de IA.";
    const forbidden = /acesso não autorizado|sessão inválida/i.test(message);
    const conflict = /já existe|já foi|em execução|não aceita|atualizado/i.test(message);
    return Response.json({ error: forbidden ? "Acesso não autorizado." : message }, { status: forbidden ? 403 : conflict ? 409 : 400 });
  }
}

function textValue(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}

function positiveInteger(value: unknown, message: string) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) throw new Error(message);
  return parsed;
}

function generationType(value: unknown) {
  return value === "generate_lab_results" || value === "generate_report" || value === "generate_exam" ? value : null;
}

function uuidValue(value: unknown) {
  if (typeof value !== "string") return null;
  const normalized = value.toLowerCase();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(normalized) ? normalized : null;
}
