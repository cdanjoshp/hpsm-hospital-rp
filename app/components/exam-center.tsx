"use client";

import dynamic from "next/dynamic";
import { FormEvent, useEffect, useMemo, useRef, useState } from "react";
import { EXAM_STATUSES, EXAM_STATUS_LABELS, type ClinicalExamStatus } from "../lib/exam-status";
import type {
  ClinicalExamDetail,
  ClinicalExamFilters,
  ClinicalExamPage,
  ClinicalExamReportConfig,
  ClinicalExamReportVersion,
  ExamAttendanceOption,
  ExamCategory,
  ExamReferenceData,
  ExamType,
  ImagingResultData,
} from "../lib/exams";
import { imagingResultDraft, isImagingResultData, isLabResultData, missingRequiredImagingFields, missingRequiredLabParameters } from "../lib/exam-result-guards";
import { analyzeExamResults, generateExamWithAi, generateSelectedExamWithAi, selectExamResult } from "../lib/exam-ai-flow";
import type { Patient } from "../lib/operational-data";
import type { PatientDirectoryEntry } from "../lib/patient-center";
import type { ExamCardContext } from "../lib/exam-card-context";
import { formatPatientPassport } from "../lib/passport";
import { ExamPageActions } from "./exam-page-actions";
import { PatientPassportCombobox } from "./patient-passport-combobox";

const ExamReportView = dynamic(() => import("./exam-report-view").then((module) => module.ExamReportView));
const FinalExamDocumentActions = dynamic(() => import("./final-exam-document-actions").then((module) => module.FinalExamDocumentActions));
const ExamAiAssistant = dynamic(() => import("./exam-ai-assistant").then((module) => module.ExamAiAssistant));
const ClinicalExamImageGallery = dynamic(() => import("./imaging-results").then((module) => module.ClinicalExamImageGallery));
const ImagingResultEditor = dynamic(() => import("./imaging-results").then((module) => module.ImagingResultEditor));
const ImagingResultView = dynamic(() => import("./imaging-results").then((module) => module.ImagingResultView));
const ImagingTemplateManager = dynamic(() => import("./imaging-results").then((module) => module.ImagingTemplateManager));
const LaboratoryResultEditor = dynamic(() => import("./laboratory-results").then((module) => module.LaboratoryResultEditor));
const LaboratoryTemplateManager = dynamic(() => import("./laboratory-results").then((module) => module.LaboratoryTemplateManager));

type ExamCenterProps = {
  canCatalogManage: boolean;
  canCreate: boolean;
  canDeleteAny: boolean;
  canDeleteCompleted: boolean;
  canPerform: boolean;
  canReview: boolean;
  currentUserId: string;
  initialData: ClinicalExamPage;
  initialContexts: Record<number, ExamCardContext>;
  initialReferenceData: ExamReferenceData;
  permissionCodes: string[];
  initialPatient?: Patient | null;
};

const EMPTY_FILTERS: ClinicalExamFilters = { search: "", passport: "", categoryId: undefined, examTypeId: undefined, status: undefined, dateFrom: "", dateTo: "" };

export function ExamCenter(props: ExamCenterProps) {
  const [data, setData] = useState(props.initialData);
  const [contexts, setContexts] = useState(props.initialContexts);
  const [references, setReferences] = useState(props.initialReferenceData);
  const [filters, setFilters] = useState<ClinicalExamFilters>(EMPTY_FILTERS);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [moreFilters, setMoreFilters] = useState(false);
  const [panel, setPanel] = useState<"create" | "catalog" | null>(props.canCreate && props.initialPatient ? "create" : null);
  const [detail, setDetail] = useState<ClinicalExamDetail | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const firstFilterRun = useRef(true);
  const listController = useRef<AbortController | null>(null);
  const requestNumber = useRef(0);

  async function load(page: number, activeFilters = filters) {
    listController.current?.abort();
    const controller = new AbortController();
    listController.current = controller;
    const requestId = ++requestNumber.current;
    setLoading(true);
    setError("");
    try {
      const params = new URLSearchParams({ page: String(page), pageSize: String(data.pageSize), view: "list" });
      const quickPassport = /^\d{1,4}$/.test(activeFilters.search?.trim() ?? "") ? activeFilters.search?.trim() : "";
      addParam(params, "search", quickPassport ? "" : activeFilters.search);
      addParam(params, "passport", activeFilters.passport || quickPassport);
      addParam(params, "categoryId", activeFilters.categoryId);
      addParam(params, "examTypeId", activeFilters.examTypeId);
      addParam(params, "status", activeFilters.status);
      addParam(params, "dateFrom", activeFilters.dateFrom);
      addParam(params, "dateTo", activeFilters.dateTo);
      const response = await fetch(`/api/exams?${params}`, { cache: "no-store", signal: controller.signal });
      const payload = await response.json() as ClinicalExamPage & { contexts?: Record<number, ExamCardContext>; error?: string };
      if (!response.ok) throw new Error(payload.error ?? "Não foi possível consultar os exames.");
      if (requestId === requestNumber.current) { setData(payload); setContexts(payload.contexts ?? {}); }
    } catch (cause) {
      if (cause instanceof DOMException && cause.name === "AbortError") return;
      if (requestId === requestNumber.current) setError(messageOf(cause));
    } finally {
      if (requestId === requestNumber.current) setLoading(false);
    }
  }

  useEffect(() => () => listController.current?.abort(), []);

  useEffect(() => {
    if (firstFilterRun.current) {
      firstFilterRun.current = false;
      return;
    }
    const timer = window.setTimeout(() => void load(1, filters), 350);
    return () => window.clearTimeout(timer);
    // A busca reage ao valor sem disparar uma consulta por tecla imediatamente.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filters]);

  async function openDetail(examId: number) {
    setDetailLoading(true);
    setError("");
    try {
      const response = await fetch(`/api/exams?view=detail&id=${examId}`, { cache: "no-store" });
      const payload = await response.json() as { exam?: ClinicalExamDetail; error?: string };
      if (!response.ok || !payload.exam) throw new Error(payload.error ?? "Não foi possível abrir o exame.");
      setDetail(payload.exam);
    } catch (cause) {
      setError(messageOf(cause));
    } finally {
      setDetailLoading(false);
    }
  }

  async function refreshReferences() {
    const response = await fetch("/api/exams?view=reference", { cache: "no-store" });
    const payload = await response.json() as ExamReferenceData & { error?: string };
    if (!response.ok) throw new Error(payload.error ?? "Não foi possível atualizar o catálogo.");
    setReferences(payload);
  }

  const filteredTypes = useMemo(() => references.types.filter((type) => !filters.categoryId || type.category_id === filters.categoryId), [references.types, filters.categoryId]);
  const totalPages = Math.max(1, Math.ceil(data.total / data.pageSize));
  const first = data.total ? (data.page - 1) * data.pageSize + 1 : 0;
  const last = Math.min(data.total, data.page * data.pageSize);

  return <section className="exam-center">
    <div className="exam-hub-toolbar">
      <label className="exam-hub-search"><span className="sr-only">Buscar por paciente, passaporte ou exame</span><svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"><circle cx="10.8" cy="10.8" r="6.8"/><path d="m16 16 4.5 4.5"/></svg><input value={filters.search ?? ""} onChange={(event) => setFilters((current) => ({ ...current, search: event.target.value }))} placeholder="Buscar por paciente ou passaporte" maxLength={120} /></label>
      <label className="exam-hub-filter">Status <select value={filters.status ?? ""} onChange={(event) => setFilters((current) => ({ ...current, status: (event.target.value || undefined) as ClinicalExamStatus | undefined }))}><option value="">Todos</option>{EXAM_STATUSES.map((status) => <option key={status} value={status}>{EXAM_STATUS_LABELS[status]}</option>)}</select></label>
      <label className="exam-hub-filter">Tipo <select value={filters.examTypeId ?? ""} onChange={(event) => setFilters((current) => ({ ...current, examTypeId: optionalSelectNumber(event.target.value) }))}><option value="">Todos</option>{filteredTypes.map((type) => <option key={type.id} value={type.id}>{type.name}</option>)}</select></label>
      <button className="exam-hub-button" type="button" aria-expanded={moreFilters} onClick={() => setMoreFilters((current) => !current)}>⚙ Mais filtros</button>
      {props.canCreate ? <button className="exam-hub-button exam-hub-new" type="button" onClick={() => setPanel("create")}>＋ Novo exame</button> : null}
    </div>
    {moreFilters ? <div className="exam-hub-extra">
      <label>Passaporte<input inputMode="numeric" value={filters.passport ?? ""} onChange={(event) => setFilters((current) => ({ ...current, passport: event.target.value.replace(/\D/g, "").slice(0, 4) }))} placeholder="0000" /></label>
      <label>Categoria<select value={filters.categoryId ?? ""} onChange={(event) => setFilters((current) => ({ ...current, categoryId: optionalSelectNumber(event.target.value), examTypeId: undefined }))}><option value="">Todas</option>{references.categories.map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}</select></label>
      <label>De<input type="date" value={filters.dateFrom ?? ""} onChange={(event) => setFilters((current) => ({ ...current, dateFrom: event.target.value }))} /></label>
      <label>Até<input type="date" value={filters.dateTo ?? ""} onChange={(event) => setFilters((current) => ({ ...current, dateTo: event.target.value }))} /></label>
      <button className="exam-hub-text-button" type="button" onClick={() => setFilters(EMPTY_FILTERS)} disabled={loading}>Limpar filtros</button>
      {props.canCatalogManage ? <button className="exam-hub-text-button" type="button" onClick={() => setPanel("catalog")}>Catálogo e templates</button> : null}
    </div> : null}
    <div className="exam-hub-count"><div><strong>{data.total}</strong> {data.total === 1 ? "exame encontrado" : "exames encontrados"}</div><span>{loading ? "Atualizando…" : `${first}–${last} de ${data.total}`}</span></div>

    {error ? <p className="form-error exam-page-message" role="alert">{error}</p> : null}
    {notice ? <p className="form-success exam-page-message" role="status">{notice}</p> : null}

    {data.items.length ? <div className="exam-hub-grid" aria-busy={loading}>{data.items.map((exam) => {
      const linked = contexts[exam.id];
      return <article className="exam-hub-card" key={exam.id} tabIndex={0} aria-label={`Abrir exame ${exam.exam_type_name} de ${exam.patient_name}`}
        onClick={(event) => { if (!(event.target as Element).closest("button, a, input, select, textarea, [role='button'], [role='dialog'], .document-image-viewer-backdrop")) void openDetail(exam.id); }}
        onKeyDown={(event) => { if (event.target !== event.currentTarget || detailLoading || !["Enter", " "].includes(event.key)) return; event.preventDefault(); void openDetail(exam.id); }}>
        <div className="exam-hub-card-top"><span>{examHeaderLabel(exam.category_name, exam.exam_type_name)}</span><span className="exam-status" data-status={exam.status}>{EXAM_STATUS_LABELS[exam.status]}</span></div>
        <button className="exam-hub-title" type="button" onClick={() => void openDetail(exam.id)} disabled={detailLoading}>{exam.exam_type_name}</button>
        <div className="exam-hub-person"><span className="patient-hub-avatar" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round"><circle cx="12" cy="8" r="3"/><path d="M5.75 19c.2-3.4 2.4-5.25 6.25-5.25s6.05 1.85 6.25 5.25"/></svg></span><div><strong>{exam.patient_name}</strong><span>Passaporte {formatPatientPassport(exam.patient_passport)} · {formatDateTime(exam.requested_at)}</span></div></div>
        <p className="exam-hub-responsible">Responsável: <strong>{exam.responsible_name}</strong></p>
        {linked?.cast ? <div className="exam-hub-clinical" data-kind="cast"><span><strong>{linked.cast.status === "in_use" ? "Gesso ativo" : "Gesso retirado"}</strong> · {linked.cast.location}</span><div><a href={`/gessos?registro=${linked.cast.id}`}>Acompanhar ↗</a>{linked.cast.status === "in_use" && props.permissionCodes.includes("casts.remove") ? <a href={`/gessos?registro=${linked.cast.id}&acao=retirar`}>Registrar retirada</a> : null}</div></div> : null}
        {linked?.hospitalization ? <div className="exam-hub-clinical" data-kind="hospitalization"><span><strong>{linked.hospitalization.status === "active" ? "Internação ativa" : "Alta registrada"}</strong> · {linked.hospitalization.reason}</span><div>{linked.hospitalization.status === "active" ? <a href={`/internacoes?registro=${linked.hospitalization.id}`}>Acompanhar ↗</a> : props.permissionCodes.includes("patients.view") ? <a href={`/pacientes/${exam.patient_id}`}>Ver no perfil ↗</a> : null}{linked.hospitalization.status === "active" && props.permissionCodes.includes("hospitalizations.discharge") ? <a href={`/internacoes?registro=${linked.hospitalization.id}&acao=alta`}>Registrar alta</a> : null}</div></div> : null}
        {linked?.suggestedAction === "CAST" && linked.consultationId && props.permissionCodes.includes("casts.create") ? <div className="exam-hub-clinical" data-kind="cast"><span><strong>Imobilização indicada</strong> · Aguardando registro</span><a href={`/gessos?nova=true&consulta=${linked.consultationId}`}>Aplicar gesso ↗</a></div> : null}
        {linked?.suggestedAction === "HOSPITALIZATION" && linked.consultationId && props.permissionCodes.includes("hospitalizations.create") ? <div className="exam-hub-clinical" data-kind="hospitalization"><span><strong>Internação indicada</strong> · Aguardando registro</span><a href={`/internacoes?nova=true&consulta=${linked.consultationId}`}>Iniciar internação ↗</a></div> : null}
        {exam.status === "completed" ? <ExamPageActions key={`${exam.id}-${linked?.pageCount ?? "pending"}`} examId={exam.id} label={`${exam.exam_type_name} de ${exam.patient_name}`} initialPageCount={linked?.pageCount ?? null} /> : <div className="exam-hub-awaiting">Resultado disponível após a conclusão do exame.</div>}
      </article>;
    })}</div> : <div className="empty-state"><span>⌕</span><strong>Nenhum exame localizado</strong><p>Revise os filtros ou crie uma nova solicitação clínica.</p></div>}
    <div className="exam-pagination exam-hub-pagination"><button type="button" disabled={loading || data.page <= 1} onClick={() => void load(data.page - 1)}>← Anterior</button><span>Página <strong>{data.page}</strong> de {totalPages}</span><button type="button" disabled={loading || data.page >= totalPages} onClick={() => void load(data.page + 1)}>Próxima →</button></div>

    {panel === "create" ? <ExamCreatePanel currentUserId={props.currentUserId} initialPatient={props.initialPatient} references={references} onClose={() => setPanel(null)} onCreated={(examId) => { setPanel(null); setNotice(`Exame #${examId} solicitado com sucesso.`); void load(1); void openDetail(examId); }} /> : null}
    {panel === "catalog" ? <CatalogPanel references={references} onClose={() => setPanel(null)} onChanged={async () => { await refreshReferences(); await load(1); }} /> : null}
    {detail ? <ExamDetailPanel
      key={`${detail.id}-${detail.updated_at}`}
      canDeleteAny={props.canDeleteAny}
      canDeleteCompleted={props.canDeleteCompleted}
      canPerform={props.canPerform}
      canReview={props.canReview}
      currentUserId={props.currentUserId}
      exam={detail}
      onClose={() => setDetail(null)}
      onChanged={async () => { await openDetail(detail.id); await load(data.page); }}
      onDeleted={async (storageCleanupPending) => { const deletedId = detail.id; setDetail(null); setNotice(storageCleanupPending ? `Exame #${deletedId} excluído; um arquivo privado requer limpeza técnica.` : `Exame #${deletedId} excluído permanentemente.`); await load(data.page); }}
    /> : null}
  </section>;
}

export function ExamCreatePanel({ consultationId, currentUserId, initialExamTypeId, initialImagingRequest, initialIndication = "", initialPatient = null, inline = false, references, onClose, onCreated }: {
  consultationId?: number;
  currentUserId: string;
  initialExamTypeId?: number;
  initialImagingRequest?: ImagingResultData | null;
  initialIndication?: string;
  initialPatient?: Patient | PatientDirectoryEntry | null;
  inline?: boolean;
  references: ExamReferenceData;
  onClose: () => void;
  onCreated: (id: number) => void;
}) {
  const initialType = references.types.find((type) => type.id === initialExamTypeId);
  const [patientSearch, setPatientSearch] = useState(initialPatient?.passport ?? "");
  const [patient, setPatient] = useState<Patient | null>(initialPatient);
  const [categoryId, setCategoryId] = useState<number | undefined>(initialType?.category_id);
  const [examTypeId, setExamTypeId] = useState<number | undefined>(initialType?.id);
  const [imagingRequest, setImagingRequest] = useState<ReturnType<typeof imagingResultDraft>>(() => initialImagingRequest ?? imagingResultDraft(initialType));
  const [indication, setIndication] = useState(initialIndication);
  const [gestationalWeeks, setGestationalWeeks] = useState("");
  const [betaHcgOutcome, setBetaHcgOutcome] = useState<"" | "positive" | "negative">("");
  const [attendances, setAttendances] = useState<ExamAttendanceOption[]>([]);
  const [attendanceId, setAttendanceId] = useState<number | undefined>();
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const activeCategories = references.categories.filter((category) => category.active);
  const activeTypes = references.types.filter((type) => type.active && (!categoryId || type.category_id === categoryId));
  const isImagingExam = activeCategories.find((category) => category.id === categoryId)?.code === "imagem";
  const isBetaHcg = references.types.find((type) => type.id === examTypeId)?.code === "beta_hcg";
  const responsible = references.professionals.find((professional) => professional.id === currentUserId) ?? null;

  async function loadAttendanceOptions(nextPatient: Patient) {
    try {
      const response = await fetch(`/api/exams?view=attendance-options&patientId=${nextPatient.id}`, { cache: "no-store" });
      const payload = await response.json() as { attendances?: ExamAttendanceOption[]; error?: string };
      if (!response.ok) throw new Error(payload.error ?? "Não foi possível consultar os atendimentos.");
      setAttendances(payload.attendances ?? []);
    } catch (cause) {
      setError(messageOf(cause));
    }
  }

  useEffect(() => {
    const timer = window.setTimeout(() => {
      if (initialPatient) void loadAttendanceOptions(initialPatient);
    }, 0);
    // O paciente vindo do Perfil permanece fixo e só os atendimentos opcionais são carregados.
    return () => window.clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [initialPatient?.id]);

  async function selectPatient(nextPatient: Patient) {
    setPatient(nextPatient);
    setPatientSearch(nextPatient.passport);
    setAttendanceId(undefined);
    await loadAttendanceOptions(nextPatient);
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (indication.trim().length < 2) {
      setError("Informe a suspeita e o contexto do caso.");
      return;
    }
    if (isBetaHcg && !betaHcgOutcome) {
      setError("Selecione Positivo ou Negativo para o Beta HCG.");
      return;
    }
    if (isBetaHcg && betaHcgOutcome === "positive" && (!/^\d{1,2}$/.test(gestationalWeeks) || Number(gestationalWeeks) < 3 || Number(gestationalWeeks) > 40)) {
      setError("Informe a idade gestacional entre 3 e 40 semanas antes de solicitar o Beta HCG.");
      return;
    }
    if (imagingRequest) {
      const missing = missingRequiredImagingFields(imagingRequest);
      if (missing.length) {
        setError(`Preencha os dados obrigatórios da solicitação: ${missing.join(", ")}.`);
        return;
      }
    }
    setSaving(true);
    setError("");
    try {
      const payload = await postExamAction<{ examId: number }>({ action: "create", attendanceId, consultationId, examTypeId, indication, initialResultData: isBetaHcg ? { beta_hcg_outcome: betaHcgOutcome, ...(betaHcgOutcome === "positive" ? { gestational_weeks: Number(gestationalWeeks) } : {}) } : imagingRequest, patientId: patient?.id });
      onCreated(payload.examId);
    } catch (cause) {
      setError(messageOf(cause));
    } finally {
      setSaving(false);
    }
  }

  const form = <form className="exam-panel-form" onSubmit={submit}>
      {error ? <p className="form-error" role="alert">{error}</p> : null}
      {!initialPatient ? <PatientPassportCombobox className="exam-full-field" label="Paciente obrigatório · passaporte" value={patientSearch} selectedPatient={patient} showSelectedSummary={false} onValueChange={(value) => { setPatient(null); setPatientSearch(value); setAttendances([]); setAttendanceId(undefined); }} onSelect={(nextPatient) => void selectPatient(nextPatient)} /> : null}
      {patient ? <div className="exam-selected-patient"><span>{initials(patient.name)}</span><div><strong>{patient.name}</strong><small>Passaporte {formatPatientPassport(patient.passport)}</small></div></div> : null}
      <label>Categoria<select value={categoryId ?? ""} onChange={(event) => { setCategoryId(optionalSelectNumber(event.target.value)); setExamTypeId(undefined); setImagingRequest(null); setGestationalWeeks(""); setBetaHcgOutcome(""); }} required><option value="">Selecione</option>{activeCategories.map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}</select></label>
      <label>Tipo de exame<select value={examTypeId ?? ""} onChange={(event) => { const nextId = optionalSelectNumber(event.target.value); setExamTypeId(nextId); setImagingRequest(imagingResultDraft(references.types.find((type) => type.id === nextId))); setGestationalWeeks(""); setBetaHcgOutcome(""); }} required disabled={!categoryId}><option value="">Selecione</option>{activeTypes.map((type) => <option key={type.id} value={type.id}>{type.name}</option>)}</select></label>
      {isBetaHcg ? <label className="exam-full-field">Resultado do Beta HCG<em>Obrigatório</em><select required disabled={saving} value={betaHcgOutcome} onChange={(event) => { setBetaHcgOutcome(event.target.value as "" | "positive" | "negative"); setGestationalWeeks(""); }}><option value="">Selecione</option><option value="positive">Positivo</option><option value="negative">Negativo</option></select></label> : null}
      {isBetaHcg && betaHcgOutcome === "positive" ? <label className="exam-full-field">Idade gestacional informada pelo médico (semanas)<em>Obrigatório</em><input type="number" inputMode="numeric" min={3} max={40} step={1} required disabled={saving} value={gestationalWeeks} onChange={(event) => setGestationalWeeks(event.target.value)} placeholder="3 a 40 semanas" /><small>Informe as semanas antes de iniciar a execução. O resultado quantitativo será gerado para essa idade gestacional.</small></label> : null}
      {imagingRequest ? <div className="exam-full-field"><ImagingResultEditor result={imagingRequest} disabled={saving} onChange={setImagingRequest} /></div> : null}
      {examTypeId ? <label className="exam-full-field">Suspeita e contexto do caso<textarea value={indication} onChange={(event) => setIndication(event.target.value)} required rows={4} maxLength={4000} placeholder={isImagingExam ? "Ex.: suspeita de fratura após queda, com dor no braço direito" : "Ex.: suspeita clínica, sintomas observados e o que deve ser avaliado"} /></label> : null}
      <label>Profissional responsável<input value={responsible ? `${responsible.name} · ${responsible.position ?? "Sem cargo"}` : "Perfil profissional indisponível"} readOnly aria-readonly="true" /><small>Preenchido automaticamente pelo seu login.</small></label>
      <label>Atendimento relacionado (opcional)<select value={attendanceId ?? ""} onChange={(event) => setAttendanceId(optionalSelectNumber(event.target.value))} disabled={!patient}><option value="">{patient && !attendances.length ? "Nenhuma venda compatível" : "Sem vínculo financeiro"}</option>{attendances.map((attendance) => <option key={attendance.id} value={attendance.id}>#{attendance.id} · {formatDate(attendance.created_at)} · {attendance.summary}</option>)}</select><small>Somente vendas concluídas com EXAMES / RAIO-X ou RESSON. TOMO.</small></label>
      <div className="exam-panel-actions"><button type="button" className="exam-secondary-button" onClick={onClose}>Cancelar</button><button type="submit" className="exam-primary-button" disabled={saving || !patient || !responsible}>{saving ? "Solicitando…" : "Solicitar exame"}</button></div>
    </form>;
  if (inline) return <section className="inline-module-panel"><header><div><span className="consultation-kicker">Exame vinculado</span><h4>Novo exame clínico</h4><p>Revise o formulário oficial antes de criar a solicitação.</p></div></header>{form}</section>;
  return <Overlay title="Novo exame clínico" subtitle="A solicitação clínica é independente da venda; o atendimento abaixo é apenas um vínculo opcional." onClose={onClose}>{form}</Overlay>;
}

export function ExamDetailPanel({ allowDelete = true, canDeleteAny = false, canDeleteCompleted = false, canPerform, canReview, currentUserId, exam, initialDocumentOpen = false, inline = false, onClose, onChanged, onDeleted, readOnly = false }: {
  allowDelete?: boolean;
  canDeleteAny?: boolean;
  canDeleteCompleted?: boolean;
  canPerform: boolean;
  canReview: boolean;
  currentUserId: string;
  exam: ClinicalExamDetail;
  initialDocumentOpen?: boolean;
  inline?: boolean;
  onClose: () => void;
  onChanged: () => Promise<void>;
  onDeleted?: (storageCleanupPending: boolean) => Promise<void>;
  readOnly?: boolean;
}) {
  const [technique, setTechnique] = useState(exam.technique ?? "");
  const [findings, setFindings] = useState(exam.findings ?? "");
  const [conclusion, setConclusion] = useState(exam.conclusion ?? "");
  const [notes, setNotes] = useState(typeof exam.result_data?.notes === "string" ? exam.result_data.notes : "");
  const [resultData, setResultData] = useState(exam.result_data);
  const [reason, setReason] = useState("");
  const [working, setWorking] = useState(false);
  const [generationStage, setGenerationStage] = useState("");
  const [error, setError] = useState("");
  const [galleryRevision, setGalleryRevision] = useState(0);
  const [deleteConfirmation, setDeleteConfirmation] = useState("");
  const [confirmingDelete, setConfirmingDelete] = useState(false);
  const [showManualEditing, setShowManualEditing] = useState(false);
  const [chosenOption, setChosenOption] = useState("");
  const [manualTitle, setManualTitle] = useState("");
  const [manualContext, setManualContext] = useState("");
  const resultState = exam.result_state;
  const canOperate = !readOnly && (canReview || (canPerform && exam.responsible_professional.id === currentUserId));
  const canApprove = !readOnly && (canReview || exam.requested_by.id === currentUserId || exam.responsible_professional.id === currentUserId);
  const canDelete = allowDelete && !readOnly && (exam.status === "completed" ? canDeleteCompleted : canDeleteAny || exam.responsible_professional.id === currentUserId);
  const laboratoryResult = isLabResultData(resultData) ? resultData : null;
  const imagingResult = isImagingResultData(resultData) ? resultData : null;
  const reportConfig = exam.report_config;
  const observations = laboratoryResult?.notes ?? imagingResult?.notes ?? notes;
  const hasClinicalReportV3 = exam.ai_generations?.some((generation) => generation.status === "applied" && generation.suggestion_payload?.schema === "hpsm.ai.clinical_report.v3") ?? false;
  const latestCorrection = [...exam.history].reverse().find((item) => item.from_status === "awaiting_review" && item.to_status === "in_progress") ?? null;
  const [galleryState, setGalleryState] = useState({ count: 0, loading: Boolean(imagingResult) });
  const dirty = technique !== (exam.technique ?? "")
    || findings !== (exam.findings ?? "")
    || conclusion !== (exam.conclusion ?? "")
    || (laboratoryResult || imagingResult ? JSON.stringify(resultData) !== JSON.stringify(exam.result_data) : notes !== (typeof exam.result_data?.notes === "string" ? exam.result_data.notes : ""));

  useEffect(() => {
    if (exam.status !== "in_progress" || resultState?.status !== "analyzing" || working) return;
    const timer = window.setTimeout(() => { void onChanged().catch(() => undefined); }, 5_000);
    return () => window.clearTimeout(timer);
  }, [exam.status, resultState?.status, working, onChanged]);

  async function act(action: string, extra: Record<string, unknown> = {}, refresh = true) {
    setWorking(true);
    setError("");
    try {
      await postExamAction({ action, examId: exam.id, ...extra });
      if (refresh) await onChanged();
      return true;
    } catch (cause) {
      setError(messageOf(cause));
      return false;
    } finally {
      setWorking(false);
    }
  }

  async function generateAfterStart(start: boolean) {
    setWorking(true);
    setError("");
    let started = !start;
    try {
      if (start) {
        setGenerationStage("Iniciando execução…");
        await postExamAction({ action: "start", examId: exam.id });
        started = true;
      }
      if (resultState?.status === "legacy") {
        await generateExamWithAi(exam.id, Boolean(imagingResult), (stage) => {
          setGenerationStage({ image: "Gerando a imagem clínica…", report: "Sol está preparando o laudo…", apply: "Enviando à revisão humana…", exam: "Sol está gerando o exame…" }[stage]);
        });
        setGalleryRevision((current) => current + 1);
      } else {
        setGenerationStage("Sol está analisando as possibilidades…");
        await analyzeExamResults(exam.id);
      }
    } catch (cause) {
      setError(messageOf(cause));
    } finally {
      if (started) {
        try { await onChanged(); }
        catch { setError("A execução foi iniciada, mas não foi possível atualizar o exame. Abra o detalhe novamente."); }
      }
      setGenerationStage("");
      setWorking(false);
    }
  }

  async function analyzeAgain(reanalyze: boolean) {
    setWorking(true); setError("");
    try {
      setGenerationStage("Sol está analisando as possibilidades…");
      await analyzeExamResults(exam.id, reanalyze);
      setChosenOption(""); setManualTitle(""); setManualContext("");
      await onChanged();
    } catch (cause) { setError(messageOf(cause)); await onChanged().catch(() => undefined); }
    finally { setWorking(false); setGenerationStage(""); }
  }

  async function confirmAndGenerate() {
    setWorking(true); setError("");
    try {
      if (!resultState?.selected_snapshot) {
        if (!chosenOption) throw new Error("Selecione uma possibilidade ou informe outra direção clínica.");
        await selectExamResult(exam.id, chosenOption, manualTitle, manualContext);
      }
      await generateSelectedExamWithAi(exam.id, Boolean(imagingResult), (stage) => {
        setGenerationStage({ image: "Gerando o estudo visual…", report: "Sol está preparando o laudo…", apply: "Enviando à revisão humana…", exam: "Sol está gerando o exame…" }[stage]);
      });
      setGalleryRevision((current) => current + 1);
    } catch (cause) { setError(messageOf(cause)); }
    finally { await onChanged().catch(() => setError("Atualize o detalhe para conferir o estado do exame.")); setWorking(false); setGenerationStage(""); }
  }

  async function saveAndMaybeSubmit(submit: boolean) {
    let confirmedImageCount = galleryState.count;
    if (submit) {
      const missing = laboratoryResult ? missingRequiredLabParameters(laboratoryResult) : [];
      const missingReport = missingRequiredReportFields(reportConfig, { conclusion, findings, observations, technique });
      if (missingReport.length) {
        setError(`Preencha os campos obrigatórios do laudo: ${missingReport.join(", ")}.`);
        return;
      }
      if (missing.length) {
        setError(`Preencha os parâmetros obrigatórios: ${missing.map((parameter) => parameter.label).join(", ")}.`);
        return;
      }
      if (imagingResult) {
        const missingImaging = missingRequiredImagingFields(imagingResult);
        if (missingImaging.length) {
          setError(`Preencha os campos obrigatórios: ${missingImaging.join(", ")}.`);
          return;
        }
        if (galleryState.loading) {
          setWorking(true);
          setError("");
          try {
            const response = await fetch(`/api/exams/images?examId=${exam.id}`, { cache: "no-store" });
            const payload = await response.json() as { error?: string; images?: unknown[] };
            if (!response.ok) throw new Error(payload.error ?? "Não foi possível confirmar as imagens do exame.");
            confirmedImageCount = payload.images?.length ?? 0;
            setGalleryState({ count: confirmedImageCount, loading: false });
            setGalleryRevision((current) => current + 1);
          } catch (cause) {
            setError(messageOf(cause));
            return;
          } finally {
            setWorking(false);
          }
        }
        if (imagingResult.template_snapshot.requires_image && confirmedImageCount < 1) {
          setError("Adicione ao menos uma imagem antes do envio para revisão.");
          return;
        }
      }
    }
    const saved = await act("save", { technique, findings, conclusion, notes, resultData: laboratoryResult ?? imagingResult ?? undefined }, !submit);
    if (submit && saved) await act("submit");
  }

  async function deleteExam() {
    if (deleteConfirmation !== `EXCLUIR ${exam.id}`) return;
    setWorking(true);
    setError("");
    try {
      const result = await postExamAction<{ ok: true; storageCleanupPending?: boolean }>({ action: "delete", examId: exam.id });
      await onDeleted?.(result.storageCleanupPending === true);
    } catch (cause) {
      setError(messageOf(cause));
      setWorking(false);
    }
  }

  const imageGallery = imagingResult && exam.status !== "completed" ? <ClinicalExamImageGallery
    editable={exam.status === "in_progress" && canOperate}
    examId={exam.id}
    examTypeName={exam.exam_type.name}
    onStateChange={setGalleryState}
    refreshToken={galleryRevision}
    required={imagingResult.template_snapshot.requires_image}
  /> : null;

  const content = <div className="exam-detail">
      {error ? <p className="form-error" role="alert">{error}</p> : null}
      <div className="exam-stepper">{EXAM_STATUSES.map((status, index) => <div key={status} data-state={stepState(exam.status, status)}><span>{index + 1}</span><strong>{EXAM_STATUS_LABELS[status]}</strong></div>)}</div>
      {readOnly && exam.status !== "completed" ? <p className="patient-exam-preliminary">Exame ainda não concluído. O conteúdo abaixo é preliminar e respeita o estágio atual do fluxo clínico.</p> : null}
      {exam.status === "completed" ? <FinalExamDocumentActions exam={exam} initialOpen={initialDocumentOpen} /> : <><dl className="exam-detail-facts">
        <div><dt>Categoria</dt><dd>{exam.exam_type.category_name}</dd></div>
        <div><dt>Solicitado por</dt><dd>{identityLabel(exam.requested_by)}</dd></div>
        <div><dt>Responsável</dt><dd>{identityLabel(exam.responsible_professional)}</dd></div>
        <div><dt>Revisor</dt><dd>{exam.reviewed_by ? identityLabel(exam.reviewed_by) : "Ainda não definido"}</dd></div>
        <div><dt>Solicitação</dt><dd>{formatDateTime(exam.requested_at)}</dd></div>
        <div><dt>Atendimento vinculado</dt><dd>{exam.attendance_id ? `#${exam.attendance_id}` : "Sem vínculo financeiro"}</dd></div>
      </dl>
      <div className="exam-clinical-context"><div><strong>Indicação clínica</strong><p>{exam.indication}</p></div>{exam.clinical_context ? <div><strong>Contexto clínico</strong><p>{exam.clinical_context}</p></div> : null}</div>
      {imagingResult ? <ImagingResultView result={imagingResult} /> : null}
      </>}
      {exam.status === "in_progress" && latestCorrection ? <div className="exam-correction"><div><strong>Correção solicitada</strong><span>{identityLabel(latestCorrection.changed_by)} · {formatDateTime(latestCorrection.changed_at)}</span></div><p>{latestCorrection.note || exam.correction_reason || "Revise o conteúdo indicado pelo revisor."}</p></div> : null}

      {exam.status === "requested" && canOperate ? <div className="exam-work-actions"><button className="exam-primary-button" type="button" disabled={working} onClick={() => void generateAfterStart(true)}>{working ? generationStage : "Iniciar execução"}</button></div> : null}
      {exam.status === "in_progress" ? <div className="exam-result-form">
        {canOperate && !latestCorrection && resultState?.status === "legacy" ? <ExamAiAssistant
          dirty={dirty}
          error={error}
          imagingContext={imagingResult ? { caseSummary: clinicalCaseSummary(exam.indication, exam.clinical_context), result: imagingResult } : null}
          onRetry={() => generateAfterStart(false)}
          retrying={working}
        /> : null}
        {canOperate && !latestCorrection && resultState?.status !== "legacy" ? <section className="exam-result-choice" aria-label="Definição do resultado do exame">
          <header><span className="exam-ai-mark" aria-hidden="true">✦</span><div><small>Execução com revisão humana · Sol</small><h3>{resultState?.status === "selected" ? "Resultado definido" : "Possibilidades de resultado"}</h3></div></header>
          {resultState?.status === "ready" ? <><p>Confira a análise clínica e escolha a direção do exame. Os valores, o laudo e a imagem serão produzidos depois da sua confirmação.</p>
            <div className="exam-result-options" role="radiogroup" aria-label="Possibilidades clínicas">
              {resultState.options.map((option) => <label key={option.id} className="exam-result-option" data-selected={chosenOption === option.id}>
                <input type="radio" name={`exam-result-${exam.id}`} value={option.id} checked={chosenOption === option.id} disabled={working} onChange={() => setChosenOption(option.id)} />
                <span><strong>{option.title}</strong><span>{option.summary}</span><small>{option.result_pattern}</small></span>
              </label>)}
              <label className="exam-result-option" data-selected={chosenOption === "manual"}><input type="radio" name={`exam-result-${exam.id}`} value="manual" checked={chosenOption === "manual"} disabled={working} onChange={() => setChosenOption("manual")} /><span><strong>Nenhuma corresponde</strong><span>Informe uma direção clínica breve para o resultado.</span></span></label>
            </div>
            {chosenOption === "manual" ? <div className="exam-result-manual"><label>Resultado pretendido<input value={manualTitle} onChange={(event) => setManualTitle(event.target.value)} maxLength={120} disabled={working} placeholder="Ex.: achado focal específico" /></label><label>Contexto complementar<textarea value={manualContext} onChange={(event) => setManualContext(event.target.value)} maxLength={1000} rows={3} disabled={working} placeholder="Descreva a direção do resultado em poucas palavras." /></label></div> : null}
            <div className="exam-work-actions"><button className="exam-secondary-button" type="button" disabled={working || resultState.analysis_count >= 2} onClick={() => void analyzeAgain(true)}>Reanalisar possibilidades</button><button className="exam-primary-button" type="button" disabled={working || !chosenOption || chosenOption === "manual" && (manualTitle.trim().length < 3 || manualContext.trim().length < 8)} onClick={() => void confirmAndGenerate()}>{working ? generationStage : "Confirmar e gerar exame"}</button></div>
          </> : resultState?.status === "selected" ? <><p><strong>{resultState.selected_snapshot?.title}</strong> · {resultState.selected_snapshot?.summary}</p><p>Direção confirmada. A geração pode ser retomada a partir do estado salvo.</p><button className="exam-primary-button" type="button" disabled={working || dirty} onClick={() => void confirmAndGenerate()}>{working ? generationStage : "Retomar geração final"}</button></> : <><p>{resultState?.status === "analyzing" ? "Sol está analisando os possíveis resultados. O estado será atualizado automaticamente." : "A análise não foi concluída. Tente novamente para ver as possibilidades."}</p><div className="exam-work-actions"><button className="exam-secondary-button" type="button" disabled={working} onClick={() => void onChanged()}>Atualizar estado</button>{resultState?.status !== "analyzing" ? <button className="exam-primary-button" type="button" disabled={working || dirty} onClick={() => void analyzeAgain(false)}>{working ? generationStage : "Tentar novamente"}</button> : null}</div></>}
          {error ? <p className="form-error" role="alert">{error}</p> : null}
        </section> : null}
        {imageGallery}
        {canOperate ? <button className="exam-secondary-button" type="button" disabled={working} onClick={() => setShowManualEditing((current) => !current)}>{showManualEditing ? "Ocultar preenchimento manual" : "Editar ou preencher manualmente"}</button> : null}
        {showManualEditing ? <>
        {laboratoryResult ? <LaboratoryResultEditor result={laboratoryResult} disabled={!canOperate || working} onChange={setResultData} /> : null}
        <div className="exam-report-editor">
          <header><span>Edição humana</span><h3>Ajuste manual do laudo</h3><p>Revise o texto sugerido ou preencha manualmente quando preferir.</p></header>
          <ReportEditorField config={reportConfig} name="technique" value={technique} onChange={setTechnique} readOnly={!canOperate} rows={5} maxLength={4000} />
          <ReportEditorField config={reportConfig} name="findings" value={findings} onChange={setFindings} readOnly={!canOperate} rows={8} maxLength={8000} />
          <ReportEditorField config={reportConfig} name="conclusion" value={conclusion} onChange={setConclusion} readOnly={!canOperate} rows={5} maxLength={4000} />
          {imagingResult ? <label>Conduta / Próximos passos<small>Opcional para preenchimento manual</small><textarea value={imagingResult.notes} onChange={(event) => setResultData({ ...imagingResult, notes: event.target.value })} readOnly={!canOperate} rows={4} maxLength={1200} placeholder="Ex.: imobilização, controle da dor e acompanhamento clínico" /></label> : null}
          {!laboratoryResult && !imagingResult ? <ReportEditorField config={reportConfig} label={hasClinicalReportV3 ? "Conduta / Próximos passos" : undefined} name="observations" value={notes} onChange={setNotes} readOnly={!canOperate} rows={4} maxLength={12000} /> : null}
        </div>
        {canOperate ? <div className="exam-draft-actions"><span data-dirty={dirty}>{dirty ? "Alterações não salvas" : "Rascunho sincronizado"}</span><div className="exam-work-actions"><button className="exam-secondary-button" type="button" disabled={working || !dirty} onClick={() => void saveAndMaybeSubmit(false)}>Salvar rascunho</button><button className="exam-primary-button" type="button" disabled={working} onClick={() => void saveAndMaybeSubmit(true)}>Salvar e enviar à revisão</button></div></div> : null}
        </> : null}
      </div> : null}
      {exam.status === "awaiting_review" ? <div className="exam-review-box">
        <ExamReportView exam={exam} imageGallery={imageGallery} />
        {canApprove ? <div className="exam-review-actions">{canReview ? <label>Motivo para devolução<textarea value={reason} onChange={(event) => setReason(event.target.value)} rows={4} maxLength={2000} placeholder="Descreva objetivamente o que precisa ser corrigido" /></label> : null}<div className="exam-work-actions">{canReview ? <button className="exam-danger-button" type="button" disabled={working || reason.trim().length < 2} onClick={() => void act("review", { decision: "return", reason })}>Solicitar correção</button> : null}<button className="exam-primary-button" type="button" disabled={working} onClick={() => void act("review", { decision: "approve" })}>Aprovar e concluir</button></div></div> : null}
      </div> : null}
      {exam.report_versions.length ? <ReportVersionHistory versions={exam.report_versions} /> : null}
      <div className="exam-history"><h3>Histórico clínico</h3>{exam.history.map((item) => <article key={item.id}><span /><div><strong>{historyLabel(item.from_status, item.to_status)}</strong><p>{item.note || "Alteração registrada."}</p><small>{identityLabel(item.changed_by)} · {formatDateTime(item.changed_at)}</small></div></article>)}</div>
      {canDelete ? <section className="exam-delete-zone">
        <div><strong>Excluir exame permanentemente</strong><p>Remove o exame, imagens, laudos e vínculos no HPSM. Esta ação não pode ser desfeita.{exam.status === "completed" ? " Links públicos de páginas já copiadas podem continuar acessíveis fora do sistema." : ""}</p></div>
        {!confirmingDelete ? <button className="exam-danger-button" type="button" disabled={working} onClick={() => setConfirmingDelete(true)}>Excluir exame</button> : <div className="exam-delete-confirmation" role="alertdialog" aria-label="Confirmar exclusão permanente do exame">
          <label>Digite <strong>EXCLUIR {exam.id}</strong> para confirmar<input value={deleteConfirmation} onChange={(event) => setDeleteConfirmation(event.target.value.toUpperCase())} autoComplete="off" disabled={working} /></label>
          <div><button className="exam-secondary-button" type="button" disabled={working} onClick={() => { setConfirmingDelete(false); setDeleteConfirmation(""); }}>Cancelar</button><button className="exam-danger-button" type="button" disabled={working || deleteConfirmation !== `EXCLUIR ${exam.id}`} onClick={() => void deleteExam()}>{working ? "Excluindo…" : "Excluir definitivamente"}</button></div>
        </div>}
      </section> : null}
    </div>;
  if (inline) return <section className="inline-module-panel inline-exam-detail"><header><div><span className="consultation-kicker">Exame vinculado · {EXAM_STATUS_LABELS[exam.status]}</span><h4>{exam.exam_type.name} · #{exam.id}</h4><p>{exam.patient.name} · Passaporte {formatPatientPassport(exam.patient.passport)}</p></div><button className="exam-secondary-button" type="button" onClick={onClose}>Recolher</button></header>{content}</section>;
  return <Overlay title={`${exam.exam_type.name} · #${exam.id}`} subtitle={`${exam.patient.name} · Passaporte ${formatPatientPassport(exam.patient.passport)}`} onClose={onClose} wide>{content}</Overlay>;
}

function ReportEditorField({ config, label, maxLength, name, onChange, readOnly, rows, value }: {
  config: ClinicalExamReportConfig;
  label?: string;
  maxLength: number;
  name: keyof ClinicalExamReportConfig["fields"];
  onChange: (value: string) => void;
  readOnly: boolean;
  rows: number;
  value: string;
}) {
  const field = config.fields[name];
  if (!field?.visible) return null;
  return <label>{label ?? field.label}{field.required ? <em>Obrigatório</em> : <small>Opcional</small>}<textarea value={value} onChange={(event) => onChange(event.target.value)} readOnly={readOnly} rows={rows} maxLength={maxLength} /></label>;
}

function ReportVersionHistory({ versions }: { versions: ClinicalExamReportVersion[] }) {
  return <section className="exam-report-versions"><header><div><span>Controle de versões</span><h3>Ciclos de revisão do laudo</h3></div><strong>{versions.length}</strong></header><div>{versions.map((version) => <article key={version.id} data-decision={version.decision}><span>v{version.version_number}</span><div><strong>{reportDecisionLabel(version.decision)}</strong><small>Enviado por {identityLabel(version.submitted_by)} · {formatDateTime(version.submitted_at)}</small>{version.reviewed_by && version.reviewed_at ? <small>{identityLabel(version.reviewed_by)} · {formatDateTime(version.reviewed_at)}</small> : null}{version.review_reason ? <p>{version.review_reason}</p> : null}</div></article>)}</div></section>;
}

function CatalogPanel({ references, onClose, onChanged }: { references: ExamReferenceData; onClose: () => void; onChanged: () => Promise<void> }) {
  const [tab, setTab] = useState<"categories" | "types" | "templates" | "imaging-templates">("categories");
  const [working, setWorking] = useState(false);
  const [error, setError] = useState("");

  async function save(payload: Record<string, unknown>) {
    setWorking(true);
    setError("");
    try {
      await postExamAction(payload);
      await onChanged();
    } catch (cause) {
      setError(messageOf(cause));
    } finally {
      setWorking(false);
    }
  }

  return <Overlay title="Catálogo clínico" subtitle="Categorias, tipos e modelos versionados preservam o histórico clínico." onClose={onClose} wide>
    <div className="exam-catalog">
      {error ? <p className="form-error" role="alert">{error}</p> : null}
      <div className="exam-catalog-tabs"><button type="button" data-active={tab === "categories"} onClick={() => setTab("categories")}>Categorias</button><button type="button" data-active={tab === "types"} onClick={() => setTab("types")}>Tipos de exame</button><button type="button" data-active={tab === "templates"} onClick={() => setTab("templates")}>Templates laboratoriais</button><button type="button" data-active={tab === "imaging-templates"} onClick={() => setTab("imaging-templates")}>Templates de imagem</button></div>
      {tab === "categories" ? <><NewCategoryForm disabled={working} onSave={save} /><div className="exam-catalog-list">{references.categories.map((category) => <CategoryRow key={`${category.id}-${category.name}-${category.sort_order}-${category.active}`} category={category} disabled={working} onSave={save} />)}</div></> : null}
      {tab === "types" ? <><NewTypeForm categories={references.categories} disabled={working} onSave={save} /><div className="exam-catalog-list">{references.types.map((type) => <TypeRow key={`${type.id}-${type.category_id}-${type.name}-${type.sort_order}-${type.active}`} type={type} categories={references.categories} disabled={working} onSave={save} />)}</div></> : null}
      {tab === "templates" ? <LaboratoryTemplateManager /> : null}
      {tab === "imaging-templates" ? <ImagingTemplateManager /> : null}
    </div>
  </Overlay>;
}

function NewCategoryForm({ disabled, onSave }: { disabled: boolean; onSave: (payload: Record<string, unknown>) => Promise<void> }) {
  const [name, setName] = useState(""); const [code, setCode] = useState(""); const [sortOrder, setSortOrder] = useState(0);
  return <form className="exam-catalog-create" onSubmit={(event) => { event.preventDefault(); void onSave({ action: "category", active: true, code, name, sortOrder }).then(() => { setName(""); setCode(""); }); }}><label>Nova categoria<input value={name} onChange={(event) => setName(event.target.value)} required maxLength={80} /></label><label>Código<input value={code} onChange={(event) => setCode(slugCode(event.target.value))} required maxLength={40} /></label><label>Ordem<input type="number" min="0" value={sortOrder} onChange={(event) => setSortOrder(Number(event.target.value))} /></label><button className="exam-primary-button" disabled={disabled}>Adicionar</button></form>;
}

function CategoryRow({ category, disabled, onSave }: { category: ExamCategory; disabled: boolean; onSave: (payload: Record<string, unknown>) => Promise<void> }) {
  const [name, setName] = useState(category.name); const [sortOrder, setSortOrder] = useState(category.sort_order);
  return <form onSubmit={(event) => { event.preventDefault(); void onSave({ action: "category", active: category.active, code: category.code, id: category.id, name, sortOrder }); }}><div><strong>{category.code}</strong><span data-active={category.active}>{category.active ? "Ativa" : "Inativa"}</span></div><label>Nome<input value={name} onChange={(event) => setName(event.target.value)} required /></label><label>Ordem<input type="number" min="0" value={sortOrder} onChange={(event) => setSortOrder(Number(event.target.value))} /></label><button className="exam-secondary-button" disabled={disabled}>Salvar</button><button className={category.active ? "exam-danger-button" : "exam-primary-button"} type="button" disabled={disabled} onClick={() => void onSave({ action: "category", active: !category.active, code: category.code, id: category.id, name, sortOrder })}>{category.active ? "Inativar" : "Ativar"}</button></form>;
}

function NewTypeForm({ categories, disabled, onSave }: { categories: ExamCategory[]; disabled: boolean; onSave: (payload: Record<string, unknown>) => Promise<void> }) {
  const [categoryId, setCategoryId] = useState<number | undefined>(); const [name, setName] = useState(""); const [code, setCode] = useState(""); const [description, setDescription] = useState(""); const [sortOrder, setSortOrder] = useState(0);
  return <form className="exam-catalog-create exam-type-create" onSubmit={(event) => { event.preventDefault(); void onSave({ action: "type", active: true, categoryId, code, description, name, sortOrder }).then(() => { setName(""); setCode(""); setDescription(""); }); }}><label>Categoria<select value={categoryId ?? ""} onChange={(event) => setCategoryId(optionalSelectNumber(event.target.value))} required><option value="">Selecione</option>{categories.filter((item) => item.active).map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label><label>Novo tipo<input value={name} onChange={(event) => setName(event.target.value)} required maxLength={100} /></label><label>Código<input value={code} onChange={(event) => setCode(slugCode(event.target.value))} required maxLength={50} /></label><label>Ordem<input type="number" min="0" value={sortOrder} onChange={(event) => setSortOrder(Number(event.target.value))} /></label><label className="exam-full-field">Descrição<input value={description} onChange={(event) => setDescription(event.target.value)} maxLength={1000} /></label><button className="exam-primary-button" disabled={disabled}>Adicionar tipo</button></form>;
}

function TypeRow({ type, categories, disabled, onSave }: { type: ExamType; categories: ExamCategory[]; disabled: boolean; onSave: (payload: Record<string, unknown>) => Promise<void> }) {
  const [name, setName] = useState(type.name); const [description, setDescription] = useState(type.description ?? ""); const [categoryId, setCategoryId] = useState(type.category_id); const [sortOrder, setSortOrder] = useState(type.sort_order);
  const payload = (active: boolean) => ({ action: "type", active, categoryId, code: type.code, description, id: type.id, name, sortOrder });
  return <form onSubmit={(event) => { event.preventDefault(); void onSave(payload(type.active)); }}><div><strong>{type.code}</strong><span data-active={type.active}>{type.active ? "Ativo" : "Inativo"}</span></div><label>Categoria<select value={categoryId} onChange={(event) => setCategoryId(Number(event.target.value))}>{categories.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label><label>Nome<input value={name} onChange={(event) => setName(event.target.value)} required /></label><label>Descrição<input value={description} onChange={(event) => setDescription(event.target.value)} /></label><label>Ordem<input type="number" min="0" value={sortOrder} onChange={(event) => setSortOrder(Number(event.target.value))} /></label><button className="exam-secondary-button" disabled={disabled}>Salvar</button><button className={type.active ? "exam-danger-button" : "exam-primary-button"} type="button" disabled={disabled} onClick={() => void onSave(payload(!type.active))}>{type.active ? "Inativar" : "Ativar"}</button></form>;
}

function Overlay({ children, onClose, subtitle, title, wide = false }: { children: React.ReactNode; onClose: () => void; subtitle: string; title: string; wide?: boolean }) {
  return <div className="exam-overlay" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}><section className="exam-panel" data-wide={wide} role="dialog" aria-modal="true" aria-label={title}><header><div><h2>{title}</h2><p>{subtitle}</p></div><button type="button" onClick={onClose} aria-label="Fechar">×</button></header>{children}</section></div>;
}

async function postExamAction<T = { ok: true }>(body: Record<string, unknown>) {
  const response = await fetch("/api/exams", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
  const payload = await response.json() as T & { error?: string };
  if (!response.ok) throw new Error(payload.error ?? "Não foi possível concluir a operação.");
  return payload;
}

function addParam(params: URLSearchParams, key: string, value: unknown) {
  if (value !== undefined && value !== null && value !== "") params.set(key, String(value));
}

function optionalSelectNumber(value: string) {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : undefined;
}

function messageOf(error: unknown) {
  return error instanceof Error ? error.message : "Não foi possível concluir a operação.";
}

function identityLabel(person: { name: string; position: string | null }) {
  return `${person.name} · ${person.position ?? "Cargo não informado"}`;
}

function clinicalCaseSummary(indication: string, context: string | null) {
  const primary = indication.trim();
  const complementary = context?.trim() ?? "";
  if (!complementary || complementary === primary) return primary;
  return `${primary}\n${complementary}`;
}

function missingRequiredReportFields(config: ClinicalExamReportConfig, values: Record<keyof ClinicalExamReportConfig["fields"], string>) {
  return (Object.keys(config.fields) as Array<keyof ClinicalExamReportConfig["fields"]>)
    .filter((name) => config.fields[name].visible && config.fields[name].required && !values[name].trim())
    .map((name) => config.fields[name].label);
}

function historyLabel(from: ClinicalExamStatus | null, to: ClinicalExamStatus) {
  if (from === "awaiting_review" && to === "in_progress") return "Correção solicitada";
  if (from === "in_progress" && to === "awaiting_review") return "Enviado para revisão";
  if (from === "awaiting_review" && to === "completed") return "Laudo aprovado";
  if (from === "requested" && to === "in_progress") return "Execução iniciada";
  return EXAM_STATUS_LABELS[to];
}

function reportDecisionLabel(decision: ClinicalExamReportVersion["decision"]) {
  if (decision === "approved") return "Aprovado";
  if (decision === "returned") return "Devolvido para correção";
  return "Aguardando revisão";
}

function examHeaderLabel(category: string, type: string) {
  const normalized = type.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
  const abbreviated = /tomografia/.test(normalized) ? "TC"
    : /ressonancia/.test(normalized) ? "RM"
      : /raio.?x|radiografia/.test(normalized) ? "RAIO-X"
        : /ultrassonografia|ultrassom/.test(normalized) ? "USG"
          : /beta.?hcg/.test(normalized) ? "BETA HCG" : type.toLocaleUpperCase("pt-BR");
  return `${category.toLocaleUpperCase("pt-BR")} · ${abbreviated}`;
}

function formatDate(value: string) {
  return new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric", timeZone: "America/Sao_Paulo" }).format(new Date(value));
}

function formatDateTime(value: string) {
  return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(value));
}

function initials(name: string) {
  return name.trim().split(/\s+/).slice(0, 2).map((part) => part[0]?.toUpperCase()).join("");
}

function stepState(current: ClinicalExamStatus, status: ClinicalExamStatus) {
  const currentIndex = EXAM_STATUSES.indexOf(current);
  const targetIndex = EXAM_STATUSES.indexOf(status);
  return targetIndex < currentIndex ? "done" : targetIndex === currentIndex ? "active" : "pending";
}

function slugCode(value: string) {
  return value.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "").slice(0, 50);
}
