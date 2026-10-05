"use client";

import { FormEvent, useState } from "react";
import type { HrAbsenceRequest, HrSelfData, HrWeeklyRecord } from "../lib/hr";
import type { CareerSelfData } from "../lib/career";
import { useAppRefresh } from "../lib/client-refresh";
import { CareerSelfPanel } from "./career-self-panel";
import { HrWeekCard } from "./hr-week-card";

type MyHrSection = "career" | "absences" | "history";

export function MyHrPanel({ initialCareerData, initialData }: { initialCareerData: CareerSelfData; initialData: HrSelfData }) {
  const refreshApp = useAppRefresh();
  const [absences, setAbsences] = useState(initialData.absences);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");
  const [justifying, setJustifying] = useState<HrWeeklyRecord | null>(null);
  const [section, setSection] = useState<MyHrSection>("career");
  const today = todayIso();
  const tomorrow = addDays(today, 1);
  const pendingAbsences = absences.filter((absence) => absence.status === "pending").length;
  const openJustifications = initialData.weeklyRecords.filter((record) => record.closure_status === "awaiting_justification" || record.closure_status === "justification_pending").length;

  async function submitAbsence(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (loading) return;
    const form = event.currentTarget;
    const data = new FormData(form);
    setLoading(true);
    setError("");
    setSuccess("");
    try {
      const response = await fetch("/api/hr/absences", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          startDate: data.get("startDate"),
          endDate: data.get("endDate"),
          observation: data.get("observation"),
          reason: data.get("reason"),
        }),
      });
      const payload = (await response.json()) as { absence?: HrAbsenceRequest; error?: string };
      if (!response.ok || !payload.absence) {
        setError(payload.error ?? "Não foi possível solicitar o afastamento.");
        return;
      }
      setAbsences((current) => [payload.absence!, ...current]);
      setSuccess("Afastamento enviado para análise da Diretoria.");
      form.reset();
    } catch {
      setError("Não foi possível solicitar o afastamento.");
    } finally {
      setLoading(false);
    }
  }

  async function submitHourJustification(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!justifying || loading) return;
    const data = new FormData(event.currentTarget);
    setLoading(true);
    setError("");
    try {
      const response = await fetch("/api/hr/justifications", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ weeklyRecordId: justifying.id, reason: data.get("reason") }),
      });
      const payload = (await response.json()) as { error?: string };
      if (!response.ok) {
        setError(payload.error ?? "Não foi possível enviar a justificativa de horas.");
        return;
      }
      setJustifying(null);
      setSuccess("Justificativa de horas enviada para análise.");
      refreshApp(600);
    } catch {
      setError("Não foi possível enviar a justificativa de horas.");
    } finally {
      setLoading(false);
    }
  }

  async function cancelAbsence(requestId: number) {
    if (loading) return;
    setLoading(true);
    setError("");
    setSuccess("");
    try {
      const response = await fetch("/api/hr/absences", {
        method: "PATCH",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ requestId }),
      });
      const payload = (await response.json()) as { absence?: HrAbsenceRequest; error?: string };
      if (!response.ok || !payload.absence) {
        setError(payload.error ?? "Não foi possível cancelar a solicitação.");
        return;
      }
      setAbsences((current) => current.map((item) => item.id === requestId ? payload.absence! : item));
      setSuccess("Solicitação cancelada.");
    } catch {
      setError("Não foi possível cancelar a solicitação.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="my-hr-page">
      <section className="my-hr-summary-grid" aria-label="Resumo do Meu RH">
        <HrWeekCard progress={initialData.progress} />
        <article className="management-card my-hr-snapshot-card">
          <header>
            <div><p className="eyebrow">Situação atual</p><h2>Seu quadro funcional</h2></div>
            <span className="my-hr-live-dot">Atualizado</span>
          </header>
          <div className="my-hr-snapshot-grid">
            <div><span className="my-hr-snapshot-icon" aria-hidden="true">◆</span><p>Cargo atual</p><strong>{initialCareerData.position?.name ?? "Não definido"}</strong><small>{initialCareerData.position ? `Nível ${initialCareerData.position.level}` : "Aguardando atribuição"}</small></div>
            <div><span className="my-hr-snapshot-icon" aria-hidden="true">◷</span><p>Acumulado no mês</p><strong>{initialData.progress.monthlyAccumulated === null ? "—" : formatMinutes(initialData.progress.monthlyAccumulated)}</strong><small>Fonte oficial de horas</small></div>
            <div><span className="my-hr-snapshot-icon" aria-hidden="true">◇</span><p>Afastamentos</p><strong>{pendingAbsences}</strong><small>{pendingAbsences === 1 ? "solicitação aguardando análise" : "solicitações aguardando análise"}</small></div>
            <div data-warning={initialData.progress.warningCount > 0}><span className="my-hr-snapshot-icon" aria-hidden="true">!</span><p>Advertências no ciclo</p><strong>{initialData.progress.warningCount}/3</strong><small>{openJustifications ? `${openJustifications} pendência(s) de horas` : "Nenhuma pendência de horas"}</small></div>
          </div>
        </article>
      </section>

      <nav className="my-hr-section-nav" aria-label="Áreas do Meu RH">
        <button type="button" data-active={section === "career"} aria-current={section === "career" ? "page" : undefined} onClick={() => setSection("career")}><span className="my-hr-nav-icon" aria-hidden="true">↑</span><span><strong>Carreira e formação</strong><small>Progressão, cursos e cargos</small></span><em>{initialCareerData.courseRecords.length}</em></button>
        <button type="button" data-active={section === "absences"} aria-current={section === "absences" ? "page" : undefined} onClick={() => setSection("absences")}><span className="my-hr-nav-icon" aria-hidden="true">○</span><span><strong>Afastamentos</strong><small>Solicitações preventivas e abatimentos</small></span><em>{pendingAbsences}</em></button>
        <button type="button" data-active={section === "history"} aria-current={section === "history" ? "page" : undefined} onClick={() => setSection("history")}><span className="my-hr-nav-icon" aria-hidden="true">≡</span><span><strong>Histórico semanal</strong><small>Fechamentos, justificativas e advertências</small></span><em>{initialData.weeklyRecords.length}</em></button>
      </nav>

      <section className="my-hr-workspace" aria-live="polite">
        {section === "career" ? (
          <div className="my-hr-section-body" data-section="career">
            <header className="my-hr-section-heading"><div><p className="eyebrow">Desenvolvimento profissional</p><h2>Carreira e formação</h2><span>Acompanhe os requisitos reais da sua progressão e todo o seu histórico funcional.</span></div></header>
            <CareerSelfPanel initialData={initialCareerData} />
          </div>
        ) : null}

        {section === "absences" ? (
          <div className="my-hr-section-body" data-section="absences">
            <header className="my-hr-section-heading"><div><p className="eyebrow">Ausências planejadas</p><h2>Afastamentos</h2><span>Solicite antes da ausência e acompanhe a decisão e o abatimento de horas no mesmo lugar.</span></div></header>
            <div className="my-hr-absence-grid">
              <article className="management-card absence-request-card">
                <div className="section-title"><div><p className="eyebrow">Nova solicitação</p><h2>Solicitar afastamento</h2></div><span>＋</span></div>
                <p className="hr-card-intro">A Diretoria definirá o abatimento exato de horas para cada semana afetada.</p>
                <form className="hr-form" onSubmit={submitAbsence}>
                  <div className="form-row"><label>Data inicial<input type="date" name="startDate" min={tomorrow} defaultValue={tomorrow} required /></label><label>Data final<input type="date" name="endDate" min={tomorrow} defaultValue={tomorrow} required /></label></div>
                  <label>Motivo<textarea name="reason" minLength={10} maxLength={2000} rows={4} required placeholder="Explique de forma objetiva o motivo do afastamento." /></label>
                  <details className="my-hr-optional-field"><summary>Adicionar observação opcional</summary><label>Observação<textarea name="observation" maxLength={2000} rows={3} placeholder="Inclua algum detalhe somente se for necessário." /></label></details>
                  {error ? <p className="form-error" role="alert">{error}</p> : null}
                  {success ? <p className="form-success" role="status">{success}</p> : null}
                  <button className="submit-button" disabled={loading} type="submit"><span>{loading ? "Enviando…" : "Enviar para análise"}</span><span>→</span></button>
                </form>
              </article>

              <section className="management-card hr-history-card my-hr-absence-history">
                <div className="section-title"><div><p className="eyebrow">Acompanhamento</p><h2>Minhas solicitações</h2></div><span className="count-pill">{absences.length}</span></div>
                <div className="hr-record-list">
                  {absences.map((request) => <article key={request.id}><span className="hr-record-icon" data-status={request.status}>○</span><div><strong>{formatPeriod(request.start_date, request.end_date)}</strong><p>{request.reason}</p>{request.observation ? <span>{request.observation}</span> : null}{approvedDeduction(initialData, request.id) > 0 ? <small>Abatimento aprovado: {formatMinutes(approvedDeduction(initialData, request.id))}</small> : null}{request.review_note ? <blockquote>{request.review_note}</blockquote> : null}</div><aside><em data-status={request.status}>{absenceStatus(request)}</em><time>{formatDateTime(request.requested_at)}</time>{request.status === "pending" ? <button className="table-action" type="button" disabled={loading} onClick={() => cancelAbsence(request.id)}>Cancelar</button> : null}</aside></article>)}
                  {!absences.length ? <Empty text="Você ainda não solicitou afastamentos." /> : null}
                </div>
              </section>
            </div>
          </div>
        ) : null}

        {section === "history" ? (
          <div className="my-hr-section-body" data-section="history">
            <header className="my-hr-section-heading"><div><p className="eyebrow">Registro permanente</p><h2>Histórico semanal</h2><span>Consulte fechamentos, justificativas disponíveis e advertências sem misturar os fluxos.</span></div></header>
            <div className="my-hr-history-grid">
              <section className="management-card hr-history-card"><div className="section-title"><div><p className="eyebrow">Controle semanal</p><h2>Fechamentos</h2></div><span className="count-pill">{initialData.weeklyRecords.length}</span></div><div className="hr-compact-list">{initialData.weeklyRecords.slice(0, 12).map((record) => <article key={record.id}><div><strong>{formatPeriod(record.week_start, record.week_end)}</strong><span>{formatMinutes(record.worked_minutes)} realizadas · meta ajustada {formatMinutes(record.required_minutes)}</span>{record.leave_deduction_minutes ? <small>Afastamento: −{formatMinutes(record.leave_deduction_minutes)}</small> : null}{record.justification_minutes ? <small>Abonado: {formatMinutes(record.justification_minutes)}</small> : null}</div><aside><em data-status={record.closure_status}>{weekStatus(record)}</em>{record.closure_status === "awaiting_justification" ? <button className="table-action" type="button" onClick={() => setJustifying(record)}>Justificar déficit</button> : null}</aside></article>)}{!initialData.weeklyRecords.length ? <Empty text="Nenhuma semana foi fechada até o momento." /> : null}</div></section>
              <section className="management-card hr-history-card"><div className="section-title"><div><p className="eyebrow">Ciclo mensal</p><h2>Advertências</h2></div><span className="count-pill">{initialData.progress.warningCount}/3</span></div><p className="hr-card-intro">A contagem reinicia no novo mês. Registros anulados permanecem no histórico, mas deixam de contar.</p><div className="hr-compact-list">{initialData.warnings.slice(0, 12).map((warning) => <article key={warning.id}><div><strong>{warning.sequence_in_cycle}ª advertência · {monthLabel(warning.cycle_month)}</strong><span>{warning.reason}</span></div><em data-status={warning.status}>{warning.status === "active" ? "Ativa" : "Anulada"}</em></article>)}{!initialData.warnings.length ? <Empty text="Nenhuma advertência registrada." /> : null}</div></section>
            </div>
          </div>
        ) : null}
      </section>

      {justifying ? <div className="credential-overlay" role="dialog" aria-modal="true" aria-labelledby="hour-justification-title"><section className="credential-dialog hr-decision-dialog"><div className="decision-dialog-symbol">?</div><p className="eyebrow">Após a apuração</p><h2 id="hour-justification-title">Justificativa de horas</h2><p>O déficit desta semana é de <strong>{formatMinutes(justifying.remaining_deficit_minutes)}</strong>. Explique o motivo para análise da Diretoria.</p><form className="hr-form" onSubmit={submitHourJustification}><label>Motivo<textarea name="reason" minLength={10} maxLength={2000} rows={5} required placeholder="Descreva por que a meta ajustada não foi cumprida." /></label>{error ? <p className="form-error" role="alert">{error}</p> : null}<div className="decision-dialog-actions"><button className="secondary-button" type="button" disabled={loading} onClick={() => { setJustifying(null); setError(""); }}>Cancelar</button><button className="submit-button" type="submit" disabled={loading}>{loading ? "Enviando…" : "Enviar justificativa"}</button></div></form></section></div> : null}
    </div>
  );
}

function Empty({ text }: { text: string }) {
  return <div className="compact-empty"><span>◇</span><strong>Nenhum registro</strong><p>{text}</p></div>;
}

function absenceStatus(request: HrAbsenceRequest) {
  if (request.status === "pending") return "Aguardando análise";
  if (request.status === "rejected") return "Recusada";
  if (request.status === "cancelled") return "Cancelada";
  return "Aprovado com abatimento";
}

function weekStatus(record: HrWeeklyRecord) {
  if (record.closure_status === "awaiting_justification") return "Justificativa disponível";
  if (record.closure_status === "justification_pending") return "Justificativa em análise";
  if (record.closure_status !== "closed") return "Aguardando fechamento";
  return ({ met: "Meta cumprida", justified: "Déficit abonado", deficit: "Déficit mantido", warning_issued: "Advertência aplicada", warning_annulled: "Advertência anulada" } as Record<string, string>)[record.status] ?? record.status;
}

function approvedDeduction(data: HrSelfData, requestId: number) {
  return data.leaveAdjustments.filter((item) => item.leave_request_id === requestId).reduce((total, item) => total + item.deducted_minutes, 0);
}

function formatMinutes(total: number) {
  return `${Math.floor(total / 60)}h${String(total % 60).padStart(2, "0")}`;
}

function formatPeriod(start: string, end: string) {
  const formatter = new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "short", timeZone: "UTC" });
  const first = formatter.format(new Date(`${start}T00:00:00Z`));
  const last = formatter.format(new Date(`${end}T00:00:00Z`));
  return start === end ? first : `${first} — ${last}`;
}

function formatDateTime(value: string) {
  return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(value));
}

function monthLabel(value: string) {
  return new Intl.DateTimeFormat("pt-BR", { month: "long", timeZone: "UTC", year: "numeric" }).format(new Date(`${value}T00:00:00Z`));
}

function todayIso() {
  const parts = new Intl.DateTimeFormat("en-US", { day: "2-digit", month: "2-digit", timeZone: "America/Sao_Paulo", year: "numeric" }).formatToParts(new Date());
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}`;
}

function addDays(value: string, amount: number) {
  const date = new Date(`${value}T00:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() + amount);
  return date.toISOString().slice(0, 10);
}
