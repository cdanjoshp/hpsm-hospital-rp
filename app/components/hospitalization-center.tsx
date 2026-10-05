"use client";

import Link from "next/link";
import { FormEvent, useEffect, useState } from "react";
import type { HospitalBed, HospitalBedBoard, HospitalizationPage, HospitalizationRecord, HospitalizationSource, HospitalizationStatus } from "../lib/hospitalizations";
import type { Patient } from "../lib/operational-data";
import { formatPatientPassport } from "../lib/passport";
import { HpsmButton } from "./hpsm-button";
import { PatientPassportCombobox } from "./patient-passport-combobox";

type Props = {
  canCreate: boolean;
  canDischarge: boolean;
  canSearchPatients: boolean;
  canUpdate: boolean;
  canViewHistory: boolean;
  initialBoard: HospitalBedBoard;
  initialPatient?: Patient | null;
  initialHospitalizationId?: number | null;
  initialDischarge?: boolean;
};

type Filters = { bedId: string; dateFrom: string; dateTo: string; search: string; source: string; status: string };
export type ConsultationHospitalizationPrefill = { consultationId: number; notes?: string; patient: Patient; reason: string };
const EMPTY_FILTERS: Filters = { bedId: "", dateFrom: "", dateTo: "", search: "", source: "", status: "" };
const SOURCE_LABEL: Record<HospitalizationSource, string> = { hpsm: "HPSM", hp_norte: "HP Norte" };
const STATUS_LABEL: Record<HospitalizationStatus, string> = { active: "ATIVA", cancelled: "CANCELADA", discharged: "ALTA" };

export function HospitalizationCenter({ canCreate, canDischarge, canSearchPatients, canUpdate, canViewHistory, initialBoard, initialPatient = null, initialHospitalizationId = null, initialDischarge = false }: Props) {
  const initialBed = initialHospitalizationId ? initialBoard.beds.find((bed) => bed.hospitalization_id === initialHospitalizationId) ?? null : null;
  const [board, setBoard] = useState(initialBoard);
  const [detail, setDetail] = useState<HospitalBed | null>(initialBed);
  const [editing, setEditing] = useState<HospitalBed | null | undefined>(canCreate && initialPatient && initialBoard.available > 0 ? null : undefined);
  const [consultationPrefill, setConsultationPrefill] = useState<ConsultationHospitalizationPrefill | null>(null);
  const [history, setHistory] = useState<HospitalizationPage | null>(null);
  const [historyDetail, setHistoryDetail] = useState<HospitalizationRecord | null>(null);
  const [filters, setFilters] = useState(EMPTY_FILTERS);
  const [mode, setMode] = useState<"board" | "history">("board");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(initialHospitalizationId && !initialBed ? "Essa internação não está mais ativa. Consulte o histórico para ver o registro." : "");
  const [notice, setNotice] = useState("");
  const [action, setAction] = useState<"discharge" | "cancel" | null>(initialBed && initialDischarge && canDischarge ? "discharge" : null);

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const consultationId = Number(params.get("consulta"));
    if (params.get("nova") !== "true" || !Number.isInteger(consultationId) || consultationId < 1 || !canCreate) return;
    let cancelled = false;
    void (async () => {
      try {
        const consultationResponse = await fetch(`/api/consultations?view=detail&id=${consultationId}`, { cache: "no-store" });
        const consultationPayload = await consultationResponse.json() as { consultation?: { patient?: { passport?: string }; final_diagnosis_plan?: string | null; anamnesis?: string | null }; error?: string };
        const passport = consultationPayload.consultation?.patient?.passport;
        if (!consultationResponse.ok || !passport) throw new Error(consultationPayload.error ?? "Não foi possível carregar a consulta.");
        const patientResponse = await fetch(`/api/patients?passport=${encodeURIComponent(passport)}`, { cache: "no-store" });
        const patientPayload = await patientResponse.json() as { patients?: Patient[]; error?: string };
        const patient = patientPayload.patients?.find((item) => item.passport === passport) ?? patientPayload.patients?.[0];
        if (!patientResponse.ok || !patient) throw new Error(patientPayload.error ?? "Paciente não localizado.");
        if (!cancelled) {
          setConsultationPrefill({ consultationId, patient, reason: consultationPayload.consultation?.final_diagnosis_plan || consultationPayload.consultation?.anamnesis || "" });
          setEditing(null);
        }
      } catch (cause) { if (!cancelled) setError(messageOf(cause)); }
    })();
    return () => { cancelled = true; };
  }, [canCreate]);

  async function refreshBoard(message?: string) {
    setLoading(true); setError("");
    try {
      const response = await fetch("/api/hospitalizations?view=board", { cache: "no-store" });
      const payload = await response.json() as HospitalBedBoard & { error?: string };
      if (!response.ok) throw new Error(payload.error ?? "Não foi possível atualizar os leitos.");
      setBoard(payload);
      if (message) setNotice(message);
      setDetail(null); setEditing(undefined); setAction(null);
      if (history) await loadHistory(1, filters);
    } catch (cause) { setError(messageOf(cause)); }
    finally { setLoading(false); }
  }

  async function loadHistory(page = 1, nextFilters = filters) {
    setLoading(true); setError("");
    try {
      const params = new URLSearchParams({ view: "history", page: String(page), pageSize: "20" });
      Object.entries(nextFilters).forEach(([key, value]) => { if (value) params.set(key, value); });
      const response = await fetch(`/api/hospitalizations?${params}`, { cache: "no-store" });
      const payload = await response.json() as HospitalizationPage & { error?: string };
      if (!response.ok) throw new Error(payload.error ?? "Não foi possível carregar o histórico.");
      setHistory(payload);
    } catch (cause) { setError(messageOf(cause)); }
    finally { setLoading(false); }
  }

  function changeMode(next: "board" | "history") {
    setMode(next); setError(""); setNotice("");
    if (next === "history" && !history) void loadHistory(1);
  }

  return <div className="bed-center">
    <section className="bed-toolbar">
      <div>
        <p className="eyebrow">Mapa assistencial</p>
        <h2>10 leitos compartilhados</h2>
        <p>A ocupação é calculada pelas internações ativas. Nenhum leito é alterado manualmente.</p>
      </div>
      <div className="bed-toolbar-actions">
        <div className="bed-view-switch" role="tablist" aria-label="Visualização de leitos">
          <button type="button" role="tab" aria-selected={mode === "board"} onClick={() => changeMode("board")}>Leitos</button>
          {canViewHistory ? <button type="button" role="tab" aria-selected={mode === "history"} onClick={() => changeMode("history")}>Histórico</button> : null}
        </div>
        {canCreate ? <button className="primary-button" type="button" disabled={board.available === 0} onClick={() => setEditing(null)}>Nova internação</button> : null}
      </div>
    </section>

    <section className="bed-summary" aria-label="Resumo dos leitos">
      <SummaryCard label="Disponíveis" value={`${board.available}/${board.total}`} tone="available" />
      <SummaryCard label="Ocupados" value={`${board.occupied}/${board.total}`} tone="occupied" />
      <SummaryCard label="HPSM" value={String(board.hpsm)} tone="hpsm" />
      <SummaryCard label="HP Norte" value={String(board.hp_norte)} tone="north" />
    </section>

    {notice ? <p className="form-success" role="status">{notice}</p> : null}
    {error ? <p className="form-error" role="alert">{error}</p> : null}

    {mode === "board" ? <section className="bed-grid" aria-label="Mapa dos dez leitos">
      {board.beds.map((bed) => <button className="bed-card" data-status={bed.hospitalization_id ? "occupied" : "available"} key={bed.id} type="button" onClick={() => bed.hospitalization_id ? setDetail(bed) : canCreate ? setEditing(bed) : undefined}>
        <header><span>{bed.label}</span><strong>{bed.hospitalization_id ? "OCUPADO" : "DISPONÍVEL"}</strong></header>
        {bed.hospitalization_id ? <>
          <div className="bed-patient"><b>{initials(bed.patient_name ?? "")}</b><span><strong>{bed.patient_name}</strong><small>{bed.patient_passport ? `Passaporte ${formatPatientPassport(bed.patient_passport)}` : "Sem passaporte informado"}</small></span></div>
          <footer><em data-source={bed.source}>{bed.source ? SOURCE_LABEL[bed.source] : "—"}</em><time>{bed.admitted_at ? formatDateTime(bed.admitted_at) : "—"}</time></footer>
        </> : <div className="bed-empty"><span>＋</span><strong>{canCreate ? "Registrar internação" : "Sem internação ativa"}</strong></div>}
      </button>)}
    </section> : <HistoryPanel board={board} data={history} filters={filters} loading={loading} onFilters={setFilters} onOpen={setHistoryDetail} onPage={(page) => void loadHistory(page)} onSearch={(next) => { setFilters(next); void loadHistory(1, next); }} />}

    {editing !== undefined ? <HospitalizationForm
      board={board}
      canSearchPatients={canSearchPatients}
      consultationPrefill={consultationPrefill}
      initialPatient={initialPatient}
      initial={editing}
      onClose={() => setEditing(undefined)}
      onSaved={(message) => void refreshBoard(message)}
    /> : null}
    {detail ? <ActiveDetail bed={detail} canDischarge={canDischarge} canUpdate={canUpdate} onAction={setAction} onClose={() => setDetail(null)} onEdit={() => { setEditing(detail); setDetail(null); }} /> : null}
    {action && detail ? <ActionDialog action={action} bed={detail} onClose={() => setAction(null)} onSaved={(message) => void refreshBoard(message)} /> : null}
    {historyDetail ? <HistoryDetail record={historyDetail} onClose={() => setHistoryDetail(null)} /> : null}
  </div>;
}

function SummaryCard({ label, tone, value }: { label: string; tone: string; value: string }) {
  return <article data-tone={tone}><span aria-hidden="true">●</span><div><small>{label}</small><strong>{value}</strong></div></article>;
}

export function HospitalizationForm({ board, canSearchPatients, consultationPrefill, initialPatient = null, initial, inline = false, onClose, onSaved }: {
  board: HospitalBedBoard;
  canSearchPatients: boolean;
  consultationPrefill: ConsultationHospitalizationPrefill | null;
  initialPatient?: Patient | null;
  initial: HospitalBed | null;
  inline?: boolean;
  onClose: () => void;
  onSaved: (message: string) => void;
}) {
  const editing = Boolean(initial?.hospitalization_id);
  const [bedId, setBedId] = useState(String(initial?.id ?? firstAvailableBed(board)?.id ?? ""));
  const [source, setSource] = useState<HospitalizationSource>(initial?.source ?? "hpsm");
  const [patient, setPatient] = useState<Patient | null>(initial?.patient_id ? minimalPatient(initial) : consultationPrefill?.patient ?? initialPatient);
  const [patientSearch, setPatientSearch] = useState(initial?.patient_passport ?? consultationPrefill?.patient.passport ?? initialPatient?.passport ?? "");
  const [externalName, setExternalName] = useState(initial?.source === "hp_norte" ? initial.patient_name ?? "" : "");
  const [externalPassport, setExternalPassport] = useState(initial?.source === "hp_norte" ? initial.patient_passport ?? "" : "");
  const [admittedAt, setAdmittedAt] = useState(toLocalInput(initial?.admitted_at ?? new Date().toISOString()));
  const [reason, setReason] = useState(initial?.reason ?? consultationPrefill?.reason ?? "");
  const [notes, setNotes] = useState(initial?.notes ?? consultationPrefill?.notes ?? "");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  async function submit(event: FormEvent) {
    event.preventDefault(); setLoading(true); setError("");
    try {
      const response = await fetch("/api/hospitalizations", {
        method: "POST", headers: { "content-type": "application/json" },
        body: JSON.stringify({
          action: editing ? "update" : "create", admittedAt: new Date(admittedAt).toISOString(), bedId: Number(bedId), externalPassport,
          externalPatientName: externalName, hospitalizationId: initial?.hospitalization_id, notes,
          patientId: patient?.id, reason, source, consultationId: consultationPrefill?.consultationId,
        }),
      });
      const payload = await response.json() as { error?: string };
      if (!response.ok) throw new Error(payload.error ?? "Não foi possível salvar a internação.");
      onSaved(editing ? "Internação corrigida e auditoria atualizada." : "Internação registrada e leito ocupado com segurança.");
    } catch (cause) { setError(messageOf(cause)); }
    finally { setLoading(false); }
  }

  const form = <form className="bed-form" onSubmit={submit}>
      {error ? <p className="form-error bed-full" role="alert">{error}</p> : null}
      <label>Leito<select value={bedId} onChange={(event) => setBedId(event.target.value)} required>
        <option value="">Selecione</option>
        {board.beds.map((bed) => <option key={bed.id} value={bed.id} disabled={Boolean(bed.hospitalization_id && bed.id !== initial?.id)}>{bed.label}{bed.hospitalization_id && bed.id !== initial?.id ? " · ocupado" : ""}</option>)}
      </select></label>
      <label>Origem<select value={source} disabled={Boolean(consultationPrefill)} onChange={(event) => { setSource(event.target.value as HospitalizationSource); setPatient(null); setPatientSearch(""); }}><option value="hpsm">HPSM</option><option value="hp_norte">HP Norte</option></select></label>
      {source === "hpsm" ? <div className="bed-full bed-patient-field">
        {!consultationPrefill ? <PatientPassportCombobox label="Paciente HPSM · passaporte" value={patientSearch} selectedPatient={patient} showSelectedSummary={false} disabled={!canSearchPatients} onValueChange={(value) => { setPatient(null); setPatientSearch(value); }} onSelect={(item) => { setPatient(item); setPatientSearch(item.passport); }} /> : null}
        {patient ? <div className="bed-selected-patient"><b>{initials(patient.name)}</b><span><strong>{patient.name}</strong><small>Passaporte {formatPatientPassport(patient.passport)}</small></span>{!consultationPrefill ? <button type="button" onClick={() => { setPatient(null); setPatientSearch(""); }}>Trocar</button> : null}</div> : null}
        {!canSearchPatients ? <small>Seu acesso não permite consultar o cadastro de pacientes HPSM.</small> : null}
      </div> : <>
        <label>Nome do paciente externo<input value={externalName} onChange={(event) => setExternalName(event.target.value)} maxLength={120} required /></label>
        <label>Passaporte externo (opcional)<input value={externalPassport} onChange={(event) => setExternalPassport(event.target.value.toUpperCase())} maxLength={32} /></label>
      </>}
      <label className="bed-full">Data e hora da internação<input type="datetime-local" value={admittedAt} onChange={(event) => setAdmittedAt(event.target.value)} required /></label>
      <label className="bed-full">Motivo da internação<textarea value={reason} onChange={(event) => setReason(event.target.value)} minLength={2} maxLength={2000} required /></label>
      <label className="bed-full">Observações (opcional)<textarea value={notes} onChange={(event) => setNotes(event.target.value)} maxLength={2000} /></label>
      <footer className="bed-form-actions"><HpsmButton variant="ghost" type="button" onClick={onClose}>Cancelar</HpsmButton><HpsmButton variant="primary" loading={loading} type="submit" disabled={!bedId || (source === "hpsm" && !patient)}>{loading ? "Salvando…" : editing ? "Salvar correção" : "Registrar internação"}</HpsmButton></footer>
    </form>;
  if (inline) return <section className="inline-module-panel"><header><div><span className="consultation-kicker">Conduta vinculada</span><h4>Nova internação</h4><p>Origem HPSM e paciente permanecem fixos nesta admissão.</p></div></header>{form}</section>;
  return <Modal title={editing ? "Corrigir internação" : "Nova internação"} subtitle="A origem define se o paciente será vinculado ao cadastro HPSM ou registrado somente como externo." onClose={onClose}>{form}</Modal>;
}

function ActiveDetail({ bed, canDischarge, canUpdate, onAction, onClose, onEdit }: { bed: HospitalBed; canDischarge: boolean; canUpdate: boolean; onAction: (action: "discharge" | "cancel") => void; onClose: () => void; onEdit: () => void }) {
  return <Modal title={`${bed.label} · Internação ativa`} subtitle={`${bed.source ? SOURCE_LABEL[bed.source] : "—"} · entrada em ${bed.admitted_at ? formatDateTime(bed.admitted_at) : "—"}`} onClose={onClose}>
    <div className="bed-detail">
      <dl><div><dt>Paciente</dt><dd>{bed.patient_name}</dd></div><div><dt>Passaporte</dt><dd>{bed.patient_passport ? formatPatientPassport(bed.patient_passport) : "Não informado"}</dd></div><div><dt>Motivo</dt><dd>{bed.reason}</dd></div><div><dt>Observações</dt><dd>{bed.notes ?? "Sem observações"}</dd></div><div><dt>Registrado por</dt><dd>{bed.admitted_by_name ?? "Profissional não informado"}</dd></div></dl>
      {bed.patient_id ? <Link href={`/pacientes/${bed.patient_id}`}>Abrir perfil do paciente →</Link> : <p className="bed-external-note">Paciente externo do HP Norte, sem criação de cadastro HPSM.</p>}
      <footer>{canUpdate ? <><button type="button" onClick={onEdit}>Corrigir dados</button><button className="danger-button" type="button" onClick={() => onAction("cancel")}>Cancelar registro</button></> : null}{canDischarge ? <button className="primary-button" type="button" onClick={() => onAction("discharge")}>Registrar alta</button> : null}</footer>
    </div>
  </Modal>;
}

function ActionDialog({ action, bed, onClose, onSaved }: { action: "discharge" | "cancel"; bed: HospitalBed; onClose: () => void; onSaved: (message: string) => void }) {
  const [dischargedAt, setDischargedAt] = useState(toLocalInput(new Date().toISOString()));
  const [reason, setReason] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  async function submit(event: FormEvent) {
    event.preventDefault(); setLoading(true); setError("");
    try {
      const response = await fetch("/api/hospitalizations", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ action, dischargedAt: new Date(dischargedAt).toISOString(), hospitalizationId: bed.hospitalization_id, reason }) });
      const payload = await response.json() as { error?: string };
      if (!response.ok) throw new Error(payload.error ?? "Não foi possível concluir a operação.");
      onSaved(action === "discharge" ? "Alta registrada; o leito está disponível novamente." : "Registro cancelado com motivo; o leito está disponível novamente.");
    } catch (cause) { setError(messageOf(cause)); }
    finally { setLoading(false); }
  }
  return <Modal title={action === "discharge" ? `Registrar alta · ${bed.label}` : `Cancelar registro · ${bed.label}`} subtitle={action === "discharge" ? "A data da alta deve ser igual ou posterior à internação." : "Use cancelamento somente para corrigir um registro criado indevidamente."} onClose={onClose}>
    <form className="bed-action-form" onSubmit={submit}>
      {error ? <p className="form-error" role="alert">{error}</p> : null}
      {action === "discharge" ? <label>Data e hora da alta<input type="datetime-local" min={bed.admitted_at ? toLocalInput(bed.admitted_at) : undefined} value={dischargedAt} onChange={(event) => setDischargedAt(event.target.value)} required /></label> : <label>Motivo do cancelamento<textarea value={reason} onChange={(event) => setReason(event.target.value)} minLength={2} maxLength={500} required /></label>}
      <footer className="bed-form-actions"><button type="button" onClick={onClose}>Voltar</button><button className={action === "cancel" ? "danger-button" : "primary-button"} type="submit" disabled={loading}>{loading ? "Salvando…" : action === "discharge" ? "Confirmar alta" : "Confirmar cancelamento"}</button></footer>
    </form>
  </Modal>;
}

function HistoryPanel({ board, data, filters, loading, onFilters, onOpen, onPage, onSearch }: { board: HospitalBedBoard; data: HospitalizationPage | null; filters: Filters; loading: boolean; onFilters: (filters: Filters) => void; onOpen: (record: HospitalizationRecord) => void; onPage: (page: number) => void; onSearch: (filters: Filters) => void }) {
  const pages = data ? Math.max(1, Math.ceil(data.total / data.pageSize)) : 1;
  return <section className="bed-history">
    <form className="bed-history-filters" onSubmit={(event) => { event.preventDefault(); onSearch(filters); }}>
      <label>Paciente ou passaporte<input value={filters.search} onChange={(event) => onFilters({ ...filters, search: event.target.value })} placeholder="Buscar" /></label>
      <label>Origem<select value={filters.source} onChange={(event) => onFilters({ ...filters, source: event.target.value })}><option value="">Todas</option><option value="hpsm">HPSM</option><option value="hp_norte">HP Norte</option></select></label>
      <label>Leito<select value={filters.bedId} onChange={(event) => onFilters({ ...filters, bedId: event.target.value })}><option value="">Todos</option>{board.beds.map((bed) => <option key={bed.id} value={bed.id}>{bed.label}</option>)}</select></label>
      <label>Status<select value={filters.status} onChange={(event) => onFilters({ ...filters, status: event.target.value })}><option value="">Todos</option><option value="active">Ativa</option><option value="discharged">Alta</option><option value="cancelled">Cancelada</option></select></label>
      <label>De<input type="date" value={filters.dateFrom} onChange={(event) => onFilters({ ...filters, dateFrom: event.target.value })} /></label>
      <label>Até<input type="date" value={filters.dateTo} onChange={(event) => onFilters({ ...filters, dateTo: event.target.value })} /></label>
      <div><button type="button" onClick={() => { onFilters(EMPTY_FILTERS); onSearch(EMPTY_FILTERS); }}>Limpar</button><button className="primary-button" type="submit">Filtrar</button></div>
    </form>
    {loading && !data ? <div className="bed-history-loading" role="status">Carregando histórico…</div> : null}
    {data && !data.items.length ? <div className="empty-state"><span>▥</span><strong>Nenhuma internação encontrada</strong><p>Ajuste os filtros para consultar outro período.</p></div> : null}
    {data?.items.length ? <div className="bed-history-list">{data.items.map((item) => <button key={item.id} type="button" onClick={() => onOpen(item)}>
      <span className="bed-history-code">IN-{String(item.id).padStart(6, "0")}</span>
      <span><strong>{item.patient_name}</strong><small>{item.patient_passport ? `Passaporte ${formatPatientPassport(item.patient_passport)}` : "Sem passaporte"}</small></span>
      <span><strong>{item.bed_label}</strong><small>{SOURCE_LABEL[item.source]}</small></span>
      <time>{formatDateTime(item.admitted_at)}</time>
      <em data-status={item.status}>{STATUS_LABEL[item.status]}</em>
    </button>)}</div> : null}
    {data && data.total > data.pageSize ? <div className="bed-pagination"><button type="button" disabled={loading || data.page <= 1} onClick={() => onPage(data.page - 1)}>← Anterior</button><span>Página {data.page} de {pages}</span><button type="button" disabled={loading || data.page >= pages} onClick={() => onPage(data.page + 1)}>Próxima →</button></div> : null}
  </section>;
}

function HistoryDetail({ onClose, record }: { onClose: () => void; record: HospitalizationRecord }) {
  return <Modal title={`IN-${String(record.id).padStart(6, "0")} · ${record.bed_label}`} subtitle={`${SOURCE_LABEL[record.source]} · ${STATUS_LABEL[record.status]}`} onClose={onClose}>
    <div className="bed-detail"><dl>
      <div><dt>Paciente</dt><dd>{record.patient_name}</dd></div><div><dt>Passaporte</dt><dd>{record.patient_passport ? formatPatientPassport(record.patient_passport) : "Não informado"}</dd></div>
      <div><dt>Internação</dt><dd>{formatDateTime(record.admitted_at)} · {record.admitted_by_name}</dd></div>
      <div><dt>Motivo</dt><dd>{record.reason}</dd></div><div><dt>Observações</dt><dd>{record.notes ?? "Sem observações"}</dd></div>
      {record.discharged_at ? <div><dt>Alta</dt><dd>{formatDateTime(record.discharged_at)} · {record.discharged_by_name ?? "Profissional não informado"}</dd></div> : null}
      {record.cancelled_at ? <div><dt>Cancelamento</dt><dd>{formatDateTime(record.cancelled_at)} · {record.cancellation_reason}</dd></div> : null}
    </dl>{record.patient_id ? <Link href={`/pacientes/${record.patient_id}`}>Abrir perfil do paciente →</Link> : <p className="bed-external-note">Registro externo do HP Norte.</p>}</div>
  </Modal>;
}

function Modal({ children, onClose, subtitle, title }: { children: React.ReactNode; onClose: () => void; subtitle: string; title: string }) {
  return <div className="bed-modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}><section className="bed-modal" role="dialog" aria-modal="true" aria-label={title}><header><div><h2>{title}</h2><p>{subtitle}</p></div><button type="button" aria-label="Fechar" onClick={onClose}>×</button></header>{children}</section></div>;
}

function firstAvailableBed(board: HospitalBedBoard) { return board.beds.find((bed) => !bed.hospitalization_id); }
function messageOf(cause: unknown) { return cause instanceof Error ? cause.message : "Não foi possível concluir a operação."; }
function initials(name: string) { return name.trim().split(/\s+/).slice(0, 2).map((part) => part[0]).join("").toUpperCase() || "—"; }
function formatDateTime(value: string) { return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(value)); }
function toLocalInput(value: string) {
  const date = new Date(value);
  const parts = new Intl.DateTimeFormat("en-CA", { day: "2-digit", hour: "2-digit", hour12: false, minute: "2-digit", month: "2-digit", timeZone: "America/Sao_Paulo", year: "numeric" }).formatToParts(date);
  const get = (type: Intl.DateTimeFormatPartTypes) => parts.find((part) => part.type === type)?.value ?? "";
  return `${get("year")}-${get("month")}-${get("day")}T${get("hour") === "24" ? "00" : get("hour")}:${get("minute")}`;
}

function minimalPatient(bed: HospitalBed): Patient {
  return {
    id: bed.patient_id as number, name: bed.patient_name ?? "", passport: bed.patient_passport ?? "", phone: null,
    allergies: null, birth_date: null, created_at: bed.admitted_at ?? "", emergency_contact_name: null,
    emergency_contact_phone: null, health_plan: { activated_at: null, authorized_by: null, authorized_by_name: null, pending_request_id: null, pending_requested_at: null, status: "none", valid_until: null },
    updated_at: bed.admitted_at ?? "",
  };
}
