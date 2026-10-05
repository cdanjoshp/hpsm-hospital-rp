"use client";

import { useEffect, useState } from "react";
import type { ConsultationDocumentState } from "../lib/consultation-document-service";
import type { DocumentPublicationClientState } from "../lib/document-media-types";
import { DocumentImageViewer } from "./document-image-viewer";
import { HpsmButton } from "./hpsm-button";

type ClientState = ConsultationDocumentState & DocumentPublicationClientState & {
  downloadUrl: string | null;
  inlineUrl: string | null;
  shareUrl: string | null;
};

export function ConsultationDocumentActions({ consultationId }: { consultationId: number }) {
  const [state, setState] = useState<ClientState | null>(null);
  const [preparing, setPreparing] = useState(true);
  const [copying, setCopying] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [viewerOpen, setViewerOpen] = useState(false);

  useEffect(() => {
    let cancelled = false;
    async function prepareAutomatically() {
      setPreparing(true);
      try {
        const next = await requestState({ action: "ensure", consultationId });
        if (!cancelled) setState(next);
      } catch {
        if (!cancelled) setError("O prontuário foi preservado. A publicação automática no FiveManage será retomada ao reabrir esta consulta.");
      } finally {
        if (!cancelled) setPreparing(false);
      }
    }
    void prepareAutomatically();
    return () => { cancelled = true; };
  }, [consultationId]);

  async function copyLink() {
    if (!state?.shareUrl) return;
    setCopying(true);
    setError("");
    setNotice("");
    try {
      await navigator.clipboard.writeText(state.shareUrl);
      await requestState({ action: "link-copied", consultationId }).catch(() => undefined);
      setNotice("Link da imagem copiado.");
    } catch {
      setError("Não foi possível copiar automaticamente. Selecione o link exibido no documento.");
    } finally {
      setCopying(false);
    }
  }

  return <section className="consultation-document-panel">
    <div>
      <span className="consultation-kicker">Documento clínico</span>
      <h3>Prontuário Completo da Consulta</h3>
      <p>Imagem vertical e imutável criada do snapshot da conclusão e publicada automaticamente no FiveManage.</p>
    </div>
    <div className="consultation-document-actions">
      {state?.document ? <>
        <HpsmButton variant="ghost" disabled={!state.inlineUrl} onClick={() => setViewerOpen(true)}>Visualizar prontuário</HpsmButton>
        <a className="hpsm-button hpsm-button-primary" href={state.downloadUrl ?? "#"}>Baixar imagem</a>
        {state.shareUrl ? <HpsmButton disabled={copying} loading={copying} onClick={() => void copyLink()}>{copying ? "Copiando…" : "Copiar link"}</HpsmButton> : null}
      </> : null}
    </div>
    {preparing ? <p className="final-exam-share-status" role="status">Preparando e publicando automaticamente no FiveManage…</p> : null}
    {notice ? <p className="form-success" role="status">{notice}</p> : null}
    {error ? <p className="form-error" role="alert">{error}</p> : null}
    {viewerOpen && state?.inlineUrl ? <DocumentImageViewer downloadUrl={state.downloadUrl} imageUrl={state.inlineUrl} onClose={() => setViewerOpen(false)} title="Prontuário Completo" /> : null}
  </section>;
}

async function requestState(body: Record<string, unknown>) {
  const response = await fetch("/api/consultations/document", {
    body: JSON.stringify(body),
    headers: { "content-type": "application/json" },
    method: "POST",
  });
  const payload = await response.json() as ClientState & { error?: string };
  if (!response.ok) throw new Error(payload.error ?? "Não foi possível preparar o prontuário.");
  return payload;
}
