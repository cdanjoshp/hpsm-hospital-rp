"use client";

import Link from "next/link";
import { useState } from "react";
import type { PatientPortalHistoryItem, PatientPortalHistoryPage } from "../lib/patient-portal";
import { formatPortalDate, formatPortalMoney } from "../lib/patient-portal-format";
import { SidebarIcon } from "./sidebar-icon";

const EVENT_LABELS = {
  attendance: "Atendimento",
  cast: "Gesso",
  exam: "Exame",
  health_plan: "Plano de Saúde",
  consultation: "Consulta",
  certificate: "Atestado",
  hospitalization: "Internação",
  legacy: "HP Norte",
} satisfies Record<PatientPortalHistoryItem["type"], string>;

const EVENT_ICONS = {
  attendance: "attendances",
  cast: "casts",
  exam: "exams",
  health_plan: "patients",
  consultation: "attendances",
  certificate: "attendances",
  hospitalization: "patients",
  legacy: "patients",
} as const satisfies Record<PatientPortalHistoryItem["type"], "attendances" | "casts" | "exams" | "patients">;

export function PatientPortalHistoryList({ initialPage }: { initialPage: PatientPortalHistoryPage }) {
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
      const response = await fetch(`/api/patient-portal/history?${query}`, { cache: "no-store" });
      if (response.status === 401) {
        window.location.assign("/portal-paciente");
        return;
      }
      if (!response.ok) throw new Error("history_request_failed");
      const page = await response.json() as PatientPortalHistoryPage;
      setItems((current) => {
        const known = new Set(current.map((item) => item.key));
        return [...current, ...page.items.filter((item) => !known.has(item.key))];
      });
      setCursor(page.nextCursor);
    } catch {
      setError("Não foi possível carregar mais registros agora.");
    } finally {
      setLoading(false);
    }
  }

  if (!items.length) {
    return <p className="patient-portal-empty patient-portal-empty-page">Seu histórico hospitalar ainda está vazio.</p>;
  }

  return (
    <div className="patient-portal-timeline-wrap">
      <ol className="patient-portal-timeline" aria-label="Histórico hospitalar">
        {items.map((item) => (
          <li key={item.key}>
            <span className="patient-portal-timeline-icon" data-type={item.type} aria-hidden="true">
              <SidebarIcon name={EVENT_ICONS[item.type]} />
            </span>
            <article>
              <div className="patient-portal-timeline-meta">
                <span>{EVENT_LABELS[item.type]}</span>
                <time dateTime={item.occurredAt}>{formatPortalDate(item.occurredAt, true)}</time>
              </div>
              <h2>{item.title}</h2>
              {professionalLabel(item) ? <p>{professionalLabel(item)}</p> : item.description ? <p>{item.description}</p> : null}
              <div className="patient-portal-timeline-actions">
                {item.amount !== null ? <strong>{formatPortalMoney(item.amount)}</strong> : <span />}
                {item.attendanceId ? <Link href={`/portal-paciente/atendimentos/${item.attendanceId}`} prefetch={false}>Ver atendimento</Link> : null}
                {item.examId ? <Link href={`/portal-paciente/exames/${item.examId}`} prefetch={false}>Ver exame</Link> : null}
                {item.type === "health_plan" ? <Link href="/portal-paciente/plano-saude" prefetch={false}>Ver plano</Link> : null}
                {item.type === "cast" ? <Link href="/portal-paciente/gessos" prefetch={false}>Ver gessos</Link> : null}
                {consultationHref(item) ? <Link href={consultationHref(item)!} prefetch={false}>Ver consulta</Link> : null}
                {item.type === "certificate" ? <Link href="/portal-paciente/atestados" prefetch={false}>Ver atestados</Link> : null}
                {item.type === "hospitalization" ? <Link href="/portal-paciente/internacoes" prefetch={false}>Ver internações</Link> : null}
                {item.type === "legacy" ? <Link href="/portal-paciente/historico-norte" prefetch={false}>Ver histórico HP Norte</Link> : null}
              </div>
            </article>
          </li>
        ))}
      </ol>

      {error ? <p className="patient-portal-inline-error" role="alert">{error}</p> : null}
      {cursor ? <button className="patient-portal-load-more" disabled={loading} onClick={loadMore} type="button">{loading ? "Carregando…" : "Carregar mais"}</button> : null}
    </div>
  );
}
function consultationHref(item: PatientPortalHistoryItem) {
  const match = /^consultation:(appointment|consultation):([1-9]\d*)$/.exec(item.key);
  return item.type === "consultation" && match ? `/portal-paciente/consultas/${match[1]}/${match[2]}` : null;
}
function professionalLabel(item: PatientPortalHistoryItem) {
  if (!item.professionalName) return item.description;
  return item.professionalPosition
    ? `${item.professionalName} · ${item.professionalPosition}`
    : item.professionalName;
}
