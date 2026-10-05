"use client";

import Link from "next/link";
import { FormEvent, useEffect, useRef, useState } from "react";
import { castBodyRegionLabel, castLateralityLabel } from "../lib/cast-types";
import type { Patient } from "../lib/operational-data";
import { formatPatientPassport } from "../lib/passport";
import { PatientPassportCombobox } from "./patient-passport-combobox";
import { HpsmButton } from "./hpsm-button";
import { MedicalCertificateCopyLinkAction, MedicalCertificateDocumentActions } from "./medical-certificate-document-actions";
import {
  type MedicalCertificateDetail,
  type MedicalCertificatePage,
  type MedicalCertificateReferenceOptions,
  type MedicalCertificateStatus,
} from "../lib/medical-certificates";

const STATUS_LABEL: Record<MedicalCertificateStatus, string> = { cancelled: "Cancelado", draft: "Rascunho", finalized: "Finalizado" };
export type CurrentProfessional = { id: string; name: string; position: string | null };

export function MedicalCertificateCenter({ canCancel, canCreate, canFinalize, currentProfessional, initialData }: {
  canCancel: boolean;
  canCreate: boolean;
  canFinalize: boolean;
  currentProfessional: CurrentProfessional;
  initialData: MedicalCertificatePage;
}) {
  const [data, setData] = useState(initialData);
  const [status, setStatus] = useState<MedicalCertificateStatus | "all">("all");
  const [search, setSearch] = useState("");
  const [dateFrom, setDateFrom] = useState("");
  const [dateTo, setDateTo] = useState("");
  const [filtersOpen, setFiltersOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [creating, setCreating] = useState(false);
  const [quickPassport, setQuickPassport] = useState("");
  const [detail, setDetail] = useState<MedicalCertificateDetail | null>(null);
  const firstFilter = useRef(true);
  const deepLinkOpened = useRef(false);
  const controller = useRef<AbortController | null>(null);

  useEffect(() => () => controller.current?.abort(), []);
  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    if (canCreate && params.get("novo") === "1") {
      const timer = window.setTimeout(() => { setQuickPassport(params.get("paciente") ?? ""); setCreating(true); }, 0);
      return () => window.clearTimeout(timer);
    }
    if (deepLinkOpened.current) return;
    deepLinkOpened.current = true;
    const certificateId = Number(params.get("registro"));
    if (Number.isSafeInteger(certificateId) && certificateId > 0) void openDetail(certificateId);
  }, [canCreate]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    if (firstFilter.current) { firstFilter.current = false; return; }
    const timer = window.setTimeout(() => void load(1), 350);
    return () => window.clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [search, status, dateFrom, dateTo]);

  async function load(page: number) {
    controller.current?.abort();
    const request = new AbortController();
    controller.current = request;
    setLoading(true);
    setError("");
    try {
      const params = new URLSearchParams({ view: "list", page: String(page), pageSize: "20", search: search.trim(), status });
      if (dateFrom) params.set("dateFrom", dateFrom);
      if (dateTo) params.set("dateTo", dateTo);
      const response = await fetch(`/api/medical-certificates?${params}`, { cache: "no-store", signal: request.signal });
      const payload = await response.json() as MedicalCertificatePage & { error?: string };
      if (!response.ok) throw new Error(payload.error ?? "Não foi possível consultar os atestados.");
      setData(payload);
    } catch (cause) {
      if (cause instanceof DOMException && cause.name === "AbortError") return;
      setError(messageOf(cause));
    } finally { setLoading(false); }
  }

  async function openDetail(id: number) {
    setLoading(true);
    setError("");
    try {
      const response = await fetch(`/api/medical-certificates?view=detail&id=${id}`, { cache: "no-store" });
      const payload = await response.json() as { certificate?: MedicalCertificateDetail; error?: string };
      if (!response.ok || !payload.certificate) throw new Error(payload.error ?? "Não foi possível abrir o atestado.");
      setDetail(payload.certificate);
    } catch (cause) { setError(messageOf(cause)); }
    finally { setLoading(false); }
  }

  async function changed(id: number, message: string) {
    setNotice(message);
    await Promise.all([load(data.page), openDetail(id)]);
  }

  const totalPages = Math.max(1, Math.ceil(data.total / data.pageSize));
  const activeFilters = Number(status !== "all") + Number(Boolean(dateFrom)) + Number(Boolean(dateTo));
  return <section className="certificate-center" aria-busy={loading}>
    <div className="certificate-command-bar">
      <div><p className="eyebrow">Assistência clínica</p><h2>Atestados médicos</h2><p>Consulte os documentos vinculados aos atendimentos.</p></div>
      {canCreate ? <HpsmButton variant="primary" type="button" onClick={() => setCreating(true)}>＋ Novo atestado</HpsmButton> : null}
    </div>
    {notice ? <p className="form-success" role="status">{notice}</p> : null}
    {error ? <p className="form-error" role="alert">{error}</p> : null}
    <div className="certificate-monitor-controls">
      <label className="certificate-search"><span className="sr-only">Buscar atestado</span><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true"><circle cx="10.8" cy="10.8" r="6.5" /><path d="m16 16 5 5" /></svg><input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Buscar paciente, passaporte ou número" maxLength={120} /></label>
      <button className="certificate-filter-toggle" type="button" aria-expanded={filtersOpen} aria-controls="certificate-filter-panel" onClick={() => setFiltersOpen((open) => !open)}>Filtros{activeFilters ? <span>{activeFilters}</span> : null}<span aria-hidden="true">{filtersOpen ? "⌃" : "⌄"}</span></button>
      <span className="certificate-count" role="status">{loading ? "Atualizando…" : `${data.total} ${data.total === 1 ? "atestado" : "atestados"}`}</span>
    </div>
    {filtersOpen ? <div className="certificate-filter-panel" id="certificate-filter-panel">
      <div className="certificate-filters" role="group" aria-label="Filtrar por situação">{(["all", "draft", "finalized", "cancelled"] as const).map((item) => <button key={item} type="button" data-active={status === item} aria-pressed={status === item} onClick={() => setStatus(item)}>{item === "all" ? "Todos" : STATUS_LABEL[item]}</button>)}</div>
      <label>De<input type="date" value={dateFrom} onChange={(event) => setDateFrom(event.target.value)} /></label>
      <label>Até<input type="date" value={dateTo} min={dateFrom || undefined} onChange={(event) => setDateTo(event.target.value)} /></label>
      {activeFilters ? <button className="certificate-clear-filters" type="button" onClick={() => { setStatus("all"); setDateFrom(""); setDateTo(""); }}>Limpar filtros</button> : null}
    </div> : null}
    {data.items.length ? <div className="certificate-card-grid">
      {data.items.map((item) => <article key={item.id} className="certificate-case">
        <div className="certificate-case-heading">
          <span className="certificate-patient-avatar" aria-hidden="true">{initials(item.patient_name)}</span>
          <div><h3>{item.patient_name}</h3><p>Passaporte {formatPatientPassport(item.patient_passport)}</p></div>
          <span className="certificate-status" data-status={item.status}>{STATUS_LABEL[item.status]}</span>
        </div>
        <div className="certificate-case-body">
          <div className="certificate-case-title"><span>{certificateCode(item.id)}</span><span>·</span><span>{item.consultation_id ? `Consulta #${item.consultation_id}` : `Atendimento #${item.attendance_id}`}</span></div>
          <div className="certificate-case-meta"><span><strong>{item.leave_days} {item.leave_days === 1 ? "dia" : "dias"}</strong> de afastamento</span><span>{item.status === "draft" ? "Criado em" : item.status === "cancelled" ? "Cancelado em" : "Finalizado em"} <time dateTime={item.cancelled_at ?? item.finalized_at ?? item.created_at}>{formatDateTime(item.cancelled_at ?? item.finalized_at ?? item.created_at)}</time></span></div>
          <p className="certificate-case-professional">{item.professional_name}{item.professional_position ? ` · ${item.professional_position}` : ""}</p>
        </div>
        <button className="certificate-case-open" type="button" aria-label={`Abrir atestado ${certificateCode(item.id)} de ${item.patient_name}`} onClick={() => void openDetail(item.id)} />
        <div className="certificate-case-actions">
          <button type="button" onClick={() => void openDetail(item.id)}>{item.status === "draft" ? "Revisar atestado" : "Abrir atestado"} <span aria-hidden="true">→</span></button>
          {item.status === "finalized" ? <MedicalCertificateCopyLinkAction certificateId={item.id} /> : null}
        </div>
      </article>)}
    </div> : <div className="certificate-monitor-empty"><span aria-hidden="true">▤</span><strong>Nenhum atestado localizado</strong><p>Revise a busca e os filtros ou crie um atestado a partir de um atendimento concluído.</p></div>}
    {data.total > data.pageSize ? <div className="certificate-pagination"><button type="button" disabled={loading || data.page <= 1} onClick={() => void load(data.page - 1)}>← Anterior</button><span>Página <strong>{data.page}</strong> de {totalPages}</span><button type="button" disabled={loading || data.page >= totalPages} onClick={() => void load(data.page + 1)}>Próxima →</button></div> : null}
    {creating ? <CertificateCreatePanel initialPassport={quickPassport} currentProfessional={currentProfessional} onClose={() => setCreating(false)} onCreated={async (id) => { setCreating(false); setNotice(`Atestado #${id} criado como rascunho.`); await load(1); await openDetail(id); }} /> : null}
    {detail ? <CertificateDetailPanel certificate={detail} canCancel={canCancel} canFinalize={canFinalize} currentUserId={currentProfessional.id} onChanged={(message) => changed(detail.id, message)} onClose={() => setDetail(null)} /> : null}
  </section>;
}

function CertificateCreatePanel({ initialPassport, currentProfessional, onClose, onCreated }: { initialPassport: string; currentProfessional: CurrentProfessional; onClose: () => void; onCreated: (id: number) => Promise<void> }) {
  const [patientSearch, setPatientSearch] = useState("");
  const [patient, setPatient] = useState<Patient | null>(null);
  const [options, setOptions] = useState<MedicalCertificateReferenceOptions | null>(null);
  const [attendanceId, setAttendanceId] = useState("");
  const [medicalContext, setMedicalContext] = useState("");
  const [leaveDays, setLeaveDays] = useState("");
  const [examIds, setExamIds] = useState<number[]>([]);
  const [castIds, setCastIds] = useState<number[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  useEffect(() => {
    if (!/^[0-9]{4}$/.test(initialPassport)) return;
    let active = true;
    void fetch(`/api/patients?passport=${initialPassport}`, { cache: "no-store" }).then(async (response) => {
      const payload = await response.json() as { patients?: Patient[] };
      const match = payload.patients?.find((entry) => entry.passport === initialPassport);
      if (active && match) void selectPatient(match);
    }).catch(() => undefined);
    return () => { active = false; };
  }, [initialPassport]);

  async function selectPatient(next: Patient) {
    setPatient(next); setPatientSearch(next.passport); setAttendanceId(""); setExamIds([]); setCastIds([]); setError("");
    try {
      const response = await fetch(`/api/medical-certificates?view=options&patientId=${next.id}`, { cache: "no-store" });
      const payload = await response.json() as MedicalCertificateReferenceOptions & { error?: string };
      if (!response.ok) throw new Error(payload.error ?? "Não foi possível carregar os vínculos clínicos.");
      setOptions(payload);
    } catch (cause) { setError(messageOf(cause)); }
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    const days = Number(leaveDays);
    if (!patient) return setError("Selecione um paciente da lista.");
    if (!attendanceId) return setError("Selecione um atendimento concluído.");
    if (!Number.isInteger(days) || days <= 0) return setError("Informe uma quantidade inteira e positiva de dias.");
    if (medicalContext.trim().length < 3) return setError("Informe o motivo e o contexto médico.");
    setLoading(true); setError("");
    try {
      const response = await fetch("/api/medical-certificates", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ action: "create", patientId: patient.id, attendanceId: Number(attendanceId), medicalContext, leaveDays: days, examIds, castIds }) });
      const payload = await response.json() as { certificateId?: number; error?: string };
      if (!response.ok || !payload.certificateId) throw new Error(payload.error ?? "Não foi possível criar o atestado.");
      await onCreated(payload.certificateId);
    } catch (cause) { setError(messageOf(cause)); }
    finally { setLoading(false); }
  }

  return <CertificateOverlay title="Novo Atestado Médico" subtitle="O atendimento é obrigatório e deve pertencer ao paciente selecionado." onClose={onClose}>
    <form className="certificate-form" onSubmit={submit}>
      {error ? <p className="form-error certificate-full" role="alert">{error}</p> : null}
      <PatientPassportCombobox className="certificate-full" label="Paciente · passaporte" value={patientSearch} selectedPatient={patient} showSelectedSummary={false} onValueChange={(value) => { setPatient(null); setPatientSearch(value); setOptions(null); setAttendanceId(""); setExamIds([]); setCastIds([]); }} onSelect={(next) => void selectPatient(next)} />
      {patient ? <div className="certificate-selected-patient certificate-full"><span>{initials(patient.name)}</span><div><strong>{patient.name}</strong><small>Passaporte {formatPatientPassport(patient.passport)}</small></div></div> : null}
      <label className="certificate-full">Atendimento obrigatório<select value={attendanceId} onChange={(event) => setAttendanceId(event.target.value)} disabled={!options} required><option value="">Selecione</option>{options?.attendances.map((item) => <option key={item.id} value={item.id}>#{item.id} · {formatDateTime(item.created_at)} · {item.summary}</option>)}</select><small>Somente atendimentos concluídos deste paciente.</small></label>
      <label className="certificate-full">Motivo / contexto médico<textarea rows={5} value={medicalContext} onChange={(event) => setMedicalContext(event.target.value)} maxLength={4000} required placeholder="Descreva o contexto clínico, o motivo do afastamento e observações relevantes." /></label>
      <label>Dias de afastamento<input type="number" min={1} max={365} step={1} value={leaveDays} onChange={(event) => setLeaveDays(event.target.value)} required /></label>
      <label>Profissional responsável<input value={`${currentProfessional.name} · ${currentProfessional.position ?? "Cargo não informado"}`} readOnly /></label>
      <CertificateLinks options={options} examIds={examIds} castIds={castIds} onExamIds={setExamIds} onCastIds={setCastIds} />
      <div className="certificate-actions certificate-full"><button type="button" className="certificate-secondary" onClick={onClose}>Cancelar</button><button type="submit" className="certificate-primary" disabled={loading || !patient || !attendanceId}>{loading ? "Salvando…" : "Criar rascunho"}</button></div>
    </form>
  </CertificateOverlay>;
}

export function CertificateDetailPanel({ aiEnabled = true, certificate, canCancel, canFinalize, currentUserId, inline = false, onChanged, onClose }: { aiEnabled?: boolean; certificate: MedicalCertificateDetail; canCancel: boolean; canFinalize: boolean; currentUserId: string; inline?: boolean; onChanged: (message: string) => Promise<void>; onClose: () => void }) {
  const editable = certificate.status === "draft" && certificate.created_by === currentUserId;
  const [medicalContext, setMedicalContext] = useState(certificate.medical_context);
  const [leaveDays, setLeaveDays] = useState(String(certificate.leave_days));
  const [diagnosisText, setDiagnosisText] = useState(certificate.diagnosis_text ?? "");
  const [cidCode, setCidCode] = useState(certificate.cid_code ?? "");
  const [finalText, setFinalText] = useState(certificate.final_text ?? certificate.generated_text ?? "");
  const [examIds, setExamIds] = useState(certificate.exams.map((item) => item.id));
  const [castIds, setCastIds] = useState(certificate.casts.map((item) => item.id));
  const [options, setOptions] = useState<MedicalCertificateReferenceOptions | null>(null);
  const [working, setWorking] = useState<"save" | "ai" | "finalize" | "download" | "cancel" | null>(null);
  const [cancelReason, setCancelReason] = useState("");
  const [showCancel, setShowCancel] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    if (!editable) return;
    const controller = new AbortController();
    void fetch(`/api/medical-certificates?view=options&patientId=${certificate.patient_id}`, { cache: "no-store", signal: controller.signal })
      .then(async (response) => { const payload = await response.json() as MedicalCertificateReferenceOptions & { error?: string }; if (!response.ok) throw new Error(payload.error ?? "Não foi possível carregar os vínculos."); setOptions(payload); })
      .catch((cause) => { if (!(cause instanceof DOMException && cause.name === "AbortError")) setError(messageOf(cause)); });
    return () => controller.abort();
  }, [certificate.patient_id, editable]);

  async function save(showNotice = true, contextOnly = false) {
    const days = Number(leaveDays);
    const response = await fetch("/api/medical-certificates", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ action: contextOnly ? "update-context" : "update", certificateId: certificate.id, medicalContext, leaveDays: days, diagnosisText, cidCode, finalText, examIds, castIds }) });
    const payload = await response.json() as { error?: string };
    if (!response.ok) throw new Error(payload.error ?? "Não foi possível salvar o rascunho.");
    if (showNotice) await onChanged("Rascunho do atestado salvo.");
  }

  async function act(action: "save" | "ai" | "finalize") {
    setWorking(action); setError("");
    try {
      if (action === "save") return await save();
      await save(false, action === "ai");
      if (action === "ai") {
        const response = await fetch("/api/medical-certificates/ai", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ certificateId: certificate.id }) });
        const payload = await response.json() as { cidCode?: string; diagnosis?: string; error?: string; text?: string };
        if (!response.ok || !payload.text) throw new Error(payload.error ?? "Não foi possível gerar o texto.");
        if (payload.diagnosis) setDiagnosisText(payload.diagnosis);
        if (payload.cidCode) setCidCode(payload.cidCode);
        setFinalText(payload.text);
        await onChanged("Texto institucional gerado para revisão médica.");
        return;
      }
      if (!finalText.trim()) throw new Error("Revise ou escreva o texto final antes de concluir.");
      const response = await fetch("/api/medical-certificates", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ action: "finalize", certificateId: certificate.id, finalText }) });
      const payload = await response.json() as { error?: string; warning?: string };
      if (!response.ok) throw new Error(payload.error ?? "Não foi possível finalizar o atestado.");
      await onChanged(payload.warning ?? "Atestado finalizado e imagem preparada.");
    } catch (cause) { setError(messageOf(cause)); }
    finally { setWorking(null); }
  }

  function applyInstitutionalText() {
    const days = Number(leaveDays);
    setError("");
    if (!Number.isInteger(days) || days < 1 || days > 365) {
      setError("Informe uma quantidade válida de dias de afastamento.");
      return;
    }
    if (diagnosisText.trim().length < 3 || !cidCode.trim()) {
      setError("Preencha o diagnóstico e selecione o CID-10 antes de aplicar o texto institucional.");
      return;
    }
    setFinalText(`Atesto, para os devidos fins, que o paciente necessita de afastamento de suas atividades por ${days} ${days === 1 ? "dia" : "dias"}, em decorrência de ${diagnosisText.trim()}, CID-10 ${cidCode.trim().toUpperCase()}.`);
  }

  async function cancel() {
    setWorking("cancel"); setError("");
    try {
      const response = await fetch("/api/medical-certificates", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ action: "cancel", certificateId: certificate.id, reason: cancelReason }) });
      const payload = await response.json() as { error?: string };
      if (!response.ok) throw new Error(payload.error ?? "Não foi possível cancelar o atestado.");
      await onChanged("Atestado cancelado sem apagar o histórico.");
    } catch (cause) { setError(messageOf(cause)); }
    finally { setWorking(null); }
  }

  const content = <div className="certificate-detail">
      {error ? <p className="form-error" role="alert">{error}</p> : null}
      <div className="certificate-detail-head"><span className="certificate-status" data-status={certificate.status}>{STATUS_LABEL[certificate.status]}</span>{certificate.consultation_id ? <span>Consulta <Link href={`/consultas/${certificate.consultation_id}`}>#{certificate.consultation_id}</Link></span> : <span>Atendimento <Link href={`/atendimentos/registro/${certificate.attendance_id}`}>#{certificate.attendance_id}</Link></span>}<span>{certificate.leave_days} {certificate.leave_days === 1 ? "dia" : "dias"}</span></div>
      {editable ? <form className="certificate-form" onSubmit={(event) => { event.preventDefault(); void act("save"); }}>
        <label className="certificate-full">Motivo / contexto médico<textarea rows={5} value={medicalContext} onChange={(event) => setMedicalContext(event.target.value)} maxLength={4000} required /></label>
        <label>Dias de afastamento<input type="number" min={1} max={365} step={1} value={leaveDays} onChange={(event) => setLeaveDays(event.target.value)} required /></label>
        <label>{certificate.consultation_id ? "Consulta" : "Atendimento"}<input value={`#${certificate.consultation_id ?? certificate.attendance_id} · ${formatDateTime(certificate.attendance_created_at)}`} readOnly /></label>
        <label className="certificate-full">Diagnóstico do atestado<input value={diagnosisText} onChange={(event) => setDiagnosisText(event.target.value)} minLength={3} maxLength={500} required /></label>
        <label className="certificate-full">CID-10 validado<select value={cidCode} onChange={(event) => setCidCode(event.target.value)} required><option value="">Selecione no catálogo</option>{options?.cids.map((item) => <option key={item.code} value={item.code}>{item.code} · {item.description}</option>)}</select><small>Somente códigos ativos do catálogo institucional podem ser utilizados.</small></label>
        <CertificateLinks options={options} examIds={examIds} castIds={castIds} onExamIds={setExamIds} onCastIds={setCastIds} />
        <label className="certificate-full">Texto do atestado<textarea rows={7} value={finalText} onChange={(event) => setFinalText(event.target.value)} maxLength={4000} placeholder={`O texto deve mencionar exatamente ${leaveDays || "X"} dias.`} /><small>{aiEnabled ? "A Luna pode redigir, mas os dias nunca são escolhidos por ela. Revise antes de finalizar." : "O texto institucional é montado de forma determinística, sem consumo de IA, e permanece editável antes da finalização."}</small></label>
        <div className="certificate-review-actions certificate-full"><button type="submit" className="certificate-secondary" disabled={working !== null}>{working === "save" ? "Salvando…" : "Salvar rascunho"}</button>{aiEnabled ? <button type="button" className="certificate-ai" disabled={working !== null} onClick={() => void act("ai")}>{working === "ai" ? "Gerando…" : "Gerar texto com Luna"}</button> : <button type="button" className="certificate-ai" disabled={working !== null} onClick={applyInstitutionalText}>Aplicar texto institucional</button>}{canFinalize ? <button type="button" className="certificate-primary" disabled={working !== null || !finalText.trim()} onClick={() => void act("finalize")}>{working === "finalize" ? "Finalizando…" : "Finalizar Atestado"}</button> : null}</div>
      </form> : <>
        <section className="certificate-final-preview"><p className="eyebrow">Texto final</p><blockquote>{certificate.final_text}</blockquote><dl><div><dt>Diagnóstico</dt><dd>{certificate.diagnosis_text ?? "Não informado"}</dd><small>{certificate.cid_code ? `${certificate.cid_code} · ${certificate.cid_description ?? "CID-10"}` : "CID-10 não informado"}</small></div><div><dt>Período</dt><dd>{certificate.leave_days} {certificate.leave_days === 1 ? "dia" : "dias"}</dd></div><div><dt>Responsável</dt><dd>{certificate.professional_name}</dd><small>{certificate.professional_position ?? "Cargo não informado"}</small></div><div><dt>{certificate.status === "cancelled" ? "Cancelado em" : "Finalizado em"}</dt><dd>{formatDateTime(certificate.cancelled_at ?? certificate.finalized_at ?? certificate.created_at)}</dd></div></dl></section>
        {certificate.cancellation_reason ? <p className="certificate-cancelled-note"><strong>Motivo do cancelamento:</strong> {certificate.cancellation_reason}</p> : null}
        <div className="certificate-final-actions">{certificate.status === "finalized" ? <MedicalCertificateDocumentActions certificateId={certificate.id} /> : null}{certificate.status === "finalized" && canCancel ? <button type="button" className="certificate-danger" onClick={() => setShowCancel(true)}>Cancelar atestado</button> : null}</div>
        {showCancel ? <div className="certificate-cancel-box"><label>Motivo do cancelamento<textarea value={cancelReason} onChange={(event) => setCancelReason(event.target.value)} rows={3} maxLength={500} /></label><div><button type="button" className="certificate-secondary" onClick={() => setShowCancel(false)}>Voltar</button><button type="button" className="certificate-danger" disabled={working !== null || cancelReason.trim().length < 5} onClick={() => void cancel()}>{working === "cancel" ? "Cancelando…" : "Confirmar cancelamento"}</button></div></div> : null}
      </>}
    </div>;
  if (inline) return <section className="inline-module-panel inline-certificate-detail"><header><div><span className="consultation-kicker">Atestado vinculado · {STATUS_LABEL[certificate.status]}</span><h4>{certificateCode(certificate.id)}</h4><p>{certificate.patient_name} · Passaporte {formatPatientPassport(certificate.patient_passport)}</p></div><button className="certificate-secondary" type="button" onClick={onClose}>Recolher</button></header>{content}</section>;
  return <CertificateOverlay title={`Atestado ${certificateCode(certificate.id)}`} subtitle={`${certificate.patient_name} · Passaporte ${formatPatientPassport(certificate.patient_passport)}`} onClose={onClose}>{content}</CertificateOverlay>;
}

function CertificateLinks({ castIds, examIds, onCastIds, onExamIds, options }: { castIds: number[]; examIds: number[]; onCastIds: (ids: number[]) => void; onExamIds: (ids: number[]) => void; options: MedicalCertificateReferenceOptions | null }) {
  return <div className="certificate-links certificate-full">
    <fieldset><legend>Exames relacionados (opcional)</legend>{options?.exams.length ? options.exams.map((item) => <label key={item.id}><input type="checkbox" checked={examIds.includes(item.id)} onChange={() => onExamIds(toggleId(examIds, item.id))} /><span><strong>{item.type} · #{item.id}</strong><small>{formatDateTime(item.requested_at)} · {examStatusLabel(item.status)}</small></span></label>) : <p>Nenhum exame disponível ou autorizado para este paciente.</p>}</fieldset>
    <fieldset><legend>Gessos relacionados (opcional)</legend>{options?.casts.length ? options.casts.map((item) => <label key={item.id}><input type="checkbox" checked={castIds.includes(item.id)} onChange={() => onCastIds(toggleId(castIds, item.id))} /><span><strong>{castBodyRegionLabel(item.body_region)} · {castLateralityLabel(item.laterality)}</strong><small>Registro #{item.id} · {formatDateTime(item.applied_at)} · {castStatusLabel(item.status)}</small></span></label>) : <p>Nenhum registro de gesso disponível ou autorizado para este paciente.</p>}</fieldset>
  </div>;
}

function CertificateOverlay({ children, onClose, subtitle, title }: { children: React.ReactNode; onClose: () => void; subtitle: string; title: string }) {
  useEffect(() => { function close(event: KeyboardEvent) { if (event.key === "Escape") onClose(); } window.addEventListener("keydown", close); return () => window.removeEventListener("keydown", close); }, [onClose]);
  return <div className="certificate-overlay" role="presentation" onMouseDown={(event) => { if (event.currentTarget === event.target) onClose(); }}><section className="certificate-panel" role="dialog" aria-modal="true" aria-label={title}><header><div><h2>{title}</h2><p>{subtitle}</p></div><button type="button" aria-label="Fechar" onClick={onClose}>×</button></header>{children}</section></div>;
}

function toggleId(values: number[], id: number) { return values.includes(id) ? values.filter((value) => value !== id) : [...values, id]; }
function certificateCode(id: number) { return `AT-${String(id).padStart(6, "0")}`; }
function initials(name: string) { return name.split(/\s+/).filter(Boolean).slice(0, 2).map((part) => part[0]?.toUpperCase()).join(""); }
function formatDateTime(value: string) { return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(value)); }
function messageOf(cause: unknown) { return cause instanceof Error ? cause.message : "Não foi possível concluir a operação."; }
function examStatusLabel(value: string) { return ({ requested: "Solicitado", in_progress: "Em execução", awaiting_review: "Aguardando revisão", completed: "Concluído" } as Record<string, string>)[value] ?? "Status indisponível"; }
function castStatusLabel(value: string) { return ({ active: "Ativo", removed: "Retirado", cancelled: "Cancelado" } as Record<string, string>)[value] ?? "Status indisponível"; }
