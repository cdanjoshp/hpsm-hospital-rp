"use client";

import { useState } from "react";
import type { PatientPortalLegacyHistoryPage, PatientPortalLegacyRecordType } from "../lib/patient-portal";
import { formatPortalDate } from "../lib/patient-portal-format";

const FILTERS: Array<{ code: PatientPortalLegacyRecordType | "all"; label: string }> = [
  { code: "all", label: "Todos" }, { code: "registration", label: "Cadastro" },
  { code: "attendance", label: "Atendimentos" }, { code: "exam", label: "Exames" },
  { code: "vaccine", label: "Vacinas" }, { code: "appointment", label: "Agendamentos" },
  { code: "health_plan", label: "Plano de saúde" },
];
export function PatientPortalLegacyHistory({ initialPage }: { initialPage: PatientPortalLegacyHistoryPage }) {
  const [data, setData] = useState(initialPage);
  const [filter, setFilter] = useState<PatientPortalLegacyRecordType | "all">("all");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  async function load(page: number, type: PatientPortalLegacyRecordType | "all") {
    setLoading(true); setError("");
    try {
      const params = new URLSearchParams({ page: String(page) });
      if (type !== "all") params.set("recordType", type);
      const response = await fetch(`/api/patient-portal/legacy-history?${params}`, { cache: "no-store" });
      if (response.status === 401) { window.location.assign("/portal-paciente"); return; }
      if (!response.ok) throw new Error("legacy_unavailable");
      setData(await response.json() as PatientPortalLegacyHistoryPage); setFilter(type);
    } catch { setError("Não foi possível carregar o histórico HP Norte agora."); }
    finally { setLoading(false); }
  }
  return <div className="patient-portal-full-record-list" aria-busy={loading}>
    <div className="patient-portal-record-filters" role="group" aria-label="Filtrar histórico HP Norte">{FILTERS.map((item) => <button key={item.code} type="button" aria-pressed={filter === item.code} disabled={loading} onClick={() => void load(1, item.code)}>{item.label} <span>{item.code === "all" ? Object.values(data.summary).reduce((total, count) => total + count, 0) : data.summary[item.code] ?? 0}</span></button>)}</div>
    {!data.items.length ? <p className="patient-portal-empty patient-portal-empty-page">Nenhum registro HP Norte neste filtro.</p> : data.items.map((item) => <article className="patient-portal-detail-card" key={item.id}>
      <header><div><p>{FILTERS.find((option) => option.code === item.recordType)?.label} · HP Norte</p><h2>{item.title}</h2></div><span>{item.occurredAt ? formatPortalDate(item.occurredAt, item.occurredPrecision === "datetime") : "Data não informada"}</span></header>
      {item.summary ? <p>{item.summary}</p> : null}
      {item.professionalName ? <p>Profissional: {item.professionalName}{item.professionalRegistration ? ` · ${item.professionalRegistration}` : ""}</p> : null}
      {item.status ? <p>Situação: {item.status.replaceAll("_", " ")}</p> : null}
      {Object.keys(item.details).length || item.referenceLinks.length ? <details className="patient-portal-record-details"><summary>Ver dados preservados</summary>
        {Object.keys(item.details).length ? <dl>{Object.entries(item.details).filter(([, value]) => value !== null && value !== "").map(([key, value]) => <div key={key}><dt>{key.replaceAll("_", " ")}</dt><dd>{formatValue(value)}</dd></div>)}</dl> : null}
        {item.referenceLinks.map(referenceLink).filter((link): link is { href: string; label: string } => Boolean(link)).map((link) => <a href={link.href} key={link.href} rel="noopener noreferrer" target="_blank">{link.label} ↗</a>)}
      </details> : null}
    </article>)}
    {error ? <p className="patient-portal-inline-error" role="alert">{error}</p> : null}
    {data.total > data.pageSize ? <div className="patient-portal-pagination" aria-label="Páginas do histórico HP Norte"><button type="button" disabled={loading || data.page <= 1} onClick={() => void load(data.page - 1, filter)}>← Anterior</button><span>Página {data.page} de {Math.ceil(data.total / data.pageSize)}</span><button type="button" disabled={loading || data.page * data.pageSize >= data.total} onClick={() => void load(data.page + 1, filter)}>Próxima →</button></div> : null}
  </div>;
}
function formatValue(value: unknown) { return typeof value === "string" || typeof value === "number" ? String(value) : typeof value === "boolean" ? value ? "Sim" : "Não" : JSON.stringify(value); }
function referenceLink(value: unknown, index: number) {
  const record = value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : null;
  const href = typeof value === "string" ? value : typeof record?.href === "string" ? record.href : typeof record?.url === "string" ? record.url : "";
  try { const url = new URL(href); if (url.protocol !== "https:" && url.protocol !== "http:") return null;
    return { href: url.toString(), label: typeof record?.label === "string" ? record.label : typeof record?.title === "string" ? record.title : `Referência ${index + 1}` };
  } catch { return null; }
}
