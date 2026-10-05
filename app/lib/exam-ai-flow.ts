import type { ClinicalExamDetail, ExamAiGeneration, ExamAiImageDraft, ExamResultState } from "./exams";

type GenerationStage = "image" | "report" | "apply" | "exam";

export async function analyzeExamResults(examId: number, reanalyze = false) {
  const response = await fetch("/api/exams/ai", {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ action: "generate", examId, operation: "result_options", reanalyze, idempotencyKey: crypto.randomUUID() }),
    signal: AbortSignal.timeout(75_000),
  });
  const payload = await response.json() as { error?: string; result_state?: ExamResultState };
  if (!response.ok || !payload.result_state) throw responseError(response, payload.error ?? "A análise não foi concluída.");
  return payload.result_state;
}

export async function selectExamResult(examId: number, optionId: string, manualTitle = "", manualContext = "") {
  const response = await fetch("/api/exams/ai", { method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ action: "select_result", examId, optionId, manualTitle, manualContext }),
    signal: AbortSignal.timeout(15_000),
  });
  const payload = await response.json() as { error?: string };
  if (!response.ok) throw responseError(response, payload.error ?? "Não foi possível confirmar o resultado.");
}

export async function generateSelectedExamWithAi(examId: number, imaging: boolean, onStage: (stage: GenerationStage) => void) {
  try {
    if (!imaging) {
      onStage("exam");
      await requestSuggestion(examId, "generate_exam");
      return;
    }
    const exam = await readExamDetail(examId);
    onStage("report");
    const reusableReport = exam.result_state?.report_generation_id
      ? exam.ai_generations?.find((generation) => generation.id === exam.result_state?.report_generation_id
        && generation.prompt_version === "exam-sol-report-v3" && ["completed", "applied"].includes(generation.status))
      : undefined;
    const reportGenerationId = reusableReport?.id || await requestSuggestion(examId, "generate_report");
    onStage("image");
    const existing = await callImage(examId, "status");
    const image = reusableReport && existing.draft?.status === "completed" ? existing.draft
      : (await callImage(examId, "generate", { idempotencyKey: crypto.randomUUID() })).draft;
    if (!image?.id || image.status !== "completed") throw new Error("A imagem ainda não ficou pronta. Tente novamente.");
    onStage("apply");
    await callImage(examId, "apply_bundle", { generationId: image.id, reportGenerationId });
  } catch (cause) {
    if (isTimeout(cause) && await recoverCompletedExam(examId)) return;
    throw cause;
  }
}

async function readExamDetail(examId: number): Promise<ClinicalExamDetail> {
  const response = await fetch(`/api/exams?view=detail&id=${examId}`, { cache: "no-store" });
  const payload = await response.json() as { exam?: ClinicalExamDetail; error?: string };
  if (!response.ok || !payload.exam) throw responseError(response, payload.error ?? "Não foi possível consultar o exame.");
  return payload.exam;
}

// O início da execução e a geração compartilham este fluxo com a retomada após falha.
export async function generateExamWithAi(examId: number, imaging: boolean, onStage: (stage: GenerationStage) => void) {
  try {
    if (!imaging) {
      onStage("exam");
      await requestSuggestion(examId, "generate_exam");
      return;
    }

    onStage("image");
    const existing = await callImage(examId, "status");
    const image = existing.draft?.status === "completed"
      ? existing.draft
      : (await callImage(examId, "generate", { idempotencyKey: crypto.randomUUID(), visualDirection: "" })).draft;
    if (!image?.id || image.status !== "completed") throw new Error("A imagem ainda não ficou pronta. Tente novamente.");

    onStage("report");
    const reportId = await requestSuggestion(examId, "generate_report", image.id);
    onStage("apply");
    await callImage(examId, "apply_bundle", { generationId: image.id, reportGenerationId: reportId });
  } catch (cause) {
    if (isTimeout(cause) && await recoverCompletedExam(examId)) return;
    throw cause;
  }
}

async function callImage(examId: number, action: string, extra: Record<string, unknown> = {}) {
  const response = await fetch("/api/exams/ai-image", {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ action, examId, ...extra }), signal: AbortSignal.timeout(85_000),
  });
  const payload = await response.json() as { draft?: ExamAiImageDraft | null; error?: string };
  if (!response.ok) throw responseError(response, payload.error ?? "Não foi possível concluir a operação de imagem.");
  return payload;
}

async function requestSuggestion(examId: number, operation: "generate_exam" | "generate_report", imageGenerationId: string | null = null) {
  const response = await fetch("/api/exams/ai", {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ action: "generate", examId, operation, imageGenerationId, idempotencyKey: crypto.randomUUID() }),
    signal: AbortSignal.timeout(75_000),
  });
  const payload = await response.json() as {
    error?: string; generation?: { generation_id?: string }; suggestion?: ExamAiGeneration["suggestion_payload"];
  };
  if (!response.ok || !payload.generation?.generation_id || !payload.suggestion) {
    throw responseError(response, payload.error ?? "Não foi possível gerar o exame.");
  }
  return payload.generation.generation_id;
}

async function recoverCompletedExam(examId: number) {
  for (let attempt = 0; attempt < 5; attempt += 1) {
    if (attempt) await new Promise((resolve) => window.setTimeout(resolve, 1_500));
    try {
      const response = await fetch(`/api/exams?view=detail&id=${examId}`, { cache: "no-store" });
      const payload = await response.json() as { exam?: { status?: string } };
      if (response.ok && ["awaiting_review", "completed"].includes(payload.exam?.status ?? "")) return true;
    } catch {
      // A persistência tardia pode aparecer na próxima consulta do estado canônico.
    }
  }
  return false;
}

function isTimeout(error: unknown) {
  return error instanceof Error && (error.name === "AbortError" || error.name === "TimeoutError");
}

function responseError(response: Response, message: string) {
  const error = new Error(message);
  if (response.status === 504) error.name = "TimeoutError";
  return error;
}
