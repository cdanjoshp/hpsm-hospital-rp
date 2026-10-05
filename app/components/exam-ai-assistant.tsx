"use client";

import type { ImagingResultData } from "../lib/exams";

type ImagingContext = { caseSummary: string; result: ImagingResultData };

export function ExamAiAssistant({ dirty, error, imagingContext, onRetry, retrying }: {
  dirty: boolean;
  error: string;
  imagingContext: ImagingContext | null;
  onRetry: () => Promise<void>;
  retrying: boolean;
}) {
  const missing = imagingContext ? missingImagingAiFields(imagingContext) : [];
  return <section className="exam-ai-assistant exam-ai-simplified" aria-label="Geração automática do exame">
    <header><div><span className="exam-ai-mark" aria-hidden="true">✦</span><div><small>Execução com revisão humana</small><h3>Geração automática</h3></div></div><span className="exam-ai-model">{imagingContext ? "GPT-Image-2 + Sol" : "Sol"}</span></header>
    <p className="exam-ai-guidance">A execução foi iniciada, mas a geração não foi concluída. Você pode retomá-la ou preencher o exame manualmente. A aprovação final permanece humana.</p>
    {imagingContext ? <dl className="exam-ai-case-summary"><div><dt>Suspeita e contexto do caso</dt><dd>{imagingContext.caseSummary}</dd></div></dl> : null}
    {dirty ? <p className="exam-ai-dirty" role="status">Salve suas alterações manuais antes de retomar.</p> : null}
    {missing.length ? <p className="exam-ai-dirty" role="status">Complete antes de retomar: {missing.join(", ")}.</p> : null}
    {error ? <p className="form-error" role="alert">{error}</p> : null}
    <div className="exam-ai-primary-action"><button className="exam-ai-main-button" type="button" disabled={dirty || missing.length > 0 || retrying} onClick={() => void onRetry()}>{retrying ? "Gerando exame…" : "✦ Retomar geração automática"}</button></div>
  </section>;
}

function missingImagingAiFields(context: ImagingContext) {
  const result = context.result;
  const region = result.region === "Outra região" ? result.other_region : result.region;
  const missing: string[] = [];
  if (!region.trim()) missing.push("região");
  if (result.template_snapshot.supports_laterality && !result.laterality) missing.push("lateralidade");
  if (!context.caseSummary.trim()) missing.push("suspeita e contexto do caso");
  return missing;
}
