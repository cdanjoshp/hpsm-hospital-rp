"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import type { MedicalCertificateStatus } from "../lib/medical-certificates";

type Item = {
  attendance_id: number;
  cancelled_at: string | null;
  created_at: string;
  document_ready: boolean;
  finalized_at: string | null;
  id: number;
  leave_days: number;
  professional_name: string;
  professional_position: string | null;
  status: MedicalCertificateStatus;
};
type Page = { items: Item[]; page: number; pageSize: number; total: number };
const STATUS_LABEL: Record<MedicalCertificateStatus, string> = { cancelled: "Cancelado", draft: "Rascunho", finalized: "Finalizado" };

export function PatientMedicalCertificatesTab({ patientId }: { patientId: number }) {
  const [data, setData] = useState<Page | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  async function load(page: number) {
    setLoading(true); setError("");
    try {
      const response = await fetch(`/api/medical-certificates?view=patient&patientId=${patientId}&page=${page}&pageSize=10`, { cache: "no-store" });
      const payload = await response.json() as Page & { error?: string };
      if (!response.ok) throw new Error(payload.error ?? "Não foi possível carregar os atestados.");
      setData(payload);
    } catch (cause) { setError(cause instanceof Error ? cause.message : "Não foi possível carregar os atestados."); }
    finally { setLoading(false); }
  }
  useEffect(() => {
    const timer = window.setTimeout(() => void load(1), 0);
    return () => window.clearTimeout(timer);
  }, [patientId]); // eslint-disable-line react-hooks/exhaustive-deps
  if (loading && !data) return <div className="patient-exam-skeleton" role="status"><i /><i /><i /></div>;
  if (error && !data) return <p className="form-error" role="alert">{error}</p>;
  if (!data?.items.length) return <div className="empty-state"><span>▤</span><strong>Nenhum atestado registrado</strong><p>Os atestados vinculados aos atendimentos deste paciente aparecerão aqui.</p><Link href="/atestados">Abrir Atestados Médicos</Link></div>;
  const pages = Math.max(1, Math.ceil(data.total / data.pageSize));
  return <div className="patient-certificate-tab">
    <div className="patient-tab-title"><div><p className="eyebrow">Documentos clínicos</p><h3>Atestados Médicos</h3></div><Link href="/atestados">Abrir módulo completo →</Link></div>
    {error ? <p className="form-error" role="alert">{error}</p> : null}
    <div className="patient-certificate-list">{data.items.map((item) => <article key={item.id}>
      <div><strong>{certificateCode(item.id)}</strong><small>Atendimento #{item.attendance_id}</small></div>
      <div><strong>{item.leave_days} {item.leave_days === 1 ? "dia" : "dias"}</strong><small>{item.professional_name} · {item.professional_position ?? "Cargo não informado"}</small></div>
      <time>{formatDateTime(item.finalized_at ?? item.created_at)}</time>
      <span className="certificate-status" data-status={item.status}>{STATUS_LABEL[item.status]}</span>
      <div>{item.status === "finalized" ? <a href={`/api/medical-certificates/document?id=${item.id}&download=1`}>Baixar imagem</a> : <Link href={`/atestados?registro=${item.id}`}>Visualizar</Link>}</div>
    </article>)}</div>
    <div className="certificate-pagination"><button type="button" disabled={loading || data.page <= 1} onClick={() => void load(data.page - 1)}>← Anterior</button><span>Página {data.page} de {pages}</span><button type="button" disabled={loading || data.page >= pages} onClick={() => void load(data.page + 1)}>Próxima →</button></div>
  </div>;
}

function certificateCode(id: number) { return `AT-${String(id).padStart(6, "0")}`; }
function formatDateTime(value: string) { return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(value)); }
