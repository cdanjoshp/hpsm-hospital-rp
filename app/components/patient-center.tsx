"use client";

import Link from "next/link";
import { FormEvent, useEffect, useRef, useState } from "react";
import type { PatientCard, PatientCardFilter, PatientCardPage } from "../lib/patient-center";
import { formatPatientPassport } from "../lib/passport";
import { PatientCreateForm } from "./patient-create-form";

const FILTERS: Array<{ code: PatientCardFilter; label: string }> = [
  { code: "all", label: "Todos" },
  { code: "active", label: "Plano ativo" },
  { code: "expired", label: "Plano expirado" },
  { code: "partner", label: "Parceiro HP" },
  { code: "police", label: "Polícia / Arcanjo" },
  { code: "none", label: "Sem benefício" },
];

const BENEFITS: Record<Exclude<PatientCardFilter, "all">, string> = {
  active: "Plano ativo", expired: "Plano expirado", partner: "Parceiro HP",
  police: "Polícia / Arcanjo", none: "Sem benefício",
};

export function PatientCenter({ initialData, initialFilter, initialSearch, permissionCodes }: {
  initialData: PatientCardPage;
  initialFilter: PatientCardFilter;
  initialSearch: string;
  permissionCodes: string[];
}) {
  const [creating, setCreating] = useState(false);
  const [data, setData] = useState(initialData);
  const [error, setError] = useState("");
  const [filter, setFilter] = useState<PatientCardFilter>(initialFilter);
  const [loading, setLoading] = useState(false);
  const [notice, setNotice] = useState("");
  const [search, setSearch] = useState(initialSearch);
  const firstRun = useRef(true);
  const skipNextFilterRun = useRef(false);
  const searchTimer = useRef<number | null>(null);
  const requestId = useRef(0);
  const controller = useRef<AbortController | null>(null);

  async function load(nextPage: number, nextFilter = filter, nextSearch = search) {
    controller.current?.abort();
    const nextController = new AbortController();
    controller.current = nextController;
    const currentRequest = ++requestId.current;
    setLoading(true);
    setError("");
    setNotice("");
    try {
      const params = new URLSearchParams({
        filter: nextFilter, page: String(nextPage), pageSize: String(data.pageSize),
        search: nextSearch.trim(), view: "list",
      });
      const response = await fetch(`/api/patient-center?${params}`, { cache: "no-store", signal: nextController.signal });
      const payload = (await response.json()) as PatientCardPage & { error?: string };
      if (!response.ok) throw new Error(payload.error ?? "Não foi possível consultar os pacientes.");
      if (currentRequest !== requestId.current) return false;
      setData(payload);
      const url = new URL(window.location.href);
      if (nextSearch.trim()) url.searchParams.set("search", nextSearch.trim());
      else url.searchParams.delete("search");
      if (nextFilter !== "all") url.searchParams.set("filter", nextFilter);
      else url.searchParams.delete("filter");
      if (nextPage > 1) url.searchParams.set("page", String(nextPage));
      else url.searchParams.delete("page");
      window.history.replaceState(window.history.state, "", url);
      return true;
    } catch (cause) {
      if (nextController.signal.aborted) return false;
      if (currentRequest === requestId.current) setError(cause instanceof Error ? cause.message : "Não foi possível consultar os pacientes.");
      return false;
    } finally {
      if (currentRequest === requestId.current) setLoading(false);
    }
  }

  useEffect(() => {
    if (firstRun.current) { firstRun.current = false; return; }
    if (skipNextFilterRun.current) { skipNextFilterRun.current = false; return; }
    searchTimer.current = window.setTimeout(() => void load(1, filter, search), 320);
    return () => { if (searchTimer.current !== null) window.clearTimeout(searchTimer.current); };
    // A consulta só começa após a pausa na digitação.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filter, search]);
  useEffect(() => () => controller.current?.abort(), []);

  function submit(event: FormEvent) {
    event.preventDefault();
    if (searchTimer.current !== null) window.clearTimeout(searchTimer.current);
    void load(1);
  }

  const first = data.total ? (data.page - 1) * data.pageSize + 1 : 0;
  const last = Math.min(data.total, data.page * data.pageSize);
  const totalPages = Math.max(1, Math.ceil(data.total / data.pageSize));
  const filtered = Boolean(search.trim()) || filter !== "all";
  const canEditPatients = permissionCodes.includes("patients.manage");
  const actions = [
    { label: "Vender", path: "/atendimentos", allowed: permissionCodes.includes("attendances.create") },
    { label: "Consultar", path: "/consultas", allowed: permissionCodes.includes("consultations.view") && permissionCodes.includes("consultations.create") },
    { label: "Exame", path: "/exames", allowed: permissionCodes.includes("exams.view") && permissionCodes.includes("exams.create") },
    { label: "Gesso", path: "/gessos", allowed: permissionCodes.includes("casts.view") && permissionCodes.includes("casts.create") },
    { label: "Internação", path: "/internacoes", allowed: permissionCodes.includes("hospitalizations.view") && permissionCodes.includes("hospitalizations.create") },
  ];

  return (
    <section className="management-card patient-hub">
      <div className="patient-hub-toolbar">
        <form onSubmit={submit} className="patient-center-search patient-hub-search" role="search">
          <label htmlFor="patient-center-search">Buscar por passaporte ou nome</label>
          <div>
            <svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round"><circle cx="10.8" cy="10.8" r="6.8" /><path d="m16 16 4.5 4.5" /></svg>
            <input id="patient-center-search" value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Buscar por nome ou passaporte" maxLength={100} autoComplete="off" />
          </div>
        </form>
        <label className="patient-hub-filter">
          <svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M4 6h16M7 12h10m-7 6h4" /></svg>
          <span>Benefício</span>
          <select value={filter} onChange={(event) => setFilter(event.target.value as PatientCardFilter)}>
            {FILTERS.map((item) => <option key={item.code} value={item.code}>{item.label}</option>)}
          </select>
          <svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="m7 10 5 5 5-5" /></svg>
        </label>
        <button className="patient-hub-create" type="button" onClick={() => { setError(""); setNotice(""); setCreating(true); }}>＋ Novo paciente</button>
        {filtered ? <button className="patient-hub-clear" type="button" onClick={() => { setSearch(""); setFilter("all"); }}>Limpar filtros</button> : null}
      </div>

      <div className="patient-center-result-head patient-hub-result-head">
        <div><strong>{data.total}</strong><span>{data.total === 1 ? "paciente encontrado" : "pacientes encontrados"}</span></div>
        {loading ? <span className="patient-center-loading" role="status">Atualizando…</span> : <span>{first}–{last} de {data.total}</span>}
      </div>
      {error ? <p className="form-error" role="alert">{error}</p> : null}
      {notice ? <p className="form-success" role="status">{notice}</p> : null}

      {loading ? <div className="patient-hub-grid" aria-hidden="true">{Array.from({ length: data.pageSize }, (_, index) => <div className="patient-hub-skeleton" key={index} />)}</div>
        : data.patients.length ? (
          <div className="patient-hub-grid">
            {data.patients.map((patient) => (
              <article className="patient-hub-card" data-editable={canEditPatients} key={patient.id}>
                <Link className="patient-hub-card-link" href={`/pacientes/${patient.id}`} aria-label={`Abrir perfil de ${patient.name}`} />
                {canEditPatients ? <Link className="patient-hub-edit" href={`/pacientes/${patient.id}?editar=1`} aria-label={`Editar dados de ${patient.name}`} title="Editar dados" onClick={(event) => event.stopPropagation()}><svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="m4 16.5-.5 4 4-.5L19 8.5 15.5 5 4 16.5Z" /><path d="m13.5 7 3.5 3.5M18 3.5l2.5 2.5" /></svg></Link> : null}
                <div className="patient-hub-identity">
                  <span className="patient-hub-avatar" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round"><circle cx="12" cy="8" r="3" /><path d="M5.75 19c.2-3.4 2.4-5.25 6.25-5.25s6.05 1.85 6.25 5.25" /></svg></span>
                  <div className="patient-hub-identity-copy">
                    <strong className="patient-hub-name" title={patient.name}>{patient.name}</strong>
                    <div className="patient-hub-meta"><span className="patient-hub-passport">Passaporte {formatPatientPassport(patient.passport)}</span><span className="patient-hub-benefit" data-benefit={patient.benefit} title={BENEFITS[patient.benefit]}>{BENEFITS[patient.benefit]}</span></div>
                  </div>
                </div>
                <p className="patient-hub-allergies" data-alert={hasReportedAllergies(patient.allergies)} data-unknown={!patient.allergies?.trim()} title={patient.allergies?.trim() || "Alergias não informadas"}>
                  <svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M12 3.5 21 20H3L12 3.5Z" /><path d="M12 9v4.5M12 17h.01" /></svg><span><b>Alergias:</b> {patient.allergies?.trim() || "Não informadas"}</span>
                </p>
                <PatientCardAlerts patient={patient} permissionCodes={permissionCodes} />
                <div className="patient-hub-actions" aria-label={`Ações para ${patient.name}`}>
                  {actions.filter((action) => action.allowed).map((action) => (
                    <Link key={action.path} href={`${action.path}?novo=1&paciente=${encodeURIComponent(patient.passport)}`} aria-label={`${action.label} para ${patient.name}`} onClick={(event) => event.stopPropagation()}>
                      <PatientActionIcon label={action.label} /><span>{action.label === "Internação" ? "Internar" : action.label}</span>
                    </Link>
                  ))}
                </div>
              </article>
            ))}
          </div>
        ) : <div className="empty-state"><span>⌕</span><strong>{filtered ? "Nenhum paciente encontrado para essa busca." : "Ainda não há pacientes cadastrados."}</strong><p>{filtered ? "Revise o nome, passaporte ou benefício selecionado." : "Use Novo paciente para criar a primeira ficha."}</p></div>}

      <div className="patient-center-pagination">
        <button type="button" disabled={loading || data.page <= 1} onClick={() => void load(data.page - 1)}>← Anterior</button>
        <span>Página <strong>{data.page}</strong> de {totalPages}</span>
        <button type="button" disabled={loading || data.page >= totalPages} onClick={() => void load(data.page + 1)}>Próxima →</button>
      </div>
      {creating ? <div className="patient-create-overlay" role="dialog" aria-modal="true" aria-label="Cadastrar novo paciente" onMouseDown={(event) => { if (event.target === event.currentTarget) setCreating(false); }}>
        <section>
          <header><div><span>Novo cadastro</span><h2>Adicionar paciente</h2><p>Crie a ficha agora e use o paciente depois em atendimentos, exames e Plano de Saúde.</p></div><button type="button" aria-label="Fechar cadastro" onClick={() => setCreating(false)}>×</button></header>
          <PatientCreateForm onCancel={() => setCreating(false)} onCreated={(patient) => {
            setCreating(false);
            skipNextFilterRun.current = filter !== "all" || search !== patient.passport;
            setFilter("all");
            setSearch(patient.passport);
            void load(1, "all", patient.passport).then((success) => { if (success) setNotice(`${patient.name} foi cadastrado com sucesso.`); });
          }} />
        </section>
      </div> : null}
    </section>
  );
}

function PatientCardAlerts({ patient, permissionCodes }: { patient: PatientCard; permissionCodes: string[] }) {
  const { casts, hospitalization, appointments } = patient.alerts ?? {};
  if (!casts && !hospitalization && !appointments) return null;
  return <div className="patient-hub-alerts" aria-label={`Pendências clínicas de ${patient.name}`}>
    {casts ? <div className="patient-hub-alert" data-tone="cast">
      <div><strong>Gessos ativos ({casts.count})</strong><span title={casts.latest.location}>{casts.latest.location}</span><small>Retirada prevista: {formatAlertDate(casts.latest.expectedRemovalAt)}</small></div>
      <AlertShortcut href={`/gessos?registro=${casts.latest.id}${permissionCodes.includes("casts.remove") ? "&acao=retirar" : ""}`} label={permissionCodes.includes("casts.remove") ? `Registrar retirada do gesso de ${patient.name}` : `Ver gesso de ${patient.name}`} icon="cast" />
    </div> : null}
    {hospitalization ? <div className="patient-hub-alert" data-tone="hospitalization">
      <div><strong>Internação ativa</strong><span title={hospitalization.reason}>{hospitalization.bed} · {hospitalization.reason}</span><small>Desde {formatAlertDate(hospitalization.admittedAt)}</small></div>
      <AlertShortcut href={`/internacoes?registro=${hospitalization.id}${permissionCodes.includes("hospitalizations.discharge") ? "&acao=alta" : ""}`} label={permissionCodes.includes("hospitalizations.discharge") ? `Registrar alta de ${patient.name}` : `Ver internação de ${patient.name}`} icon="hospitalization" />
    </div> : null}
    {appointments ? <div className="patient-hub-alert" data-tone="appointment">
      <div><strong>Consultas pendentes ({appointments.count})</strong><span title={appointments.next.reason}>{appointments.next.reason}</span><small>{appointments.next.status === "confirmed" ? "Confirmada" : "Agendada"}: {formatAlertDate(appointments.next.scheduledStart)}</small></div>
      <AlertShortcut href={`/consultas?agendamento=${appointments.next.id}&paciente=${encodeURIComponent(patient.passport)}&situacao=${appointments.next.status}`} label={`Abrir consulta agendada de ${patient.name}`} icon="appointment" />
    </div> : null}
  </div>;
}

function AlertShortcut({ href, icon, label }: { href: string; icon: "cast" | "hospitalization" | "appointment"; label: string }) {
  return <a className="patient-hub-alert-shortcut" href={href} aria-label={label} title={label} onClick={(event) => event.stopPropagation()}>
    <svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
      {icon === "cast" ? <><path d="m7.5 10 6.5-6.5a3 3 0 0 1 4.2 4.2l-1.3 1.3a3 3 0 0 1-1.9 5.2l-6.5 6.5a3 3 0 0 1-4.2-4.2L5.6 15a3 3 0 0 1 1.9-5Z" /><path d="m9 12 3 3" /></> : icon === "hospitalization" ? <><path d="M3 19V8m0 7h18v4m-18-4V8h7a3 3 0 0 1 3 3v4M13 11h5a3 3 0 0 1 3 3v1" /><path d="M18 6v4m-2-2h4" /></> : <><rect x="4" y="5" width="16" height="16" rx="2" /><path d="M8 3v4m8-4v4M4 10h16m-9 5 2 2 3-4" /></>}
    </svg>
  </a>;
}

function formatAlertDate(value: string) {
  return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(value));
}

function PatientActionIcon({ label }: { label: string }) {
  const common = { "aria-hidden": true as const, viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", strokeWidth: 1.7, strokeLinecap: "round" as const, strokeLinejoin: "round" as const };
  if (label === "Vender") return <span className="patient-hub-money-icon" aria-hidden="true">$</span>;
  if (label === "Consultar") return <svg {...common}><path d="M5 4v5a5 5 0 0 0 10 0V4M3 4h4m6 0h4M10 14v2a5 5 0 0 0 10 0v-2" /><circle cx="20" cy="12" r="2" /></svg>;
  if (label === "Exame") return <svg {...common}><path d="M5 20h14M9 4l5 5m-5-5 2-2 5 5-2 2m0 0-5 5m-2 4a5 5 0 0 0 10 0" /></svg>;
  if (label === "Gesso") return <svg {...common}><path d="m7.5 10 6.5-6.5a3 3 0 0 1 4.2 4.2l-1.3 1.3a3 3 0 0 1-1.9 5.2l-6.5 6.5a3 3 0 0 1-4.2-4.2L5.6 15a3 3 0 0 1 1.9-5Z" /><path d="m9 12 3 3m0-6 3 3" /></svg>;
  return <svg {...common}><path d="M3 19V8m0 7h18v4m-18-4V8h7a3 3 0 0 1 3 3v4M13 11h5a3 3 0 0 1 3 3v1M5 19v2m14-2v2" /></svg>;
}

function hasReportedAllergies(value: string | null) {
  const normalized = value?.trim().toLocaleLowerCase("pt-BR") ?? "";
  return Boolean(normalized && !/^(n[aã]o (possui|tem)( alergias)?|sem alergias( registradas)?|nenhuma(s)?|n[aã]o( informado| informadas)?)\.?$/.test(normalized));
}
