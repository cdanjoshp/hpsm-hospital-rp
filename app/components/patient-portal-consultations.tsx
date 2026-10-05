"use client";

import Link from "next/link";
import { useState } from "react";
import type { PatientPortalConsultationItem, PatientPortalConsultationPage } from "../lib/patient-portal";
import { formatPortalDate } from "../lib/patient-portal-format";

export const CONSULTATION_STATUS: Record<PatientPortalConsultationItem["status"], string> = {
  scheduled: "Agendada", confirmed: "Confirmada", in_progress: "Em andamento",
  completed: "Concluída", cancelled: "Cancelada", no_show: "Não realizada",
};

export function PatientPortalConsultationList({ initialPage }: { initialPage: PatientPortalConsultationPage }) {
  const [items, setItems] = useState(initialPage.items);
  const [cursor, setCursor] = useState(initialPage.nextCursor);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  async function loadMore() {
    if (!cursor || loading) return;
    setLoading(true);
    setError("");
    try {
      const query = new URLSearchParams({ cursorAt: cursor.occurredAt, cursorKey: cursor.key });
      const response = await fetch(`/api/patient-portal/consultations?${query}`, { cache: "no-store" });
      if (response.status === 401) { window.location.assign("/portal-paciente"); return; }
      if (!response.ok) throw new Error("consultation_request_failed");
      const page = await response.json() as PatientPortalConsultationPage;
      setItems((current) => {
        const known = new Set(current.map((item) => `${item.kind}:${item.id}`));
        return [...current, ...page.items.filter((item) => !known.has(`${item.kind}:${item.id}`))];
      });
      setCursor(page.nextCursor);
    } catch { setError("Não foi possível carregar mais consultas agora."); }
    finally { setLoading(false); }
  }

  return <div className="patient-portal-attendance-wrap">
    {items.length ? <div className="patient-portal-attendance-list" aria-busy={loading}>
      {items.map((item) => <article key={`${item.kind}:${item.id}`}>
        <div className="patient-portal-attendance-card-main">
          <time dateTime={item.occurredAt}>{formatPortalDate(item.occurredAt, true)}</time>
          <h2>{item.professionalName || "Profissional não informado"}</h2>
          <p>{item.reason || "Consulta clínica"}{item.professionalPosition ? ` · ${item.professionalPosition}` : ""}</p>
        </div>
        <div className="patient-portal-attendance-card-action">
          <span className="patient-portal-status" data-status={item.status}>{CONSULTATION_STATUS[item.status]}</span>
          <Link href={`/portal-paciente/consultas/${item.kind}/${item.id}`} prefetch={false}>Ver detalhes</Link>
        </div>
      </article>)}
    </div> : <p className="patient-portal-empty patient-portal-empty-page">Nenhuma consulta ou agendamento registrado até o momento.</p>}
    {error ? <p className="patient-portal-inline-error" role="alert">{error}</p> : null}
    {cursor ? <button className="patient-portal-load-more" disabled={loading} onClick={() => void loadMore()} type="button">{loading ? "Carregando…" : "Carregar mais"}</button> : null}
  </div>;
}
