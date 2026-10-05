"use client";

import Link from "next/link";
import { useEffect, useMemo, useRef, useState } from "react";
import type {
  ReportFinancialData,
  ReportHrData,
  ReportHrRow,
  ReportIndividualData,
  ReportOverview,
  ReportStaffOption,
  ReportTeamData,
} from "../lib/administrative-reports";

type ReportView = "overview" | "hr" | "financial" | "team" | "individual";
type PeriodPreset = "this_week" | "previous_week" | "this_month" | "previous_month" | "last_30" | "custom";
type ReportData = ReportFinancialData | ReportHrData | ReportIndividualData | ReportOverview | ReportTeamData;

export function AdministrativeReports({ canViewFinancial, referenceDate }: { canViewFinancial: boolean; referenceDate: string }) {
  const initialPeriod = useMemo(() => periodFor("this_month", referenceDate), [referenceDate]);
  const [view, setView] = useState<ReportView>("overview");
  const [preset, setPreset] = useState<PeriodPreset>("this_month");
  const [start, setStart] = useState(initialPeriod.start);
  const [end, setEnd] = useState(initialPeriod.end);
  const [result, setResult] = useState<{ data: ReportData; key: string } | null>(null);
  const [requestError, setRequestError] = useState<{ key: string; message: string } | null>(null);
  const [hrSearch, setHrSearch] = useState("");
  const [debouncedHrSearch, setDebouncedHrSearch] = useState("");
  const [hrPosition, setHrPosition] = useState("");
  const [hrStatus, setHrStatus] = useState("active");
  const [hrSort, setHrSort] = useState("name");
  const [hrDirection, setHrDirection] = useState("asc");
  const [hrPage, setHrPage] = useState(1);
  const [financialPosition, setFinancialPosition] = useState("");
  const [financialStaff, setFinancialStaff] = useState<ReportStaffOption | null>(null);
  const [financialSort, setFinancialSort] = useState("value");
  const [financialDirection, setFinancialDirection] = useState("desc");
  const [financialPage, setFinancialPage] = useState(1);
  const [individualStaff, setIndividualStaff] = useState<ReportStaffOption | null>(null);
  const requestRef = useRef<AbortController | null>(null);

  useEffect(() => {
    const timer = window.setTimeout(() => setDebouncedHrSearch(hrSearch.trim()), 275);
    return () => window.clearTimeout(timer);
  }, [hrSearch]);

  const requestUrl = useMemo(() => {
    if (view === "individual" && !individualStaff) return "";
    const params = new URLSearchParams({ view, start, end });
    if (view === "hr") {
      params.set("search", debouncedHrSearch);
      params.set("position", hrPosition);
      params.set("status", hrStatus);
      params.set("sort", hrSort);
      params.set("direction", hrDirection);
      params.set("page", String(hrPage));
    }
    if (view === "financial") {
      params.set("position", financialPosition);
      params.set("employee", financialStaff?.id ?? "");
      params.set("sort", financialSort);
      params.set("direction", financialDirection);
      params.set("page", String(financialPage));
    }
    if (view === "individual") params.set("employee", individualStaff!.id);
    return `/api/administrative-reports?${params}`;
  }, [debouncedHrSearch, end, financialDirection, financialPage, financialPosition, financialSort, financialStaff, hrDirection, hrPage, hrPosition, hrSort, hrStatus, individualStaff, start, view]);

  useEffect(() => {
    requestRef.current?.abort();
    if (!requestUrl) return;
    const controller = new AbortController();
    requestRef.current = controller;
    fetch(requestUrl, { signal: controller.signal, cache: "no-store" })
      .then(async (response) => {
        const payload = await response.json() as ReportData & { error?: string };
        if (!response.ok) throw new Error(payload.error ?? "Não foi possível gerar este relatório agora.");
        return payload;
      })
      .then((payload) => { if (requestRef.current === controller) setResult({ data: payload, key: requestUrl }); })
      .catch((cause: unknown) => {
        if (cause instanceof DOMException && cause.name === "AbortError") return;
        if (requestRef.current === controller) setRequestError({ key: requestUrl, message: cause instanceof Error ? cause.message : "Não foi possível gerar este relatório agora." });
      })
      .finally(() => {
        if (requestRef.current === controller) {
          requestRef.current = null;
        }
      });
    return () => controller.abort();
  }, [requestUrl]);

  const data = result?.key === requestUrl ? result.data : null;
  const error = requestError?.key === requestUrl ? requestError.message : "";
  const loading = Boolean(requestUrl && !data && !error);

  function selectPreset(value: PeriodPreset) {
    setPreset(value);
    if (value !== "custom") {
      const period = periodFor(value, referenceDate);
      setStart(period.start);
      setEnd(period.end);
      setHrPage(1);
      setFinancialPage(1);
    }
  }

  const exportUrl = (target: "financial" | "hr" | "individual") => {
    const params = new URLSearchParams({ view: target, start, end, export: "csv" });
    if (target === "hr") {
      params.set("search", debouncedHrSearch); params.set("position", hrPosition); params.set("status", hrStatus);
      params.set("sort", hrSort); params.set("direction", hrDirection);
    }
    if (target === "financial") {
      params.set("position", financialPosition); params.set("employee", financialStaff?.id ?? "");
      params.set("sort", financialSort); params.set("direction", financialDirection);
    }
    if (target === "individual") params.set("employee", individualStaff?.id ?? "");
    return `/api/administrative-reports?${params}`;
  };

  return <main className="admin-reports" data-report-view={view}>
    <header className="admin-reports-header management-card">
      <div><p className="eyebrow">Central administrativa</p><h1>Relatórios</h1><p>Análise administrativa, jornada e produção do hospital.</p></div>
      <div className="report-period-control">
        <label>Período<select value={preset} onChange={(event) => selectPreset(event.target.value as PeriodPreset)}>
          <option value="this_week">Esta semana</option><option value="previous_week">Semana anterior</option>
          <option value="this_month">Este mês</option><option value="previous_month">Mês anterior</option>
          <option value="last_30">Últimos 30 dias</option><option value="custom">Personalizado</option>
        </select></label>
        {preset === "custom" ? <div className="report-custom-period">
          <label>Data inicial<input type="date" max={end} value={start} onChange={(event) => { setStart(event.target.value); setHrPage(1); setFinancialPage(1); }} /></label>
          <label>Data final<input type="date" min={start} max={referenceDate} value={end} onChange={(event) => { setEnd(event.target.value); setHrPage(1); setFinancialPage(1); }} /></label>
        </div> : <span>{formatDate(start)} a {formatDate(end)}</span>}
      </div>
    </header>

    <nav className="report-view-tabs" aria-label="Áreas dos relatórios">
      <ReportTab active={view === "overview"} label="Visão Geral" onClick={() => setView("overview")} />
      <ReportTab active={view === "hr"} label="RH e Jornada" onClick={() => setView("hr")} />
      {canViewFinancial ? <ReportTab active={view === "financial"} label="Atendimentos e Vendas" onClick={() => setView("financial")} /> : null}
      <ReportTab active={view === "team"} label="Equipe" onClick={() => setView("team")} />
      <ReportTab active={view === "individual"} label="Relatório Individual" onClick={() => setView("individual")} />
    </nav>

    {view === "hr" ? <ReportFilters>
      <label>Buscar profissional<input value={hrSearch} maxLength={80} placeholder="Nome ou passaporte" onChange={(event) => { setHrSearch(event.target.value); setHrPage(1); }} /></label>
      <PositionFilter value={hrPosition} positions={(data as ReportHrData | null)?.positions ?? []} onChange={(value) => { setHrPosition(value); setHrPage(1); }} />
      <label>Situação<select value={hrStatus} onChange={(event) => { setHrStatus(event.target.value); setHrPage(1); }}><option value="active">Ativos</option><option value="suspended">Suspensos</option><option value="all">Ativos e suspensos</option></select></label>
      <label>Ordenar por<select value={hrSort} onChange={(event) => { setHrSort(event.target.value); setHrPage(1); }}><option value="name">Nome</option><option value="position">Cargo</option><option value="hours">Horas</option><option value="difference">Diferença</option><option value="status">Situação da meta</option></select></label>
      <Direction value={hrDirection} onChange={(value) => { setHrDirection(value); setHrPage(1); }} />
      <a className="report-export-button" href={exportUrl("hr")}>Exportar CSV</a>
    </ReportFilters> : null}

    {view === "financial" ? <ReportFilters>
      <StaffPicker label="Profissional" optional selected={financialStaff} onSelect={(staff) => { setFinancialStaff(staff); setFinancialPage(1); }} />
      <PositionFilter value={financialPosition} positions={(data as ReportFinancialData | null)?.positions ?? []} onChange={(value) => { setFinancialPosition(value); setFinancialPage(1); }} />
      <label>Ordenar por<select value={financialSort} onChange={(event) => { setFinancialSort(event.target.value); setFinancialPage(1); }}><option value="value">Valor</option><option value="attendances">Atendimentos</option><option value="items">Itens</option><option value="name">Nome</option></select></label>
      <Direction value={financialDirection} onChange={(value) => { setFinancialDirection(value); setFinancialPage(1); }} />
      <a className="report-export-button" href={exportUrl("financial")}>Exportar CSV</a>
    </ReportFilters> : null}

    {view === "individual" ? <section className="management-card report-individual-picker">
      <StaffPicker label="Selecione o profissional" selected={individualStaff} onSelect={setIndividualStaff} />
      {individualStaff ? <div className="report-individual-actions"><a className="report-export-button" href={exportUrl("individual")}>Exportar CSV</a><button type="button" onClick={() => window.print()}>Imprimir / Salvar como PDF</button></div> : null}
    </section> : null}

    {loading ? <ReportSkeleton /> : error ? <ReportError message={error} /> : view === "overview" && data ? <Overview data={data as ReportOverview} />
      : view === "hr" && data ? <HrReport data={data as ReportHrData} page={hrPage} onPage={setHrPage} />
        : view === "financial" && data ? <FinancialReport data={data as ReportFinancialData} page={financialPage} onPage={setFinancialPage} />
          : view === "team" && data ? <TeamReport data={data as ReportTeamData} />
            : view === "individual" && data ? <IndividualReport data={data as ReportIndividualData} start={start} end={end} />
              : view === "individual" ? <ReportEmpty title="Escolha um profissional" text="Busque por nome ou passaporte para consolidar os dados do período." /> : null}
  </main>;
}

function ReportTab({ active, label, onClick }: { active: boolean; label: string; onClick: () => void }) {
  return <button type="button" aria-current={active ? "page" : undefined} data-active={active} onClick={onClick}>{label}</button>;
}

function ReportFilters({ children }: { children: React.ReactNode }) { return <section className="management-card report-filter-bar">{children}</section>; }
function PositionFilter({ onChange, positions, value }: { onChange: (value: string) => void; positions: Array<{ id: number; name: string }>; value: string }) { return <label>Cargo<select value={value} onChange={(event) => onChange(event.target.value)}><option value="">Todos os cargos</option>{positions.map((position) => <option key={position.id} value={position.id}>{position.name}</option>)}</select></label>; }
function Direction({ onChange, value }: { onChange: (value: string) => void; value: string }) { return <label>Direção<select value={value} onChange={(event) => onChange(event.target.value)}><option value="asc">Crescente</option><option value="desc">Decrescente</option></select></label>; }

function Overview({ data }: { data: ReportOverview }) {
  return <section className="report-view-stack">
    <div className="report-kpi-grid">
      <Kpi label="Profissionais ativos" value={String(data.active_professionals)} />
      <Kpi label="Horas registradas" value={formatMinutes(data.hours_minutes)} />
      <Kpi label="Meta atingida" value={String(data.met_professionals)} tone="positive" />
      <Kpi label="Abaixo da meta" value={String(data.below_professionals)} tone={data.below_professionals ? "warning" : undefined} />
      {data.fully_excused_professionals ? <Kpi label="Meta integralmente abonada" value={String(data.fully_excused_professionals)} /> : null}
      {data.financial_access ? <><Kpi label="Atendimentos e vendas" value={String(data.attendance_count ?? 0)} /><Kpi label="Valor movimentado" value={formatMoney(data.total_amount ?? 0)} /><Kpi label="Ticket médio" value={formatMoney(data.ticket_average ?? 0)} /></> : null}
    </div>
    <section className="management-card report-note"><span>i</span><div><strong>Leitura do período</strong><p>Metas refletem os fechamentos registrados e os abatimentos aprovados. Este relatório informa a situação; qualquer consequência permanece sujeita à revisão humana.</p></div></section>
  </section>;
}

function HrReport({ data, onPage, page }: { data: ReportHrData; onPage: (page: number) => void; page: number }) {
  return <section className="management-card report-table-card">
    <ReportTableMeta total={data.total} noun="profissional(is)" />
    {data.items.length ? <div className="report-table-scroll"><table className="report-table report-hr-table"><thead><tr><th>Profissional</th><th>Cargo</th><th>Horas</th><th>Meta efetiva</th><th>Diferença</th><th>Situação</th><th>Contexto</th></tr></thead><tbody>{data.items.map((row) => <tr key={row.id}><td><strong>{row.name}</strong><small>Passaporte {row.passport}</small></td><td>{row.position}<small>{profileStatus(row.profile_status)}</small></td><td>{formatMinutes(row.worked_minutes)}</td><td><strong>{formatMinutes(row.effective_target_minutes)}</strong><small>{row.leave_minutes ? `${formatMinutes(row.leave_minutes)} abonadas` : `Base ${formatMinutes(row.base_target_minutes)}`}</small></td><td><span className="report-difference" data-negative={row.difference_minutes < 0}>{formatSignedMinutes(row.difference_minutes)}</span></td><td><GoalBadge row={row} /></td><td><div className="report-context-tags">{row.has_absence ? <span>Afastamento</span> : null}{row.has_justification ? <span>Justificativa</span> : null}{row.active_warnings ? <span data-warning="true">{row.active_warnings} ADV ativa(s)</span> : null}{!row.has_absence && !row.has_justification && !row.active_warnings ? <small>Sem ocorrências</small> : null}</div></td></tr>)}</tbody></table></div> : <ReportEmpty inline title="Nenhum registro" text="Nenhum registro encontrado para o período selecionado." />}
    <Pagination page={page} pageSize={data.page_size} total={data.total} onPage={onPage} />
  </section>;
}

function FinancialReport({ data, onPage, page }: { data: ReportFinancialData; onPage: (page: number) => void; page: number }) {
  return <section className="report-view-stack">
    <div className="report-kpi-grid compact"><Kpi label="Atendimentos e vendas" value={String(data.summary.attendance_count)} /><Kpi label="Valor total" value={formatMoney(data.summary.total_amount)} /><Kpi label="Ticket médio" value={formatMoney(data.summary.ticket_average)} /><Kpi label="Itens/procedimentos" value={String(data.summary.item_count)} /><Kpi label="Profissionais participantes" value={String(data.summary.professional_count)} /><Kpi label="Pacientes atendidos" value={String(data.summary.unique_patients)} /></div>
    <section className="management-card report-table-card"><div className="report-section-heading"><div><p className="eyebrow">Produção no período</p><h2>Por profissional</h2></div><span>{data.production_total}</span></div>{data.production.length ? <div className="report-table-scroll"><table className="report-table"><thead><tr><th>Profissional</th><th>Cargo</th><th>Atendimentos</th><th>Itens</th><th>Valor movimentado</th><th>Ticket médio</th></tr></thead><tbody>{data.production.map((row) => <tr key={row.employee_id}><td><strong>{row.name}</strong><small>Passaporte {row.passport}</small></td><td>{row.position}</td><td>{row.attendance_count}</td><td>{row.item_count}</td><td><strong>{formatMoney(row.total_amount)}</strong></td><td>{formatMoney(row.ticket_average)}</td></tr>)}</tbody></table></div> : <ReportEmpty inline title="Nenhuma produção" text="Nenhum registro encontrado para o período selecionado." />}<Pagination page={page} pageSize={data.page_size} total={data.production_total} onPage={onPage} /></section>
    <div className="report-two-columns"><section className="management-card report-table-card"><div className="report-section-heading"><div><p className="eyebrow">Registros e vendas</p><h2>Itens mais registrados</h2></div></div>{data.top_items.length ? <div className="report-table-scroll"><table className="report-table"><thead><tr><th>Item</th><th>Categoria</th><th>Quantidade</th><th>Valor</th></tr></thead><tbody>{data.top_items.map((item) => <tr key={`${item.service_id}-${item.name}`}><td><strong>{item.name}</strong></td><td>{item.category}</td><td>{item.quantity}</td><td>{formatMoney(item.total_amount)}</td></tr>)}</tbody></table></div> : <ReportEmpty inline title="Nenhum item" text="Não há itens registrados neste período." />}</section>
      <section className="management-card report-table-card"><div className="report-section-heading"><div><p className="eyebrow">Descontos históricos</p><h2>Uso de benefícios</h2></div></div>{data.benefits.length ? <div className="report-benefit-list">{data.benefits.map((benefit) => <article key={benefit.code}><div><strong>{benefit.name}</strong><small>{benefit.attendance_count} atendimento(s)</small></div><div><strong>{formatMoney(benefit.total_amount)}</strong><small>{formatMoney(benefit.discount_amount)} concedidos</small></div></article>)}</div> : <ReportEmpty inline title="Nenhum benefício" text="Não há benefícios registrados neste período." />}</section></div>
    <section className="management-card report-table-card"><div className="report-section-heading"><div><p className="eyebrow">Parceiro do HP</p><h2>Utilização por parceria</h2></div></div>{data.partnerships.length ? <div className="report-benefit-list">{data.partnerships.map((partnership) => <article key={partnership.partnership_id ?? `legacy-${partnership.name}`}><div><strong>{partnership.name}</strong><small>{partnership.attendance_count} atendimento(s)</small></div><div><strong>{formatMoney(partnership.total_amount)}</strong><small>{formatMoney(partnership.discount_amount)} concedidos</small></div></article>)}</div> : <ReportEmpty inline title="Nenhuma parceria utilizada" text="Não houve uso do benefício Parceiro do HP neste período." />}</section>
  </section>;
}

function TeamReport({ data }: { data: ReportTeamData }) {
  return <section className="report-view-stack"><div className="report-kpi-grid compact"><Kpi label="Profissionais ativos" value={String(data.summary.active_professionals)} /><Kpi label="Admissões" value={String(data.summary.admissions)} /><Kpi label="Promoções" value={String(data.summary.promotions)} /><Kpi label="Afastamentos aprovados" value={String(data.summary.approved_absences)} /><Kpi label="Suspensões atuais" value={String(data.summary.suspensions)} tone={data.summary.suspensions ? "warning" : undefined} /></div>
    <div className="report-three-columns"><TeamList title="Admissões no período" empty="Nenhuma admissão no período." items={data.admissions.map((item) => ({ id: `a-${item.employee_id}`, title: item.name, subtitle: `${item.position} · passaporte ${item.passport}`, meta: formatDate(item.date) }))} /><TeamList title="Promoções no período" empty="Nenhuma promoção no período." items={data.promotions.map((item, index) => ({ id: `p-${item.employee_id}-${index}`, title: item.name, subtitle: `${item.from_position} → ${item.to_position}`, meta: formatDate(item.date) }))} /><TeamList title="Afastamentos aprovados" empty="Nenhum afastamento aprovado no período." items={data.absences.map((item, index) => ({ id: `l-${item.employee_id}-${index}`, title: item.name, subtitle: `${formatDate(item.start_date)} a ${formatDate(item.end_date)}`, meta: item.deducted_minutes ? `${formatMinutes(item.deducted_minutes)} abonadas` : "Sem abatimento" }))} /></div>
  </section>;
}

function IndividualReport({ data, end, start }: { data: ReportIndividualData; end: string; start: string }) {
  if (!data.found || !data.profile) return <ReportEmpty title="Profissional não encontrado" text="Selecione outro profissional para consultar o relatório." />;
  return <article className="management-card report-individual-sheet">
    <header><div><p className="eyebrow">Hospital Santa Marcelina · Relatório Administrativo</p><h2>{data.profile.name}</h2><p>{data.profile.position} · Passaporte {data.profile.passport}</p></div><div><em data-status={data.profile.status}>{profileStatus(data.profile.status)}</em><span>{formatDate(start)} a {formatDate(end)}</span></div></header>
    <div className="report-individual-grid">
      <ReportIndividualSection title="Jornada"><MetricLine label="Horas trabalhadas" value={formatMinutes(data.journey.worked_minutes)} /><MetricLine label="Meta base" value={formatMinutes(data.journey.base_target_minutes)} /><MetricLine label="Horas abonadas" value={formatMinutes(data.journey.leave_minutes)} /><MetricLine label="Meta efetiva" value={formatMinutes(data.journey.effective_target_minutes)} /><MetricLine label="Diferença" value={formatSignedMinutes(data.journey.difference_minutes)} /><MetricLine label="Semanas cumpridas / abaixo" value={`${data.journey.met_weeks} / ${data.journey.below_weeks}`} /></ReportIndividualSection>
      {data.production ? <ReportIndividualSection title="Produção"><MetricLine label="Atendimentos e vendas" value={String(data.production.attendance_count)} /><MetricLine label="Itens/procedimentos" value={String(data.production.item_count)} /><MetricLine label="Valor movimentado" value={formatMoney(data.production.total_amount)} /><MetricLine label="Ticket médio" value={formatMoney(data.production.ticket_average)} /></ReportIndividualSection> : null}
      <ReportIndividualSection title="RH"><MetricLine label="ADVs ativas no ciclo" value={String(data.rh.active_warnings)} /><MetricLine label="Afastamentos no período" value={String(data.rh.absences)} /><MetricLine label="Justificativas" value={String(data.rh.justifications)} /><MetricLine label="Situação funcional" value={profileStatus(data.profile.status)} /></ReportIndividualSection>
      <ReportIndividualSection title="Carreira"><MetricLine label="Cargo atual" value={data.profile.position} />{data.career.completed_courses !== null ? <MetricLine label="Cursos concluídos no período" value={String(data.career.completed_courses)} /> : null}<MetricLine label="Promoções no período" value={String(data.career.promotions.length)} />{data.career.promotions.slice(0, 3).map((promotion, index) => <p className="report-career-event" key={`${promotion.date}-${index}`}>{formatDate(promotion.date)} · {promotion.from_position} → {promotion.to_position}</p>)}</ReportIndividualSection>
    </div>
    <footer><Link href={`/administrativo/perfis?selecionar=${data.profile.id}`} prefetch={false}>Abrir Perfil Funcional</Link><p>Documento administrativo gerado exclusivamente para uso interno do HPSM.</p></footer>
  </article>;
}

function StaffPicker({ label, onSelect, optional = false, selected }: { label: string; onSelect: (staff: ReportStaffOption | null) => void; optional?: boolean; selected: ReportStaffOption | null }) {
  const [query, setQuery] = useState(selected?.name ?? "");
  const [searchResult, setSearchResult] = useState<{ items: ReportStaffOption[]; query: string } | null>(null);
  const [loadingQuery, setLoadingQuery] = useState<string | null>(null);
  useEffect(() => {
    const normalized = query.trim();
    if (selected || normalized.length < 2) return;
    const controller = new AbortController();
    const timer = window.setTimeout(() => {
      setLoadingQuery(normalized);
      fetch(`/api/administrative-reports?view=staff&search=${encodeURIComponent(normalized)}`, { signal: controller.signal, cache: "no-store" })
        .then((response) => response.ok ? response.json() : Promise.reject())
        .then((payload: { items?: ReportStaffOption[] }) => setSearchResult({ items: payload.items ?? [], query: normalized }))
        .catch(() => { if (!controller.signal.aborted) setSearchResult({ items: [], query: normalized }); })
        .finally(() => { if (!controller.signal.aborted) setLoadingQuery(null); });
    }, 250);
    return () => { window.clearTimeout(timer); controller.abort(); };
  }, [query, selected]);
  const normalized = query.trim();
  const items = searchResult?.query === normalized ? searchResult.items : [];
  const loading = loadingQuery === normalized;
  return <div className="report-staff-picker"><label>{label}{optional ? <small>Opcional</small> : null}<input value={query} placeholder="Nome ou passaporte" onChange={(event) => { setQuery(event.target.value); if (selected) onSelect(null); }} /></label>{selected ? <button className="report-picker-clear" type="button" onClick={() => { onSelect(null); setQuery(""); }}>Limpar</button> : null}{!selected && normalized.length >= 2 && (loading || items.length) ? <div className="report-staff-options" role="listbox" aria-label="Profissionais encontrados">{loading ? <span>Buscando…</span> : items.map((item) => <button key={item.id} type="button" role="option" aria-selected="false" onClick={() => { setQuery(item.name); onSelect(item); }}><strong>{item.name}</strong><small>{item.position} · passaporte {item.passport}</small></button>)}</div> : null}</div>;
}

function TeamList({ empty, items, title }: { empty: string; items: Array<{ id: string; meta: string; subtitle: string; title: string }>; title: string }) { return <section className="management-card report-team-list"><h2>{title}</h2>{items.length ? items.map((item) => <article key={item.id}><div><strong>{item.title}</strong><small>{item.subtitle}</small></div><time>{item.meta}</time></article>) : <p>{empty}</p>}</section>; }
function ReportIndividualSection({ children, title }: { children: React.ReactNode; title: string }) { return <section><h3>{title}</h3>{children}</section>; }
function MetricLine({ label, value }: { label: string; value: string }) { return <div className="report-metric-line"><span>{label}</span><strong>{value}</strong></div>; }
function Kpi({ label, tone, value }: { label: string; tone?: string; value: string }) { return <article className="management-card report-kpi" data-tone={tone}><span>{label}</span><strong>{value}</strong></article>; }
function ReportTableMeta({ noun, total }: { noun: string; total: number }) { return <div className="report-table-meta"><strong>{total}</strong> {noun} no filtro</div>; }
function Pagination({ onPage, page, pageSize, total }: { onPage: (page: number) => void; page: number; pageSize: number; total: number }) { const pages = Math.max(1, Math.ceil(total / pageSize)); if (pages <= 1) return null; return <nav className="report-pagination" aria-label="Paginação do relatório"><button type="button" disabled={page <= 1} onClick={() => onPage(page - 1)}>Anterior</button><span>Página {page} de {pages}</span><button type="button" disabled={page >= pages} onClick={() => onPage(page + 1)}>Próxima</button></nav>; }
function GoalBadge({ row }: { row: ReportHrRow }) { const label = ({ below: "Meta não atingida", fully_excused: "Meta integralmente abonada", met: "Meta atingida", no_data: "Sem fechamento" } as const)[row.goal_status]; return <em className="report-status" data-status={row.goal_status}>{label}<small>{row.met_weeks} cumprida(s) · {row.below_weeks} abaixo</small></em>; }
function ReportEmpty({ inline = false, text, title }: { inline?: boolean; text: string; title: string }) { return <section className={inline ? "report-empty inline" : "management-card report-empty"}><span>◇</span><div><strong>{title}</strong><p>{text}</p></div></section>; }
function ReportError({ message }: { message: string }) { return <section className="management-card report-error" role="alert"><span>!</span><div><strong>Relatório indisponível</strong><p>{message}</p></div></section>; }
function ReportSkeleton() { return <section className="report-skeleton" role="status" aria-label="Gerando relatório"><div /><div /><div /><div /></section>; }

function periodFor(preset: Exclude<PeriodPreset, "custom"> | PeriodPreset, today: string) {
  const current = parseIso(today);
  if (preset === "this_week") return { start: iso(addDays(current, -((current.getUTCDay() + 6) % 7))), end: today };
  if (preset === "previous_week") { const thisMonday = addDays(current, -((current.getUTCDay() + 6) % 7)); return { start: iso(addDays(thisMonday, -7)), end: iso(addDays(thisMonday, -1)) }; }
  if (preset === "previous_month") { const first = new Date(Date.UTC(current.getUTCFullYear(), current.getUTCMonth() - 1, 1)); return { start: iso(first), end: iso(new Date(Date.UTC(current.getUTCFullYear(), current.getUTCMonth(), 0))) }; }
  if (preset === "last_30") return { start: iso(addDays(current, -29)), end: today };
  return { start: `${today.slice(0, 7)}-01`, end: today };
}
function parseIso(value: string) { return new Date(`${value}T00:00:00Z`); }
function addDays(date: Date, days: number) { const next = new Date(date); next.setUTCDate(next.getUTCDate() + days); return next; }
function iso(date: Date) { return date.toISOString().slice(0, 10); }
function formatDate(value: string) { if (!value) return "—"; return new Intl.DateTimeFormat("pt-BR", { timeZone: "UTC" }).format(parseIso(value)); }
function formatMoney(value: number) { return `$ ${new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 2, minimumFractionDigits: 2 }).format(Number(value) || 0)}`; }
function formatMinutes(value: number) { const safe = Math.max(0, Math.round(Number(value) || 0)); return `${Math.floor(safe / 60)}h${String(safe % 60).padStart(2, "0")}`; }
function formatSignedMinutes(value: number) { const numeric = Math.round(Number(value) || 0); return `${numeric >= 0 ? "+" : "−"}${formatMinutes(Math.abs(numeric))}`; }
function profileStatus(value: string) { return value === "suspended" ? "Suspenso" : "Ativo"; }
