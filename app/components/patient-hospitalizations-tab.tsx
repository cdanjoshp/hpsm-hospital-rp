"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import type { HospitalizationRecord, HospitalizationSource, HospitalizationStatus } from "../lib/hospitalizations";

type Item = Pick<HospitalizationRecord, "admitted_at" | "admitted_by_name" | "bed_id" | "bed_label" | "cancellation_reason" | "cancelled_at" | "discharged_at" | "discharged_by_name" | "id" | "notes" | "reason" | "source" | "status">;
type Page = { items: Item[]; page: number; pageSize: number; total: number };
const STATUS: Record<HospitalizationStatus, string> = { active: "ATIVA", cancelled: "CANCELADA", discharged: "ALTA" };
const SOURCE: Record<HospitalizationSource, string> = { hpsm: "HPSM", hp_norte: "HP Norte" };

export function PatientHospitalizationsTab({ patientId }: { patientId: number }) {
  const [data, setData] = useState<Page | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  async function load(page: number) {
    setLoading(true); setError("");
    try {
      const response = await fetch(`/api/hospitalizations?view=patient&patientId=${patientId}&page=${page}&pageSize=10`, { cache: "no-store" });
      const payload = await response.json() as Page & { error?: string };
      if (!response.ok) throw new Error(payload.error ?? "Não foi possível carregar as internações.");
      setData(payload);
    } catch (cause) { setError(cause instanceof Error ? cause.message : "Não foi possível carregar as internações."); }
    finally { setLoading(false); }
  }
  useEffect(() => { const timer = window.setTimeout(() => void load(1), 0); return () => window.clearTimeout(timer); }, [patientId]); // eslint-disable-line react-hooks/exhaustive-deps
  if (loading && !data) return <div className="patient-exam-skeleton" role="status"><i /><i /><i /></div>;
  if (error && !data) return <p className="form-error" role="alert">{error}</p>;
  if (!data?.items.length) return <div className="empty-state"><span>▥</span><strong>Nenhuma internação registrada</strong><p>As internações HPSM deste paciente aparecerão aqui.</p><Link href="/internacoes">Abrir Internações e Leitos</Link></div>;
  const pages = Math.max(1, Math.ceil(data.total / data.pageSize));
  return <div className="patient-hospitalization-tab">
    <div className="patient-tab-title"><div><p className="eyebrow">Histórico assistencial</p><h3>Internações</h3></div><Link href="/internacoes">Abrir módulo completo →</Link></div>
    {error ? <p className="form-error" role="alert">{error}</p> : null}
    <div className="patient-hospitalization-list">{data.items.map((item) => <article key={item.id}>
      <div><strong>{item.bed_label}</strong><small>{SOURCE[item.source]} · IN-{String(item.id).padStart(6, "0")}</small></div>
      <div><strong>{item.reason}</strong><small>Entrada em {formatDateTime(item.admitted_at)}</small></div>
      <span data-status={item.status}>{STATUS[item.status]}</span>
    </article>)}</div>
    {data.total > data.pageSize ? <div className="bed-pagination"><button type="button" disabled={loading || data.page <= 1} onClick={() => void load(data.page - 1)}>← Anterior</button><span>Página {data.page} de {pages}</span><button type="button" disabled={loading || data.page >= pages} onClick={() => void load(data.page + 1)}>Próxima →</button></div> : null}
  </div>;
}

function formatDateTime(value: string) { return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(value)); }
