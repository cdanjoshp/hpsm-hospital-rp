"use client";

import { useState } from "react";

export function PatientPortalExamActions({ examId }: { examId: number }) {
  const [busy, setBusy] = useState<"download" | "share" | null>(null);
  const [error, setError] = useState("");
  const [manualShareUrl, setManualShareUrl] = useState("");
  const [notice, setNotice] = useState("");
  const [shareConfirmation, setShareConfirmation] = useState(false);

  async function download() {
    setBusy("download");
    setError("");
    setNotice("");
    try {
      const result = await prepare("download");
      window.location.assign(result.downloadUrl);
    } catch {
      setError("Não foi possível baixar o resultado agora.");
    } finally {
      setBusy(null);
    }
  }

  async function share() {
    setBusy("share");
    setError("");
    setManualShareUrl("");
    setNotice("");
    try {
      const result = await prepare("share");
      if (!result.shareUrl) throw new Error("share_missing");
      try {
        if (!navigator.clipboard?.writeText) throw new Error("clipboard_unavailable");
        await navigator.clipboard.writeText(result.shareUrl);
        setNotice("Link copiado.");
      } catch {
        setManualShareUrl(result.shareUrl);
        setNotice("O link está pronto. Selecione e copie manualmente.");
      }
      setShareConfirmation(false);
    } catch {
      setError("Não foi possível copiar o link agora.");
    } finally {
      setBusy(null);
    }
  }

  async function prepare(action: "download" | "share") {
    const response = await fetch(`/api/patient-portal/exams/${examId}/document`, {
      body: JSON.stringify({ action }),
      cache: "no-store",
      headers: { "content-type": "application/json" },
      method: "POST",
    });
    if (response.status === 401) {
      window.location.assign("/portal-paciente");
      throw new Error("unauthorized");
    }
    if (!response.ok) throw new Error("document_request_failed");
    return await response.json() as { downloadUrl: string; shareUrl: string | null };
  }

  return (
    <section className="patient-portal-exam-actions" aria-label="Segunda via do resultado">
      <div>
        <h2>Segunda via</h2>
        <p>Baixe a imagem oficial ou copie o link direto para compartilhar.</p>
      </div>
      <div className="patient-portal-exam-action-buttons">
        <button disabled={Boolean(busy)} onClick={() => void download()} type="button">{busy === "download" ? "Preparando…" : "Baixar imagem"}</button>
        <button disabled={Boolean(busy)} onClick={() => setShareConfirmation(true)} type="button">Copiar link</button>
      </div>
      {shareConfirmation ? (
        <div className="patient-portal-share-confirmation" role="alert">
          <p>Qualquer pessoa com este link poderá visualizar este exame.</p>
          <div>
            <button disabled={Boolean(busy)} onClick={() => void share()} type="button">{busy === "share" ? "Gerando…" : "Entendi, copiar link"}</button>
            <button disabled={Boolean(busy)} onClick={() => setShareConfirmation(false)} type="button">Cancelar</button>
          </div>
        </div>
      ) : null}
      {manualShareUrl ? (
        <label className="patient-portal-manual-share">
          Link direto do resultado
          <input autoFocus onFocus={(event) => event.currentTarget.select()} readOnly value={manualShareUrl} />
          <small>Qualquer pessoa com este link poderá visualizar o exame.</small>
        </label>
      ) : null}
      {notice ? <p className="form-success patient-portal-exam-action-status" role="status">{notice}</p> : null}
      {error ? <p className="form-error patient-portal-exam-action-status" role="alert">{error}</p> : null}
    </section>
  );
}
