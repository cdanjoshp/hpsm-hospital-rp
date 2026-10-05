"use client";

import Link from "next/link";
import { useState } from "react";
import type {
  PatientPortalExamFilter,
  PatientPortalExamListItem,
  PatientPortalExamPage,
  PatientPortalExamStatus,
} from "../lib/patient-portal";
import { formatPortalDate } from "../lib/patient-portal-format";

const FILTERS: Array<{ key: PatientPortalExamFilter; label: string }> = [
  { key: "all", label: "Todos" },
  { key: "in_progress", label: "Em andamento" },
  { key: "completed", label: "Concluídos" },
];

const STATUS_LABELS: Record<PatientPortalExamStatus, string> = {
  awaiting_review: "Em finalização",
  completed: "Concluído",
  in_progress: "Em andamento",
  requested: "Solicitado",
};

export function PatientPortalExamList({ initialPage }: { initialPage: PatientPortalExamPage }) {
  const [filter, setFilter] = useState<PatientPortalExamFilter>("all");
  const [items, setItems] = useState(initialPage.items);
  const [cursor, setCursor] = useState(initialPage.nextCursor);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  async function selectFilter(nextFilter: PatientPortalExamFilter) {
    if (nextFilter === filter || loading) return;
    setLoading(true);
    setError("");
    try {
      const page = await fetchPage(nextFilter);
      setFilter(nextFilter);
      setItems(page.items);
      setCursor(page.nextCursor);
    } catch (requestError) {
      if (requestError === "unauthorized") return window.location.assign("/portal-paciente");
      setError("Não foi possível aplicar este filtro agora.");
    } finally {
      setLoading(false);
    }
  }

  async function loadMore() {
    if (!cursor || loading) return;
    setLoading(true);
    setError("");
    try {
      const page = await fetchPage(filter, cursor);
      setItems((current) => {
        const known = new Set(current.map((item) => item.id));
        return [...current, ...page.items.filter((item) => !known.has(item.id))];
      });
      setCursor(page.nextCursor);
    } catch (requestError) {
      if (requestError === "unauthorized") return window.location.assign("/portal-paciente");
      setError("Não foi possível carregar mais exames agora.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="patient-portal-exams-wrap">
      <div className="patient-portal-exam-filters" role="group" aria-label="Filtrar exames">
        {FILTERS.map((item) => (
          <button
            aria-pressed={filter === item.key}
            disabled={loading}
            key={item.key}
            onClick={() => void selectFilter(item.key)}
            type="button"
          >{item.label}</button>
        ))}
      </div>

      {items.length ? (
        <div className="patient-portal-exam-list" aria-busy={loading}>
          {items.map((exam) => <ExamCard exam={exam} key={exam.id} />)}
        </div>
      ) : <p className="patient-portal-empty patient-portal-empty-page">Nenhum exame encontrado neste filtro.</p>}

      {error ? <p className="patient-portal-inline-error" role="alert">{error}</p> : null}
      {cursor ? <button className="patient-portal-load-more" disabled={loading} onClick={() => void loadMore()} type="button">{loading ? "Carregando…" : "Carregar mais"}</button> : null}
    </div>
  );
}

function ExamCard({ exam }: { exam: PatientPortalExamListItem }) {
  return (
    <article>
      <div className="patient-portal-exam-card-copy">
        <div className="patient-portal-exam-card-heading">
          <p>{exam.category}</p>
          <span className="patient-portal-status" data-status={exam.status}>{STATUS_LABELS[exam.status]}</span>
        </div>
        <h2>{exam.type}</h2>
        <time dateTime={exam.occurredAt}>Solicitado em {formatPortalDate(exam.occurredAt, true)}</time>
        {exam.completedAt ? <small>Concluído em {formatPortalDate(exam.completedAt, true)}</small> : null}
      </div>
      <Link href={`/portal-paciente/exames/${exam.id}`} prefetch={false}>
        {exam.status === "completed" ? "Ver resultado" : "Ver detalhes"}
      </Link>
    </article>
  );
}

async function fetchPage(
  filter: PatientPortalExamFilter,
  cursor?: { id: number; occurredAt: string } | null,
) {
  const query = new URLSearchParams({ filter });
  if (cursor) {
    query.set("cursorAt", cursor.occurredAt);
    query.set("cursorId", String(cursor.id));
  }
  const response = await fetch(`/api/patient-portal/exams?${query}`, { cache: "no-store" });
  if (response.status === 401) throw "unauthorized";
  if (!response.ok) throw new Error("exam_request_failed");
  return await response.json() as PatientPortalExamPage;
}
