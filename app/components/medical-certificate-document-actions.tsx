"use client";

import { useEffect, useState } from "react";
import type { DocumentPublicationClientState } from "../lib/document-media-types";
import { DocumentImageViewer } from "./document-image-viewer";
import { HpsmButton } from "./hpsm-button";

type CertificateDocumentClientState = DocumentPublicationClientState & {
  documentReady: boolean;
  downloadUrl: string | null;
  previewUrl: string | null;
  shareUrl: string | null;
};

export function MedicalCertificateCopyLinkAction({ certificateId }: { certificateId: number }) {
  const [copying, setCopying] = useState(false);
  const [feedback, setFeedback] = useState("");
  const [error, setError] = useState("");

  async function copy() {
    setCopying(true); setFeedback(""); setError("");
    try {
      await copyMedicalCertificateLink(certificateId);
      setFeedback("Link copiado.");
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Não foi possível copiar o link do atestado.");
    } finally { setCopying(false); }
  }

  return <>
    <button type="button" disabled={copying} onClick={() => void copy()} aria-label={`Copiar link do atestado AT-${String(certificateId).padStart(6, "0")}`}>{copying ? "Preparando link…" : "Copiar link"}</button>
    {feedback ? <small className="certificate-case-feedback" role="status">{feedback}</small> : null}
    {error ? <small className="certificate-case-feedback" data-error="true" role="alert">{error}</small> : null}
  </>;
}

export function MedicalCertificateDocumentActions({ certificateId }: { certificateId: number }) {
  const [preparing, setPreparing] = useState(true);
  const [copying, setCopying] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [state, setState] = useState<CertificateDocumentClientState | null>(null);
  const [viewerOpen, setViewerOpen] = useState(false);

  useEffect(() => {
    let cancelled = false;
    async function prepareAutomatically() {
      setPreparing(true);
      try {
        const next = await prepare("ensure");
        if (!cancelled) setState(next);
      } catch {
        if (!cancelled) setError("O atestado foi preservado. A publicação automática no FiveManage será retomada ao reabrir este documento.");
      } finally {
        if (!cancelled) setPreparing(false);
      }
    }
    void prepareAutomatically();
    return () => { cancelled = true; };
    // prepare usa apenas o certificado atual.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [certificateId]);

  async function copyLink() {
    setCopying(true); setError(""); setNotice("");
    try {
      await copyMedicalCertificateLink(certificateId, state?.shareUrl);
      setNotice("Link da imagem copiado.");
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Não foi possível copiar automaticamente.");
    } finally { setCopying(false); }
  }

  return <>
    <HpsmButton type="button" variant="ghost" onClick={() => setViewerOpen(true)}>Visualizar imagem</HpsmButton>
    <a className="certificate-primary" href={`/api/medical-certificates/document?id=${certificateId}&download=1`}>Baixar imagem</a>
    <HpsmButton disabled={copying} loading={copying} type="button" onClick={() => void copyLink()}>{copying ? "Preparando link…" : "Copiar link"}</HpsmButton>
    {preparing ? <p className="final-exam-share-status" role="status">Preparando e publicando automaticamente no FiveManage…</p> : null}
    {notice ? <p className="form-success" role="status">{notice}</p> : null}
    {error ? <p className="form-error" role="alert">{error}</p> : null}
    {viewerOpen ? <DocumentImageViewer downloadUrl={`/api/medical-certificates/document?id=${certificateId}&download=1`} imageUrl={`/api/medical-certificates/document?id=${certificateId}`} onClose={() => setViewerOpen(false)} title={`Atestado AT-${String(certificateId).padStart(6, "0")}`} /> : null}
  </>;

  async function prepare(action: "ensure" | "link-copied") {
    const response = await fetch("/api/medical-certificates/document", { body: JSON.stringify({ action, certificateId }), headers: { "content-type": "application/json" }, method: "POST" });
    const payload = await response.json() as CertificateDocumentClientState & { error?: string };
    if (!response.ok) throw new Error(payload.error ?? "Não foi possível concluir a publicação automática da imagem.");
    return payload;
  }
}

async function copyMedicalCertificateLink(certificateId: number, existingUrl?: string | null) {
  const link = existingUrl ? Promise.resolve(existingUrl) : fetch("/api/medical-certificates/document", {
    body: JSON.stringify({ action: "ensure", certificateId }),
    headers: { "content-type": "application/json" },
    method: "POST",
  }).then(async (response) => {
    const payload = await response.json() as CertificateDocumentClientState & { error?: string };
    if (!response.ok) throw new Error(payload.error ?? "Não foi possível publicar o atestado.");
    if (!payload.shareUrl) throw new Error("O link do atestado ainda não ficou disponível. Tente novamente em instantes.");
    return payload.shareUrl;
  });
  // ClipboardItem recebe a promessa antes de terminar a publicação, preservando a ativação do clique.
  void link.catch(() => undefined);
  if (typeof ClipboardItem !== "undefined" && navigator.clipboard?.write) {
    await navigator.clipboard.write([new ClipboardItem({ "text/plain": link.then((url) => new Blob([url], { type: "text/plain" })) })]);
  } else {
    await navigator.clipboard.writeText(await link);
  }
  void fetch("/api/medical-certificates/document", {
    body: JSON.stringify({ action: "link-copied", certificateId }),
    headers: { "content-type": "application/json" },
    method: "POST",
  }).catch(() => undefined);
}
