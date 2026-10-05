"use client";

import { useState } from "react";
import { CAST_STATUS_LABELS, castLocationLabel } from "../lib/cast-types";
import type { PatientPortalCastItem, PatientPortalCastPage } from "../lib/patient-portal";
import { formatPortalDate } from "../lib/patient-portal-format";

export function PatientPortalCasts({ initialPage }: { initialPage: PatientPortalCastPage }) {
  const [history, setHistory] = useState(initialPage.history);
  const [cursor, setCursor] = useState(initialPage.nextCursor);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  async function loadMore() {
    if (!cursor || loading) return;
    setLoading(true);
    setError("");
    try {
      const query = new URLSearchParams({ cursorAt: cursor.occurredAt, cursorId: String(cursor.id) });
      const response = await fetch(`/api/patient-portal/casts?${query}`, { cache: "no-store" });
      if (response.status === 401) {
        window.location.assign("/portal-paciente");
        return;
      }
      if (!response.ok) throw new Error("casts_request_failed");
      const page = await response.json() as PatientPortalCastPage;
      setHistory((current) => appendUnique(current, page.history));
      setCursor(page.nextCursor);
    } catch {
      setError("Não foi possível carregar mais registros agora.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="patient-portal-casts-wrap">
      <section className="patient-portal-casts-section" aria-labelledby="patient-portal-active-casts-title">
        <header>
          <div><p>Cuidados atuais</p><h2 id="patient-portal-active-casts-title">Gessos em uso</h2></div>
          <span>{initialPage.activeCasts.length}</span>
        </header>
        {initialPage.activeCasts.length ? (
          <div className="patient-portal-casts-grid">
            {initialPage.activeCasts.map((item) => <ActiveCast item={item} key={item.key} referenceTime={initialPage.referenceTime} />)}
          </div>
        ) : <p className="patient-portal-empty">Você não possui gessos em uso.</p>}
      </section>

      <section className="patient-portal-casts-section" aria-labelledby="patient-portal-cast-history-title">
        <header><div><p>Registros anteriores</p><h2 id="patient-portal-cast-history-title">Histórico de gessos</h2></div></header>
        {history.length ? <div className="patient-portal-casts-grid">{history.map((item) => <HistoricalCast item={item} key={item.key} />)}</div> : <p className="patient-portal-empty">Nenhum gesso anterior foi registrado.</p>}
        {error ? <p className="patient-portal-inline-error" role="alert">{error}</p> : null}
        {cursor ? <button className="patient-portal-load-more" disabled={loading} onClick={loadMore} type="button">{loading ? "Carregando…" : "Carregar mais"}</button> : null}
      </section>
    </div>
  );
}

function ActiveCast({ item, referenceTime }: { item: PatientPortalCastItem; referenceTime: string }) {
  const due = castDueState(item.expectedRemovalAt, referenceTime);
  return (
    <article className="patient-portal-cast-card" data-due={due}>
      <div className="patient-portal-cast-card-head"><h3>{castLocationLabel(item.bodyRegion, item.laterality)}</h3><span>{CAST_STATUS_LABELS[item.status]}</span></div>
      <dl>
        <CastDetail label="Aplicado em" value={formatPortalDate(item.appliedAt)} />
        <CastDetail label="Retirada prevista" value={formatPortalDate(item.expectedRemovalAt)} />
      </dl>
      {professionalLabel(item.appliedByName, item.appliedByPosition) ? <p>Aplicado por {professionalLabel(item.appliedByName, item.appliedByPosition)}.</p> : null}
      {due === "overdue" ? <strong className="patient-portal-cast-alert">A data prevista para retirada já foi atingida.</strong> : null}
      {due === "today" ? <strong className="patient-portal-cast-alert">Retirada prevista para hoje.</strong> : null}
    </article>
  );
}

function HistoricalCast({ item }: { item: PatientPortalCastItem }) {
  const eventDate = item.status === "removed" ? item.removedAt : item.cancelledAt;
  return (
    <article className="patient-portal-cast-card" data-status={item.status}>
      <div className="patient-portal-cast-card-head"><h3>{castLocationLabel(item.bodyRegion, item.laterality)}</h3><span>{CAST_STATUS_LABELS[item.status]}</span></div>
      <dl>
        <CastDetail label="Aplicado em" value={formatPortalDate(item.appliedAt)} />
        <CastDetail label={item.status === "removed" ? "Retirado em" : "Cancelado em"} value={eventDate ? formatPortalDate(eventDate) : "Data não informada"} />
      </dl>
      {item.status === "removed" && professionalLabel(item.removedByName, item.removedByPosition) ? <p>Retirado por {professionalLabel(item.removedByName, item.removedByPosition)}.</p> : null}
    </article>
  );
}

function CastDetail({ label, value }: { label: string; value: string }) {
  return <div><dt>{label}</dt><dd>{value}</dd></div>;
}

function professionalLabel(name: string | null, position: string | null) {
  if (!name) return "";
  return position ? `${name} · ${position}` : name;
}

function castDueState(expectedRemovalAt: string, referenceTime: string) {
  const expected = dateKey(expectedRemovalAt);
  const reference = dateKey(referenceTime);
  if (!expected || !reference) return "future";
  if (expected === reference) return "today";
  return expected < reference ? "overdue" : "future";
}

function dateKey(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  return new Intl.DateTimeFormat("en-CA", {
    day: "2-digit",
    month: "2-digit",
    timeZone: "America/Sao_Paulo",
    year: "numeric",
  }).format(date);
}

function appendUnique(current: PatientPortalCastItem[], incoming: PatientPortalCastItem[]) {
  const known = new Set(current.map((item) => item.key));
  return [...current, ...incoming.filter((item) => !known.has(item.key))];
}
