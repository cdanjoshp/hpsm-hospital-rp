"use client";

import { useState } from "react";
import type { PatientPortalMedicalCertificatePage } from "../lib/patient-portal";
import { formatPortalDate } from "./patient-portal-shell";

export function PatientPortalMedicalCertificates({ initialPage }: { initialPage: PatientPortalMedicalCertificatePage }) {
  const [page, setPage] = useState(initialPage);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const totalPages = Math.max(1, Math.ceil(page.total / page.pageSize));
  async function load(next: number) {
    setLoading(true); setError("");
    try {
      const response = await fetch(`/api/patient-portal/medical-certificates?page=${next}`, { cache: "no-store" });
      const payload = await response.json() as PatientPortalMedicalCertificatePage & { error?: string };
      if (!response.ok) throw new Error(payload.error ?? "Não foi possível carregar os atestados.");
      setPage(payload);
    } catch (cause) { setError(cause instanceof Error ? cause.message : "Não foi possível carregar os atestados."); }
    finally { setLoading(false); }
  }
  return <section className="patient-portal-certificates" aria-busy={loading}>
    {error ? <p className="patient-portal-inline-error" role="alert">{error}</p> : null}
    {page.items.length ? <div className="patient-portal-certificate-list">{page.items.map((item) => <article key={item.id}>
      <div><p>Atestado {certificateCode(item.id)}</p><strong>{item.leaveDays} {item.leaveDays === 1 ? "dia" : "dias"}</strong><small>Finalizado em {formatPortalDate(item.finalizedAt)}</small></div>
      <div><span>Profissional responsável</span><strong>{item.professionalName}</strong><small>{item.professionalPosition ?? "Cargo não informado"}</small></div>
      <div><span>Origem</span><strong>{item.attendanceId ? `Atendimento #${item.attendanceId}` : "Consulta clínica"}</strong></div>
      <a href={`/api/patient-portal/medical-certificates/${item.id}/document`}>Baixar imagem</a>
    </article>)}</div> : <div className="patient-portal-empty"><span aria-hidden="true">▤</span><h2>Nenhum atestado finalizado</h2><p>Somente documentos finalizados e válidos aparecem no Portal do Paciente.</p></div>}
    <div className="patient-portal-pagination"><button type="button" disabled={loading || page.page <= 1} onClick={() => void load(page.page - 1)}>← Anterior</button><span>Página {page.page} de {totalPages}</span><button type="button" disabled={loading || page.page >= totalPages} onClick={() => void load(page.page + 1)}>Próxima →</button></div>
  </section>;
}

function certificateCode(id: number) { return `AT-${String(id).padStart(6, "0")}`; }
