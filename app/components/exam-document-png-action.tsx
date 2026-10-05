"use client";

import { useState } from "react";
import type { ClinicalExamDocumentClientState } from "../lib/exams";
import { DocumentImageViewer } from "./document-image-viewer";

export function ExamPngListAction({ examId, label }: { examId: number; label: string }) {
  const [busy, setBusy] = useState<"copy" | "download" | "view" | null>(null);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [viewerUrl, setViewerUrl] = useState("");

  async function view() {
    setBusy("view"); setError(""); setNotice("");
    try {
      const state = await ensureExamPng(examId);
      if (!state.inlineUrl) throw new Error("A imagem não ficou disponível para visualizar.");
      setViewerUrl(state.inlineUrl);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Não foi possível preparar a imagem.");
    } finally { setBusy(null); }
  }

  async function download() {
    setBusy("download");
    setError("");
    setNotice("");
    try {
      const state = await ensureExamPng(examId);
      if (!state.downloadUrl) throw new Error("A imagem não ficou disponível para baixar.");
      triggerDownload(state.downloadUrl);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Não foi possível preparar a imagem.");
    } finally {
      setBusy(null);
    }
  }

  async function copyLink() {
    setBusy("copy");
    setError("");
    setNotice("");
    try {
      const state = await ensureExamPng(examId);
      if (!state.shareUrl) throw new Error("O link do resultado não ficou disponível.");
      await navigator.clipboard.writeText(state.shareUrl);
      await auditExamLinkCopy(examId);
      setNotice("Link copiado.");
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Não foi possível copiar o link.");
    } finally {
      setBusy(null);
    }
  }

  return <><span className="exam-list-document-control">
    <button
      aria-label={`Visualizar imagem do exame ${label}`}
      className="exam-list-document-action"
      disabled={busy !== null}
      onClick={() => void view()}
      type="button"
    >{busy === "view" ? "Preparando…" : "Visualizar imagem"}</button>
    <button
      className="exam-list-document-action"
      type="button"
      disabled={busy !== null}
      aria-label={`${busy === "download" ? "Preparando" : "Baixar imagem"} do exame ${label}`}
      onClick={() => void download()}
    >{busy === "download" ? "Preparando…" : "Baixar imagem"}</button>
    <button
      className="exam-list-document-action"
      type="button"
      disabled={busy !== null}
      aria-label={`${busy === "copy" ? "Copiando link" : "Copiar link"} do exame ${label}`}
      onClick={() => void copyLink()}
    >{busy === "copy" ? "Copiando…" : "Copiar link"}</button>
    {notice ? <small className="exam-list-document-feedback" role="status">{notice}</small> : null}
    {error ? <small className="exam-list-document-feedback" data-error="true" role="alert">{error}</small> : null}
  </span>{viewerUrl ? <DocumentImageViewer downloadUrl={`/api/exams/document-image?id=${examId}&download=1`} imageUrl={viewerUrl} onClose={() => setViewerUrl("")} title={`Imagem do exame ${label}`} /> : null}</>;
}

export async function ensureExamPng(examId: number) {
  const response = await fetch("/api/exams/document-image", {
    body: JSON.stringify({ action: "ensure", examId }),
    headers: { "content-type": "application/json" },
    method: "POST",
  });
  const payload = await response.json() as ClinicalExamDocumentClientState & { error?: string };
  if (!response.ok) throw new Error(payload.error ?? "Não foi possível preparar a imagem compartilhável.");
  return payload;
}

async function auditExamLinkCopy(examId: number) {
  await fetch("/api/exams/document-image", { body: JSON.stringify({ action: "link-copied", examId }), headers: { "content-type": "application/json" }, method: "POST" }).catch(() => undefined);
}

export function triggerDownload(url: string) {
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = "";
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
}
