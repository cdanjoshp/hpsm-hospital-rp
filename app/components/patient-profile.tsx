"use client";

import Link from "next/link";
import dynamic from "next/dynamic";
import { FormEvent, useEffect, useRef, useState } from "react";
import { formatBirthDate } from "../lib/birth-date";
import {
  castBodyRegionLabel,
  castLateralityLabel,
  type ClinicalCastDetail,
} from "../lib/cast-types";
import type {
  PatientActivityPage,
  PatientActivityRecord,
  PatientActiveHospitalization,
  PatientDirectoryEntry,
  PatientPlanHistoryPage,
  PatientPartnershipPage,
  PatientRecord,
  PatientRecordPage,
  PatientSummary,
  PatientCardFilter,
} from "../lib/patient-center";
import { invalidatePatientClientCache } from "../lib/patient-client-cache";
import { formatPatientPassport } from "../lib/passport";
import { PatientEditForm } from "./patient-edit-form";
import { useModalFocus } from "./use-modal-focus";

const PatientRecordsTab = dynamic(() => import("./patient-records-tab").then((module) => module.PatientRecordsTab), { loading: () => <PatientPanelLoading label="Carregando registros…" /> });
const PatientExamsTab = dynamic(() => import("./patient-exams-tab").then((module) => module.PatientExamsTab), {
  loading: () => <PatientPanelLoading label="Carregando módulo de exames…" />,
});
const PatientMedicalCertificatesTab = dynamic(() => import("./patient-medical-certificates-tab").then((module) => module.PatientMedicalCertificatesTab), {
  loading: () => <PatientPanelLoading label="Carregando atestados…" />,
});
const PatientHospitalizationsTab = dynamic(() => import("./patient-hospitalizations-tab").then((module) => module.PatientHospitalizationsTab), {
  loading: () => <PatientPanelLoading label="Carregando internações…" />,
});
const PatientLegacyHistoryTab = dynamic(() => import("./patient-legacy-history-tab").then((module) => module.PatientLegacyHistoryTab), {
  loading: () => <PatientPanelLoading label="Carregando histórico HP Norte…" />,
});
const PatientConsultationsTab = dynamic(() => import("./patient-consultations-tab").then((module) => module.PatientConsultationsTab), {
  loading: () => <PatientPanelLoading label="Carregando consultas…" />,
});
const CastDetailPanel = dynamic(() => import("./cast-control").then((module) => module.CastDetailPanel), {
  loading: () => <PatientPanelLoading label="Abrindo registro de gesso…" />,
});

type Tab = "summary" | "attendances" | "consultations" | "exams" | "documents" | "procedures" | "sales" | "casts" | "hospitalizations" | "certificates" | "plans" | "partnerships" | "legacy";

const TABS: Array<{ code: Tab; label: string }> = [
  { code: "attendances", label: "Atendimentos e vendas" },
  { code: "sales", label: "Compras e vendas por item" },
  { code: "procedures", label: "Procedimentos" },
  { code: "consultations", label: "Consultas e agendamentos" },
  { code: "exams", label: "Exames" },
  { code: "documents", label: "Documentos" },
  { code: "casts", label: "Gessos" },
  { code: "hospitalizations", label: "Internações" },
  { code: "certificates", label: "Atestados" },
  { code: "plans", label: "Plano de Saúde" },
  { code: "partnerships", label: "Parcerias" },
  { code: "legacy", label: "Histórico HP Norte" },
  { code: "summary", label: "Resumo e acompanhamento" },
];

type PatientProfileProps = {
  benefit: Exclude<PatientCardFilter, "all">;
  canCreateAttendance: boolean;
  canCreateConsultation: boolean;
  canCreateHospitalization: boolean;
  canCreateCertificate: boolean;
  canViewRecords: boolean;
  canAdminHealthPlan: boolean;
  canCreateCasts: boolean;
  canCreateExams: boolean;
  canManage: boolean;
  canManageCasts: boolean;
  canRemoveCasts: boolean;
  canResetPortalPin: boolean;
  canViewCasts: boolean;
  canViewCertificates: boolean;
  canViewExams: boolean;
  canViewHospitalizations: boolean;
  currentPositionName: string | null;
  currentUserId: string;
  currentUserName: string;
  initialPatient: PatientDirectoryEntry;
  initialEditing: boolean;
};

type CurrentProfessional = { id: string; name: string; position: string | null };

export function PatientProfile({ benefit, canCreateAttendance, canCreateConsultation, canCreateHospitalization, canCreateCertificate, canViewRecords, canAdminHealthPlan, canCreateCasts, canCreateExams, canManage, canManageCasts, canRemoveCasts, canResetPortalPin, canViewCasts, canViewCertificates, canViewExams, canViewHospitalizations, currentPositionName, currentUserId, currentUserName, initialPatient, initialEditing }: PatientProfileProps) {
  const [activity, setActivity] = useState<PatientActivityPage | null>(null);
  const [activityView, setActivityView] = useState("attendances");
  const [activeHospitalization, setActiveHospitalization] = useState<PatientActiveHospitalization | null>(null);
  const [currentBenefit, setCurrentBenefit] = useState(benefit);
  const [editing, setEditing] = useState(initialEditing);
  const [detailOpen, setDetailOpen] = useState(false);
  const [error, setError] = useState("");
  const [loadingTab, setLoadingTab] = useState<Tab | null>(null);
  const [notice, setNotice] = useState("");
  const [patient, setPatient] = useState(initialPatient);
  const [plans, setPlans] = useState<PatientPlanHistoryPage | null>(null);
  const [resettingPortalPin, setResettingPortalPin] = useState(false);
  const [showResetPortalPin, setShowResetPortalPin] = useState(false);
  const [partnerships, setPartnerships] = useState<PatientPartnershipPage | null>(null);
  const [summary, setSummary] = useState<PatientSummary | null>(null);
  const [tab, setTab] = useState<Tab>("summary");
  const tabController = useRef<AbortController | null>(null);
  const tabRequestNumber = useRef(0);
  const visibleTabs = TABS.filter((item) =>
    (item.code !== "exams" || canViewExams) &&
    (item.code !== "casts" || canViewCasts) &&
    (item.code !== "certificates" || canViewCertificates) &&
    (item.code !== "hospitalizations" || canViewHospitalizations) &&
    (item.code !== "consultations" || canViewRecords) &&
    (item.code !== "documents" || canViewExams || canViewCertificates || canViewRecords));
  const currentProfessional = { id: currentUserId, name: currentUserName, position: currentPositionName };

  useEffect(() => {
    if (!canViewHospitalizations) return;
    const controller = new AbortController();
    void fetch(`/api/patient-center?patientId=${patient.id}&view=active-hospitalization`, { cache: "no-store", signal: controller.signal })
      .then(async (response) => response.ok ? response.json() as Promise<{ hospitalization: PatientActiveHospitalization | null }> : null)
      .then((payload) => { if (!controller.signal.aborted) setActiveHospitalization(payload?.hospitalization ?? null); }).catch(() => undefined);
    return () => controller.abort();
  }, [patient.id, canViewHospitalizations]);

  useEffect(() => {
    if (tab === "summary" && summary) return;
    if (tab === "plans" && plans) return;
    if (tab === "partnerships" && partnerships) return;
    if (["consultations", "exams", "documents", "casts", "hospitalizations", "certificates", "legacy"].includes(tab)) return;
    if ((tab === "attendances" && activity && activityView === "attendances") || ((tab === "procedures" || tab === "sales") && activity && activityView === (tab === "sales" ? "purchases" : "procedures"))) return;
    void loadTab(tab, 1);
    return () => tabController.current?.abort();
  }, [tab]); // eslint-disable-line react-hooks/exhaustive-deps

  async function loadTab(target: Tab, page: number, month?: string) {
    tabController.current?.abort();
    const controller = new AbortController();
    const requestId = ++tabRequestNumber.current;
    tabController.current = controller;
    setLoadingTab(target);
    setError("");
    try {
      const params = new URLSearchParams({ patientId: String(patient.id), view: target === "sales" ? "purchases" : target === "procedures" ? "procedures" : viewForTab(target) });
      if (["attendances", "procedures", "sales", "plans"].includes(target)) {
        params.set("page", String(page));
        params.set("pageSize", "10");
      }
      if (["attendances", "procedures", "sales"].includes(target) && month) params.set("month", month);
      const response = await fetch(`/api/patient-center?${params}`, { cache: "no-store", signal: controller.signal });
      const payload = await response.json() as { error?: string };
      if (!response.ok) {
        if (requestId === tabRequestNumber.current) setError(payload.error ?? "Não foi possível carregar esta seção.");
        return;
      }
      if (requestId !== tabRequestNumber.current) return;
      if (target === "summary") setSummary(payload as PatientSummary);
      else if (target === "plans") setPlans(payload as PatientPlanHistoryPage);
      else if (target === "partnerships") setPartnerships(payload as PatientPartnershipPage);
      else { setActivity(payload as PatientActivityPage); setActivityView(target === "sales" ? "purchases" : target === "procedures" ? "procedures" : "attendances"); }
    } catch (cause) {
      if (cause instanceof DOMException && cause.name === "AbortError") return;
      if (requestId === tabRequestNumber.current) setError("Não foi possível carregar esta seção.");
    } finally {
      if (requestId === tabRequestNumber.current) setLoadingTab(null);
    }
  }

  async function refreshCastViews(message: string) {
    setNotice(message);
    const response = await fetch(`/api/patient-center?patientId=${patient.id}&view=summary`, { cache: "no-store" });
    if (response.ok) setSummary(await response.json() as PatientSummary);
  }

  async function refreshHealthPlan(message: string) {
    setError("");
    const common = `patientId=${patient.id}`;
    const requests = [
      fetch(`/api/patient-center?${common}&view=profile`, { cache: "no-store" }),
      fetch(`/api/patient-center?${common}&view=plans&page=1&pageSize=10`, { cache: "no-store" }),
    ] as const;
    const [profileResponse, plansResponse] = await Promise.all(requests);
    const [profilePayload, plansPayload] = await Promise.all([
      profileResponse.json(),
      plansResponse.json(),
    ]) as [
      { error?: string; patient?: PatientDirectoryEntry },
      PatientPlanHistoryPage & { error?: string },
    ];
    if (!profileResponse.ok || !profilePayload.patient) throw new Error(profilePayload.error ?? "O plano foi salvo, mas o perfil não pôde ser atualizado.");
    if (!plansResponse.ok) throw new Error(plansPayload.error ?? "O plano foi salvo, mas o histórico não pôde ser atualizado.");
    setPatient(profilePayload.patient);
    setPlans(plansPayload);
    const cardResponse = await fetch(`/api/patient-center?view=list&search=${encodeURIComponent(patient.passport)}&pageSize=1`, { cache: "no-store" });
    if (cardResponse.ok) {
      const cards = await cardResponse.json() as { patients: Array<{ id: number; benefit: Exclude<PatientCardFilter, "all"> }> };
      const match = cards.patients.find((entry) => entry.id === patient.id);
      if (match) setCurrentBenefit(match.benefit);
    }
    setNotice(message);
  }

  return (
    <div className="patient-profile-v3">
      <div className="patient-v3-back"><Link href="/pacientes">← Voltar para pacientes</Link></div>
      <section className="patient-v3-hero" aria-labelledby="patient-v3-name">
        <div className="patient-v3-identity"><span className="patient-v3-avatar" aria-hidden="true">{initials(patient.name)}</span><div><p className="eyebrow">Perfil do paciente</p><h2 id="patient-v3-name">{patient.name}</h2><p>Passaporte <strong>{formatPatientPassport(patient.passport)}</strong><span aria-hidden="true"> · </span>Último atendimento {patient.last_attendance_at ? formatDate(patient.last_attendance_at) : "não registrado"}</p></div></div>
        <div className="patient-v3-actions" aria-label="Ações do paciente">
          {canCreateConsultation ? <Link className="patient-v3-primary" href={`/consultas?novo=1&paciente=${encodeURIComponent(patient.passport)}`}>＋ Nova consulta</Link> : null}
          {canCreateAttendance ? <Link href={quickAction("/atendimentos", patient.passport)}>＋ Nova venda</Link> : null}
          {((canCreateExams && canViewExams) || (canCreateCasts && canViewCasts) || canCreateHospitalization || canCreateCertificate) ? <details className="patient-v3-menu"><summary>＋ Novo registro</summary><div>
            {canCreateExams && canViewExams ? <Link href={quickAction("/exames", patient.passport)}>Solicitar exame</Link> : null}
            {canCreateCasts && canViewCasts ? <Link href={quickAction("/gessos", patient.passport)}>Aplicar gesso</Link> : null}
            {canCreateHospitalization ? <Link href={quickAction("/internacoes", patient.passport)}>Registrar internação</Link> : null}
            {canCreateCertificate ? <Link href={quickAction("/atestados", patient.passport)}>Criar atestado</Link> : null}
          </div></details> : null}
          {(canManage || canResetPortalPin) ? <details className="patient-v3-menu patient-v3-more"><summary aria-label="Mais opções">···</summary><div>
            {canManage ? <button type="button" onClick={() => setEditing((current) => !current)}>{editing ? "Fechar edição" : "Editar dados"}</button> : null}
            {canResetPortalPin ? <button type="button" onClick={() => { setError(""); setShowResetPortalPin(true); }}>Redefinir PIN do Portal</button> : null}
          </div></details> : null}
        </div>
        {editing ? <div className="patient-v3-edit"><PatientEditForm patient={patient} onCancel={() => setEditing(false)} onSaved={(updated) => { setPatient((current) => ({ ...updated, last_attendance_at: current.last_attendance_at })); setEditing(false); }} /></div> : null}
      </section>
      {(patient.allergies?.trim() || activeHospitalization || summary?.active_casts.length) ? <div className="patient-v3-alerts" aria-label="Alertas do paciente">
        {patient.allergies?.trim() ? <div className="patient-v3-alert" data-tone="allergy"><strong>Alergias</strong><span>{patient.allergies}</span></div> : null}
        {summary?.active_casts.length ? <div className="patient-v3-alert" data-tone="cast"><strong>Gesso em uso</strong><span>{castBodyRegionLabel(summary.active_casts[0].body_region)} · {castLateralityLabel(summary.active_casts[0].laterality)} · retirada prevista {formatDate(summary.active_casts[0].expected_removal_at)}</span></div> : null}
        {activeHospitalization ? <div className="patient-v3-alert" data-tone="hospitalization"><strong>Internação ativa</strong><span>Desde {formatDate(activeHospitalization.admitted_at)} · {activeHospitalization.reason || "Em acompanhamento"}</span></div> : null}
      </div> : null}
      {notice ? <p className="form-success" role="status">{notice}</p> : null}
      <div className="patient-v3-columns">
        <aside className="patient-v3-sidebar">
          <section className="patient-v3-panel"><div className="patient-v3-panel-head"><h3>Dados do paciente</h3>{canManage ? <button type="button" onClick={() => setEditing(true)}>Editar</button> : null}</div><dl>
            <div><dt>Nascimento</dt><dd>{formatBirthDate(patient.birth_date)}</dd></div><div><dt>Telefone</dt><dd>{patient.phone || "Não informado"}</dd></div><div><dt>Contato de emergência</dt><dd>{patient.emergency_contact_name ? `${patient.emergency_contact_name} · ${patient.emergency_contact_phone || "sem telefone"}` : "Não informado"}</dd></div>
          </dl><details className="patient-v3-extra"><summary>Mais informações</summary><dl><div><dt>Alergias</dt><dd>{patient.allergies?.trim() || "Alergias não informadas"}</dd></div><div><dt>Cadastro criado em</dt><dd>{formatDate(patient.created_at)}</dd></div><div><dt>Última atualização</dt><dd>{formatDate(patient.updated_at)}</dd></div></dl></details></section>
          <section className="patient-v3-panel"><div className="patient-v3-panel-head"><h3>Benefícios</h3><button type="button" onClick={() => { setTab("plans"); setDetailOpen(true); }}>Ver histórico</button></div><div className="patient-v3-benefit"><span className="patient-hub-benefit" data-benefit={currentBenefit}>{benefitLabel(currentBenefit)}</span><small>{patient.health_plan.valid_until && patient.health_plan.status === "active" ? `Plano ativo até ${formatDate(patient.health_plan.valid_until)}` : planStatusShort(patient)}</small></div><button className="patient-v3-inline-link" type="button" onClick={() => { setTab("partnerships"); setDetailOpen(true); }}>Ver parcerias →</button></section>
          {summary ? <section className="patient-v3-panel patient-v3-metrics" aria-label="Resumo de atividade"><div><span>Atendimentos</span><strong>{summary.total_attendances}</strong></div><div><span>Vendas com produtos</span><strong>{summary.total_purchases}</strong></div></section> : null}
        </aside>
        <div className="patient-v3-main">
          <section className="patient-v3-panel patient-v3-history-select"><div><h3>Históricos completos</h3><p>Consulte vendas, documentos e acompanhamentos por área.</p></div><label>Escolher área<select value={detailOpen ? tab : ""} onChange={(event) => { if (event.target.value) { setTab(event.target.value as Tab); setDetailOpen(true); } else setDetailOpen(false); }}><option value="">Selecione um histórico</option>{visibleTabs.map((item) => <option key={item.code} value={item.code}>{item.label}</option>)}</select></label></section>
          {detailOpen ? <section className="patient-v3-panel patient-v3-detail" id="patient-detail"><div className="patient-v3-detail-head"><h3>{TABS.find((item) => item.code === tab)?.label}</h3><button type="button" onClick={() => setDetailOpen(false)} aria-label="Fechar histórico selecionado">Fechar ×</button></div>
            {error ? <p className="form-error" role="alert">{error}</p> : null}
            {loadingTab === tab ? <PatientTabLoading /> : null}
            {tab === "summary" && summary && loadingTab !== tab ? <SummaryTab benefit={currentBenefit} canCreateCasts={canCreateCasts} canManageCasts={canManageCasts} canRemoveCasts={canRemoveCasts} canViewCasts={canViewCasts} currentProfessional={currentProfessional} onCastsChanged={refreshCastViews} patient={patient} summary={summary} /> : null}
            {tab === "consultations" && canViewRecords ? <PatientConsultationsTab patientId={patient.id} passport={patient.passport} /> : null}
            {tab === "attendances" && activityView === "attendances" && activity && loadingTab !== tab ? <ActivityTab page={activity} onMonth={(month) => void loadTab("attendances", 1, month)} onPage={(page) => void loadTab("attendances", page, activity.selectedMonth)} /> : null}
            {tab === "sales" && activityView === "purchases" && activity && loadingTab !== tab ? <ActivityTab page={activity} onMonth={(month) => void loadTab("sales", 1, month)} onPage={(page) => void loadTab("sales", page, activity.selectedMonth)} /> : null}
            {tab === "procedures" && activityView === "procedures" && activity && loadingTab !== tab ? <ActivityTab page={activity} onMonth={(month) => void loadTab("procedures", 1, month)} onPage={(page) => void loadTab("procedures", page, activity.selectedMonth)} /> : null}
            {tab === "exams" && canViewExams ? <PatientExamsTab patient={patient} canCreate={canCreateExams} currentUserId={currentUserId} /> : null}
            {tab === "documents" ? <PatientRecordsTab mode="documents" patientId={patient.id} passport={patient.passport} /> : null}
            {tab === "casts" && canViewCasts ? <>{summary && <SummaryTab benefit={currentBenefit} canCreateCasts={canCreateCasts} canManageCasts={canManageCasts} canRemoveCasts={canRemoveCasts} canViewCasts={canViewCasts} currentProfessional={currentProfessional} onCastsChanged={refreshCastViews} patient={patient} summary={summary} castsOnly />}<PatientRecordsTab mode="timeline" patientId={patient.id} passport={patient.passport} initialFilter="cast" /></> : null}
            {tab === "hospitalizations" && canViewHospitalizations ? <PatientHospitalizationsTab patientId={patient.id} /> : null}
            {tab === "certificates" && canViewCertificates ? <PatientMedicalCertificatesTab patientId={patient.id} /> : null}
            {tab === "plans" && plans && loadingTab !== tab ? <PlanTab canAdmin={canAdminHealthPlan} patient={patient} page={plans} onPage={(page) => void loadTab("plans", page)} onUpdated={refreshHealthPlan} /> : null}
            {tab === "partnerships" && partnerships && loadingTab !== tab ? <PartnershipsTab page={partnerships} /> : null}
            {tab === "legacy" ? <PatientLegacyHistoryTab patientId={patient.id} /> : null}
          </section> : null}
          <section className="patient-v3-panel patient-v3-timeline"><PatientRecordsTab mode="timeline" patientId={patient.id} passport={patient.passport} /></section>
        </div>
      </div>
      {showResetPortalPin ? <ResetPortalPinModal
        patientName={patient.name}
        saving={resettingPortalPin}
        onClose={() => { if (!resettingPortalPin) setShowResetPortalPin(false); }}
        onConfirm={async () => {
          setResettingPortalPin(true);
          setError("");
          try {
            const response = await fetch("/api/patient-portal/reset-pin", {
              method: "POST",
              headers: { "content-type": "application/json" },
              body: JSON.stringify({ patientId: patient.id }),
            });
            const payload = await response.json() as { error?: string; ok?: boolean };
            if (!response.ok || payload.ok !== true) throw new Error(payload.error ?? "Não foi possível redefinir o PIN.");
            setShowResetPortalPin(false);
            setNotice("PIN redefinido. No próximo acesso, o paciente criará um novo PIN.");
          } catch (cause) {
            setError(cause instanceof Error ? cause.message : "Não foi possível redefinir o PIN.");
            setShowResetPortalPin(false);
          } finally {
            setResettingPortalPin(false);
          }
        }}
      /> : null}
    </div>
  );
}

function ResetPortalPinModal({ onClose, onConfirm, patientName, saving }: { onClose: () => void; onConfirm: () => void; patientName: string; saving: boolean }) {
  const dialogRef = useModalFocus(onClose);
  return (
    <div className="patient-plan-admin-overlay" onMouseDown={(event) => { if (event.target === event.currentTarget && !saving) onClose(); }} role="presentation">
      <section aria-describedby="reset-portal-pin-description" aria-labelledby="reset-portal-pin-title" aria-modal="true" className="patient-plan-admin-dialog" ref={dialogRef} role="dialog" tabIndex={-1}>
        <span aria-hidden="true">◇</span>
        <p className="eyebrow">Segurança do Portal</p>
        <h2 id="reset-portal-pin-title">Redefinir o PIN do paciente?</h2>
        <p id="reset-portal-pin-description">Paciente: <strong>{patientName}</strong><br />O PIN atual será removido, todas as sessões serão encerradas e, no próximo acesso, o paciente criará um novo PIN.</p>
        <footer>
          <button className="secondary-button" disabled={saving} onClick={onClose} type="button">Cancelar</button>
          <button className="submit-button" disabled={saving} onClick={onConfirm} type="button">{saving ? "Redefinindo…" : "Redefinir PIN"}</button>
        </footer>
      </section>
    </div>
  );
}

function SummaryTab({ benefit, canCreateCasts, canManageCasts, canRemoveCasts, canViewCasts, castsOnly = false, currentProfessional, onCastsChanged, patient, summary }: {
  benefit: Exclude<PatientCardFilter, "all">;
  canCreateCasts: boolean;
  canManageCasts: boolean;
  canRemoveCasts: boolean;
  canViewCasts: boolean;
  castsOnly?: boolean;
  currentProfessional: CurrentProfessional;
  onCastsChanged: (message: string) => Promise<void>;
  patient: PatientDirectoryEntry;
  summary: PatientSummary;
}) {
  const [detail, setDetail] = useState<ClinicalCastDetail | null>(null);
  const [detailAction, setDetailAction] = useState<"remove" | null>(null);
  const [openingCast, setOpeningCast] = useState<number | null>(null);
  const [castError, setCastError] = useState("");

  async function openCast(castId: number, action: "remove" | null = null) {
    setOpeningCast(castId);
    setCastError("");
    try {
      const response = await fetch(`/api/casts?view=detail&id=${castId}`, { cache: "no-store" });
      const payload = await response.json() as { cast?: ClinicalCastDetail; error?: string };
      if (!response.ok || !payload.cast) throw new Error(payload.error ?? "Não foi possível abrir o registro de gesso.");
      setDetail(payload.cast);
      setDetailAction(action);
    } catch (cause) {
      setCastError(cause instanceof Error ? cause.message : "Não foi possível abrir o registro de gesso.");
    } finally {
      setOpeningCast(null);
    }
  }

  return (
    <div className="patient-summary-tab">
      {!castsOnly ? <div className="patient-summary-grid">
        <SummaryCard label="Atendimentos" value={String(summary.total_attendances)} detail="registros concluídos" />
        <SummaryCard label="Último atendimento" value={summary.last_attendance_at ? formatDate(summary.last_attendance_at) : "—"} detail={summary.last_attendance_at ? formatTime(summary.last_attendance_at) : "Sem registro"} />
        <SummaryCard label="Compras / vendas" value={String(summary.total_purchases)} detail="atendimentos com produtos" />
        <SummaryCard label="Benefício" value={benefitLabel(benefit)} detail={patient.health_plan.valid_until ? `Validade ${formatDate(patient.health_plan.valid_until)}` : "Sem validade ativa"} />
      </div> : null}
      {canViewCasts ? <div className="patient-active-casts">
        <div className="patient-tab-title">
          <div><p className="eyebrow">Acompanhamento clínico</p><h3>Gessos em uso</h3></div>
          <Link href="/gessos">Ver controle completo →</Link>
        </div>
        {castError ? <p className="form-error" role="alert">{castError}</p> : null}
        {summary.active_casts.length ? <div className="patient-active-cast-list">{summary.active_casts.map((cast) => {
          const due = castDueState(cast.expected_removal_at);
          return <article key={cast.id} className="patient-active-cast" data-due={due.code}>
            <div className="patient-active-cast-icon" aria-hidden="true">▰</div>
            <div className="patient-active-cast-main">
              <span>Gesso #{cast.id}</span>
              <strong>{castBodyRegionLabel(cast.body_region)} · {castLateralityLabel(cast.laterality)}</strong>
              <small>Aplicado em {formatDateTime(cast.applied_at)} por {cast.applied_by_name}</small>
            </div>
            <div className="patient-active-cast-due">
              <span>{due.label}</span>
              <strong>{formatDateTime(cast.expected_removal_at)}</strong>
            </div>
            <div className="patient-active-cast-actions">
              <button type="button" disabled={openingCast !== null} onClick={() => void openCast(cast.id)}>{openingCast === cast.id ? "Abrindo…" : "Ver registro"}</button>
              {canRemoveCasts ? <button type="button" data-primary="true" disabled={openingCast !== null} onClick={() => void openCast(cast.id, "remove")}>Registrar retirada</button> : null}
            </div>
          </article>;
        })}</div> : <PatientEmpty title="Nenhum gesso em uso" text="Aplicações ativas aparecerão aqui, ordenadas pela previsão de retirada mais próxima." />}
      </div> : null}
      {!castsOnly ? <div className="patient-recent-procedures">
        <div className="patient-tab-title"><div><p className="eyebrow">Atividade recente</p><h3>Procedimentos recentes</h3></div></div>
        {summary.recent_procedures.length ? summary.recent_procedures.map((item) => (
          <div key={item.id}><span>{item.category}</span><strong>{item.name}</strong><time>{formatDateTime(item.date)}</time></div>
        )) : <PatientEmpty title="Nenhum procedimento registrado" text="Os procedimentos realizados aparecerão aqui após um atendimento." />}
      </div> : null}
      {detail ? <CastDetailPanel
        canAdjustExpected={canManageCasts || (canCreateCasts && detail.applied_by === currentProfessional.id)}
        canManage={canManageCasts}
        canRemove={canRemoveCasts}
        currentProfessional={currentProfessional}
        initialAction={detailAction}
        onChanged={async (message) => {
          await onCastsChanged(message);
          await openCast(detail.id);
        }}
        onClose={() => { setDetail(null); setDetailAction(null); }}
        record={detail}
      /> : null}
    </div>
  );
}

function SummaryCard({ detail, label, value }: { detail: string; label: string; value: string }) {
  return <article><span>{label}</span><strong>{value}</strong><small>{detail}</small></article>;
}

function PatientPanelLoading({ label }: { label: string }) {
  return <div className="patient-exam-skeleton" role="status" aria-label={label}><i /><i /><i /></div>;
}

function ActivityTab({ onMonth, onPage, page }: { onMonth: (month: string) => void; onPage: (page: number) => void; page: PatientActivityPage }) {
  return (
    <div className="patient-activity-tab">
      <div className="patient-attendance-month">
        <label>Período<select value={page.selectedMonth} onChange={(event) => onMonth(event.target.value)}>{page.availableMonths.length ? page.availableMonths.map((month) => <option key={month.month} value={month.month}>{monthLabel(month.month)}</option>) : <option value={page.selectedMonth}>{monthLabel(page.selectedMonth)}</option>}</select></label>
        <div><span>Total gasto no mês</span><strong>{formatMoney(page.monthlyTotal)}</strong><small>{page.monthlyCount} registro(s) concluído(s)</small></div>
      </div>
      {page.records.length ? page.records.map((record) => <ActivityRecord key={record.id} record={record} />) : <PatientEmpty title="Nenhum atendimento registrado neste mês" text="Escolha outro período ou aguarde um novo registro no HPSM." />}
      <PatientPagination page={page.page} pageSize={page.pageSize} total={page.total} onPage={onPage} />
    </div>
  );
}

function ActivityRecord({ record }: { record: PatientActivityRecord }) {
  const title = `Atendimento #${record.id}`;
  return (
    <details className="patient-activity-record">
      <summary>
        <div><strong>{title || `Registro #${record.id}`}</strong><span>{formatDateTime(record.created_at)} · {record.professional_name}</span></div>
        <div><span className="patient-record-status" data-status={record.status}>{record.status === "completed" ? "Concluído" : "Cancelado"}</span><strong>{formatMoney(record.total)}</strong></div>
      </summary>
      <div className="patient-activity-detail">
        <div className="patient-record-meta">
          <p><span>Profissional</span><strong>{record.professional_name}</strong><small>{record.professional_passport} · {record.professional_position}</small></p>
          <p><span>Benefício</span><strong>{record.plan_name ?? "Sem benefício"}</strong><small>Desconto efetivo: {formatMoney(record.discount)}</small></p>
          {record.notes ? <p><span>Observação</span><strong>{record.notes}</strong></p> : null}
        </div>
        <div className="patient-record-items">
          {record.items.map((item) => (
            <div key={item.id}><span>{item.quantity}×</span><strong>{item.service_name}<small>{item.category} · unitário {formatMoney(item.unit_price)}{item.discount_percent ? ` · ${formatPercent(item.discount_percent)} de desconto` : ""}</small></strong><em>{formatMoney(item.line_total)}</em></div>
          ))}
        </div>
        <div className="patient-record-total"><span>Subtotal {formatMoney(record.subtotal)}</span><span>Desconto {formatMoney(record.discount)}</span><strong>Total {formatMoney(record.total)}</strong></div>
      </div>
    </details>
  );
}

function PlanTab({ canAdmin, onPage, onUpdated, page, patient }: { canAdmin: boolean; onPage: (page: number) => void; onUpdated: (message: string) => Promise<void>; page: PatientPlanHistoryPage; patient: PatientDirectoryEntry }) {
  return (
    <div className="patient-plan-tab">
      <div className="patient-plan-current">
        <div><span>Situação atual</span><strong data-status={patient.health_plan.status}>{planStatusShort(patient)}</strong></div>
        <div><span>Ativação / início</span><strong>{patient.health_plan.activated_at ? formatDateTime(patient.health_plan.activated_at) : "—"}</strong></div>
        <div><span>Validade</span><strong>{patient.health_plan.valid_until ? formatDate(patient.health_plan.valid_until) : "—"}</strong></div>
        <div><span>Autorização</span><strong>{patient.health_plan.authorized_by_name ?? "—"}</strong></div>
      </div>
      {canAdmin ? <HealthPlanAdmin key={`${patient.health_plan.status}-${patient.health_plan.valid_until ?? "none"}`} onUpdated={onUpdated} patient={patient} /> : null}
      <div className="patient-plan-history">
        <div className="patient-tab-title"><div><p className="eyebrow">Histórico real</p><h3>Ativações e renovações</h3></div></div>
        {page.records.length ? page.records.map((record) => (
          <article key={record.id}>
            <span className="patient-record-status" data-status={record.status}>{planRequestStatus(record.status)}</span>
            <div><strong>{record.origin === "administrative" ? administrativePlanLabel(record.administrative_action) : `Solicitação #${record.id}`}</strong><small>{record.origin === "administrative" ? `Registro administrativo · ${formatDateTime(record.requested_at)}` : `Venda / atendimento #${record.attendance_id} · ${formatDateTime(record.requested_at)}`}</small></div>
            <div><strong>{record.origin === "administrative" ? "Sem cobrança" : formatMoney(record.plan_value)}</strong><small>{record.origin === "administrative" ? `Registrado por ${record.authorized_by_name ?? "Diretoria"}` : `Realizada por ${record.seller_name ?? "Profissional"}${record.seller_passport ? ` · ${record.seller_passport}` : ""}`}</small></div>
            <div><strong>{record.coverage_end ? `Até ${formatDate(record.coverage_end)}` : record.rejection_reason ?? "Aguardando conferência"}</strong><small>{record.authorized_by_name ? `Analisada por ${record.authorized_by_name}` : "Sem decisão"}</small></div>
          </article>
        )) : <PatientEmpty title="Sem histórico de Plano de Saúde" text="Contratações, renovações e recusas aparecerão nesta seção." />}
      </div>
      <PatientPagination page={page.page} pageSize={page.pageSize} total={page.total} onPage={onPage} />
    </div>
  );
}

function HealthPlanAdmin({ onUpdated, patient }: { onUpdated: (message: string) => Promise<void>; patient: PatientDirectoryEntry }) {
  const [confirming, setConfirming] = useState(false);
  const [error, setError] = useState("");
  const [saving, setSaving] = useState(false);
  const [validUntil, setValidUntil] = useState(() => defaultAdminPlanDate(patient));
  const openButtonRef = useRef<HTMLButtonElement | null>(null);
  const dialogRef = useRef<HTMLDivElement | null>(null);
  const isGrant = patient.health_plan.status !== "active";

  useEffect(() => {
    if (!confirming) return;
    const dialog = dialogRef.current;
    const focusable = dialog?.querySelectorAll<HTMLElement>('button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex="-1"])');
    focusable?.[0]?.focus();
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape" && !saving) { event.preventDefault(); closeConfirmation(); return; }
      if (event.key !== "Tab" || !focusable?.length) return;
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    }
    document.addEventListener("keydown", onKeyDown);
    return () => document.removeEventListener("keydown", onKeyDown);
  }, [confirming, saving]); // eslint-disable-line react-hooks/exhaustive-deps

  if (patient.health_plan.status === "awaiting_confirmation") {
    return <section className="patient-plan-admin patient-plan-admin-pending"><div><p className="eyebrow">Ação da Diretoria</p><h3>Solicitação aguardando confirmação</h3><p>Analise a solicitação existente em Pendências antes de conceder um plano sem cobrança.</p></div><Link href="/administrativo/pendencias#planos-saude">Abrir Pendências →</Link></section>;
  }

  function review(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (saving || !isIsoDate(validUntil)) return;
    setError("");
    setConfirming(true);
  }

  function closeConfirmation() {
    if (saving) return;
    setConfirming(false);
    requestAnimationFrame(() => openButtonRef.current?.focus());
  }

  async function save() {
    if (saving) return;
    setSaving(true);
    setError("");
    try {
      const response = await fetch("/api/health-plans/admin", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ patientId: patient.id, validUntil }),
      });
      const payload = await response.json() as { action?: "expiry_adjustment" | "grant"; error?: string; financialValue?: number };
      if (!response.ok || !payload.action || payload.financialValue !== 0) throw new Error(payload.error ?? "Não foi possível salvar o plano.");
      invalidatePatientClientCache();
      setConfirming(false);
      await onUpdated(payload.action === "grant" ? "Plano concedido sem cobrança e registrado no histórico." : "Data de vencimento alterada e registrada no histórico.");
      requestAnimationFrame(() => openButtonRef.current?.focus());
    } catch (cause) {
      setConfirming(false);
      setError(cause instanceof Error ? cause.message : "Não foi possível salvar o plano.");
    } finally {
      setSaving(false);
    }
  }

  return <>
    <section className="patient-plan-admin">
      <div><p className="eyebrow">Ação da Diretoria</p><h3>{isGrant ? "Conceder plano sem cobrança" : "Alterar data de vencimento"}</h3><p>Esta operação não cria venda, atendimento ou valor financeiro. O responsável e a nova validade ficam registrados no histórico.</p></div>
      <form onSubmit={review}><label>Vencimento<input disabled={saving} min={todayAtHpsm()} max={maxAdminPlanDate()} required type="date" value={validUntil} onChange={(event) => { setValidUntil(event.target.value); setError(""); }} /></label><button disabled={saving} ref={openButtonRef} type="submit">{isGrant ? "Conceder plano" : "Alterar vencimento"}</button></form>
      {error ? <p className="form-error" role="alert">{error}</p> : null}
    </section>
    {confirming ? <div className="patient-plan-admin-overlay" role="presentation" onMouseDown={(event) => event.target === event.currentTarget && closeConfirmation()}><div aria-describedby="patient-plan-admin-description" aria-labelledby="patient-plan-admin-title" aria-modal="true" className="patient-plan-admin-dialog" ref={dialogRef} role="dialog"><span aria-hidden="true">◇</span><p className="eyebrow">Confirmar ação administrativa</p><h2 id="patient-plan-admin-title">{isGrant ? "Conceder o plano sem cobrança?" : "Alterar a data de vencimento?"}</h2><p id="patient-plan-admin-description">Paciente: <strong>{patient.name}</strong><br />Nova validade: <strong>{formatIsoDate(validUntil)}</strong><br />Nenhuma venda, atendimento ou cobrança será criada.</p><footer><button className="secondary-button" disabled={saving} onClick={closeConfirmation} type="button">Cancelar</button><button className="submit-button" disabled={saving} onClick={() => void save()} type="button">{saving ? "Salvando…" : "Confirmar"}</button></footer></div></div> : null}
  </>;
}

function PartnershipsTab({ page }: { page: PatientPartnershipPage }) {
  return <div className="patient-partnership-tab">
    <div className="patient-tab-title"><div><p className="eyebrow">Vínculos institucionais</p><h3>Parcerias do paciente</h3><p>Somente parcerias ativas podem ser utilizadas no benefício Parceiro do HP.</p></div></div>
    {page.items.length ? <div className="patient-partnership-list">{page.items.map((partnership) => <article key={partnership.id}><span aria-hidden="true">⌁</span><div><strong>{partnership.name}</strong><small>Vinculado em {formatDateTime(partnership.linked_at)}</small></div><em data-status={partnership.status}>{partnership.status === "active" ? "Parceria ativa" : "Parceria inativa"}</em></article>)}</div> : <PatientEmpty title="Sem parcerias vinculadas" text="Quando uma organização incluir este paciente, o vínculo aparecerá aqui." />}
  </div>;
}

function PatientPagination({ onPage, page, pageSize, total }: { onPage: (page: number) => void; page: number; pageSize: number; total: number }) {
  const totalPages = Math.max(1, Math.ceil(total / pageSize));
  if (totalPages <= 1) return null;
  return <div className="patient-center-pagination"><button type="button" disabled={page <= 1} onClick={() => onPage(page - 1)}>← Anterior</button><span>Página <strong>{page}</strong> de {totalPages}</span><button type="button" disabled={page >= totalPages} onClick={() => onPage(page + 1)}>Próxima →</button></div>;
}

function PatientTabLoading() {
  return <div className="patient-tab-loading" role="status"><span /><p>Carregando registros do paciente…</p></div>;
}

function PatientEmpty({ text, title }: { text: string; title: string }) {
  return <div className="empty-state"><span>＋</span><strong>{title}</strong><p>{text}</p></div>;
}

function viewForTab(tab: Tab) {
  return tab;
}

function benefitLabel(benefit: Exclude<PatientCardFilter, "all">) {
  return ({ active: "Plano ativo", expired: "Plano expirado", partner: "Parceiro HP", police: "Polícia / Arcanjo", none: "Sem benefício" })[benefit];
}

function planStatusShort(patient: PatientDirectoryEntry) {
  if (patient.health_plan.status === "active") return "Ativo";
  if (patient.health_plan.status === "expired") return "Expirado";
  if (patient.health_plan.status === "awaiting_confirmation") return "Aguardando";
  return "Sem plano";
}

function quickAction(path: string, passport: string) {
  return `${path}?novo=1&paciente=${encodeURIComponent(passport)}`;
}

function PatientSummaryRecent({ patientId, canViewHospitalizations }: { patientId: number; canViewHospitalizations: boolean }) {
  const [recent, setRecent] = useState<{ activity: PatientRecord[]; documents: PatientRecord[]; exams: PatientRecord[]; hospitalization: PatientRecord[] } | null>(null);
  useEffect(() => {
    const controller = new AbortController();
    const read = async (view: string, filter: string, pageSize: number) => {
      const response = await fetch(`/api/patient-center?view=${view}&patientId=${patientId}&filter=${filter}&pageSize=${pageSize}`, { cache: "no-store", signal: controller.signal });
      return response.ok ? (await response.json() as PatientRecordPage).items : [];
    };
    void Promise.all([
      read("timeline-page", "all", 4), read("documents", "all", 3), read("timeline-page", "exam", 1),
      canViewHospitalizations ? read("timeline-page", "hospitalization", 2) : Promise.resolve([]),
    ]).then(([activity, documents, exams, hospitalization]) => { if (!controller.signal.aborted) setRecent({ activity, documents, exams, hospitalization }); }).catch(() => undefined);
    return () => controller.abort();
  }, [patientId, canViewHospitalizations]);
  if (!recent) return null;
  const latestHospitalization = recent.hospitalization.find((item) => item.status === "active") ?? recent.hospitalization[0];
  return <div className="patient-summary-recent">
    <section><h3>Último exame</h3><p>{recent.exams[0]?.title ?? "Sem exame registrado"}</p><button type="button" onClick={() => document.querySelector<HTMLButtonElement>('[data-patient-tab="exams"]')?.click()}>Ver exames →</button></section>
    {canViewHospitalizations ? <section><h3>Internação</h3><p>{latestHospitalization ? `${latestHospitalization.title} · ${formatDate(latestHospitalization.date)}` : "Sem internação registrada"}</p></section> : null}
    <section><h3>Documentos recentes</h3>{recent.documents.length ? recent.documents.map((item) => <p key={item.id}>{item.title} · {formatDate(item.date)}</p>) : <p>Sem documento finalizado</p>}</section>
    <section><h3>Atividade recente</h3>{recent.activity.length ? recent.activity.map((item) => <p key={item.id}>{item.title} · {formatDate(item.date)}</p>) : <p>Sem atividade registrada</p>}</section>
  </div>;
}

function monthLabel(value: string) {
  if (!/^\d{4}-\d{2}$/.test(value)) return "Mês atual";
  const label = new Intl.DateTimeFormat("pt-BR", { month: "long", timeZone: "UTC", year: "numeric" }).format(new Date(`${value}-01T00:00:00Z`));
  return label.charAt(0).toUpperCase() + label.slice(1);
}

function planRequestStatus(status: string) {
  if (status === "approved") return "Aprovada";
  if (status === "rejected") return "Recusada";
  return "Aguardando";
}

function administrativePlanLabel(action: PatientPlanHistoryPage["records"][number]["administrative_action"]) {
  return action === "expiry_adjustment" ? "Vencimento ajustado" : "Plano concedido sem cobrança";
}

function defaultAdminPlanDate(patient: PatientDirectoryEntry) {
  if (patient.health_plan.status === "active" && patient.health_plan.valid_until) return dateAtHpsm(new Date(patient.health_plan.valid_until));
  const base = new Date(`${todayAtHpsm()}T12:00:00Z`);
  base.setUTCDate(base.getUTCDate() + 30);
  return dateAtHpsm(base);
}

function todayAtHpsm() { return dateAtHpsm(new Date()); }
function maxAdminPlanDate() {
  const base = new Date(`${todayAtHpsm()}T12:00:00Z`);
  base.setUTCFullYear(base.getUTCFullYear() + 10);
  return dateAtHpsm(base);
}
function dateAtHpsm(value: Date) {
  const parts = new Intl.DateTimeFormat("en-US", { day: "2-digit", month: "2-digit", timeZone: "America/Sao_Paulo", year: "numeric" }).formatToParts(value);
  const part = (type: Intl.DateTimeFormatPartTypes) => parts.find((item) => item.type === type)?.value ?? "";
  return `${part("year")}-${part("month")}-${part("day")}`;
}
function isIsoDate(value: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(parsed.valueOf()) && parsed.toISOString().slice(0, 10) === value;
}
function formatIsoDate(value: string) {
  if (!isIsoDate(value)) return "Data inválida";
  const [year, month, day] = value.split("-");
  return `${day}/${month}/${year}`;
}

function initials(name: string) {
  return name.trim().split(/\s+/).slice(0, 2).map((part) => part[0]?.toUpperCase()).join("");
}

function formatDate(value: string) {
  return new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric", timeZone: "America/Sao_Paulo" }).format(new Date(value));
}

function formatTime(value: string) {
  return new Intl.DateTimeFormat("pt-BR", { hour: "2-digit", minute: "2-digit", timeZone: "America/Sao_Paulo" }).format(new Date(value));
}

function formatDateTime(value: string) {
  return `${formatDate(value)} às ${formatTime(value)}`;
}

function castDueState(value: string) {
  const expected = new Date(value);
  if (expected.getTime() <= Date.now()) return { code: "overdue", label: "Retirada atrasada" } as const;
  const expectedDay = new Intl.DateTimeFormat("en-CA", {
    day: "2-digit",
    month: "2-digit",
    timeZone: "America/Sao_Paulo",
    year: "numeric",
  }).format(expected);
  const today = new Intl.DateTimeFormat("en-CA", {
    day: "2-digit",
    month: "2-digit",
    timeZone: "America/Sao_Paulo",
    year: "numeric",
  }).format(new Date());
  return expectedDay === today
    ? { code: "today", label: "Retirada prevista hoje" } as const
    : { code: "normal", label: "Retirada prevista" } as const;
}

function formatMoney(value: number) {
  return new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(Number(value));
}

function formatPercent(value: number) {
  return `${new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 2 }).format(Number(value))}%`;
}
