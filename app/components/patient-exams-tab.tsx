"use client";

import dynamic from "next/dynamic";
import { useEffect, useMemo, useRef, useState } from "react";
import { EXAM_STATUSES, EXAM_STATUS_LABELS, type ClinicalExamStatus } from "../lib/exam-status";
import type { ClinicalExamDetail, ExamReferenceData } from "../lib/exams";
import type {
  PatientClinicalExamFilters,
  PatientClinicalExamPage,
  PatientDirectoryEntry,
} from "../lib/patient-center";
import { ExamPngListAction } from "./exam-document-png-action";

const ExamCreatePanel = dynamic(() => import("./exam-center").then((module) => module.ExamCreatePanel));
const ExamDetailPanel = dynamic(() => import("./exam-center").then((module) => module.ExamDetailPanel));

const EMPTY_FILTERS: PatientClinicalExamFilters = { categoryId: undefined, examTypeId: undefined, status: undefined, dateFrom: "", dateTo: "" };

export function PatientExamsTab({ canCreate, currentUserId, patient }: { canCreate: boolean; currentUserId: string; patient: PatientDirectoryEntry }) {
  const [data, setData] = useState<PatientClinicalExamPage | null>(null);
  const [references, setReferences] = useState<ExamReferenceData | null>(null);
  const [filters, setFilters] = useState<PatientClinicalExamFilters>(EMPTY_FILTERS);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [detail, setDetail] = useState<ClinicalExamDetail | null>(null);
  const [detailDocumentOpen, setDetailDocumentOpen] = useState(false);
  const [detailLoadingId, setDetailLoadingId] = useState<number | null>(null);
  const [creating, setCreating] = useState(false);
  const firstFilterRun = useRef(true);
  const listController = useRef<AbortController | null>(null);
  const referencesController = useRef<AbortController | null>(null);
  const requestNumber = useRef(0);

  async function load(page: number, activeFilters = filters) {
    listController.current?.abort();
    const controller = new AbortController();
    listController.current = controller;
    const requestId = ++requestNumber.current;
    setLoading(true);
    setError("");
    try {
      const params = new URLSearchParams({ patientId: String(patient.id), view: "exams", page: String(page), pageSize: "10" });
      addParam(params, "categoryId", activeFilters.categoryId);
      addParam(params, "examTypeId", activeFilters.examTypeId);
      addParam(params, "status", activeFilters.status);
      addParam(params, "dateFrom", activeFilters.dateFrom);
      addParam(params, "dateTo", activeFilters.dateTo);
      const response = await fetch(`/api/patient-center?${params}`, { cache: "no-store", signal: controller.signal });
      const payload = await response.json() as PatientClinicalExamPage & { error?: string };
      if (!response.ok) throw new Error(payload.error ?? "Não foi possível carregar os exames deste paciente.");
      if (requestId === requestNumber.current) setData(payload);
    } catch (cause) {
      if (cause instanceof DOMException && cause.name === "AbortError") return;
      if (requestId === requestNumber.current) setError(messageOf(cause));
    } finally {
      if (requestId === requestNumber.current) setLoading(false);
    }
  }

  async function loadReferences() {
    referencesController.current?.abort();
    const controller = new AbortController();
    referencesController.current = controller;
    try {
      const response = await fetch("/api/exams?view=reference", { cache: "no-store", signal: controller.signal });
      const payload = await response.json() as ExamReferenceData & { error?: string };
      if (!response.ok) throw new Error(payload.error ?? "Não foi possível carregar os filtros clínicos.");
      setReferences(payload);
    } catch (cause) {
      if (cause instanceof DOMException && cause.name === "AbortError") return;
      setError(messageOf(cause));
    }
  }

  useEffect(() => {
    const timer = window.setTimeout(() => void Promise.all([load(1, EMPTY_FILTERS), loadReferences()]), 0);
    // A montagem só acontece quando a aba Exames é aberta.
    return () => {
      window.clearTimeout(timer);
      listController.current?.abort();
      referencesController.current?.abort();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [patient.id]);

  useEffect(() => {
    if (firstFilterRun.current) {
      firstFilterRun.current = false;
      return;
    }
    const timer = window.setTimeout(() => void load(1, filters), 300);
    return () => window.clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filters]);

  async function openDetail(examId: number, openDocument = false) {
    setDetailLoadingId(examId);
    setError("");
    try {
      const response = await fetch(`/api/exams?view=detail&id=${examId}`, { cache: "no-store" });
      const payload = await response.json() as { exam?: ClinicalExamDetail; error?: string };
      if (!response.ok || !payload.exam) throw new Error(payload.error ?? "Não foi possível abrir o exame.");
      setDetailDocumentOpen(openDocument && payload.exam.status === "completed");
      setDetail(payload.exam);
    } catch (cause) {
      setError(messageOf(cause));
    } finally {
      setDetailLoadingId(null);
    }
  }

  const filteredTypes = useMemo(
    () => (references?.types ?? []).filter((type) => !filters.categoryId || type.category_id === filters.categoryId),
    [references?.types, filters.categoryId],
  );
  const totalPages = Math.max(1, Math.ceil((data?.total ?? 0) / (data?.pageSize ?? 10)));

  return <div className="patient-exams-tab" aria-busy={loading}>
    <div className="patient-exams-summary">
      <div><p className="eyebrow">Histórico clínico</p><h3>Exames</h3><span>{data ? `${data.summary.total} registro(s) · ${data.summary.completed} concluído(s) · ${data.summary.awaitingReview} aguardando revisão` : "Carregando resumo…"}</span></div>
      {canCreate && references ? <button className="exam-primary-button" type="button" onClick={() => setCreating(true)}>＋ Novo exame</button> : null}
    </div>

    <div className="patient-exam-filters">
      <label>Status<select value={filters.status ?? ""} onChange={(event) => setFilters((current) => ({ ...current, status: (event.target.value || undefined) as ClinicalExamStatus | undefined }))}><option value="">Todos</option>{EXAM_STATUSES.map((status) => <option key={status} value={status}>{EXAM_STATUS_LABELS[status]}</option>)}</select></label>
      <label>Categoria<select value={filters.categoryId ?? ""} onChange={(event) => setFilters((current) => ({ ...current, categoryId: optionalNumber(event.target.value), examTypeId: undefined }))}><option value="">Todas</option>{references?.categories.map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}</select></label>
      <label>Tipo<select value={filters.examTypeId ?? ""} onChange={(event) => setFilters((current) => ({ ...current, examTypeId: optionalNumber(event.target.value) }))}><option value="">Todos</option>{filteredTypes.map((type) => <option key={type.id} value={type.id}>{type.name}</option>)}</select></label>
      <label>De<input type="date" value={filters.dateFrom ?? ""} onChange={(event) => setFilters((current) => ({ ...current, dateFrom: event.target.value }))} /></label>
      <label>Até<input type="date" value={filters.dateTo ?? ""} onChange={(event) => setFilters((current) => ({ ...current, dateTo: event.target.value }))} /></label>
      <button className="exam-clear-button" type="button" onClick={() => setFilters(EMPTY_FILTERS)} disabled={loading}>Limpar filtros</button>
    </div>

    {error ? <p className="form-error" role="alert">{error}</p> : null}
    {loading && !data ? <PatientExamSkeleton /> : null}
    {data && !data.items.length && !loading ? <div className="empty-state"><span>⌕</span><strong>Nenhum exame clínico registrado para este paciente.</strong><p>{hasFilters(filters) ? "Revise os filtros para consultar outros registros." : "Os exames reais da Central de Exames aparecerão aqui."}</p>{canCreate && references ? <button className="exam-primary-button" type="button" onClick={() => setCreating(true)}>Novo Exame</button> : null}</div> : null}
    {data?.items.length ? <div className="patient-exam-list">
      {data.items.map((exam) => <article key={exam.id}>
        <div className="patient-exam-identity"><strong>{exam.exam_type_name}</strong><span>{exam.category_name}{exam.image_count ? ` · ${exam.image_count} ${exam.image_count === 1 ? "imagem" : "imagens"}` : ""}</span>{exam.indication ? <small>{exam.indication}</small> : null}</div>
        <div><span>Data clínica</span><strong>{formatDateTime(exam.relevant_at)}</strong></div>
        <div><span>Responsável</span><strong>{exam.responsible_name}</strong><small>{exam.responsible_position ?? "Cargo não informado"}</small></div>
        <div><span>Revisão</span><strong>{exam.reviewer_name ?? "—"}</strong>{exam.reviewer_position ? <small>{exam.reviewer_position}</small> : null}</div>
        <span className="exam-status" data-status={exam.status}>{EXAM_STATUS_LABELS[exam.status]}</span>
        <div className="patient-exam-actions">
          <button type="button" onClick={() => void openDetail(exam.id, exam.status === "completed")} disabled={detailLoadingId !== null}>{detailLoadingId === exam.id ? "Abrindo…" : exam.status === "completed" ? "Ver documento" : "Ver exame →"}</button>
          {exam.status === "completed" ? <ExamPngListAction examId={exam.id} label={`${exam.exam_type_name} de ${patient.name}`} /> : null}
        </div>
      </article>)}
    </div> : null}
    {data && data.total > data.pageSize ? <div className="patient-center-pagination"><button type="button" disabled={loading || data.page <= 1} onClick={() => void load(data.page - 1)}>← Anterior</button><span>Página <strong>{data.page}</strong> de {totalPages}</span><button type="button" disabled={loading || data.page >= totalPages} onClick={() => void load(data.page + 1)}>Próxima →</button></div> : null}

    {creating && references ? <ExamCreatePanel currentUserId={currentUserId} initialPatient={patient} references={references} onClose={() => setCreating(false)} onCreated={(examId) => { setCreating(false); void load(1); void openDetail(examId); }} /> : null}
    {detail ? <ExamDetailPanel key={`${detail.id}-${detail.updated_at}`} canPerform={false} canReview={false} currentUserId="" exam={detail} initialDocumentOpen={detailDocumentOpen} onClose={() => { setDetail(null); setDetailDocumentOpen(false); }} onChanged={async () => { await openDetail(detail.id, detailDocumentOpen); await load(data?.page ?? 1); }} readOnly /> : null}
  </div>;
}

function PatientExamSkeleton() {
  return <div className="patient-exam-skeleton" role="status" aria-label="Carregando exames"><i /><i /><i /></div>;
}

function addParam(params: URLSearchParams, key: string, value: unknown) {
  if (value !== undefined && value !== null && value !== "") params.set(key, String(value));
}

function optionalNumber(value: string) {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : undefined;
}

function hasFilters(filters: PatientClinicalExamFilters) {
  return Boolean(filters.categoryId || filters.examTypeId || filters.status || filters.dateFrom || filters.dateTo);
}

function messageOf(error: unknown) {
  return error instanceof Error ? error.message : "Não foi possível consultar os exames.";
}

function formatDateTime(value: string) {
  return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(value));
}
