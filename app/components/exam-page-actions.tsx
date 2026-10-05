"use client";

import { useState } from "react";
import { ensureExamPng } from "./exam-document-png-action";
import { DocumentImageViewer } from "./document-image-viewer";

export function ExamPageActions({ examId, label, initialPageCount }: { examId: number; label: string; initialPageCount: number | null }) {
  const [pageCount, setPageCount] = useState(initialPageCount);
  const [busy, setBusy] = useState<string | null>(null);
  const [feedback, setFeedback] = useState("");
  const [error, setError] = useState("");
  const [viewerUrl, setViewerUrl] = useState("");

  async function view() {
    setBusy("view"); setError(""); setFeedback("");
    try {
      const state = await ensureExamPng(examId);
      if (!state.inlineUrl) throw new Error("O laudo não ficou disponível.");
      setPageCount(state.document ? state.document.pixel_height / 1697 : null);
      setViewerUrl(state.inlineUrl);
    } catch (cause) { setError(message(cause)); }
    finally { setBusy(null); }
  }

  async function prepare() {
    setBusy("prepare"); setError(""); setFeedback("");
    try {
      const response = await fetch("/api/exams/document-page", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ action: "prepare", examId }) });
      const result = await response.json() as { pageCount?: number; error?: string };
      if (!response.ok || !result.pageCount) throw new Error(result.error || "Não foi possível preparar as páginas.");
      setPageCount(result.pageCount);
    } catch (cause) { setError(message(cause)); }
    finally { setBusy(null); }
  }

  async function copy(page: number) {
    setBusy(`page-${page}`); setError(""); setFeedback("");
    try {
      const url = fetch("/api/exams/document-page", {
        method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ examId, page }),
      }).then(async (response) => {
        const data = await response.json() as { url?: string; error?: string };
        if (!response.ok || !data.url) throw new Error(data.error || "A página não ficou disponível.");
        return data.url;
      });
      // O item prometido mantém a ativação do clique enquanto a publicação termina.
      if (typeof ClipboardItem !== "undefined" && navigator.clipboard?.write) {
        await navigator.clipboard.write([new ClipboardItem({ "text/plain": url.then((value) => new Blob([value], { type: "text/plain" })) })]);
      } else {
        await navigator.clipboard.writeText(await url);
      }
      void fetch("/api/exams/document-image", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ action: "link-copied", examId }) }).catch(() => undefined);
      setFeedback(`Link da pág. ${page} copiado.`);
    } catch (cause) { setError(message(cause)); }
    finally { setBusy(null); }
  }

  return <div className="exam-hub-pages">
    <div className="exam-hub-page-heading"><span><strong>Resultado em páginas</strong>{pageCount ? ` · ${pageCount} ${pageCount === 1 ? "arquivo A4" : "arquivos A4"}` : ""}</span><button type="button" onClick={() => void view()} disabled={busy !== null}>{busy === "view" ? "Preparando…" : "Ver laudo completo ↗"}</button></div>
    <div className="exam-hub-page-buttons">{pageCount ? Array.from({ length: pageCount }, (_, index) => <button key={index} type="button" disabled={busy !== null} onClick={() => void copy(index + 1)} aria-label={`Copiar link da página ${index + 1} do exame ${label}`}><span aria-hidden="true">▣</span> {busy === `page-${index + 1}` ? "Copiando…" : `Pág. ${index + 1}`}</button>) : <button type="button" onClick={() => void prepare()} disabled={busy !== null}>{busy === "prepare" ? "Preparando…" : "Preparar páginas A4"}</button>}</div>
    {feedback ? <small className="exam-hub-feedback" role="status">{feedback}</small> : null}
    {error ? <small className="exam-hub-feedback" data-error="true" role="alert">{error}</small> : null}
    {viewerUrl ? <DocumentImageViewer imageUrl={viewerUrl} downloadUrl={`/api/exams/document-image?id=${examId}&download=1`} title={`Laudo completo: ${label}`} onClose={() => setViewerUrl("")} /> : null}
  </div>;
}

function message(cause: unknown) { return cause instanceof Error ? cause.message : "Não foi possível preparar o resultado."; }
