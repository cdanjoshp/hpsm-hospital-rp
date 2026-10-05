"use client";

import Link from "next/link";
import dynamic from "next/dynamic";
import { useEffect, useState } from "react";
import type { ClinicalExamDetail } from "../lib/exams";
import type { PatientRecord, PatientRecordFilter, PatientRecordPage } from "../lib/patient-center";
import { ExamPageActions } from "./exam-page-actions";
import { DocumentImageViewer } from "./document-image-viewer";
import { PatientLegacyHistoryTab } from "./patient-legacy-history-tab";
import { PatientConsultationsTab } from "./patient-consultations-tab";
const ExamDetailPanel = dynamic(() => import("./exam-center").then((module) => module.ExamDetailPanel));

const TIMELINE_FILTERS: Array<{ code: PatientRecordFilter; label: string }> = [
  { code: "all", label: "Todos" }, { code: "attendance", label: "Atendimentos" },
  { code: "procedure", label: "Procedimentos" }, { code: "purchase", label: "Compras" },
  { code: "exam", label: "Exames" }, { code: "certificate", label: "Atestados" },
  { code: "prescription", label: "Receitas" }, { code: "record", label: "Prontuários" },
  { code: "cast", label: "Gessos" }, { code: "hospitalization", label: "Internações" },
  { code: "plan", label: "Plano de Saúde" },
];
const DOCUMENT_FILTERS = TIMELINE_FILTERS.filter(({ code }) => ["all", "exam", "certificate", "prescription", "record"].includes(code));
const TIMELINE_PRIMARY = TIMELINE_FILTERS.filter(({ code }) => ["all", "attendance", "purchase", "exam", "certificate", "cast"].includes(code));
const TIMELINE_MORE = TIMELINE_FILTERS.filter(({ code }) => ["procedure", "hospitalization", "plan", "prescription", "record"].includes(code));
type ViewFilter = PatientRecordFilter | "consultations";

export function PatientRecordsTab({ mode, patientId, passport, initialFilter = "all" }: { mode: "timeline" | "documents"; patientId: number; passport?: string; initialFilter?: PatientRecordFilter }) {
  const [page, setPage] = useState<PatientRecordPage | null>(null);
  const [filter, setFilter] = useState<ViewFilter>(initialFilter);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [legacyOpen, setLegacyOpen] = useState(false);
  async function load(nextPage: number, nextFilter: PatientRecordFilter, signal?: AbortSignal) {
    setLoading(true); setError("");
    try {
      const params = new URLSearchParams({ patientId: String(patientId), view: mode === "timeline" ? "timeline-page" : "documents", filter: nextFilter, page: String(nextPage), pageSize: "10" });
      const response = await fetch(`/api/patient-center?${params}`, { cache: "no-store", signal });
      const payload = await response.json() as PatientRecordPage & { error?: string };
      if (!response.ok) throw new Error(payload.error ?? "Não foi possível consultar os registros.");
      if (!signal?.aborted) setPage(payload);
    } catch (cause) {
      if (!signal?.aborted) setError(cause instanceof Error ? cause.message : "Não foi possível consultar os registros.");
    } finally { if (!signal?.aborted) setLoading(false); }
  }
  useEffect(() => {
    if (filter === "consultations") return;
    const controller = new AbortController();
    const timer = window.setTimeout(() => void load(1, filter, controller.signal), 0);
    return () => { window.clearTimeout(timer); controller.abort(); };
  }, [patientId, mode, filter]); // eslint-disable-line react-hooks/exhaustive-deps
  const filters = mode === "documents" ? DOCUMENT_FILTERS : TIMELINE_PRIMARY;
  const moreSelected = TIMELINE_MORE.some((item) => item.code === filter);
  return <div className="patient-records-section">
    <div className="patient-tab-title"><div><p className="eyebrow">{mode === "documents" ? "Arquivos institucionais" : "Linha do tempo"}</p><h3>{mode === "documents" ? "Documentos" : "Registros do paciente"}</h3></div>{mode === "timeline" && filter !== "consultations" && page ? <span className="patient-v3-total">{page.total} registro(s)</span> : null}</div>
    <div className="patient-timeline-filters patient-v3-filters" role="group" aria-label="Filtrar registros">
      {filters.map((item) => <button key={item.code} aria-pressed={filter === item.code} data-active={filter === item.code} onClick={() => { setPage(null); setFilter(item.code); }} type="button">{item.code === "all" ? "Todos" : item.code === "purchase" ? "Vendas / compras" : item.label}</button>)}
      {mode === "timeline" && passport ? <button aria-pressed={filter === "consultations"} data-active={filter === "consultations"} onClick={() => { setPage(null); setFilter("consultations"); }} type="button">Consultas</button> : null}
      {mode === "timeline" ? <select aria-label="Outros registros" value={moreSelected ? filter : ""} onChange={(event) => { if (event.target.value) { setPage(null); setFilter(event.target.value as PatientRecordFilter); } }}><option value="">Outros registros</option>{TIMELINE_MORE.map((item) => <option key={item.code} value={item.code}>{item.label}</option>)}</select> : null}
    </div>
    {filter === "consultations" && passport ? <PatientConsultationsTab patientId={patientId} passport={passport} /> : null}
    {filter !== "consultations" && error ? <p className="form-error" role="alert">{error}</p> : null}
    {filter !== "consultations" && loading && !page ? <div className="patient-exam-skeleton" role="status"><i /><i /><i /></div> : null}
    {filter !== "consultations" && !loading && page?.items.length === 0 ? <div className="empty-state"><strong>Nenhum registro nesta categoria</strong><p>Os registros aparecerão conforme forem concluídos nos módulos de origem.</p></div> : null}
    {filter !== "consultations" && page?.items.length ? <div className="patient-record-list">{page.items.map((item) => <PatientRecordRow item={item} key={item.id} />)}</div> : null}
    {filter !== "consultations" && page && page.total > page.pageSize ? <div className="patient-center-pagination">
      <button disabled={loading || page.page <= 1} onClick={() => void load(page.page - 1, filter as PatientRecordFilter)} type="button">← Anterior</button>
      <span>Página <strong>{page.page}</strong> de {Math.ceil(page.total / page.pageSize)} · {page.total} registros</span>
      <button disabled={loading || page.page * page.pageSize >= page.total} onClick={() => void load(page.page + 1, filter as PatientRecordFilter)} type="button">Próxima →</button>
    </div> : null}
    {mode === "documents" ? <section className="patient-record-legacy-link"><button type="button" onClick={() => setLegacyOpen((current) => !current)} aria-expanded={legacyOpen}>{legacyOpen ? "Ocultar" : "Ver"} exames e anexos históricos HP Norte</button>{legacyOpen ? <PatientLegacyHistoryTab patientId={patientId} documentsOnly /> : null}</section> : null}
  </div>;
}

function PatientRecordRow({ item }: { item: PatientRecord }) {
  const [exam, setExam] = useState<ClinicalExamDetail | null>(null);
  const [opening, setOpening] = useState(false);
  const [error, setError] = useState("");
  const destination = item.resource_kind === "attendance" ? "/atendimentos" : item.resource_kind === "cast" ? `/gessos?registro=${item.resource_id}` : item.resource_kind === "hospitalization" ? "/internacoes" : null;
  async function openExam() {
    setOpening(true); setError("");
    try {
      const response = await fetch(`/api/exams?view=detail&id=${item.resource_id}`, { cache: "no-store" });
      const payload = await response.json() as { exam?: ClinicalExamDetail; error?: string };
      if (!response.ok || !payload.exam) throw new Error(payload.error ?? "Não foi possível abrir o exame.");
      setExam(payload.exam);
    } catch (cause) { setError(cause instanceof Error ? cause.message : "Não foi possível abrir o exame."); }
    finally { setOpening(false); }
  }
  return <details className="patient-record-row patient-v3-record">
    <summary><span className="patient-v3-record-marker" aria-hidden="true">{recordIcon(item.category)}</span><span className="patient-v3-record-copy"><small>{label(item.category)} · {formatDateTime(item.date)}</small><strong>{item.title}</strong><span>{item.description}</span></span><span className="patient-v3-record-open">Ver detalhes⌄</span></summary>
    <div className="patient-v3-record-detail"><div className="patient-record-actions">
      {item.document && item.resource_kind === "exam" ? <ExamPageActions examId={Number(item.resource_id)} label={item.title} initialPageCount={null} /> : null}
      {item.resource_kind === "exam" ? <button disabled={opening} onClick={() => void openExam()} type="button">{opening ? "Abrindo…" : "Abrir exame"}</button> : null}
      {item.document && ["certificate", "record", "prescription"].includes(item.resource_kind) ? <PatientDocumentActions item={item} /> : null}
      {destination ? <Link href={destination}>Abrir módulo →</Link> : null}
    </div></div>
    {error ? <small role="alert">{error}</small> : null}
    {exam ? <ExamDetailPanel canPerform={false} canReview={false} currentUserId="" exam={exam} onClose={() => setExam(null)} onChanged={async () => void openExam()} readOnly /> : null}
  </details>;
}

function recordIcon(category: PatientRecord["category"]) {
  return ({ attendance: "✚", procedure: "＋", purchase: "$", exam: "▣", certificate: "▤", prescription: "▤", record: "▤", cast: "◇", hospitalization: "▥", plan: "◇" })[category];
}

function PatientDocumentActions({ item }: { item: PatientRecord }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [viewer, setViewer] = useState("");
  const id = Number(item.resource_id);
  const base = item.resource_kind === "certificate" ? "/api/medical-certificates/document" : item.resource_kind === "record" ? "/api/consultations/document" : "/api/consultations/prescription/document";
  const image = `${base}?id=${id}${item.resource_kind === "certificate" ? "" : "&inline=1"}`;
  const download = `${base}?id=${id}&download=1`;
  async function copy() {
    setBusy(true); setError(""); setNotice("");
    try {
      const response = await fetch(item.resource_kind === "certificate" ? base : `${base}?id=${id}`, item.resource_kind === "certificate" ? { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ certificateId: id }) } : { cache: "no-store" });
      // Document endpoints already enforce the source permission and return the published link.
      const state = await response.json() as { error?: string; shareUrl?: string | null };
      if (!response.ok || !state.shareUrl) throw new Error(state.error ?? "O link deste documento ainda não está disponível.");
      await navigator.clipboard.writeText(state.shareUrl);
      void fetch(base, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(item.resource_kind === "certificate" ? { certificateId: id, action: "link-copied" } : { consultationId: id, action: "link-copied" }) }).catch(() => undefined);
      setNotice("Link copiado.");
    } catch (cause) { setError(cause instanceof Error ? cause.message : "Não foi possível copiar o link."); }
    finally { setBusy(false); }
  }
  return <><button disabled={busy} onClick={() => setViewer(image)} type="button">Visualizar</button><button disabled={busy} onClick={() => void copy()} type="button">{busy ? "Preparando…" : "Copiar link"}</button>
    {error ? <small role="alert">{error}</small> : null}{notice ? <small role="status">{notice}</small> : null}
    {viewer ? <DocumentImageViewer title={item.title} imageUrl={viewer} downloadUrl={download} onClose={() => setViewer("")} /> : null}
  </>;
}

function label(category: PatientRecord["category"]) { return TIMELINE_FILTERS.find((item) => item.code === category)?.label ?? "Registro"; }
function formatDateTime(date: string) { return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(date)); }
