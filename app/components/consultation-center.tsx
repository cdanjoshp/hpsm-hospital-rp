"use client";

import { useEffect, useMemo, useState, type FormEvent } from "react";
import type { Patient } from "../lib/operational-data";
import type { AppointmentStatus, ConsultationPage, ConsultationReferenceData, ConsultationScheduleItem } from "../lib/consultations";
import { HpsmButton, HpsmButtonLink } from "./hpsm-button";
import { HpsmDialog } from "./hpsm-dialog";
import { PatientPassportCombobox } from "./patient-passport-combobox";
import { useModalFocus } from "./use-modal-focus";

const statusLabel: Record<AppointmentStatus, string> = {
  scheduled: "Agendada", confirmed: "Confirmada", in_progress: "Em consulta", completed: "Concluída", cancelled: "Cancelada", no_show: "Não compareceu",
};
type MutationResult = { ok: true } | { ok: false; error: string };

export function ConsultationCenter({ canCreate, canDeleteAppointment, canManage, currentUserId, focusAppointmentId, initialData, initialSearch = "", initialStatus = "all", initialWalkInPatient = null, openWalkIn = false, references }: {
  canCreate: boolean; canDeleteAppointment: boolean; canManage: boolean; currentUserId: string; focusAppointmentId?: number | null; initialData: ConsultationPage; initialSearch?: string; initialStatus?: string; initialWalkInPatient?: Patient | null; openWalkIn?: boolean; references: ConsultationReferenceData;
}) {
  const [data, setData] = useState(initialData);
  const [view, setView] = useState<"list" | "day" | "week">("list");
  const [anchorDate, setAnchorDate] = useState(localDate(new Date()));
  const [search, setSearch] = useState(initialSearch);
  const [status, setStatus] = useState(initialStatus);
  const [professionalId, setProfessionalId] = useState("");
  const [mine, setMine] = useState(false);
  const [creating, setCreating] = useState(false);
  const [walkIn, setWalkIn] = useState(openWalkIn);
  const [pendingStatus, setPendingStatus] = useState<{ item: ConsultationScheduleItem; status: "cancelled" | "no_show" } | null>(null);
  const [pendingDelete, setPendingDelete] = useState<ConsultationScheduleItem | null>(null);
  const [deleteConfirmation, setDeleteConfirmation] = useState("");
  const [viewing, setViewing] = useState<ConsultationScheduleItem | null>(null);
  const [statusReason, setStatusReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(focusAppointmentId && !initialData.items.some((item) => item.appointment_id === focusAppointmentId) ? "Este agendamento não está mais entre as consultas pendentes. Atualize a agenda para consultar o estado atual." : "");

  const visibleItems = useMemo(() => data.items.filter((item) => withinView(item.starts_at, view, anchorDate)), [anchorDate, data.items, view]);

  useEffect(() => {
    if (!focusAppointmentId) return;
    document.getElementById(`agendamento-${focusAppointmentId}`)?.scrollIntoView({ block: "center", behavior: "smooth" });
  }, [focusAppointmentId]);

  async function reload(overrides: { search?: string; status?: string; professionalId?: string; mine?: boolean } = {}) {
    const next = { search: overrides.search ?? search, status: overrides.status ?? status, professionalId: overrides.professionalId ?? professionalId, mine: overrides.mine ?? mine };
    setBusy(true); setError("");
    try {
      const query = new URLSearchParams({ view: "list", pageSize: "100" });
      if (next.search) query.set("search", next.search);
      if (next.status !== "all") query.set("status", next.status);
      if (next.professionalId) query.set("professionalId", next.professionalId);
      if (next.mine) query.set("mine", "true");
      const response = await fetch(`/api/consultations?${query}`, { cache: "no-store" });
      const payload = await response.json() as ConsultationPage & { error?: string };
      if (!response.ok) throw new Error(payload.error || "Não foi possível atualizar a agenda.");
      setData(payload);
    } catch (reason) { setError(reason instanceof Error ? reason.message : "Não foi possível atualizar a agenda."); }
    finally { setBusy(false); }
  }

  async function mutate(body: Record<string, unknown>, surfaceError = true): Promise<MutationResult> {
    setBusy(true); if (surfaceError) setError("");
    try {
      const response = await fetch("/api/consultations", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
      const payload = await response.json() as { consultationId?: number; error?: string };
      if (!response.ok) throw new Error(payload.error || "Não foi possível concluir a operação.");
      if (payload.consultationId) { window.location.assign(`/consultas/${payload.consultationId}`); return { ok: true }; }
      await reload();
      return { ok: true };
    } catch (reason) {
      const nextError = reason instanceof Error ? reason.message : "Não foi possível concluir a operação.";
      if (surfaceError) setError(nextError);
      return { ok: false, error: nextError };
    }
    finally { setBusy(false); }
  }

  return <div className="consultation-center">
    <section className="consultation-hero">
      <div><span className="consultation-kicker">Agenda clínica</span><h2>Consultas e Agendamentos</h2><p>Agenda e evolução clínica em um fluxo próprio, sem criar venda, procedimento financeiro ou meta de jornada.</p></div>
      <div className="consultation-hero-actions"><HpsmButtonLink href="/consultas/protocolos">Protocolos clínicos</HpsmButtonLink>{canCreate ? <><HpsmButton onClick={() => setWalkIn(true)}>Consulta sem agendamento</HpsmButton><HpsmButton variant="primary" onClick={() => { setError(""); setCreating(true); }}>Nova consulta</HpsmButton></> : null}</div>
    </section>

    <section className="consultation-toolbar" aria-label="Filtros da agenda">
      <div className="consultation-view-switch" role="group" aria-label="Modo de visualização">
        {(["list", "day", "week"] as const).map((mode) => <button aria-pressed={view === mode} className={view === mode ? "active" : ""} key={mode} onClick={() => setView(mode)}>{mode === "list" ? "Lista" : mode === "day" ? "Dia" : "Semana"}</button>)}
      </div>
      {view !== "list" ? <label>Data<input type="date" value={anchorDate} onChange={(event) => setAnchorDate(event.target.value)} /></label> : null}
      <label className="consultation-search">Paciente, passaporte ou profissional<input value={search} onChange={(event) => setSearch(event.target.value)} onKeyDown={(event) => { if (event.key === "Enter") void reload(); }} placeholder="Buscar na agenda" /></label>
      <label>Status<select value={status} onChange={(event) => { setStatus(event.target.value); void reload({ status: event.target.value }); }}><option value="all">Todos</option>{Object.entries(statusLabel).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label>
      <label>Profissional<select value={professionalId} onChange={(event) => { setProfessionalId(event.target.value); void reload({ professionalId: event.target.value }); }}><option value="">Todos</option>{references.professionals.map((item) => <option value={item.id} key={item.id}>{item.name}</option>)}</select></label>
      <label className="consultation-check"><input type="checkbox" checked={mine} onChange={(event) => { setMine(event.target.checked); void reload({ mine: event.target.checked }); }} /> Minhas</label>
      <HpsmButton disabled={busy} loading={busy} onClick={() => void reload()}>{busy ? "Atualizando…" : "Atualizar"}</HpsmButton>
    </section>

    {error ? <p className="form-error" role="alert">{error}</p> : null}
    <section className="consultation-list" aria-live="polite">
      <header><div><strong>{visibleItems.length}</strong><span>registros nesta visualização</span></div><small>{view === "list" ? "Histórico e próximos horários" : view === "day" ? `Agenda de ${formatDate(anchorDate)}` : `Semana de ${formatWeek(anchorDate)}`}</small></header>
      {visibleItems.length ? visibleItems.map((item) => <ScheduleCard busy={busy} canCreate={canCreate} canDeleteAppointment={canDeleteAppointment} currentUserId={currentUserId} focused={item.appointment_id === focusAppointmentId} item={item} key={`${item.walk_in ? "c" : "a"}-${item.consultation_id ?? item.appointment_id}`} onMutate={mutate} onRequestDelete={() => { setDeleteConfirmation(""); setPendingDelete(item); }} onRequestStatus={(nextStatus) => { setStatusReason(""); setPendingStatus({ item, status: nextStatus }); }} onView={() => setViewing(item)} />) : <div className="consultation-empty"><strong>Nenhuma consulta encontrada</strong><p>Ajuste os filtros ou crie um novo agendamento.</p></div>}
    </section>

    {creating ? <AppointmentDialog canManage={canManage} currentUserId={currentUserId} professionals={references.professionals} onClose={() => setCreating(false)} onCreated={async (body) => { const result = await mutate(body, false); if (result.ok) setCreating(false); return result; }} /> : null}
    {walkIn ? <WalkInDialog initialPatient={initialWalkInPatient} onClose={() => setWalkIn(false)} onStart={(patientId) => mutate({ action: "walk-in", patientId }, false)} /> : null}
    {pendingStatus ? <HpsmDialog
      confirmLabel={pendingStatus.status === "cancelled" ? "Cancelar agendamento" : "Registrar ausência"}
      confirmVariant="destructive"
      description={pendingStatus.status === "cancelled" ? `Informe o motivo para cancelar o agendamento de ${pendingStatus.item.patient_name}.` : `Confirme que ${pendingStatus.item.patient_name} não compareceu ao horário agendado.`}
      loading={busy}
      onClose={() => setPendingStatus(null)}
      onConfirm={() => {
        if (pendingStatus.status === "cancelled" && statusReason.trim().length < 3) return;
        const current = pendingStatus;
        void mutate({ action: "status", appointmentId: current.item.appointment_id, status: current.status, reason: current.status === "cancelled" ? statusReason.trim() : undefined }).then((result) => { if (result.ok) setPendingStatus(null); });
      }}
      title={pendingStatus.status === "cancelled" ? "Cancelar consulta" : "Registrar não comparecimento"}
    >{pendingStatus.status === "cancelled" ? <label className="dialog-field">Motivo do cancelamento<textarea autoFocus maxLength={1000} minLength={3} required rows={3} value={statusReason} onChange={(event) => setStatusReason(event.target.value)} /></label> : null}</HpsmDialog> : null}
    {pendingDelete ? <HpsmDialog
      confirmLabel={deleteConfirmation === `EXCLUIR ${pendingDelete.appointment_id}` ? "Excluir definitivamente" : undefined}
      confirmVariant="destructive"
      description={`O agendamento de ${pendingDelete.patient_name} será removido da agenda e do histórico do paciente. A exclusão não pode ser desfeita; o registro de auditoria será preservado.`}
      loading={busy}
      onClose={() => { setPendingDelete(null); setDeleteConfirmation(""); }}
      onConfirm={deleteConfirmation === `EXCLUIR ${pendingDelete.appointment_id}` ? () => {
        void mutate({ action: "delete-terminal-appointment", appointmentId: pendingDelete.appointment_id }).then((result) => {
          if (result.ok) { setPendingDelete(null); setDeleteConfirmation(""); }
        });
      } : undefined}
      title={pendingDelete.status === "no_show" ? "Excluir registro de não comparecimento" : "Excluir agendamento cancelado"}
    >
      {error ? <p className="form-error" role="alert">{error}</p> : null}
      <label className="consultation-delete-confirmation">Digite <strong>EXCLUIR {pendingDelete.appointment_id}</strong> para confirmar<input autoComplete="off" autoFocus disabled={busy} value={deleteConfirmation} onChange={(event) => setDeleteConfirmation(event.target.value.toUpperCase())} /></label>
    </HpsmDialog> : null}
    {viewing ? <HpsmDialog description={`${formatDateTime(viewing.starts_at)} · ${viewing.professional_name}${viewing.professional_position ? ` · ${viewing.professional_position}` : ""}`} onClose={() => setViewing(null)} title={`${statusLabel[viewing.status]} · ${viewing.patient_name}`}><dl className="consultation-appointment-facts"><div><dt>Paciente</dt><dd>{viewing.patient_name}</dd></div><div><dt>Passaporte</dt><dd>{viewing.patient_passport}</dd></div><div><dt>Motivo</dt><dd>{viewing.reason}</dd></div><div><dt>Status</dt><dd>{statusLabel[viewing.status]}</dd></div></dl></HpsmDialog> : null}
  </div>;
}

function ScheduleCard({ busy, canCreate, canDeleteAppointment, currentUserId, focused, item, onMutate, onRequestDelete, onRequestStatus, onView }: { busy: boolean; canCreate: boolean; canDeleteAppointment: boolean; currentUserId: string; focused: boolean; item: ConsultationScheduleItem; onMutate: (body: Record<string, unknown>) => Promise<MutationResult>; onRequestDelete: () => void; onRequestStatus: (status: "cancelled" | "no_show") => void; onView: () => void }) {
  const own = item.professional_id === currentUserId;
  return <article className="consultation-card" id={item.appointment_id ? `agendamento-${item.appointment_id}` : undefined} data-focused={focused}>
    <time dateTime={item.starts_at}><strong>{new Intl.DateTimeFormat("pt-BR", { hour: "2-digit", minute: "2-digit", timeZone: "America/Sao_Paulo" }).format(new Date(item.starts_at))}</strong><span>{new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "short", timeZone: "America/Sao_Paulo" }).format(new Date(item.starts_at))}</span></time>
    <div className="consultation-card-main"><div className="consultation-card-title"><h3>{item.patient_name}</h3><span className={`consultation-status status-${item.status}`}>{statusLabel[item.status]}</span>{item.walk_in ? <span className="consultation-origin">Demanda espontânea</span> : null}</div><p>{item.reason}</p><small>Passaporte {item.patient_passport} · {item.professional_name}{item.professional_position ? ` · ${item.professional_position}` : ""}</small></div>
    <div className="consultation-card-actions">
      {item.consultation_id ? <HpsmButtonLink href={`/consultas/${item.consultation_id}`}>{item.status === "completed" ? "Ver prontuário" : "Abrir consulta"}</HpsmButtonLink> : null}
      {!item.consultation_id && own && canCreate && (item.status === "scheduled" || item.status === "confirmed") ? <HpsmButton variant="primary" disabled={busy} onClick={() => void onMutate({ action: "start", appointmentId: item.appointment_id })}>Iniciar</HpsmButton> : null}
      {!item.consultation_id && canCreate && (item.status === "scheduled" || item.status === "confirmed") ? <><HpsmButton variant="destructive" disabled={busy} onClick={() => onRequestStatus("cancelled")}>Cancelar</HpsmButton><HpsmButton variant="ghost" disabled={busy} onClick={() => onRequestStatus("no_show")}>Não compareceu</HpsmButton></> : null}
      {!item.consultation_id && (item.status === "cancelled" || item.status === "no_show") ? <HpsmButton variant="ghost" onClick={onView}>Visualizar</HpsmButton> : null}
      {canDeleteAppointment && !item.consultation_id && item.appointment_id && (item.status === "cancelled" || item.status === "no_show") ? <HpsmButton variant="destructive" disabled={busy} onClick={onRequestDelete}>Excluir</HpsmButton> : null}
    </div>
  </article>;
}

function AppointmentDialog({ canManage, currentUserId, professionals, onClose, onCreated }: { canManage: boolean; currentUserId: string; professionals: ConsultationReferenceData["professionals"]; onClose: () => void; onCreated: (body: Record<string, unknown>) => Promise<MutationResult> }) {
  const [patient, setPatient] = useState<Patient | null>(null); const [passport, setPassport] = useState(""); const [busy, setBusy] = useState(false); const [error, setError] = useState("");
  const dialogRef = useModalFocus<HTMLFormElement>(onClose);
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!patient) { setError("Selecione um paciente antes de agendar."); return; }
    const form = new FormData(event.currentTarget);
    const scheduledDate = new Date(String(form.get("scheduledStart")));
    if (Number.isNaN(scheduledDate.getTime())) { setError("Informe uma data e hora válidas."); return; }
    setBusy(true); setError("");
    const result = await onCreated({ action: "schedule", patientId: patient.id, professionalId: canManage ? form.get("professionalId") : currentUserId, scheduledStart: scheduledDate.toISOString(), durationMinutes: 30, reason: form.get("reason"), notes: form.get("notes") });
    if (!result.ok) setError(result.error);
    setBusy(false);
  }
  return <div className="consultation-dialog-backdrop" role="presentation"><form ref={dialogRef} className="consultation-dialog" role="dialog" aria-modal="true" aria-labelledby="appointment-dialog-title" tabIndex={-1} onSubmit={submit}><header><div><span className="consultation-kicker">Agenda</span><h2 id="appointment-dialog-title">Novo agendamento</h2></div><HpsmButton aria-label="Fechar" variant="ghost" onClick={onClose} type="button">×</HpsmButton></header>{error ? <p className="form-error" role="alert">{error}</p> : null}<PatientPassportCombobox value={passport} onValueChange={(value) => { setPassport(value); setPatient(null); setError(""); }} onSelect={(value) => { setPatient(value); setPassport(value.passport); setError(""); }} selectedPatient={patient} /><div className="consultation-form-grid"><label>Profissional<select name="professionalId" defaultValue={currentUserId} disabled={!canManage}>{professionals.map((item) => <option key={item.id} value={item.id}>{item.name}{item.position ? ` · ${item.position}` : ""}</option>)}</select></label><label>Data e hora<input required name="scheduledStart" type="datetime-local" onChange={() => setError("")} /></label><label className="wide">Motivo / tipo<input required minLength={3} maxLength={500} name="reason" placeholder="Motivo principal da consulta" onChange={() => setError("")} /></label><label className="wide">Observações opcionais<textarea maxLength={4000} name="notes" rows={3} /></label></div><footer><HpsmButton variant="ghost" onClick={onClose} type="button">Voltar</HpsmButton><HpsmButton variant="primary" loading={busy} disabled={!patient || busy} type="submit">{busy ? "Agendando…" : "Agendar consulta"}</HpsmButton></footer></form></div>;
}

function WalkInDialog({ initialPatient, onClose, onStart }: { initialPatient: Patient | null; onClose: () => void; onStart: (patientId: number) => Promise<MutationResult> }) {
  const [patient, setPatient] = useState<Patient | null>(initialPatient);
  const [passport, setPassport] = useState(initialPatient?.passport ?? "");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const dialogRef = useModalFocus<HTMLDivElement>(onClose);

  async function start() {
    if (!patient || busy) return;
    setBusy(true);
    setError("");
    try {
      const result = await onStart(patient.id);
      if (!result.ok) setError(result.error);
    } finally { setBusy(false); }
  }

  return <div className="consultation-dialog-backdrop" role="presentation"><div ref={dialogRef} className="consultation-dialog compact" role="dialog" aria-modal="true" aria-labelledby="walk-in-dialog-title" tabIndex={-1}>
    <header><div><span className="consultation-kicker">Demanda espontânea</span><h2 id="walk-in-dialog-title">Iniciar consulta agora</h2></div><HpsmButton aria-label="Fechar" variant="ghost" onClick={onClose}>×</HpsmButton></header>
    <p>Selecione o paciente. Nenhuma venda ou atendimento financeiro será criado.</p>
    {error ? <p className="form-error" role="alert">{error}</p> : null}
    <PatientPassportCombobox value={passport} onValueChange={(value) => { setPassport(value); setPatient(null); setError(""); }} onSelect={(value) => { setPatient(value); setPassport(value.passport); setError(""); }} selectedPatient={patient} />
    <footer><HpsmButton variant="ghost" onClick={onClose}>Voltar</HpsmButton><HpsmButton variant="primary" loading={busy} disabled={!patient} onClick={() => void start()}>{busy ? "Iniciando…" : "Iniciar consulta"}</HpsmButton></footer>
  </div></div>;
}

function withinView(timestamp: string, view: "list" | "day" | "week", anchor: string) { if (view === "list") return true; const date = new Date(timestamp); const target = new Date(`${anchor}T12:00:00`); if (view === "day") return localDate(date) === anchor; const start = new Date(target); start.setDate(start.getDate() - ((start.getDay() + 6) % 7)); const end = new Date(start); end.setDate(end.getDate() + 7); return date >= start && date < end; }
function localDate(date: Date) { return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Sao_Paulo" }).format(date); }
function formatDate(value: string) { return new Intl.DateTimeFormat("pt-BR", { dateStyle: "long", timeZone: "America/Sao_Paulo" }).format(new Date(`${value}T12:00:00`)); }
function formatWeek(value: string) { const date = new Date(`${value}T12:00:00`); date.setDate(date.getDate() - ((date.getDay() + 6) % 7)); return formatDate(localDate(date)); }
function formatDateTime(value: string) { return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(value)); }
