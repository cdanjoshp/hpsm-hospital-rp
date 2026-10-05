"use client";

import { useState } from "react";
import type {
  PatientPortalHealthPlanHistoryItem,
  PatientPortalHealthPlanPage,
  PatientPortalHealthPlanStatus,
} from "../lib/patient-portal";
import { formatPortalDate } from "../lib/patient-portal-format";

const STATUS_COPY: Record<PatientPortalHealthPlanStatus, { label: string; tone: string }> = {
  active: { label: "✓ Ativo", tone: "active" },
  awaiting_confirmation: { label: "Aguardando confirmação", tone: "pending" },
  expired: { label: "Plano expirado", tone: "expired" },
  none: { label: "Sem plano", tone: "neutral" },
};

export function PatientPortalHealthPlan({ initialPage }: { initialPage: PatientPortalHealthPlanPage }) {
  const [items, setItems] = useState(initialPage.items);
  const [cursor, setCursor] = useState(initialPage.nextCursor);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const status = STATUS_COPY[initialPage.current.status];

  async function loadMore() {
    if (!cursor || loading) return;
    setLoading(true);
    setError("");
    try {
      const query = new URLSearchParams({ cursorAt: cursor.occurredAt, cursorId: String(cursor.id) });
      const response = await fetch(`/api/patient-portal/health-plan?${query}`, { cache: "no-store" });
      if (response.status === 401) {
        window.location.assign("/portal-paciente");
        return;
      }
      if (!response.ok) throw new Error("health_plan_request_failed");
      const page = await response.json() as PatientPortalHealthPlanPage;
      setItems((current) => appendUnique(current, page.items));
      setCursor(page.nextCursor);
    } catch {
      setError("Não foi possível carregar mais registros agora.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="patient-portal-health-plan-wrap">
      <section className="patient-portal-plan-current" aria-labelledby="patient-portal-plan-current-title">
        <div>
          <p>Situação atual</p>
          <h2 id="patient-portal-plan-current-title">Plano de Saúde HPSM</h2>
        </div>
        <span className="patient-portal-plan-status" data-tone={status.tone}>{status.label}</span>
        <CurrentPlanDetails page={initialPage} />
      </section>

      <section className="patient-portal-plan-history" aria-labelledby="patient-portal-plan-history-title">
        <header>
          <div>
            <p>Movimentações</p>
            <h2 id="patient-portal-plan-history-title">Histórico do plano</h2>
          </div>
        </header>
        {items.length ? (
          <ol>
            {items.map((item) => <PlanHistoryItem item={item} key={item.key} />)}
          </ol>
        ) : <p className="patient-portal-empty">Nenhuma movimentação do Plano de Saúde foi registrada.</p>}
        {error ? <p className="patient-portal-inline-error" role="alert">{error}</p> : null}
        {cursor ? <button className="patient-portal-load-more" disabled={loading} onClick={loadMore} type="button">{loading ? "Carregando…" : "Carregar mais"}</button> : null}
      </section>
    </div>
  );
}

function CurrentPlanDetails({ page }: { page: PatientPortalHealthPlanPage }) {
  const current = page.current;
  if (current.status === "active") {
    return <dl><PlanDetail label="Ativado em" value={current.activatedAt ? formatPortalDate(current.activatedAt) : "Data não informada"} /><PlanDetail label="Válido até" value={current.validUntil ? formatPortalDate(current.validUntil) : "Data não informada"} /></dl>;
  }
  if (current.status === "awaiting_confirmation") {
    return <div className="patient-portal-plan-message"><strong>Sua ativação ainda está sendo processada.</strong>{current.pendingRequestedAt ? <span>Solicitação recebida em {formatPortalDate(current.pendingRequestedAt)}.</span> : null}</div>;
  }
  if (current.status === "expired") {
    return <div className="patient-portal-plan-message"><strong>Plano expirado</strong>{current.validUntil ? <span>Última validade: {formatPortalDate(current.validUntil)}.</span> : null}</div>;
  }
  return <div className="patient-portal-plan-message"><strong>Você não possui Plano de Saúde ativo.</strong></div>;
}

function PlanDetail({ label, value }: { label: string; value: string }) {
  return <div><dt>{label}</dt><dd>{value}</dd></div>;
}

function PlanHistoryItem({ item }: { item: PatientPortalHealthPlanHistoryItem }) {
  const title = item.event === "activated" ? "Plano ativado"
    : item.event === "renewed" ? "Plano renovado"
      : item.event === "not_approved" ? "Solicitação não aprovada"
        : "Solicitação recebida";
  return (
    <li>
      <div>
        <strong>{title}</strong>
        <time dateTime={item.occurredAt}>{formatPortalDate(item.occurredAt, true)}</time>
      </div>
      {item.status === "approved" && item.coverageStart && item.coverageEnd
        ? <p>Vigência de {formatPortalDate(item.coverageStart)} a {formatPortalDate(item.coverageEnd)}.</p>
        : item.status === "pending" ? <p>Em análise.</p> : null}
    </li>
  );
}

function appendUnique(current: PatientPortalHealthPlanHistoryItem[], incoming: PatientPortalHealthPlanHistoryItem[]) {
  const known = new Set(current.map((item) => item.key));
  return [...current, ...incoming.filter((item) => !known.has(item.key))];
}
