"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import type { ClinicalExamDetail, ClinicalExamDocumentClientState, ClinicalExamImage } from "../lib/exams";
import { buildFinalExamDocument } from "../lib/final-exam-document";
import { ensureExamPng, triggerDownload } from "./exam-document-png-action";
import { FinalExamDocument } from "./final-exam-document";

export function FinalExamDocumentActions({ exam, initialOpen = false }: { exam: ClinicalExamDetail; initialOpen?: boolean }) {
  const [open, setOpen] = useState(false);
  const [images, setImages] = useState<ClinicalExamImage[]>([]);
  const [issuedAt, setIssuedAt] = useState(() => new Date().toISOString());
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [printRequested, setPrintRequested] = useState(false);
  const [documentState, setDocumentState] = useState<ClinicalExamDocumentClientState | null>(null);
  const [shareLoading, setShareLoading] = useState(true);
  const [copying, setCopying] = useState(false);
  const [shareError, setShareError] = useState("");
  const [shareNotice, setShareNotice] = useState("");
  const documentRef = useRef<HTMLDivElement>(null);
  const finalDocument = useMemo(() => buildFinalExamDocument(exam, images, issuedAt), [exam, images, issuedAt]);

  async function loadImages() {
    const expectedImages = exam.final_report_snapshot?.images.length ?? 0;
    if (!expectedImages) return [];
    const response = await fetch(`/api/exams/images?examId=${exam.id}`, { cache: "no-store" });
    const payload = await response.json() as { error?: string; images?: ClinicalExamImage[] };
    if (!response.ok) throw new Error(payload.error ?? "Não foi possível carregar as imagens do documento.");
    const loadedImages = payload.images ?? [];
    if (loadedImages.length < expectedImages) throw new Error("Uma das imagens finais do exame não está disponível.");
    return loadedImages;
  }

  async function showDocument(printAfterOpen = false) {
    setOpen(true);
    setLoading(true);
    setError("");
    setIssuedAt(new Date().toISOString());
    setPrintRequested(printAfterOpen);
    try {
      setImages(await loadImages());
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Não foi possível preparar o documento.");
      setPrintRequested(false);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    let cancelled = false;
    async function prepareDocumentAutomatically() {
      setShareLoading(true);
      try {
        const state = await ensureExamPng(exam.id);
        if (!cancelled) setDocumentState(state);
      } catch {
        if (!cancelled) setShareError("O documento foi preservado. A publicação automática no FiveManage será retomada ao reabrir esta tela.");
      } finally {
        if (!cancelled) setShareLoading(false);
      }
    }
    void prepareDocumentAutomatically();
    return () => { cancelled = true; };
  }, [exam.id]);

  useEffect(() => {
    if (!initialOpen) return;
    const timer = window.setTimeout(() => void showDocument(false), 0);
    // A segunda via abre apenas quando solicitada pela lista do paciente.
    return () => window.clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [initialOpen]);

  useEffect(() => {
    if (!printRequested || loading || error || !open) return;
    let cancelled = false;
    const timer = window.setTimeout(async () => {
      const imageElements = Array.from(documentRef.current?.querySelectorAll("img") ?? []);
      await Promise.all(imageElements.map((image) => image.complete ? Promise.resolve() : image.decode().catch(() => undefined)));
      if (cancelled) return;
      document.documentElement.classList.add("printing-final-exam");
      window.addEventListener("afterprint", finishPrinting, { once: true });
      window.print();
      window.setTimeout(finishPrinting, 2_000);
    }, 120);
    function finishPrinting() {
      document.documentElement.classList.remove("printing-final-exam");
      setPrintRequested(false);
    }
    return () => {
      cancelled = true;
      window.clearTimeout(timer);
      document.documentElement.classList.remove("printing-final-exam");
    };
  }, [error, loading, open, printRequested]);

  async function copyLink() {
    if (!documentState?.shareUrl) return;
    setCopying(true);
    setShareError("");
    try {
      await navigator.clipboard.writeText(documentState.shareUrl);
      await fetch("/api/exams/document-image", { body: JSON.stringify({ action: "link-copied", examId: exam.id }), headers: { "content-type": "application/json" }, method: "POST" }).catch(() => undefined);
      setShareNotice("Link copiado.");
    } catch {
      setShareError("Não foi possível copiar automaticamente. Selecione o link abaixo.");
    } finally {
      setCopying(false);
    }
  }

  if (exam.status !== "completed") return null;

  return <section className="final-exam-actions-card">
    <div><span>Documento final</span><strong>{finalDocument.examCode}</strong><p>Laudo aprovado para consulta, imagem compartilhável e impressão.</p></div>
    <div className="final-exam-actions">
      <button className="exam-primary-button" type="button" onClick={() => void showDocument(false)}>Visualizar imagem</button>
      {documentState?.downloadUrl ? <button className="exam-secondary-button" type="button" onClick={() => triggerDownload(documentState.downloadUrl!)}>Baixar imagem</button> : null}
      {documentState?.shareUrl ? <button className="exam-secondary-button" type="button" onClick={() => void copyLink()} disabled={copying}>{copying ? "Copiando…" : "Copiar link"}</button> : null}
    </div>
    {shareLoading || documentState?.shareUrl || shareNotice || shareError ? <div className="final-exam-share-feedback">
      {shareLoading ? <p className="final-exam-share-status" role="status">Preparando e publicando automaticamente no FiveManage…</p> : null}
      {documentState?.shareUrl ? <label className="final-exam-share-link">Link direto da imagem<input value={documentState.shareUrl} readOnly onFocus={(event) => event.currentTarget.select()} /><small>Quem receber este link poderá acessar diretamente a imagem publicada.</small></label> : null}
      {shareNotice ? <p className="form-success final-exam-share-status" role="status">{shareNotice}</p> : null}
      {shareError ? <p className="form-error final-exam-share-status" role="alert">{shareError}</p> : null}
    </div> : null}

    {open ? <div className="final-document-overlay" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget && !printRequested) setOpen(false); }}>
      <section role="dialog" aria-modal="true" aria-label={`Documento final ${finalDocument.examCode}`}>
        <header className="final-document-toolbar">
          <div><strong>Documento final</strong><span>{finalDocument.examCode} - {finalDocument.exam.name}</span></div>
          <div>{documentState?.downloadUrl ? <button className="exam-secondary-button" type="button" onClick={() => triggerDownload(documentState.downloadUrl!)}>Baixar imagem</button> : null}<button className="exam-secondary-button" type="button" onClick={() => setPrintRequested(true)} disabled={loading || Boolean(error)}>Imprimir</button><button type="button" aria-label="Fechar documento" onClick={() => setOpen(false)} disabled={printRequested}>×</button></div>
        </header>
        <div className="final-document-stage" ref={documentRef}>
          {loading ? <div className="final-document-loading" role="status"><i /><strong>Preparando documento…</strong></div> : null}
          {error ? <div className="final-document-error" role="alert"><strong>Documento indisponível</strong><p>{error}</p><button className="exam-secondary-button" type="button" onClick={() => void showDocument(false)}>Tentar novamente</button></div> : null}
          {!loading && !error ? <FinalExamDocument document={finalDocument} /> : null}
        </div>
      </section>
    </div> : null}
  </section>;
}
