"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import type { ConsultationPage, ConsultationScheduleItem } from "../lib/consultations";

const STATUS: Record<ConsultationScheduleItem["status"], string> = {
  scheduled: "Agendada", confirmed: "Confirmada", in_progress: "Em andamento",
  completed: "Concluída", cancelled: "Cancelada", no_show: "Não compareceu",
};

export function PatientConsultationsTab({ patientId, passport }: { patientId: number; passport: string }) {
  const [page, setPage] = useState(1);
  const [data, setData] = useState<ConsultationPage | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    const controller = new AbortController();
    async function load() {
      setLoading(true); setData(null); setError("");
      try {
        const params = new URLSearchParams({ view: "list", search: passport, page: String(page), pageSize: "50" });
        const response = await fetch(`/api/consultations?${params}`, { cache: "no-store", signal: controller.signal });
        const payload = await response.json() as ConsultationPage & { error?: string };
        if (!response.ok) throw new Error(payload.error ?? "Não foi possível carregar as consultas.");
        if (!controller.signal.aborted) setData(payload);
      } catch (cause) {
        if (!controller.signal.aborted) setError(cause instanceof Error ? cause.message : "Não foi possível carregar as consultas.");
      } finally { if (!controller.signal.aborted) setLoading(false); }
    }
    void load();
    return () => controller.abort();
  }, [page, passport]);

  const items = data?.items.filter((item) => item.patient_id === patientId && item.patient_passport === passport) ?? [];
  const pageCount = Math.max(1, Math.ceil((data?.total ?? 0) / 50));
  return <div className="patient-v3-consultations" aria-busy={loading}>
    <p className="patient-v3-section-copy">Consultas por demanda espontânea, agendamentos e situações de comparecimento.</p>
    {error ? <p className="form-error" role="alert">{error}</p> : null}
    {loading && !data ? <div className="patient-exam-skeleton" role="status"><i /><i /><i /></div> : null}
    {!loading && data && !items.length ? <div className="empty-state"><strong>Nenhuma consulta nesta página</strong><p>{pageCount > 1 ? "Avance para consultar outros registros." : "As consultas e os agendamentos aparecerão aqui."}</p></div> : null}
    {items.map((item) => <article className="patient-v3-consultation" key={`${item.appointment_id ?? "walk-in"}-${item.consultation_id ?? item.created_at}`}>
      <div><span>Consulta médica · {formatDateTime(item.starts_at)}</span><h4>{item.reason}</h4><p>{item.professional_name}{item.walk_in ? " · demanda espontânea" : " · agendada"}</p></div>
      <div className="patient-v3-consultation-actions"><span data-status={item.status}>{STATUS[item.status]}</span><Link href={item.consultation_id ? `/consultas/${item.consultation_id}` : `/consultas?agendamento=${item.appointment_id}&paciente=${encodeURIComponent(passport)}`}>{item.consultation_id ? "Abrir consulta →" : "Abrir agendamento →"}</Link></div>
    </article>)}
    {data && pageCount > 1 ? <div className="patient-center-pagination"><button type="button" disabled={loading || page === 1} onClick={() => setPage((current) => current - 1)}>← Anterior</button><span>Página {page} de {pageCount}</span><button type="button" disabled={loading || page >= pageCount} onClick={() => setPage((current) => current + 1)}>Próxima →</button></div> : null}
  </div>;
}

function formatDateTime(value: string) {
  return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(value));
}
