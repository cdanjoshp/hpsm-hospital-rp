"use client";

import { FormEvent, useState } from "react";
import Link from "next/link";
import { useAppRefresh } from "../lib/client-refresh";
import type { HealthPlanPending, PendingCenterData, PendingItem } from "../lib/pending";
import { formatPatientPassport } from "../lib/passport";

export function PendingCenter({ data, readOnly = false }: { data: PendingCenterData; readOnly?: boolean }) {
  const refreshApp = useAppRefresh();
  const [healthPlans, setHealthPlans] = useState(data.healthPlans);
  const [approving, setApproving] = useState<HealthPlanPending | null>(null);
  const [rejecting, setRejecting] = useState<HealthPlanPending | null>(null);
  const [loadingId, setLoadingId] = useState<number | null>(null);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");
  const total = data.total - data.counts.healthPlans + healthPlans.length;

  async function reviewPlan(request: HealthPlanPending, decision: "approved" | "rejected", reason?: string) {
    if (readOnly || loadingId !== null) return;
    setLoadingId(request.requestId);
    setError("");
    setSuccess("");
    try {
      const response = await fetch("/api/health-plans/review", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ requestId: request.requestId, decision, reason: reason ?? null }),
      });
      const payload = (await response.json()) as { error?: string; validUntil?: string | null };
      if (!response.ok) {
        setError(payload.error ?? "Não foi possível registrar a decisão.");
        return;
      }
      setHealthPlans((current) => current.filter((item) => item.requestId !== request.requestId));
      setApproving(null);
      setRejecting(null);
      setSuccess(decision === "approved"
        ? `Plano de ${request.patientName} ativado/renovado até ${payload.validUntil ? formatDay(payload.validUntil) : "a nova validade"}.`
        : `Ativação de ${request.patientName} recusada e pendência resolvida.`);
      refreshApp(900);
    } catch {
      setError("Não foi possível registrar a decisão.");
    } finally {
      setLoadingId(null);
    }
  }

  function confirmPlan(request: HealthPlanPending) {
    setError("");
    setApproving(request);
  }

  function rejectPlan(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!rejecting) return;
    const form = new FormData(event.currentTarget);
    void reviewPlan(rejecting, "rejected", String(form.get("reason") ?? ""));
  }

  return (
    <div className="hr-tab-panel">
      {error ? <p className="form-error hr-global-message" role="alert">{error}</p> : null}
      {success ? <p className="form-success hr-global-message" role="status">{success}</p> : null}
      <section className="pending-summary" aria-label="Resumo das pendências">
        <PendingMetric label="Total pendente" value={total} tone="total" />
        <PendingMetric label="Afastamentos" value={data.counts.absences} tone="important" />
        <PendingMetric label="Justificativas" value={data.counts.justifications} tone="important" />
        <PendingMetric label="Promoções" value={data.counts.promotions} tone="normal" />
        <PendingMetric label="Planos de saúde" value={healthPlans.length} tone="important" />
        <PendingMetric label="Gessos vencidos" value={data.counts.casts} tone="urgent" />
        <PendingMetric label="Candidaturas" value={data.counts.recruitment} tone="normal" />
        <PendingMetric label="Disciplina" value={data.counts.discipline} tone="urgent" />
      </section>

      {total ? (
        <div className="pending-columns">
          <PendingGroup readOnly={readOnly} id="disciplina" eyebrow="Prioridade máxima" title="Análises disciplinares" items={data.discipline} empty="Nenhuma suspensão aguarda análise." />
          <PendingGroup readOnly={readOnly} id="gessos" eyebrow="Acompanhamento clínico" title="Gessos com retirada vencida" items={data.casts} empty="Nenhum gesso ativo ultrapassou a previsão de retirada." />
          <HealthPlanGroup readOnly={readOnly} items={healthPlans} loadingId={loadingId} onApprove={confirmPlan} onReject={setRejecting} />
          <PendingGroup readOnly={readOnly} id="ausencias" eyebrow="Gestão de pessoas" title="Afastamentos e justificativas" items={data.absences} empty="Nenhuma análise de afastamento ou horas aguarda decisão." />
          <PendingGroup readOnly={readOnly} id="carreira" eyebrow="Carreira e formação" title="Promoções" items={data.career} empty="Nenhuma promoção aguarda decisão." />
          <PendingGroup readOnly={readOnly} id="recrutamento" eyebrow="Entrada de profissionais" title="Candidaturas" items={data.recruitment} empty="Nenhuma candidatura aguarda decisão." />
        </div>
      ) : (
        <section className="management-card pending-all-clear">
          <span>✓</span><h2>Nenhuma decisão pendente</h2><p>As filas de recrutamento, afastamentos, justificativas e disciplina estão atualizadas.</p>
        </section>
      )}
      {!readOnly && approving ? (
        <div className="credential-overlay" role="dialog" aria-modal="true" aria-labelledby="approve-health-plan-title">
          <section className="credential-dialog hr-decision-dialog">
            <div className="decision-dialog-symbol">✓</div>
            <p className="eyebrow">Plano de Saúde HPSM</p>
            <h2 id="approve-health-plan-title">Confirmar ativação</h2>
            <p>Confirme o pagamento da venda #{approving.attendanceId} e ative o plano de {approving.patientName}. A validade será calculada automaticamente sem perder dias restantes.</p>
            {error ? <p className="form-error" role="alert">{error}</p> : null}
            <div className="decision-dialog-actions">
              <button className="secondary-button" type="button" disabled={loadingId !== null} onClick={() => { setApproving(null); setError(""); }}>Cancelar</button>
              <button className="health-plan-approve" type="button" disabled={loadingId !== null} onClick={() => void reviewPlan(approving, "approved")}>{loadingId !== null ? "Ativando…" : "Confirmar pagamento e ativar"}</button>
            </div>
          </section>
        </div>
      ) : null}
      {!readOnly && rejecting ? (
        <div className="credential-overlay" role="dialog" aria-modal="true" aria-labelledby="reject-health-plan-title">
          <section className="credential-dialog hr-decision-dialog" data-danger="true">
            <div className="decision-dialog-symbol">!</div>
            <p className="eyebrow">Plano de Saúde HPSM</p>
            <h2 id="reject-health-plan-title">Recusar ativação</h2>
            <p>A venda #{rejecting.attendanceId} continuará registrada. Informe por que o plano de {rejecting.patientName} não deve ser ativado.</p>
            <form className="hr-form" onSubmit={rejectPlan}>
              <label>Motivo da recusa<textarea name="reason" rows={5} minLength={10} maxLength={2000} required placeholder="Explique o motivo da recusa (mínimo de 10 caracteres)." /></label>
              {error ? <p className="form-error" role="alert">{error}</p> : null}
              <div className="decision-dialog-actions">
                <button className="secondary-button" type="button" disabled={loadingId !== null} onClick={() => { setRejecting(null); setError(""); }}>Cancelar</button>
                <button className="reject-application-button solid" type="submit" disabled={loadingId !== null}>{loadingId !== null ? "Registrando…" : "Confirmar recusa"}</button>
              </div>
            </form>
          </section>
        </div>
      ) : null}
    </div>
  );
}

function HealthPlanGroup({ items, loadingId, onApprove, onReject, readOnly }: {
  items: HealthPlanPending[];
  loadingId: number | null;
  onApprove: (request: HealthPlanPending) => void;
  onReject: (request: HealthPlanPending) => void;
  readOnly: boolean;
}) {
  if (!items.length) return null;
  return (
    <section className="management-card pending-group" id="planos-saude">
      <div className="section-title"><div><p className="eyebrow">Conferência financeira</p><h2>Planos de saúde</h2></div><span className="count-pill">{items.length}</span></div>
      <div className="pending-list health-plan-pending-list">
        {items.map((item) => (
          <article data-priority="important" key={item.requestId}>
            <span className="pending-item-icon" aria-hidden="true">＋</span>
            <div>
              <strong>{item.patientName}</strong>
              <p>Passaporte {formatPatientPassport(item.patientPassport)} · venda #{item.attendanceId} · {formatMoney(item.planValue)}</p>
              <small>Vendido por {item.sellerName} ({item.sellerIdentity}) · {formatDateTime(item.createdAt)}</small>
            </div>
            <div className="health-plan-pending-actions">
              <em className="pending-status" data-status="pending">Pendente</em>
              {readOnly ? <span>Somente leitura</span> : <><button className="health-plan-approve" type="button" disabled={loadingId !== null} onClick={() => onApprove(item)}>{loadingId === item.requestId ? "Processando…" : "Confirmar / ativar"}</button><button className="health-plan-reject" type="button" disabled={loadingId !== null} onClick={() => onReject(item)}>Recusar</button></>}
            </div>
          </article>
        ))}
      </div>
    </section>
  );
}

function PendingMetric({ label, tone, value }: { label: string; tone: string; value: number }) {
  return <article data-tone={tone}><span aria-hidden="true">{tone === "urgent" ? "!" : tone === "important" ? "◷" : tone === "normal" ? "✦" : "▤"}</span><div><p>{label}</p><strong>{value}</strong></div></article>;
}

function PendingGroup({ empty, eyebrow, id, items, readOnly, title }: { empty: string; eyebrow: string; id: string; items: PendingItem[]; readOnly: boolean; title: string }) {
  return (
    <section className="management-card pending-group" id={id}>
      <div className="section-title"><div><p className="eyebrow">{eyebrow}</p><h2>{title}</h2></div><span className="count-pill">{items.length}</span></div>
      <div className="pending-list">
        {items.map((item) => (
          <article data-priority={item.priority} key={item.id}>
            <span className="pending-item-icon" aria-hidden="true">{item.priority === "urgent" ? "!" : item.category === "recruitment" ? "✦" : "◷"}</span>
            <div><strong>{item.title}</strong><p>{item.subtitle}</p><small>Recebido em {formatDateTime(item.createdAt)}</small></div>
            <div className="pending-item-actions"><em className="pending-status" data-status="pending">Pendente</em><Link href={item.href}>{readOnly ? "Visualizar" : item.actionLabel ?? "Resolver"}</Link></div>
          </article>
        ))}
        {!items.length ? <div className="compact-empty"><span>✓</span><strong>Fila atualizada</strong><p>{empty}</p></div> : null}
      </div>
    </section>
  );
}

function formatDateTime(value: string) {
  return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(value));
}

function formatDay(value: string) {
  return new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric", timeZone: "America/Sao_Paulo" }).format(new Date(value));
}

function formatMoney(value: number) {
  return new Intl.NumberFormat("pt-BR", { currency: "BRL", style: "currency" }).format(value);
}
