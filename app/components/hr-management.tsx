"use client";

import dynamic from "next/dynamic";
import { FormEvent, useMemo, useRef, useState } from "react";
import type {
  HrAbsenceRequest,
  HrAdminData,
  HrDisciplinaryReview,
  HrHourJustification,
  HrWeeklyRecord,
  HrWarning,
} from "../lib/hr";
import type { ManagedProfile } from "../lib/admin-data";
import type { HrProductionData, HrProductionDay } from "../lib/hr-production";
import type { PendingCenterData } from "../lib/pending";
import type { RecruitmentApplication, RecruitmentDecision } from "../lib/recruitment-management";
import type { AccessManagementData, StaffPosition } from "../lib/access";
import { positionName } from "../lib/staff-position";
import type { CareerAdminData } from "../lib/career";
import { useAppRefresh } from "../lib/client-refresh";
import { staffIdentity } from "../lib/staff-identity";
import { eligibleWarningSuggestions } from "../lib/hr-warning-suggestions";
const AccessManagement = dynamic(() => import("./access-management").then((module) => module.AccessManagement), { loading: DomainLoading });
const CareerManagement = dynamic(() => import("./career-management").then((module) => module.CareerManagement), { loading: DomainLoading });
const GuidedHoursControl = dynamic(() => import("./guided-hours-control").then((module) => module.GuidedHoursControl), { loading: DomainLoading });
const FunctionalProfile = dynamic(() => import("./functional-profile").then((module) => module.FunctionalProfile), { loading: DomainLoading });
const PendingCenter = dynamic(() => import("./pending-center").then((module) => module.PendingCenter), { loading: DomainLoading });
const RecruitmentManagement = dynamic(() => import("./recruitment-management").then((module) => module.RecruitmentManagement), { loading: DomainLoading });
const UserManagement = dynamic(() => import("./user-management").then((module) => module.UserManagement), { loading: DomainLoading });

export type HrManagementTab = "overview" | "pending" | "applications" | "hours" | "absences" | "discipline" | "career" | "profiles" | "reports" | "team";
type Tab = HrManagementTab;
type ReportView = "monthly" | "weekly" | "absences" | "warnings";
type ActionDialog =
  | { decision: "approved" | "rejected"; request: HrAbsenceRequest; type: "absence" }
  | { decision: "approved" | "rejected"; justification: HrHourJustification; type: "hourJustification" }
  | { record?: HrWeeklyRecord; type: "issueWarning" }
  | { record: HrWeeklyRecord; type: "dismissWarningSuggestion" }
  | { type: "warning"; warning: HrWarning }
  | { decision: "maintain_suspension" | "dismiss"; review: HrDisciplinaryReview; type: "review" };

type HrManagementProps = {
  actorId: string;
  initialAccessData: AccessManagementData;
  initialApplications: RecruitmentApplication[];
  initialCareerData: CareerAdminData;
  initialData: HrAdminData;
  initialDecisions: RecruitmentDecision[];
  initialPendingData: PendingCenterData;
  initialProductionData: HrProductionData;
  initialProfiles: ManagedProfile[];
  initialSelectedApplicationId?: string;
  initialTab?: Tab;
  permissionCodes: string[];
  referenceTime: string;
  visibleTabs?: HrManagementTab[];
};

export function HrManagement({ actorId, initialAccessData, initialApplications, initialCareerData, initialData, initialDecisions, initialPendingData, initialProductionData, initialProfiles, initialSelectedApplicationId, initialTab = "overview", permissionCodes, referenceTime, visibleTabs }: HrManagementProps) {
  const refreshApp = useAppRefresh();
  const permissionSet = useMemo(() => new Set(permissionCodes), [permissionCodes]);
  const allowedTabs = useMemo(() => {
    const permitted = availableTabs(permissionSet);
    return visibleTabs ? permitted.filter((tab) => visibleTabs.includes(tab)) : permitted;
  }, [permissionSet, visibleTabs]);
  const [tab, setTab] = useState<Tab>(() => allowedTabs.includes(initialTab) ? initialTab : allowedTabs[0] ?? "overview");
  const [pendingData, setPendingData] = useState(initialPendingData);
  const [productionData, setProductionData] = useState(initialProductionData);
  const [productionError, setProductionError] = useState("");
  const [productionLoading, setProductionLoading] = useState(false);
  const productionRequest = useRef<AbortController | null>(null);
  const [dialog, setDialog] = useState<ActionDialog | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");
  const [dismissedSuggestions, setDismissedSuggestions] = useState<Set<number>>(() => new Set());
  const [reportMonth, setReportMonth] = useState(todayIso().slice(0, 7));
  const [reportQuery, setReportQuery] = useState("");
  const [reportView, setReportView] = useState<ReportView>("monthly");
  const profileMap = useMemo(() => new Map(initialData.profiles.map((profile) => [profile.user_id, profile])), [initialData.profiles]);
  const positions = initialCareerData.positions.length ? initialCareerData.positions : initialAccessData.positions;
  const actorProfile = initialData.profiles.find((profile) => profile.user_id === actorId);
  const canManageIdentity = positions.some((position) => position.id === actorProfile?.position_id && position.level === 14);
  const eligibleProfiles = initialData.profiles.filter((profile) => profile.role_code !== "diretor_geral" && profile.status !== "inactive");
  const pendingAbsences = initialData.absences.filter((request) => request.status === "pending");
  const pendingJustifications = initialData.hourJustifications.filter((request) => request.status === "pending");
  const pendingReviews = initialData.reviews.filter((review) => review.status === "pending");
  const cycleMonth = `${todayIso().slice(0, 7)}-01`;
  const activeWarnings = initialData.warnings.filter((warning) => warning.status === "active" && warning.cycle_month === cycleMonth);
  const warningEligibleRecords = eligibleWarningSuggestions(initialData.weeklyRecords, initialData.warnings,
    new Set(initialData.profiles.filter((profile) => profile.role_code === "diretor_geral").map((profile) => profile.user_id)), dismissedSuggestions);

  async function changeReportMonth(month: string) {
    if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(month)) return;
    productionRequest.current?.abort();
    productionRequest.current = null;
    setReportMonth(month);
    if (productionData.month === month) {
      setProductionError("");
      setProductionLoading(false);
      return;
    }
    const controller = new AbortController();
    productionRequest.current = controller;
    setProductionLoading(true);
    setProductionError("");
    try {
      const response = await fetch(`/api/hr/reports/production?month=${encodeURIComponent(month)}`, { signal: controller.signal });
      const payload = (await response.json()) as HrProductionData & { error?: string };
      if (!response.ok) throw new Error(payload.error ?? "Não foi possível consultar a produção.");
      setProductionData(payload);
    } catch (requestError: unknown) {
      if (requestError instanceof DOMException && requestError.name === "AbortError") return;
      setProductionError(requestError instanceof Error ? requestError.message : "Não foi possível consultar a produção.");
    } finally {
      if (productionRequest.current === controller) {
        productionRequest.current = null;
        setProductionLoading(false);
      }
    }
  }

  async function decide(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!dialog || loading) return;
    const form = new FormData(event.currentTarget);
    let endpoint = "";
    let body: Record<string, unknown> = {};
    if (dialog.type === "absence") {
      endpoint = "/api/hr/absences/review";
      body = {
        requestId: dialog.request.id,
        decision: dialog.decision,
        adjustments: dialog.decision === "approved" ? leaveWeeks(dialog.request).map((weekStart) => ({ week_start: weekStart, deducted_minutes: durationToMinutes(String(form.get(`adjustment:${weekStart}`) ?? "")) })).filter((item) => item.deducted_minutes !== null && item.deducted_minutes > 0) : [],
        note: form.get("note"),
      };
    } else if (dialog.type === "hourJustification") {
      endpoint = "/api/hr/justifications/review";
      body = { justificationId: dialog.justification.id, decision: dialog.decision, creditedMinutes: durationToMinutes(String(form.get("credited") ?? "")), note: form.get("note") };
    } else if (dialog.type === "issueWarning") {
      endpoint = "/api/hr/warnings/issue";
      body = {
        employeeId: dialog.record?.employee_id ?? form.get("employeeId"),
        weeklyRecordId: dialog.record?.id ?? null,
        category: dialog.record ? "weekly_goal" : form.get("category"),
        cycleMonth: dialog.record?.cycle_month ?? form.get("cycleMonth"),
        reason: form.get("reason"),
      };
    } else if (dialog.type === "dismissWarningSuggestion") {
      endpoint = "/api/hr/warnings/dismiss-suggestion";
      body = { weeklyRecordId: dialog.record.id, note: form.get("note") };
    } else if (dialog.type === "warning") {
      endpoint = "/api/hr/warnings/annul";
      body = { warningId: dialog.warning.id, reason: form.get("note") };
    } else {
      endpoint = "/api/hr/reviews/decide";
      body = { reviewId: dialog.review.id, decision: dialog.decision, note: form.get("note") };
    }
    setLoading(true);
    setError("");
    try {
      const response = await fetch(endpoint, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
      const payload = (await response.json()) as { error?: string };
      if (!response.ok) {
        setError(payload.error ?? "Não foi possível registrar a decisão.");
        return;
      }
      if (dialog.type === "dismissWarningSuggestion") {
        setDismissedSuggestions((current) => new Set(current).add(dialog.record.id));
        setSuccess("Sugestão de ADV excluída. O fechamento e o déficit permanecem registrados.");
      } else setSuccess("Decisão registrada com sucesso.");
      setDialog(null);
      refreshApp(500);
    } catch {
      setError("Não foi possível registrar a decisão.");
    } finally {
      setLoading(false);
    }
  }

  async function toggleWarningProgression(warning: HrWarning) {
    if (loading) return;
    const impacts = !warning.impacts_progression;
    const note = impacts ? (window.prompt("Observação sobre o impacto na progressão (opcional):") ?? "") : "";
    if (note.length > 1000) return;
    setLoading(true); setError(""); setSuccess("");
    try {
      const response = await fetch("/api/career/warnings", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ impacts, note, warningId: warning.id }) });
      const payload = (await response.json()) as { error?: string };
      if (!response.ok) { setError(payload.error ?? "Não foi possível alterar o impacto da advertência."); return; }
      setSuccess(impacts ? "Advertência sinalizada para a progressão." : "Impacto na progressão removido.");
      refreshApp(500);
    } catch { setError("Não foi possível alterar o impacto da advertência."); }
    finally { setLoading(false); }
  }

  const reportProductionDays = useMemo(
    () => productionData.month === reportMonth ? productionData.days : [],
    [productionData, reportMonth],
  );
  const reportRows = useMemo(() => {
    const selectedCycle = `${reportMonth}-01`;
    const query = reportQuery.trim().toLocaleLowerCase("pt-BR");
    return initialData.profiles
      .filter((profile) => profile.role_code !== "diretor_geral")
      .filter((profile) => `${profile.display_name} ${profile.passport} ${positionName(profile, positions)}`.toLocaleLowerCase("pt-BR").includes(query))
      .map((profile) => {
        const snapshots = initialData.snapshots
          .filter((snapshot) => snapshot.employee_id === profile.user_id && snapshot.reference_month === selectedCycle)
          .sort((a, b) => a.reading_date.localeCompare(b.reading_date) || a.updated_at.localeCompare(b.updated_at));
        const records = initialData.weeklyRecords.filter((record) => record.employee_id === profile.user_id && record.cycle_month === selectedCycle);
        const warnings = initialData.warnings.filter((warning) => warning.employee_id === profile.user_id && warning.cycle_month === selectedCycle && warning.status === "active");
        const monthEnd = lastDayOfMonth(reportMonth);
        const absences = initialData.absences.filter((request) => request.employee_id === profile.user_id && request.status === "approved" && request.start_date <= monthEnd && request.end_date >= selectedCycle);
        const production = summarizeProduction(reportProductionDays, profile.user_id, selectedCycle, monthEnd);
        return {
          absences: absences.length,
          activeWarnings: warnings.length,
          attendanceCount: production.count,
          closedWeeks: records.filter((record) => record.closure_status === "closed").length,
          justifiedWeeks: records.filter((record) => record.closure_status === "closed" && (record.status === "justified" || record.status === "warning_annulled")).length,
          metWeeks: records.filter((record) => record.closure_status === "closed" && record.status === "met").length,
          monthlyMinutes: snapshots.at(-1)?.total_minutes ?? null,
          profile,
          registeredValue: production.total,
        };
      });
  }, [initialData, positions, reportMonth, reportProductionDays, reportQuery]);

  const selectedCycle = `${reportMonth}-01`;
  const reportMonthEnd = lastDayOfMonth(reportMonth);
  const matchingEmployeeIds = new Set(reportRows.map((row) => row.profile.user_id));
  const weeklyReportRows = initialData.weeklyRecords
    .filter((record) => record.cycle_month === selectedCycle && matchingEmployeeIds.has(record.employee_id))
    .sort((a, b) => b.week_start.localeCompare(a.week_start));
  const absenceReportRows = initialData.absences
    .filter((request) => request.start_date <= reportMonthEnd && request.end_date >= selectedCycle && matchingEmployeeIds.has(request.employee_id))
    .sort((a, b) => b.requested_at.localeCompare(a.requested_at));
  const warningReportRows = initialData.warnings
    .filter((warning) => warning.cycle_month === selectedCycle && matchingEmployeeIds.has(warning.employee_id))
    .sort((a, b) => b.issued_at.localeCompare(a.issued_at));

  function exportCsv() {
    let rows: string[][] = [];
    if (reportView === "monthly") {
      rows = [
        ["Profissional", "Passaporte", "Cargo", "Acumulado mensal", "Atendimentos/vendas", "Valor registrado", "Semanas apuradas", "Metas cumpridas", "Déficits abonados", "Advertências ativas", "Afastamentos aprovados"],
        ...reportRows.map((row) => [row.profile.display_name, row.profile.passport, positionName(row.profile, positions), formatMinutes(row.monthlyMinutes), String(row.attendanceCount), formatMoney(row.registeredValue), String(row.closedWeeks), String(row.metWeeks), String(row.justifiedWeeks), String(row.activeWarnings), String(row.absences)]),
      ];
    } else if (reportView === "weekly") {
      rows = [["Profissional", "Semana", "Meta base", "Afastamento", "Meta ajustada", "Horas realizadas", "Déficit", "Justificativa", "Déficit restante", "Resultado", "Atendimentos/vendas", "Valor registrado"], ...weeklyReportRows.map((record) => {
        const production = summarizeProduction(reportProductionDays, record.employee_id, record.week_start, record.week_end);
        const justification = initialData.hourJustifications.find((item) => item.weekly_record_id === record.id);
        return [nameOf(record.employee_id), formatPeriod(record.week_start, record.week_end), formatMinutes(record.base_required_minutes), formatMinutes(record.leave_deduction_minutes), formatMinutes(record.required_minutes), formatMinutes(record.worked_minutes), formatMinutes(record.deficit_minutes), justification ? justificationStatus(justification) : record.deficit_minutes ? "Não enviada" : "Não necessária", formatMinutes(record.remaining_deficit_minutes), weekStatus(record.status), String(production.count), formatMoney(production.total)];
      })];
    } else if (reportView === "absences") {
      rows = [["Profissional", "Período", "Situação", "Horas abatidas", "Solicitado em", "Analisado por"], ...absenceReportRows.map((request) => [nameOf(request.employee_id), formatPeriod(request.start_date, request.end_date), absenceStatus(request), request.status === "approved" ? formatMinutes(initialData.leaveAdjustments.filter((item) => item.leave_request_id === request.id).reduce((total, item) => total + item.deducted_minutes, 0)) : "—", formatDateTime(request.requested_at), request.reviewed_by ? nameOf(request.reviewed_by) : "—"] )];
    } else if (reportView === "warnings") {
      rows = [["Profissional", "Advertência", "Situação", "Motivo", "Emitida em", "Responsável"], ...warningReportRows.map((warning) => [nameOf(warning.employee_id), `${warning.sequence_in_cycle}/3`, warning.status === "active" ? "Ativa" : "Anulada", warning.reason, formatDateTime(warning.issued_at), nameOf(warning.annulled_by ?? warning.issued_by)])];
    }
    const csv = rows.map((row) => row.map(csvCell).join(";")).join("\n");
    const blob = new Blob(["\ufeff", csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = `rh-hpsm-${reportView}-${reportMonth}.csv`;
    anchor.click();
    URL.revokeObjectURL(url);
  }

  return (
    <div className="hr-management">
      {pendingData.total && allowedTabs.includes("pending") ? (
        <section className="hr-director-alert" role="status">
          <span>!</span>
          <div><strong>{pendingData.total} pendência(s) exigem análise</strong><p>{pendingData.counts.healthPlans} plano(s), {pendingData.counts.recruitment} candidatura(s), {pendingData.counts.absences} afastamento(s), {pendingData.counts.justifications} justificativa(s), {pendingData.counts.promotions} promoção(ões) e {pendingData.counts.discipline} caso(s) disciplinar(es).</p></div>
          <button type="button" onClick={() => setTab("pending")}>Analisar agora</button>
        </section>
      ) : null}

      {allowedTabs.length > 1 ? <nav className="hr-tabs" aria-label="Seções da área administrativa">
        {([
          ["overview", "Visão geral"], ["pending", "Pendências"], ["applications", "Candidaturas"], ["hours", "Horas e fechamento"], ["absences", "Afastamentos e justificativas"], ["discipline", "Disciplina"], ["career", "Carreira e formação"], ["profiles", "Perfis funcionais"], ["reports", "Relatórios"], ["team", "Equipe e acessos"],
        ] as Array<[Tab, string]>).filter(([value]) => allowedTabs.includes(value)).map(([value, label]) => (
          <button key={value} type="button" data-active={tab === value} onClick={() => { setTab(value); setError(""); setSuccess(""); }}>{label}{value === "pending" && pendingData.total ? <em>{pendingData.total}</em> : null}{value === "applications" && pendingData.recruitment.length ? <em>{pendingData.recruitment.length}</em> : null}{value === "absences" && pendingAbsences.length + pendingJustifications.length ? <em>{pendingAbsences.length + pendingJustifications.length}</em> : null}{value === "discipline" && pendingReviews.length ? <em>{pendingReviews.length}</em> : null}</button>
        ))}
      </nav> : null}

      {error ? <p className="form-error hr-global-message" role="alert">{error}</p> : null}
      {success ? <p className="form-success hr-global-message" role="status">{success}</p> : null}

      {tab === "overview" ? (
        <div className="hr-tab-panel">
          <section className="hr-metrics">
            <Metric icon="◷" label="Profissionais acompanhados" value={eligibleProfiles.length} />
            <Metric icon="?" label="Análises pendentes" value={pendingAbsences.length + pendingJustifications.length} tone={pendingAbsences.length + pendingJustifications.length ? "attention" : undefined} />
            <Metric icon="!" label="Advertências do mês" value={activeWarnings.length} tone={activeWarnings.length ? "warning" : undefined} />
            <Metric icon="▣" label="Suspensões para análise" value={pendingReviews.length} tone={pendingReviews.length ? "danger" : undefined} />
          </section>
          <section className="management-card hr-current-team">
            <div className="section-title"><div><p className="eyebrow">Semana atual</p><h2>Resumo da equipe</h2></div><span className="count-pill">10h</span></div>
            <div className="hr-team-table">
              <div className="hr-team-row hr-team-head"><span>Profissional</span><span>Progresso</span><span>Acumulado mensal</span><span>ADV</span><span>Situação</span></div>
              {eligibleProfiles.map((profile) => {
                const progress = initialData.progressByEmployee[profile.user_id];
                return <div className="hr-team-row" key={profile.user_id}><span><strong>{profile.display_name}</strong><small>{staffIdentity(profile.passport, positionName(profile, positions))}</small></span><span>{formatMinutes(progress?.workedMinutes ?? 0)} / {formatMinutes(progress?.requiredMinutes ?? 600)}{progress?.leaveDeductionMinutes ? <small>Afastamento −{formatMinutes(progress.leaveDeductionMinutes)}</small> : null}</span><span>{formatMinutes(progress?.monthlyAccumulated ?? null)}</span><span><b>{progress?.warningCount ?? 0}/3</b></span><span><em data-status={progress?.status ?? "awaiting_hours"}>{progressLabel(progress?.status)}</em></span></div>;
              })}
              {!eligibleProfiles.length ? <Empty text="Cadastre profissionais para iniciar o acompanhamento." /> : null}
            </div>
          </section>
        </div>
      ) : null}

      {tab === "pending" ? <PendingCenter data={pendingData} /> : null}

      {tab === "applications" ? (
        <RecruitmentManagement
          initialApplications={initialApplications}
          initialDecisions={initialDecisions}
          initialSelectedId={initialSelectedApplicationId}
          onDecision={(applicationId) => setPendingData((current) => {
            const removed = current.recruitment.some((item) => item.id === `recruitment-${applicationId}`);
            return {
              ...current,
              counts: { ...current.counts, recruitment: removed ? Math.max(0, current.counts.recruitment - 1) : current.counts.recruitment },
              recruitment: current.recruitment.filter((item) => item.id !== `recruitment-${applicationId}`),
              total: removed ? Math.max(0, current.total - 1) : current.total,
            };
          })}
        />
      ) : null}

      {tab === "hours" ? (
        <GuidedHoursControl actorId={actorId} initialData={initialData} positions={positions} />
      ) : null}

      {tab === "absences" ? (
        <div className="hr-tab-panel hr-absence-grid">
          {permissionSet.has("hr.absences.review") ? <section className="management-card hr-history-card">
            <div className="section-title"><div><p className="eyebrow">Preventivo</p><h2>Solicitações de afastamento</h2></div><span className="count-pill">{pendingAbsences.length} pendente(s)</span></div>
            <p className="hr-card-intro">Ao aprovar, defina quantas horas serão abatidas da meta em cada semana afetada.</p>
            <div className="hr-record-list">
              {initialData.absences.map((request) => <article key={request.id} data-priority={request.status === "pending"}><span className="hr-record-icon" data-status={request.status}>○</span><div><strong>{nameOf(request.employee_id)} · {formatPeriod(request.start_date, request.end_date)}</strong><p>{request.reason}</p>{request.observation ? <span>{request.observation}</span> : null}{request.status === "approved" ? <small>Abatimento total: {formatMinutes(initialData.leaveAdjustments.filter((item) => item.leave_request_id === request.id).reduce((total, item) => total + item.deducted_minutes, 0))}</small> : null}{request.review_note ? <blockquote>{request.review_note}</blockquote> : null}<small>Solicitado {formatDateTime(request.requested_at)}{request.reviewed_by ? ` · analisado por ${nameOf(request.reviewed_by)}` : ""}</small></div><aside><em data-status={request.status}>{absenceStatus(request)}</em>{request.status === "pending" ? <div className="hr-inline-actions"><button type="button" onClick={() => setDialog({ type: "absence", decision: "approved", request })}>Analisar</button><button type="button" data-danger="true" onClick={() => setDialog({ type: "absence", decision: "rejected", request })}>Recusar</button></div> : null}</aside></article>)}
              {!initialData.absences.length ? <Empty text="Nenhum afastamento foi solicitado." /> : null}
            </div>
          </section> : null}
          {permissionSet.has("hr.justifications.review") ? <section className="management-card hr-history-card">
            <div className="section-title"><div><p className="eyebrow">Após a apuração</p><h2>Justificativas de horas</h2></div><span className="count-pill">{pendingJustifications.length} pendente(s)</span></div>
            <p className="hr-card-intro">Aprove todas as horas, apenas uma parte, ou recuse. O resultado semanal será recalculado.</p>
            <div className="hr-record-list">
              {initialData.hourJustifications.map((request) => { const week = initialData.weeklyRecords.find((record) => record.id === request.weekly_record_id); return <article key={request.id} data-priority={request.status === "pending"}><span className="hr-record-icon" data-status={request.status}>◷</span><div><strong>{nameOf(request.employee_id)} · {week ? formatPeriod(week.week_start, week.week_end) : "Semana não identificada"}</strong><p>{request.reason}</p><small>Déficit: {formatMinutes(request.deficit_minutes)}{request.credited_minutes !== null ? ` · abonado: ${formatMinutes(request.credited_minutes)}` : ""}</small>{request.review_note ? <blockquote>{request.review_note}</blockquote> : null}<small>Enviada {formatDateTime(request.submitted_at)}{request.reviewed_by ? ` · analisada por ${nameOf(request.reviewed_by)}` : ""}</small></div><aside><em data-status={request.status}>{justificationStatus(request)}</em>{request.status === "pending" ? <div className="hr-inline-actions"><button type="button" onClick={() => setDialog({ type: "hourJustification", decision: "approved", justification: request })}>Aprovar</button><button type="button" data-danger="true" onClick={() => setDialog({ type: "hourJustification", decision: "rejected", justification: request })}>Recusar</button></div> : null}</aside></article>; })}
              {!initialData.hourJustifications.length ? <Empty text="Nenhuma justificativa de horas foi enviada." /> : null}
            </div>
          </section> : null}
        </div>
      ) : null}

      {tab === "discipline" ? (
        <div className="hr-tab-panel hr-discipline-grid">
          <section className="management-card hr-history-card">
            <div className="section-title"><div><p className="eyebrow">Prioridade</p><h2>Suspensões para análise</h2></div><span className="count-pill">{pendingReviews.length}</span></div>
            <div className="hr-review-list">
              {initialData.reviews.map((review) => <article key={review.id} data-status={review.status}><header><span>!</span><div><strong>{nameOf(review.employee_id)}</strong><small>Ciclo {monthLabel(review.cycle_month)} · aberto {formatDateTime(review.triggered_at)}</small></div><em>{reviewStatus(review.status)}</em></header>{review.decision_note ? <blockquote>{review.decision_note}</blockquote> : null}{review.status === "pending" ? <footer><button type="button" onClick={() => setDialog({ type: "review", decision: "maintain_suspension", review })}>Manter suspensão</button><button type="button" data-danger="true" onClick={() => setDialog({ type: "review", decision: "dismiss", review })}>Desligar do HP</button></footer> : null}</article>)}
              {!initialData.reviews.length ? <Empty text="Nenhum caso disciplinar foi aberto." /> : null}
            </div>
          </section>
          <section className="management-card hr-history-card">
            <div className="section-title"><div><p className="eyebrow">Ação humana</p><h2>Advertências</h2></div><button className="submit-button compact" type="button" onClick={() => setDialog({ type: "issueWarning" })}>Aplicar advertência</button></div>
            {warningEligibleRecords.length ? <div className="weekly-warning-candidates"><strong>{warningEligibleRecords.length} fechamento(s) com déficit</strong><p>A advertência só será aplicada se a Diretoria decidir. Você pode excluir uma sugestão sem alterar o fechamento.</p>{warningEligibleRecords.slice(0, 8).map((record) => <div className="weekly-warning-candidate" key={record.id}><button type="button" disabled={loading} onClick={() => setDialog({ type: "issueWarning", record })}><span>{nameOf(record.employee_id)} · {formatPeriod(record.week_start, record.week_end)}</span><b>Déficit {formatMinutes(record.remaining_deficit_minutes)}</b></button><button className="weekly-warning-dismiss" type="button" disabled={loading} aria-label={`Excluir sugestão de ADV para ${nameOf(record.employee_id)} no período ${formatPeriod(record.week_start, record.week_end)}`} onClick={() => setDialog({ type: "dismissWarningSuggestion", record })}>Excluir sugestão</button></div>)}</div> : null}
            <div className="section-title hr-warning-history-title"><div><p className="eyebrow">Histórico mensal</p><h3>Advertências registradas</h3></div><span className="count-pill">{initialData.warnings.length}</span></div>
            <div className="hr-warning-list">
              {initialData.warnings.map((warning) => <article key={warning.id}><span data-status={warning.status}>{warning.sequence_in_cycle}</span><div><strong>{nameOf(warning.employee_id)} · {monthLabel(warning.cycle_month)}</strong><p>{warning.reason}</p><small>{warning.origin === "manual" ? categoryLabel(warning.category) : "Descumprimento da meta semanal"} · emitida por {nameOf(warning.issued_by)} em {formatDateTime(warning.issued_at)}</small>{warning.impacts_progression ? <small className="warning-progression-flag">Impacta progressão · aumenta somente o prazo mínimo</small> : null}{warning.progression_impact_note ? <blockquote>{warning.progression_impact_note}</blockquote> : null}{warning.annulment_reason ? <blockquote>{warning.annulment_reason}</blockquote> : null}</div><aside><em data-status={warning.status}>{warning.status === "active" ? "Ativa" : "Anulada"}</em>{warning.status === "active" && permissionSet.has("hr.warnings.progression") ? <button className="table-action" type="button" disabled={loading} onClick={() => toggleWarningProgression(warning)}>{warning.impacts_progression ? "Não impactar promoção" : "Impactar promoção"}</button> : null}{warning.status === "active" && warning.employee_id !== actorId && permissionSet.has("hr.warnings.annul") ? <button className="table-action" type="button" onClick={() => setDialog({ type: "warning", warning })}>Anular</button> : null}</aside></article>)}
              {!initialData.warnings.length ? <Empty text="Nenhuma advertência foi registrada." /> : null}
            </div>
          </section>
        </div>
      ) : null}

      {tab === "career" ? <CareerManagement actorId={actorId} initialData={initialCareerData} permissionCodes={permissionCodes} /> : null}

      {tab === "profiles" ? <FunctionalProfile canManageIdentity={canManageIdentity} profiles={initialData.profiles} positions={positions} /> : null}

      {tab === "reports" ? (
        <section className="management-card hr-reports hr-tab-panel">
          <div className="section-title"><div><p className="eyebrow">Relatórios administrativos</p><h2>{reportTitle(reportView)}</h2></div><span>▤</span></div>
          <nav className="hr-report-switch" aria-label="Tipo de relatório">
            {([['monthly', 'Mensal'], ['weekly', 'Semanal'], ['absences', 'Afastamentos'], ['warnings', 'Advertências']] as Array<[ReportView, string]>).map(([value, label]) => <button key={value} type="button" data-active={reportView === value} onClick={() => setReportView(value)}>{label}</button>)}
          </nav>
          <div className="hr-report-toolbar">
            <label>Competência<input type="month" value={reportMonth} onChange={(event) => changeReportMonth(event.target.value)} /></label>
            <label>Buscar profissional<input placeholder="Nome ou passaporte" value={reportQuery} onChange={(event) => setReportQuery(event.target.value)} /></label>
            <button type="button" onClick={exportCsv}>Exportar CSV</button><button type="button" onClick={() => window.print()}>Imprimir</button>
          </div>
          {productionLoading ? <p className="hr-production-status" role="status">Atualizando os atendimentos e valores da competência…</p> : null}
          {productionError ? <p className="form-error hr-production-status" role="alert">{productionError}</p> : null}

          {reportView === "monthly" ? <div className="hr-report-table"><div className="hr-report-row hr-report-head" data-layout="monthly"><span>Profissional</span><span>Horas do mês</span><span>Atend./vendas</span><span>Valor registrado</span><span>Semanas</span><span>Cumpridas</span><span>Abonadas</span><span>ADV</span><span>Afastamentos</span></div>{reportRows.map((row) => <div className="hr-report-row" data-layout="monthly" key={row.profile.user_id}><span><strong>{row.profile.display_name}</strong><small>{staffIdentity(row.profile.passport, positionName(row.profile, positions))}</small></span><span>{formatMinutes(row.monthlyMinutes)}</span><span><strong>{row.attendanceCount}</strong></span><span><strong>{formatMoney(row.registeredValue)}</strong></span><span>{row.closedWeeks}</span><span>{row.metWeeks}</span><span>{row.justifiedWeeks}</span><span><em data-status={row.activeWarnings >= 3 ? "danger" : "active"}>{row.activeWarnings}/3</em></span><span>{row.absences}</span></div>)}{!reportRows.length ? <Empty text="Nenhum profissional corresponde aos filtros." /> : null}</div> : null}

          {reportView === "weekly" ? <div className="hr-report-table"><div className="hr-report-row hr-report-head" data-layout="weekly"><span>Profissional</span><span>Semana</span><span>Meta base</span><span>Afastamento</span><span>Meta ajustada</span><span>Realizadas</span><span>Déficit / justificativa</span><span>Resultado</span><span>Atend./vendas</span><span>Valor registrado</span></div>{weeklyReportRows.map((record) => { const production = summarizeProduction(reportProductionDays, record.employee_id, record.week_start, record.week_end); const justification = initialData.hourJustifications.find((item) => item.weekly_record_id === record.id); return <div className="hr-report-row" data-layout="weekly" key={record.id}><span><strong>{nameOf(record.employee_id)}</strong><small>{record.closed_at ? `Fechado ${formatDateTime(record.closed_at)}` : "Em apuração"}</small></span><span>{formatPeriod(record.week_start, record.week_end)}</span><span>{formatMinutes(record.base_required_minutes)}</span><span>{record.leave_deduction_minutes ? `−${formatMinutes(record.leave_deduction_minutes)}` : "—"}</span><span><strong>{formatMinutes(record.required_minutes)}</strong></span><span>{formatMinutes(record.worked_minutes)}</span><span><strong>{formatMinutes(record.remaining_deficit_minutes)}</strong><small>{justification ? `${justificationStatus(justification)} · ${formatMinutes(record.justification_minutes)} abonada(s)` : record.deficit_minutes ? "Não enviada" : "Não necessária"}</small></span><span><em data-status={record.status}>{weekStatus(record.status)}</em></span><span><strong>{production.count}</strong></span><span><strong>{formatMoney(production.total)}</strong></span></div>; })}{!weeklyReportRows.length ? <Empty text="Nenhuma semana foi apurada nesta competência." /> : null}</div> : null}

          {reportView === "absences" ? <div className="hr-report-table"><div className="hr-report-row hr-report-head" data-layout="absence"><span>Profissional</span><span>Período</span><span>Situação</span><span>Abatimento</span><span>Análise</span></div>{absenceReportRows.map((request) => <div className="hr-report-row" data-layout="absence" key={request.id}><span><strong>{nameOf(request.employee_id)}</strong><small>Pedido {formatDateTime(request.requested_at)}</small></span><span>{formatPeriod(request.start_date, request.end_date)}</span><span><em data-status={request.status}>{absenceStatus(request)}</em></span><span>{request.status === "approved" ? formatMinutes(initialData.leaveAdjustments.filter((item) => item.leave_request_id === request.id).reduce((total, item) => total + item.deducted_minutes, 0)) : "—"}</span><span>{request.reviewed_by ? `${nameOf(request.reviewed_by)} · ${formatDateTime(request.reviewed_at!)}` : "Aguardando"}</span></div>)}{!absenceReportRows.length ? <Empty text="Nenhum afastamento corresponde aos filtros." /> : null}</div> : null}

          {reportView === "warnings" ? <div className="hr-report-table"><div className="hr-report-row hr-report-head" data-layout="warning"><span>Profissional</span><span>ADV</span><span>Situação</span><span>Emissão</span><span>Responsável</span></div>{warningReportRows.map((warning) => <div className="hr-report-row" data-layout="warning" key={warning.id}><span><strong>{nameOf(warning.employee_id)}</strong><small>{warning.reason}</small></span><span>{warning.sequence_in_cycle}/3</span><span><em data-status={warning.status}>{warning.status === "active" ? "Ativa" : "Anulada"}</em></span><span>{formatDateTime(warning.issued_at)}</span><span>{nameOf(warning.annulled_by ?? warning.issued_by)}</span></div>)}{!warningReportRows.length ? <Empty text="Nenhuma advertência corresponde aos filtros." /> : null}</div> : null}

          <p className="hr-report-footnote">As advertências são contabilizadas somente dentro da competência selecionada. Atendimentos cancelados não entram nas quantidades nem nos valores. O histórico dos ciclos anteriores permanece preservado.</p>
        </section>
      ) : null}

      {tab === "team" ? <div className="hr-tab-panel access-team-stack">
        {permissionSet.has("team.manage") ? <UserManagement canManage canOverridePosition={initialProfiles.some((profile) => profile.user_id === actorId && profile.role_code === "diretor_geral") && permissionSet.has("succession.manage")} initialProfiles={initialProfiles} positions={initialAccessData.positions} /> : null}
        {permissionSet.has("access.manage") ? <AccessManagement canManage initialData={initialAccessData} profiles={initialProfiles} referenceTime={referenceTime} /> : null}
      </div> : null}

      {dialog ? <DecisionDialog dialog={dialog} positions={positions} profiles={eligibleProfiles.filter((profile) => profile.user_id !== actorId)} loading={loading} error={error} onClose={() => { setDialog(null); setError(""); }} onSubmit={decide} /> : null}
    </div>
  );

  function nameOf(userId: string) {
    const profile = profileMap.get(userId);
    return profile ? `${profile.display_name} · ${staffIdentity(profile.passport, positionName(profile, positions))}` : "Profissional não identificado";
  }
}

function DecisionDialog({ dialog, error, loading, onClose, onSubmit, positions, profiles }: { dialog: ActionDialog; error: string; loading: boolean; onClose: () => void; onSubmit: (event: FormEvent<HTMLFormElement>) => void; positions: StaffPosition[]; profiles: HrAdminData["profiles"] }) {
  const title = dialog.type === "absence"
    ? (dialog.decision === "approved" ? "Aprovar afastamento" : "Recusar afastamento")
    : dialog.type === "hourJustification"
      ? (dialog.decision === "approved" ? "Abonar horas" : "Recusar justificativa")
    : dialog.type === "issueWarning"
      ? "Aplicar advertência"
    : dialog.type === "dismissWarningSuggestion"
      ? "Excluir sugestão de ADV"
    : dialog.type === "warning"
      ? "Anular advertência"
      : dialog.decision === "dismiss" ? "Desligar colaborador" : "Manter suspensão";
  const danger = dialog.type === "warning" || dialog.type === "issueWarning" || dialog.type === "dismissWarningSuggestion" || (dialog.type === "absence" && dialog.decision === "rejected") || (dialog.type === "hourJustification" && dialog.decision === "rejected") || (dialog.type === "review" && dialog.decision === "dismiss");
  return <div className="credential-overlay" role="dialog" aria-modal="true" aria-labelledby="hr-decision-title"><section className="credential-dialog hr-decision-dialog" data-danger={danger}><div className="decision-dialog-symbol">{danger ? "!" : "✓"}</div><p className="eyebrow">Decisão da Diretoria</p><h2 id="hr-decision-title">{title}</h2><p>{dialogDescription(dialog)}</p><form className="hr-form" onSubmit={onSubmit}>
    {dialog.type === "absence" && dialog.decision === "approved" ? <fieldset className="weekly-adjustment-fields"><legend>Horas abatidas por semana</legend>{leaveWeeks(dialog.request).map((weekStart) => <label key={weekStart}>{formatPeriod(weekStart, addIsoDays(weekStart, 6))}<input name={`adjustment:${weekStart}`} inputMode="numeric" placeholder="00:00" pattern="[0-9]{1,2}:[0-5][0-9]" required /><small>Máximo de 10:00 nesta semana.</small></label>)}</fieldset> : null}
    {dialog.type === "hourJustification" && dialog.decision === "approved" ? <label>Horas que serão abonadas<input name="credited" inputMode="numeric" defaultValue={minutesInput(dialog.justification.deficit_minutes)} placeholder="00:00" pattern="[0-9]{1,3}:[0-5][0-9]" required /><small>Déficit informado: {formatMinutes(dialog.justification.deficit_minutes)}. Você pode aprovar tudo ou apenas uma parte.</small></label> : null}
    {dialog.type === "issueWarning" && !dialog.record ? <label>Colaborador<select name="employeeId" required defaultValue=""><option value="" disabled>Selecione</option>{profiles.map((profile) => <option key={profile.user_id} value={profile.user_id}>{profile.display_name} · {staffIdentity(profile.passport, positionName(profile, positions))}</option>)}</select></label> : null}
    {dialog.type === "issueWarning" ? <WarningFields dialog={dialog} /> : null}
    {dialog.type === "dismissWarningSuggestion" ? <div className="dialog-context"><strong>{formatPeriod(dialog.record.week_start, dialog.record.week_end)}</strong><span>Déficit restante: {formatMinutes(dialog.record.remaining_deficit_minutes)}</span></div> : null}
    {dialog.type !== "issueWarning" ? <label>{dialog.type === "dismissWarningSuggestion" ? "Motivo da exclusão (opcional)" : dialog.type === "absence" && dialog.decision === "approved" ? "Observação da análise" : dialog.type === "hourJustification" && dialog.decision === "approved" ? "Observação da análise" : "Fundamentação da decisão"}<textarea name="note" rows={dialog.type === "dismissWarningSuggestion" ? 3 : 5} maxLength={dialog.type === "dismissWarningSuggestion" ? 500 : 2000} minLength={dialog.type === "dismissWarningSuggestion" ? undefined : danger ? 10 : 2} required={danger && dialog.type !== "dismissWarningSuggestion"} placeholder={dialog.type === "dismissWarningSuggestion" ? "Se desejar, registre por que esta sugestão não deve virar uma ADV." : danger ? "Explique o motivo da decisão (mínimo de 10 caracteres)." : "Observação opcional."} /></label> : null}
    {error ? <p className="form-error" role="alert">{error}</p> : null}<div className="decision-dialog-actions"><button className="secondary-button" type="button" disabled={loading} onClick={onClose}>Cancelar</button><button className={danger ? "reject-application-button solid" : "submit-button"} type="submit" disabled={loading}>{loading ? "Registrando…" : "Confirmar decisão"}</button></div></form></section></div>;
}

function dialogDescription(dialog: ActionDialog) {
  if (dialog.type === "absence") return dialog.decision === "approved" ? "Defina o abatimento de cada semana afetada. A meta poderá chegar a zero." : "A recusa preservará o pedido e a fundamentação no histórico.";
  if (dialog.type === "hourJustification") return dialog.decision === "approved" ? "Informe quantas horas do déficit serão abonadas. O resultado será recalculado automaticamente." : "A recusa manterá o déficit integral e ficará registrada no histórico.";
  if (dialog.type === "issueWarning") return dialog.record ? "Este fechamento ainda possui déficit. Revise os dados antes de aplicar a consequência disciplinar." : "Registre uma ocorrência disciplinar independente do fechamento semanal.";
  if (dialog.type === "dismissWarningSuggestion") return "A sugestão desaparecerá para a Diretoria e a decisão ficará registrada. O déficit semanal permanecerá no histórico.";
  if (dialog.type === "warning") return "A advertência deixará de contar neste ciclo, mas continuará visível no histórico.";
  return dialog.decision === "dismiss" ? "O acesso será marcado como inativo e a autoria ficará registrada." : "O colaborador continuará suspenso até uma nova decisão da Diretoria.";
}

function WarningFields({ dialog }: { dialog: Extract<ActionDialog, { type: "issueWarning" }> }) {
  return <>{dialog.record ? <div className="dialog-context"><strong>{formatPeriod(dialog.record.week_start, dialog.record.week_end)}</strong><span>Déficit restante: {formatMinutes(dialog.record.remaining_deficit_minutes)}</span></div> : <><label>Categoria<select name="category" defaultValue="conduct" required><option value="attendance">Assiduidade</option><option value="conduct">Conduta</option><option value="internal_rules">Regras internas</option><option value="other">Outro motivo</option></select></label><label>Competência<input type="month" name="cycleMonth" defaultValue={todayIso().slice(0, 7)} required /></label></>}<label>Descrição da ocorrência<textarea name="reason" rows={5} minLength={10} maxLength={1000} required placeholder="Descreva objetivamente o fato que fundamenta a advertência." /></label></>;
}

function Metric({ icon, label, tone, value }: { icon: string; label: string; tone?: string; value: number | string }) {
  return <article data-tone={tone}><span>{icon}</span><div><strong>{value}</strong><p>{label}</p></div></article>;
}

function Empty({ text }: { text: string }) { return <div className="compact-empty"><span>◇</span><strong>Nenhum registro</strong><p>{text}</p></div>; }
function DomainLoading() { return <section className="management-card administrative-domain-loading" role="status"><span aria-hidden="true">◷</span><div><strong>Carregando área administrativa…</strong><p>Somente os dados deste domínio estão sendo preparados.</p></div></section>; }
function availableTabs(permissions: Set<string>): Tab[] {
  const tabs: Tab[] = [];
  if (["hr.team.view", "hr.hours.manage", "hr.weeks.close", "hr.reports.view"].some((code) => permissions.has(code))) tabs.push("overview");
  if (["recruitment.manage", "admin.pending.manage", "healthplans.review", "hr.absences.review", "hr.justifications.review", "hr.discipline.manage", "hr.discipline.review", "progression.review"].some((code) => permissions.has(code))) tabs.push("pending");
  if (permissions.has("recruitment.manage")) tabs.push("applications");
  if (["hr.hours.manage", "hr.hours.import", "hr.weeks.close", "hr.weeks.reopen"].some((code) => permissions.has(code))) tabs.push("hours");
  if (permissions.has("hr.absences.review") || permissions.has("hr.justifications.review")) tabs.push("absences");
  if (["hr.discipline.manage", "hr.discipline.review", "hr.warnings.issue", "hr.warnings.annul", "hr.warnings.progression"].some((code) => permissions.has(code))) tabs.push("discipline");
  if (["progression.review", "appointments.manage", "succession.manage", "courses.manage", "courses.completions.manage"].some((code) => permissions.has(code))) tabs.push("career");
  if (["hr.team.view", "hr.reports.view", "team.manage", "access.manage"].some((code) => permissions.has(code))) tabs.push("profiles");
  if (permissions.has("hr.reports.view")) tabs.push("reports");
  if (permissions.has("team.manage") || permissions.has("access.manage")) tabs.push("team");
  return tabs;
}
function progressLabel(status?: string) { return ({ met: "Meta cumprida", justified: "Déficit abonado", awaiting_justification: "Aguardando justificativa", justification_pending: "Justificativa em análise", deficit: "Déficit mantido", awaiting_hours: "Aguardando horas", in_progress: "Em andamento" } as Record<string, string>)[status ?? ""] ?? "Aguardando horas"; }
function absenceStatus(request: HrAbsenceRequest) { if (request.status === "pending") return "Pendente"; if (request.status === "rejected") return "Recusado"; if (request.status === "cancelled") return "Cancelado"; return "Aprovado com abatimento"; }
function justificationStatus(request: HrHourJustification) { if (request.status === "pending") return "Pendente"; if (request.status === "rejected") return "Recusada"; return request.credited_minutes === request.deficit_minutes ? "Aprovada integralmente" : "Aprovada parcialmente"; }
function weekStatus(status: string) { return ({ met: "Meta cumprida", justified: "Déficit abonado", deficit: "Déficit mantido", warning_issued: "Advertência aplicada", warning_annulled: "Advertência anulada" } as Record<string, string>)[status] ?? status; }
function reviewStatus(status: string) { return ({ pending: "Análise pendente", suspension_maintained: "Suspensão mantida", dismissed: "Desligado", reactivated: "Reativado" } as Record<string, string>)[status] ?? status; }
function reportTitle(view: ReportView) { return ({ monthly: "Consolidado mensal", weekly: "Fechamentos semanais", absences: "Afastamentos", warnings: "Advertências do ciclo" } as Record<ReportView, string>)[view]; }
function categoryLabel(category: HrWarning["category"]) { return ({ weekly_goal: "Meta semanal", attendance: "Assiduidade", conduct: "Conduta", internal_rules: "Regras internas", other: "Outro motivo" } as const)[category]; }
function durationToMinutes(value: string) { const match = value.trim().match(/^([0-9]{1,3}):([0-5][0-9])$/); if (!match) return null; const total = Number(match[1]) * 60 + Number(match[2]); return total <= 600 ? total : null; }
function minutesInput(total: number) { return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`; }
function leaveWeeks(request: HrAbsenceRequest) { let cursor = addIsoDays(request.start_date, -(isoWeekday(request.start_date) - 1)); const end = addIsoDays(request.end_date, -(isoWeekday(request.end_date) - 1)); const result: string[] = []; while (cursor <= end) { result.push(cursor); cursor = addIsoDays(cursor, 7); } return result; }
function csvCell(value: string) { const safe = /^[=+\-@]/.test(value.trimStart()) ? `'${value}` : value; return `"${safe.replaceAll('"', '""')}"`; }
function summarizeProduction(days: HrProductionDay[], employeeId: string, start: string, end: string) {
  return days.reduce((summary, day) => {
    if (day.employee_id === employeeId && day.date >= start && day.date <= end) {
      summary.count += day.attendance_count;
      summary.total += day.total_amount;
    }
    return summary;
  }, { count: 0, total: 0 });
}
function isoWeekday(value: string) { const day = new Date(`${value}T12:00:00Z`).getUTCDay(); return day === 0 ? 7 : day; }
function addIsoDays(value: string, amount: number) { const date = new Date(`${value}T12:00:00Z`); date.setUTCDate(date.getUTCDate() + amount); return date.toISOString().slice(0, 10); }
function formatMinutes(total: number | null) { if (total === null || !Number.isFinite(total)) return "—"; return `${Math.floor(total / 60)}h${String(total % 60).padStart(2, "0")}`; }
function formatMoney(value: number) { return new Intl.NumberFormat("pt-BR", { currency: "BRL", style: "currency" }).format(value); }
function formatDate(value: string) { return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeZone: "UTC" }).format(new Date(`${value}T00:00:00Z`)); }
function formatDateTime(value: string) { return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(value)); }
function formatPeriod(start: string, end: string) { return start === end ? formatDate(start) : `${formatDate(start)} — ${formatDate(end)}`; }
function monthLabel(value: string) { return new Intl.DateTimeFormat("pt-BR", { month: "short", timeZone: "UTC", year: "numeric" }).format(new Date(`${value}T00:00:00Z`)); }
function todayIso() { const parts = new Intl.DateTimeFormat("en-US", { day: "2-digit", month: "2-digit", timeZone: "America/Sao_Paulo", year: "numeric" }).formatToParts(new Date()); const values = Object.fromEntries(parts.map((part) => [part.type, part.value])); return `${values.year}-${values.month}-${values.day}`; }
function lastDayOfMonth(month: string) { const [year, value] = month.split("-").map(Number); return new Date(Date.UTC(year, value, 0)).toISOString().slice(0, 10); }
