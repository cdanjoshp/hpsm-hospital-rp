"use client";

import { useEffect, useState } from "react";
import type {
  PatientLegacyHistoryItem,
  PatientLegacyHistoryPage,
  PatientLegacyRecordType,
} from "../lib/patient-center";

type LegacyFilter = "all" | PatientLegacyRecordType;

const FILTERS: Array<{ code: LegacyFilter; label: string }> = [
  { code: "all", label: "Todos" },
  { code: "registration", label: "Cadastro" },
  { code: "attendance", label: "Atendimentos" },
  { code: "exam", label: "Exames" },
  { code: "vaccine", label: "Vacinas" },
  { code: "appointment", label: "Agendamentos" },
  { code: "health_plan", label: "Plano de saúde" },
];

const TYPE_LABELS: Record<PatientLegacyRecordType, string> = {
  appointment: "Agendamento",
  attendance: "Atendimento",
  exam: "Exame",
  health_plan: "Plano de saúde",
  registration: "Cadastro",
  vaccine: "Vacina",
};

export function PatientLegacyHistoryTab({ patientId, documentsOnly = false }: { patientId: number; documentsOnly?: boolean }) {
  const [data, setData] = useState<PatientLegacyHistoryPage | null>(null);
  const [error, setError] = useState("");
  const [filter, setFilter] = useState<LegacyFilter>(documentsOnly ? "exam" : "all");
  const [loading, setLoading] = useState(true);
  const [page, setPage] = useState(1);

  useEffect(() => {
    const controller = new AbortController();
    async function load() {
      setLoading(true);
      setError("");
      try {
        const params = new URLSearchParams({
          page: String(page),
          pageSize: "20",
          patientId: String(patientId),
          view: "legacy",
        });
        if (filter !== "all") params.set("recordType", filter);
        const response = await fetch(`/api/patient-center?${params}`, {
          cache: "no-store",
          signal: controller.signal,
        });
        const payload = await response.json() as PatientLegacyHistoryPage & { error?: string };
        if (!response.ok) throw new Error(payload.error ?? "Não foi possível carregar o histórico HP Norte.");
        setData(payload);
      } catch (cause) {
        if (cause instanceof DOMException && cause.name === "AbortError") return;
        setError(cause instanceof Error ? cause.message : "Não foi possível carregar o histórico HP Norte.");
      } finally {
        if (!controller.signal.aborted) setLoading(false);
      }
    }
    void load();
    return () => controller.abort();
  }, [filter, page, patientId]);

  function selectFilter(value: LegacyFilter) {
    setFilter(value);
    setPage(1);
  }

  const totalPages = Math.max(1, Math.ceil((data?.total ?? 0) / (data?.pageSize ?? 20)));

  return <div className="patient-legacy-tab" aria-busy={loading}>
    <header className="patient-legacy-heading">
      <div>
        <p className="eyebrow">Histórico importado · somente leitura</p>
        <h3>{documentsOnly ? "Exames e anexos históricos HP Norte" : "Registros do HP Norte"}</h3>
        <p>Dados preservados da unidade de origem, com arquivos de referência quando disponíveis.</p>
      </div>
      <span className="patient-legacy-source">HP Norte</span>
    </header>

    {data ? <div className="patient-legacy-summary">
      <article><span>Registros encontrados</span><strong>{data.total}</strong><small>no filtro selecionado</small></article>
      <article><span>Cadastros de origem</span><strong>{data.sourceProfiles}</strong><small>vínculo(s) importado(s)</small></article>
      <article><span>Tipos preservados</span><strong>{Object.values(data.summary).filter((value) => Number(value) > 0).length}</strong><small>categorias com registros</small></article>
    </div> : null}

    {!documentsOnly ? <div className="patient-legacy-filters" role="group" aria-label="Filtrar histórico importado">
      {FILTERS.map((item) => {
        const count = item.code === "all"
          ? Object.values(data?.summary ?? {}).reduce((total, value) => total + Number(value ?? 0), 0)
          : Number(data?.summary[item.code] ?? 0);
        return <button key={item.code} type="button" data-active={filter === item.code} onClick={() => selectFilter(item.code)}>
          {item.label}<span>{count}</span>
        </button>;
      })}
    </div> : null}

    {error ? <p className="form-error" role="alert">{error}</p> : null}
    {loading ? <div className="patient-tab-loading" role="status"><span /><p>Carregando registros importados…</p></div> : null}

    {!loading && data?.items.length ? <div className="patient-legacy-list">
      {data.items.map((item) => <LegacyRecord item={item} key={item.id} />)}
    </div> : null}

    {!loading && data && !data.items.length ? <div className="empty-state">
      <span>◇</span>
      <strong>{data.sourceProfiles ? "Nenhum registro neste filtro" : "Paciente sem histórico HP Norte"}</strong>
      <p>{data.sourceProfiles ? "Escolha outro tipo para consultar os registros importados." : "Não há vínculo importado da unidade HP Norte para este paciente."}</p>
    </div> : null}

    {!loading && data && totalPages > 1 ? <div className="patient-center-pagination" aria-label="Paginação do histórico HP Norte">
      <button type="button" disabled={page <= 1} onClick={() => setPage((current) => Math.max(1, current - 1))}>← Anterior</button>
      <span>Página <strong>{page}</strong> de {totalPages}</span>
      <button type="button" disabled={page >= totalPages} onClick={() => setPage((current) => current + 1)}>Próxima →</button>
    </div> : null}
  </div>;
}

function LegacyRecord({ item }: { item: PatientLegacyHistoryItem }) {
  const details = Object.entries(item.details ?? {}).filter(([, value]) => value !== null && value !== "");
  const links = (item.reference_links ?? []).map(toReferenceLink).filter((link): link is { href: string; label: string } => Boolean(link));

  return <article className="patient-legacy-record">
    <div className="patient-legacy-marker" data-type={item.record_type} aria-hidden="true">◇</div>
    <div className="patient-legacy-record-main">
      <div className="patient-legacy-record-meta">
        <span>{TYPE_LABELS[item.record_type]}</span>
        <time>{formatLegacyDate(item.occurred_at, item.occurred_precision)}</time>
        {item.status ? <em>{statusLabel(item.status)}</em> : null}
      </div>
      <h4>{item.title}</h4>
      {item.summary ? <p>{item.summary}</p> : null}
      {item.professional_name ? <small>Profissional: <strong>{item.professional_name}</strong>{item.professional_registration ? ` · ${item.professional_registration}` : ""}</small> : null}
      {details.length || links.length ? <details>
        <summary>Ver dados preservados</summary>
        {details.length ? <dl>
          {details.map(([key, value]) => <div key={key}><dt>{fieldLabel(key)}</dt><dd>{formatLegacyValue(value)}</dd></div>)}
        </dl> : null}
        {links.length ? <div className="patient-legacy-links">
          {links.map((link) => <a href={link.href} key={link.href} rel="noreferrer" target="_blank">{link.label} ↗</a>)}
        </div> : null}
      </details> : null}
    </div>
  </article>;
}

function formatLegacyDate(value: string | null, precision: PatientLegacyHistoryItem["occurred_precision"]) {
  if (!value || precision === "unknown") return "Data não informada";
  const date = new Date(value);
  if (Number.isNaN(date.valueOf())) return "Data não informada";
  const formatted = new Intl.DateTimeFormat("pt-BR", {
    day: "2-digit",
    month: "2-digit",
    timeZone: "America/Sao_Paulo",
    year: "numeric",
    ...(precision === "datetime" ? { hour: "2-digit", minute: "2-digit" } : {}),
  }).format(date);
  return precision === "datetime" ? formatted.replace(",", " às") : formatted;
}

function statusLabel(value: string) {
  const labels: Record<string, string> = {
    active: "Ativo",
    approved: "Aprovado",
    cancelled: "Cancelado",
    completed: "Concluído",
    done: "Concluído",
    expired: "Expirado",
    inactive: "Inativo",
    pending: "Pendente",
    rejected: "Recusado",
    scheduled: "Agendado",
  };
  return labels[value.toLowerCase()] ?? value.replaceAll("_", " ");
}

function fieldLabel(key: string) {
  const labels: Record<string, string> = {
    attendance_id: "Atendimento de origem",
    birth_date: "Nascimento",
    category: "Categoria",
    description: "Descrição",
    diagnosis: "Diagnóstico",
    exam_name: "Exame",
    notes: "Observações",
    plan_name: "Plano",
    result: "Resultado",
    scheduled_at: "Agendado para",
    vaccine_name: "Vacina",
  };
  return labels[key] ?? key.replaceAll("_", " ");
}

function formatLegacyValue(value: unknown) {
  if (typeof value === "boolean") return value ? "Sim" : "Não";
  if (typeof value === "string" || typeof value === "number") return String(value);
  try {
    return JSON.stringify(value);
  } catch {
    return "Dado preservado";
  }
}

function toReferenceLink(value: unknown, index: number) {
  let href = "";
  let label = `Referência ${index + 1}`;
  if (typeof value === "string") href = value;
  else if (value && typeof value === "object") {
    const object = value as Record<string, unknown>;
    href = typeof object.href === "string" ? object.href : typeof object.url === "string" ? object.url : "";
    if (typeof object.label === "string") label = object.label;
    else if (typeof object.title === "string") label = object.title;
  }
  try {
    const url = new URL(href);
    if (!["http:", "https:"].includes(url.protocol)) return null;
    return { href: url.toString(), label };
  } catch {
    return null;
  }
}
