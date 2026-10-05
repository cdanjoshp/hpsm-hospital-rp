"use client";

import { useState } from "react";
import type { PatientPortalHospitalizationPage } from "../lib/patient-portal";
import { formatPortalDate } from "../lib/patient-portal-format";

export function PatientPortalHospitalizations({ initialPage }: { initialPage: PatientPortalHospitalizationPage }) {
  const [data, setData] = useState(initialPage);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  async function load(page: number) {
    setLoading(true); setError("");
    try {
      const response = await fetch(`/api/patient-portal/hospitalizations?page=${page}`, { cache: "no-store" });
      if (response.status === 401) { window.location.assign("/portal-paciente"); return; }
      if (!response.ok) throw new Error("hospitalizations_unavailable");
      setData(await response.json() as PatientPortalHospitalizationPage);
    } catch { setError("Não foi possível carregar suas internações agora."); }
    finally { setLoading(false); }
  }
  return <div className="patient-portal-full-record-list" aria-busy={loading}>
    {!data.total ? <p className="patient-portal-empty patient-portal-empty-page">Nenhuma internação registrada no HPSM.</p> : data.items.map((item) => <article className="patient-portal-detail-card" key={item.id}>
      <header><div><p>{item.bedLabel} · Internação #{item.id}</p><h2>{formatPortalDate(item.admittedAt, true)}</h2></div><span className="patient-portal-status" data-status={item.status}>{item.status === "active" ? "Em andamento" : "Alta registrada"}</span></header>
      <dl className="patient-portal-detail-meta"><div><dt>Motivo</dt><dd>{item.reason}</dd></div><div><dt>Admissão</dt><dd>{item.admittedByName || "Equipe HPSM"}</dd></div>{item.dischargedAt ? <div><dt>Alta</dt><dd>{formatPortalDate(item.dischargedAt, true)}{item.dischargedByName ? ` · ${item.dischargedByName}` : ""}</dd></div> : null}</dl>
    </article>)}
    {error ? <p className="patient-portal-inline-error" role="alert">{error}</p> : null}
    {data.total > data.pageSize ? <div className="patient-portal-pagination" aria-label="Páginas de internações"><button type="button" disabled={loading || data.page <= 1} onClick={() => void load(data.page - 1)}>← Anterior</button><span>Página {data.page} de {Math.ceil(data.total / data.pageSize)}</span><button type="button" disabled={loading || data.page * data.pageSize >= data.total} onClick={() => void load(data.page + 1)}>Próxima →</button></div> : null}
  </div>;
}
