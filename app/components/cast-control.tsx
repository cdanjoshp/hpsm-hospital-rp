"use client";

import Link from "next/link";
import { FormEvent, useEffect, useRef, useState } from "react";
import type { Patient } from "../lib/operational-data";
import { formatPatientPassport } from "../lib/passport";
import { HpsmButton } from "./hpsm-button";
import { HpsmDialog } from "./hpsm-dialog";
import { PatientPassportCombobox } from "./patient-passport-combobox";
import {
  CAST_BODY_REGIONS,
  CAST_BODY_MODELS,
  CAST_LATERALITIES,
  CAST_STATUS_LABELS,
  castBodyModelLabel,
  castBodyRegionLabel,
  castLateralityLabel,
  castLocationLabel,
  castReferenceRegion,
  type CastAttendanceOption,
  type CastBodyModel,
  type CastBodyRegion,
  type CastLaterality,
  type ClinicalCastDetail,
  type ClinicalCastListItem,
  type ClinicalCastPatientPage,
  type ClinicalCastReference,
  type ClinicalCastStatus,
} from "../lib/cast-types";
import { CAST_DURATION_DAYS, castDurationDays, expectedCastRemovalAt, isCastDurationDays, type CastDurationDays } from "../lib/cast-duration";

type CastFilter = ClinicalCastStatus | "all";
type CastOpenAction = "remove" | "expected" | null;
export type CurrentProfessional = { id: string; name: string; position: string | null };
export type ConsultationCastPrefill = {
  applicationNotes?: string;
  bodyRegion?: CastBodyRegion | "";
  consultationId: number;
  laterality?: CastLaterality | "";
  patient: Patient;
};

export function CastControl(props: {
  canCreate: boolean;
  canManage: boolean;
  canRemove: boolean;
  currentProfessional: CurrentProfessional;
  initialData: ClinicalCastPatientPage;
  initialPatient?: Patient | null;
  initialCastId?: number | null;
  initialCastAction?: "remove" | null;
}) {
  const [data, setData] = useState(props.initialData);
  const [status, setStatus] = useState<CastFilter>("in_use");
  const [search, setSearch] = useState("");
  const [filtersOpen, setFiltersOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [creating, setCreating] = useState(Boolean(props.canCreate && props.initialPatient));
  const [consultationPrefill, setConsultationPrefill] = useState<ConsultationCastPrefill | null>(null);
  const [configuringReferences, setConfiguringReferences] = useState(false);
  const [detail, setDetail] = useState<ClinicalCastDetail | null>(null);
  const [detailAction, setDetailAction] = useState<CastOpenAction>(null);
  const firstSearch = useRef(true);
  const deepLinkOpened = useRef(false);
  const listController = useRef<AbortController | null>(null);
  const listRequestNumber = useRef(0);

  async function load(page: number, nextStatus = status, nextSearch = search) {
    listController.current?.abort();
    const controller = new AbortController();
    const requestId = ++listRequestNumber.current;
    listController.current = controller;
    setLoading(true);
    setError("");
    try {
      const params = new URLSearchParams({
        page: String(page),
        pageSize: "20",
        search: nextSearch.trim(),
        status: nextStatus,
        view: "list",
      });
      const response = await fetch(`/api/casts?${params}`, { cache: "no-store", signal: controller.signal });
      const payload = await response.json() as ClinicalCastPatientPage & { error?: string };
      if (!response.ok) throw new Error(payload.error ?? "Não foi possível consultar os registros de gesso.");
      if (requestId === listRequestNumber.current) setData(payload);
    } catch (cause) {
      if (cause instanceof DOMException && cause.name === "AbortError") return;
      if (requestId === listRequestNumber.current) setError(messageOf(cause));
    } finally {
      if (requestId === listRequestNumber.current) setLoading(false);
    }
  }

  useEffect(() => () => listController.current?.abort(), []);

  useEffect(() => {
    if (firstSearch.current) {
      firstSearch.current = false;
      return;
    }
    const timer = window.setTimeout(() => void load(1, status, search), 350);
    return () => window.clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [search, status]);

  useEffect(() => {
    if (deepLinkOpened.current) return;
    deepLinkOpened.current = true;
    const params = new URLSearchParams(window.location.search);
    const consultationId = Number(params.get("consulta"));
    if (params.get("nova") === "true" && Number.isInteger(consultationId) && consultationId > 0 && props.canCreate) {
      void (async () => {
        try {
          const consultationResponse = await fetch(`/api/consultations?view=detail&id=${consultationId}`, { cache: "no-store" });
          const consultationPayload = await consultationResponse.json() as { consultation?: { patient?: { passport?: string } }; error?: string };
          const passport = consultationPayload.consultation?.patient?.passport;
          if (!consultationResponse.ok || !passport) throw new Error(consultationPayload.error ?? "Não foi possível carregar a consulta.");
          const patientResponse = await fetch(`/api/patients?passport=${encodeURIComponent(passport)}`, { cache: "no-store" });
          const patientPayload = await patientResponse.json() as { patients?: Patient[]; error?: string };
          const patient = patientPayload.patients?.find((item) => item.passport === passport) ?? patientPayload.patients?.[0];
          if (!patientResponse.ok || !patient) throw new Error(patientPayload.error ?? "Paciente não localizado.");
          setConsultationPrefill({ consultationId, patient });
          setCreating(true);
        } catch (cause) { setError(messageOf(cause)); }
      })();
      return;
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (!props.initialCastId) return;
    void openDetail(props.initialCastId, props.initialCastAction === "remove" && props.canRemove ? "remove" : null);
    // A ação é fornecida pela rota, inclusive em navegação sem remontar o módulo.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [props.initialCastId, props.initialCastAction, props.canRemove]);

  async function openDetail(castId: number, action: CastOpenAction = null) {
    setLoading(true);
    setError("");
    try {
      const response = await fetch(`/api/casts?view=detail&id=${castId}`, { cache: "no-store" });
      const payload = await response.json() as { cast?: ClinicalCastDetail; error?: string };
      if (!response.ok || !payload.cast) throw new Error(payload.error ?? "Não foi possível abrir o registro de gesso.");
      setDetail(payload.cast);
      setDetailAction(payload.cast.status === "in_use" ? action : null);
    } catch (cause) {
      setError(messageOf(cause));
    } finally {
      setLoading(false);
    }
  }

  async function refreshDetail(castId: number) {
    await Promise.all([openDetail(castId), load(data.page)]);
  }

  const totalPages = Math.max(1, Math.ceil(data.total / data.pageSize));
  const patientGroups = groupCastPage(data.items);
  return <section className="cast-control" aria-busy={loading}>
    <div className="cast-command-bar">
      <div>
        <p className="eyebrow">Assistência · Controle clínico</p>
        <h2>Monitoramento de gessos</h2>
        <p>Aplicações e retiradas organizadas por paciente.</p>
      </div>
      <div className="cast-command-actions">
        {props.canManage ? <button className="cast-secondary-button" type="button" onClick={() => setConfiguringReferences(true)}>Configurar referências</button> : null}
        {props.canCreate ? <button className="cast-primary-button" type="button" onClick={() => setCreating(true)}>＋ Registrar aplicação</button> : null}
      </div>
    </div>

    {notice ? <p className="form-success" role="status">{notice}</p> : null}
    {error ? <p className="form-error" role="alert">{error}</p> : null}

    <div className="cast-monitor-controls">
      <label className="cast-search"><span className="sr-only">Buscar paciente por nome ou passaporte</span><svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"><circle cx="10.8" cy="10.8" r="6.3" /><path d="m15.5 15.5 5 5" /></svg><input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Buscar paciente ou passaporte" maxLength={120} /></label>
      <button className="cast-filter-toggle" type="button" aria-expanded={filtersOpen} aria-controls="cast-status-filters" onClick={() => setFiltersOpen((open) => !open)}>Mais filtros <span aria-hidden="true">{filtersOpen ? "⌃" : "⌄"}</span></button>
      <span className="cast-count">{data.castTotal} {data.castTotal === 1 ? "gesso" : "gessos"} · {status === "all" ? "Todos" : CAST_STATUS_LABELS[status]}</span>
    </div>
    {filtersOpen ? <div id="cast-status-filters" className="cast-filter-panel">
      <span>Mostrar</span>
      <div className="cast-filters" aria-label="Filtrar registros de gesso">
        {(["in_use", "removed", "cancelled", "all"] as const).map((option) => <button key={option} type="button" data-active={status === option} onClick={() => setStatus(option)}>{option === "all" ? "Todos" : CAST_STATUS_LABELS[option]}</button>)}
      </div>
    </div> : null}
    {loading ? <p className="cast-loading" role="status">Atualizando registros…</p> : null}

    {patientGroups.length ? <div className="cast-patient-grid">
      {patientGroups.map((group) => <section className="cast-patient-card" key={group.patientId} aria-label={`Gessos de ${group.name}`}>
        <header className="cast-patient-heading">
          <span className="cast-patient-avatar" aria-hidden="true">{initials(group.name)}</span>
          <div><h3>{group.name}</h3><p>Passaporte {formatPatientPassport(group.passport)}</p></div>
          <span className="cast-patient-count">{group.casts.length} {group.casts.length === 1 ? "gesso" : "gessos"}</span>
        </header>
        <div className="cast-patient-cases">{group.casts.map((item) => {
          const due = castDueLabel(item);
          const canAdjust = props.canManage || (props.canCreate && item.applied_by === props.currentProfessional.id);
          return <article className="cast-case" key={item.id}>
            <div className="cast-case-heading"><h4>{castLocationLabel(item.body_region, item.laterality)}</h4><span className="cast-case-state" data-tone={due.tone}>{due.label}</span></div>
            <p className="cast-case-professional">Aplicado por {item.applied_by_name}</p>
            <div className="cast-case-meta"><span>Aplicação <time>{formatDateTime(item.applied_at)}</time></span><span>{item.status === "removed" ? "Retirado" : item.status === "cancelled" ? "Previsão registrada" : "Retirada prevista"} <time>{formatDateTime(item.status === "removed" && item.removed_at ? item.removed_at : item.expected_removal_at)}</time></span></div>
            <button className="cast-case-open" type="button" aria-label={`Ver gesso de ${castLocationLabel(item.body_region, item.laterality)} de ${item.patient_name}`} onClick={() => void openDetail(item.id)} />
            <div className="cast-case-actions">
              <button type="button" onClick={() => void openDetail(item.id)}>Ver detalhes</button>
              {item.status === "in_use" && canAdjust ? <button type="button" onClick={() => void openDetail(item.id, "expected")}>Alterar dias</button> : null}
              {item.status === "in_use" && props.canRemove ? <button type="button" data-primary="true" onClick={() => void openDetail(item.id, "remove")}>Registrar retirada</button> : null}
            </div>
          </article>;
        })}</div>
      </section>)}
    </div> : <div className="cast-monitor-empty"><span aria-hidden="true">▱</span><strong>Nenhum gesso localizado</strong><p>{status === "in_use" ? "Não há gessos em uso para os filtros informados." : "Revise a busca ou selecione outro status."}</p></div>}

    {data.total > data.pageSize ? <div className="cast-pagination">
      <button type="button" disabled={loading || data.page <= 1} onClick={() => void load(data.page - 1)}>← Anterior</button>
      <span>Página <strong>{data.page}</strong> de {totalPages}</span>
      <button type="button" disabled={loading || data.page >= totalPages} onClick={() => void load(data.page + 1)}>Próxima →</button>
    </div> : null}

    {creating ? <CastCreatePanel
      currentProfessional={props.currentProfessional}
      consultationPrefill={consultationPrefill}
      initialPatient={props.initialPatient}
      onClose={() => setCreating(false)}
      onCreated={async (castId) => {
        setCreating(false);
        setStatus("in_use");
        setNotice(`Aplicação de gesso #${castId} registrada com sucesso.`);
        await load(1, "in_use", search);
        await openDetail(castId);
      }}
    /> : null}
    {configuringReferences ? <CastReferenceManagementPanel onClose={() => setConfiguringReferences(false)} /> : null}
    {detail ? <CastDetailPanel
      key={`${detail.id}:${detailAction ?? "view"}`}
      canAdjustExpected={props.canManage || (props.canCreate && detail.applied_by === props.currentProfessional.id)}
      canManage={props.canManage}
      canRemove={props.canRemove}
      currentProfessional={props.currentProfessional}
      initialAction={detailAction}
      record={detail}
      onClose={() => { setDetail(null); setDetailAction(null); }}
      onChanged={async (message) => {
        setNotice(message);
        await refreshDetail(detail.id);
      }}
    /> : null}
  </section>;
}

export function CastCreatePanel({ consultationPrefill, currentProfessional, initialPatient = null, inline = false, onClose, onCreated }: {
  consultationPrefill: ConsultationCastPrefill | null;
  initialPatient?: Patient | null;
  currentProfessional: CurrentProfessional;
  inline?: boolean;
  onClose: () => void;
  onCreated: (castId: number) => Promise<void>;
}) {
  const [patientSearch, setPatientSearch] = useState(consultationPrefill?.patient.passport ?? initialPatient?.passport ?? "");
  const [patient, setPatient] = useState<Patient | null>(consultationPrefill?.patient ?? initialPatient);
  const [attendances, setAttendances] = useState<CastAttendanceOption[]>([]);
  const [attendanceId, setAttendanceId] = useState<number | undefined>();
  const [bodyModel, setBodyModel] = useState<CastBodyModel | "">("");
  const [bodyRegion, setBodyRegion] = useState<CastBodyRegion | "">(consultationPrefill?.bodyRegion ?? "");
  const [laterality, setLaterality] = useState<CastLaterality | "">(consultationPrefill?.laterality ?? "");
  const [references, setReferences] = useState<ClinicalCastReference[]>([]);
  const [referenceError, setReferenceError] = useState("");
  const [appliedAt, setAppliedAt] = useState(() => localDateTimeValue(new Date()));
  const [castDays, setCastDays] = useState<CastDurationDays | "">("");
  const [applicationNotes, setApplicationNotes] = useState(consultationPrefill?.applicationNotes ?? "");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [duplicateWarning, setDuplicateWarning] = useState("");

  useEffect(() => {
    let cancelled = false;
    void fetchCastReferences(false)
      .then((items) => { if (!cancelled) setReferences(items); })
      .catch((cause) => { if (!cancelled) setReferenceError(messageOf(cause)); });
    return () => { cancelled = true; };
  }, []);

  useEffect(() => {
    if (consultationPrefill?.patient || initialPatient) void selectPatient(consultationPrefill?.patient ?? initialPatient!);
    // A consulta de origem é uma intenção inicial imutável deste painel.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function selectPatient(nextPatient: Patient) {
    setPatient(nextPatient);
    setPatientSearch(nextPatient.passport);
    setAttendanceId(undefined);
    setError("");
    try {
      const response = await fetch(`/api/casts?view=attendance-options&patientId=${nextPatient.id}`, { cache: "no-store" });
      const payload = await response.json() as { attendances?: CastAttendanceOption[]; error?: string };
      if (!response.ok) throw new Error(payload.error ?? "Não foi possível consultar os atendimentos.");
      setAttendances(payload.attendances ?? []);
    } catch (cause) {
      setError(messageOf(cause));
    }
  }

  async function create(confirmDuplicate: boolean) {
    const response = await fetch("/api/casts", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        action: "create",
        appliedAt: toIso(appliedAt),
        applicationNotes,
        attendanceId,
        bodyModel,
        bodyRegion,
        confirmDuplicate,
        consultationId: consultationPrefill?.consultationId,
        castDays,
        laterality,
        patientId: patient?.id,
      }),
    });
    const payload = await response.json() as { castId?: number; code?: string; error?: string };
    if (response.status === 409 && payload.code === "active_cast_duplicate" && !confirmDuplicate) {
      setDuplicateWarning(payload.error ?? "Já existe um gesso ativo nesta região e lateralidade.");
      return;
    }
    if (!response.ok || !payload.castId) throw new Error(payload.error ?? "Não foi possível registrar a aplicação.");
    await onCreated(payload.castId);
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (!patient) return setError("Selecione um paciente da lista.");
    if (!bodyModel || !bodyRegion || !laterality) return setError("Informe modelo, região e lateralidade.");
    if (!appliedAt || !Number.isFinite(Date.parse(appliedAt))) return setError("Informe a data e hora da aplicação.");
    if (!isCastDurationDays(castDays)) return setError("Selecione de 1 a 5 dias de gesso.");
    setSaving(true);
    setError("");
    try {
      await create(false);
    } catch (cause) {
      setError(messageOf(cause));
    } finally {
      setSaving(false);
    }
  }

  const referenceRegion = bodyRegion ? castReferenceRegion(bodyRegion) : null;
  const selectedReference = bodyModel && referenceRegion && laterality
    ? references.find((reference) => reference.active
      && reference.body_model === bodyModel
      && reference.body_region === referenceRegion
      && reference.laterality === laterality)
    : undefined;
  const referenceReady = Boolean(bodyModel && bodyRegion && laterality);
  const calculatedRemovalAt = isCastDurationDays(castDays) ? expectedCastRemovalAt(appliedAt, castDays) : null;

  const content = <><form className="cast-form" onSubmit={submit}>
      {error ? <p className="form-error cast-full-field" role="alert">{error}</p> : null}
      {!consultationPrefill ? <PatientPassportCombobox className="cast-full-field" label="Paciente · passaporte" value={patientSearch} selectedPatient={patient} showSelectedSummary={false} onValueChange={(value) => { setPatient(null); setPatientSearch(value); setAttendances([]); setAttendanceId(undefined); }} onSelect={(nextPatient) => void selectPatient(nextPatient)} /> : null}
      {patient ? <div className="cast-selected-patient cast-full-field"><span>{initials(patient.name)}</span><div><strong>{patient.name}</strong><small>Passaporte {formatPatientPassport(patient.passport)}</small></div></div> : null}
      <label className="cast-full-field">Atendimento relacionado<select value={attendanceId ?? ""} onChange={(event) => setAttendanceId(optionalNumber(event.target.value))} disabled={!patient}><option value="">Sem vínculo financeiro</option>{attendances.map((attendance) => <option key={attendance.id} value={attendance.id}>{attendance.has_cast_item ? "Gesso · " : ""}#{attendance.id} · {formatDate(attendance.created_at)} · {attendance.summary}</option>)}</select><small>Atendimentos com o item GESSO aparecem primeiro. O vínculo é opcional.</small></label>
      <label>Modelo<select value={bodyModel} onChange={(event) => setBodyModel(event.target.value as CastBodyModel)} required><option value="">Selecione</option>{CAST_BODY_MODELS.map((model) => <option key={model.code} value={model.code}>{model.label}</option>)}</select></label>
      <label>Região<select value={bodyRegion} onChange={(event) => {
        const nextRegion = event.target.value as CastBodyRegion;
        setBodyRegion(nextRegion);
        if (nextRegion === "rib") setLaterality("not_applicable");
        else if (laterality === "not_applicable") setLaterality("");
      }} required><option value="">Selecione</option>{CAST_BODY_REGIONS.map((region) => <option key={region.code} value={region.code}>{region.label}</option>)}</select></label>
      <label className="cast-full-field">Lateralidade<select value={laterality} onChange={(event) => setLaterality(event.target.value as CastLaterality)} required disabled={bodyRegion === "rib"}><option value="">Selecione</option>{CAST_LATERALITIES.map((item) => <option key={item.code} value={item.code}>{item.label}</option>)}</select></label>
      {referenceReady ? <div className="cast-reference-preview cast-full-field" aria-live="polite">
        <p className="eyebrow">Referência no jogo</p>
        {selectedReference ? <dl>
          <div><dt>Modelo</dt><dd>{castBodyModelLabel(selectedReference.body_model)}</dd></div>
          <div><dt>Parte registrada</dt><dd>{castLocationLabel(bodyRegion as CastBodyRegion, laterality as CastLaterality)}</dd></div>
          <div><dt>Aplicação compartilhada</dt><dd>{castLocationLabel(selectedReference.body_region, selectedReference.laterality)}</dd></div>
          <div><dt>ID</dt><dd>{selectedReference.game_reference}</dd></div>
          <div><dt>Descrição</dt><dd>{selectedReference.description}</dd></div>
        </dl> : <p>Nenhuma referência cadastrada para esta posição.</p>}
        {referenceError ? <small>{referenceError} O registro clínico continua disponível.</small> : null}
      </div> : null}
      <label>Data e hora da aplicação<input type="datetime-local" value={appliedAt} onChange={(event) => setAppliedAt(event.target.value)} required /></label>
      <label>Dias de gesso<select value={castDays} onChange={(event) => setCastDays(event.target.value ? Number(event.target.value) as CastDurationDays : "")} required><option value="">Selecione</option>{CAST_DURATION_DAYS.map((days) => <option key={days} value={days}>{days} {days === 1 ? "dia" : "dias"}</option>)}</select></label>
      <div className="cast-duration-preview cast-full-field" aria-live="polite"><span>Retirada prevista</span><strong>{calculatedRemovalAt ? formatDateTime(calculatedRemovalAt) : "Selecione a aplicação e os dias de gesso"}</strong><small>Calculada a partir da data e hora da aplicação.</small></div>
      <label className="cast-full-field">Observação da aplicação (opcional)<textarea value={applicationNotes} onChange={(event) => setApplicationNotes(event.target.value)} rows={3} maxLength={1000} placeholder="Ex.: imobilização após fratura do rádio." /></label>
      <label className="cast-full-field">Profissional responsável<input value={`${currentProfessional.name} · ${currentProfessional.position ?? "Cargo não informado"}`} readOnly aria-readonly="true" /><small>Preenchido automaticamente pelo seu login.</small></label>
      <div className="cast-panel-actions cast-full-field"><HpsmButton variant="ghost" type="button" onClick={onClose}>Cancelar</HpsmButton><HpsmButton variant="primary" loading={saving} type="submit" disabled={!patient}>{saving ? "Registrando…" : "Salvar aplicação"}</HpsmButton></div>
    </form>{duplicateWarning ? <HpsmDialog confirmLabel="Registrar mesmo assim" description={`${duplicateWarning} Confirme apenas se houver necessidade clínica de manter dois registros ativos na mesma região.`} loading={saving} onClose={() => setDuplicateWarning("")} onConfirm={() => { setSaving(true); setDuplicateWarning(""); void create(true).catch((cause) => setError(messageOf(cause))).finally(() => setSaving(false)); }} title="Gesso ativo já existente" /> : null}</>;
  if (inline) return <section className="inline-module-panel"><header><div><span className="consultation-kicker">Conduta vinculada</span><h4>Registrar aplicação de gesso</h4><p>O paciente e a consulta permanecem fixos neste registro.</p></div></header>{content}</section>;
  return <CastOverlay title="Registrar aplicação de gesso" subtitle="O registro clínico é manual e independente da venda." onClose={onClose}>{content}</CastOverlay>;
}

type CastReferenceDraft = {
  id: number | null;
  bodyModel: CastBodyModel;
  bodyRegion: "arm" | "leg" | "rib";
  laterality: "right" | "left" | "not_applicable";
  gameReference: string;
  description: string;
  active: boolean;
};

function CastReferenceManagementPanel({ onClose }: { onClose: () => void }) {
  const [references, setReferences] = useState<ClinicalCastReference[]>([]);
  const [draft, setDraft] = useState<CastReferenceDraft | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  useEffect(() => {
    let cancelled = false;
    void fetchCastReferences(true)
      .then((items) => { if (!cancelled) setReferences(items); })
      .catch((cause) => { if (!cancelled) setError(messageOf(cause)); })
      .finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, []);

  function edit(reference: ClinicalCastReference) {
    setDraft({
      id: reference.id,
      bodyModel: reference.body_model,
      bodyRegion: reference.body_region as "arm" | "leg" | "rib",
      laterality: reference.laterality as "right" | "left" | "not_applicable",
      gameReference: reference.game_reference,
      description: reference.description,
      active: reference.active,
    });
    setError("");
    setNotice("");
  }

  async function save(event: FormEvent) {
    event.preventDefault();
    if (!draft) return;
    setSaving(true);
    setError("");
    setNotice("");
    try {
      const response = await fetch("/api/casts", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          action: "save-reference",
          active: draft.active,
          bodyModel: draft.bodyModel,
          bodyRegion: draft.bodyRegion,
          description: draft.description,
          gameReference: draft.gameReference,
          laterality: draft.laterality,
          referenceId: draft.id,
        }),
      });
      const payload = await response.json() as { error?: string };
      if (!response.ok) throw new Error(payload.error ?? "Não foi possível salvar a referência.");
      setReferences(await fetchCastReferences(true));
      setDraft(null);
      setNotice("Referência atualizada com sucesso. Registros antigos mantêm o snapshot original.");
    } catch (cause) {
      setError(messageOf(cause));
    } finally {
      setSaving(false);
    }
  }

  return <CastOverlay title="Referências de aplicação" subtitle="Configuração da Diretoria para o registro de gesso." onClose={onClose} wide>
    <div className="cast-reference-management">
      <div className="cast-reference-management-heading">
        <p>As alterações valem apenas para novas aplicações. O histórico já registrado não é reescrito.</p>
        <button className="cast-primary-button" type="button" onClick={() => {
          setDraft({ id: null, bodyModel: "male", bodyRegion: "arm", laterality: "right", gameReference: "", description: "", active: true });
          setError("");
          setNotice("");
        }}>＋ Nova referência</button>
      </div>
      {notice ? <p className="form-success" role="status">{notice}</p> : null}
      {error ? <p className="form-error" role="alert">{error}</p> : null}
      {loading ? <p className="cast-search-hint">Carregando referências…</p> : <div className="cast-reference-list">
        {references.map((reference) => <article key={reference.id} data-active={reference.active}>
          <div>
            <strong>{castBodyModelLabel(reference.body_model)} · {castLocationLabel(reference.body_region, reference.laterality)}</strong>
            <span>ID {reference.game_reference} · {reference.description}</span>
            <small>{reference.active ? "Ativa" : "Inativa"}{reference.updated_by_name ? ` · Atualizada por ${reference.updated_by_name}` : ""}</small>
          </div>
          <button className="cast-secondary-button" type="button" onClick={() => edit(reference)}>Editar</button>
        </article>)}
      </div>}

      {draft ? <form className="cast-reference-editor" onSubmit={save}>
        <div className="cast-reference-editor-title"><div><p className="eyebrow">{draft.id ? "Editar referência" : "Nova referência"}</p><strong>{draft.id ? `Registro #${draft.id}` : "Cadastrar combinação"}</strong></div><button type="button" onClick={() => setDraft(null)} aria-label="Fechar edição">×</button></div>
        <label>Modelo<select value={draft.bodyModel} onChange={(event) => setDraft({ ...draft, bodyModel: event.target.value as CastBodyModel })}>{CAST_BODY_MODELS.map((model) => <option key={model.code} value={model.code}>{model.label}</option>)}</select></label>
        <label>Grupo de aplicação<select value={draft.bodyRegion} onChange={(event) => {
          const bodyRegion = event.target.value as CastReferenceDraft["bodyRegion"];
          setDraft({ ...draft, bodyRegion, laterality: bodyRegion === "rib" ? "not_applicable" : draft.laterality === "not_applicable" ? "right" : draft.laterality });
        }}><option value="arm">Braço · mão ao cotovelo</option><option value="leg">Perna · pé ao joelho</option><option value="rib">Costela</option></select></label>
        <label>Lateralidade<select value={draft.laterality} disabled={draft.bodyRegion === "rib"} onChange={(event) => setDraft({ ...draft, laterality: event.target.value as CastReferenceDraft["laterality"] })}>{draft.bodyRegion === "rib" ? <option value="not_applicable">Não se aplica</option> : <><option value="right">Direito</option><option value="left">Esquerdo</option></>}</select></label>
        <label>ID no jogo<input value={draft.gameReference} onChange={(event) => setDraft({ ...draft, gameReference: event.target.value })} maxLength={80} required /></label>
        <label className="cast-reference-description">Descrição<input value={draft.description} onChange={(event) => setDraft({ ...draft, description: event.target.value })} minLength={2} maxLength={160} required /></label>
        <label className="cast-reference-active"><input type="checkbox" checked={draft.active} onChange={(event) => setDraft({ ...draft, active: event.target.checked })} /> Referência ativa</label>
        <div className="cast-panel-actions"><button className="cast-secondary-button" type="button" onClick={() => setDraft(null)}>Cancelar</button><button className="cast-primary-button" type="submit" disabled={saving}>{saving ? "Salvando…" : "Salvar referência"}</button></div>
      </form> : null}
    </div>
  </CastOverlay>;
}

export function CastDetailPanel({ canAdjustExpected, canManage, canRemove, initialAction, onChanged, onClose, record }: {
  canAdjustExpected: boolean;
  canManage: boolean;
  canRemove: boolean;
  currentProfessional: CurrentProfessional;
  initialAction: CastOpenAction;
  onChanged: (message: string) => Promise<void>;
  onClose: () => void;
  record: ClinicalCastDetail;
}) {
  const [action, setAction] = useState<"expected" | "remove" | "cancel" | null>(initialAction);
  const [castDays, setCastDays] = useState<CastDurationDays | "">(() => castDurationDays(record.applied_at, record.expected_removal_at) ?? "");
  const [removedAt, setRemovedAt] = useState(() => localDateTimeValue(new Date()));
  const [reason, setReason] = useState("");
  const [notes, setNotes] = useState("");
  const [working, setWorking] = useState(false);
  const [error, setError] = useState("");
  const currentCastDays = castDurationDays(record.applied_at, record.expected_removal_at);
  const earlyRemoval = Boolean(record.removed_at && new Date(record.removed_at) < new Date(record.expected_removal_at));
  const plannedEarlyRemoval = action === "remove" && removedAt
    ? new Date(removedAt) < new Date(record.expected_removal_at)
    : false;
  const revisedRemovalAt = isCastDurationDays(castDays) ? expectedCastRemovalAt(record.applied_at, castDays) : null;

  async function submitAction(event: FormEvent) {
    event.preventDefault();
    if (!action) return;
    if (action === "expected" && !isCastDurationDays(castDays)) return setError("Selecione de 1 a 5 dias de gesso.");
    setWorking(true);
    setError("");
    try {
      const body = action === "expected"
        ? { action: "update-expected-removal", castId: record.id, castDays, reason }
        : action === "remove"
          ? { action: "remove", castId: record.id, removedAt: toIso(removedAt), removalNotes: notes }
          : { action: "cancel", castId: record.id, reason };
      const response = await fetch("/api/casts", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
      const payload = await response.json() as { error?: string };
      if (!response.ok) throw new Error(payload.error ?? "Não foi possível concluir a operação.");
      setAction(null);
      setReason("");
      setNotes("");
      await onChanged(action === "expected" ? "Dias de gesso e previsão de retirada atualizados." : action === "remove" ? "Retirada de gesso registrada." : "Registro de gesso cancelado.");
    } catch (cause) {
      setError(messageOf(cause));
    } finally {
      setWorking(false);
    }
  }

  return <CastOverlay title={`Gesso clínico #${record.id}`} subtitle={`${record.patient_name} · Passaporte ${formatPatientPassport(record.patient_passport)}`} onClose={onClose} wide>
    <div className="cast-detail">
      {error ? <p className="form-error" role="alert">{error}</p> : null}
      <div className="cast-detail-heading"><span className="cast-status" data-status={record.status}>{CAST_STATUS_LABELS[record.status]}</span>{earlyRemoval ? <span className="cast-early-badge">Retirada antecipada</span> : null}</div>
      <dl className="cast-detail-grid">
        <div><dt>Paciente</dt><dd>{record.patient_name}</dd><small>Passaporte {formatPatientPassport(record.patient_passport)}</small></div>
        <div><dt>Região</dt><dd>{castBodyRegionLabel(record.body_region)}</dd><small>{castLateralityLabel(record.laterality)}</small></div>
        <div><dt>Aplicado em</dt><dd>{formatDateTime(record.applied_at)}</dd><small>{record.applied_by_name} · {record.applied_by_position ?? "Cargo não informado"}</small></div>
        <div><dt>Previsão de retirada</dt><dd>{formatDateTime(record.expected_removal_at)}</dd>{currentCastDays ? <small>{currentCastDays} {currentCastDays === 1 ? "dia" : "dias"} de gesso</small> : null}</div>
      </dl>
      <section className="cast-detail-section"><h3>Aplicação</h3><p>{record.application_notes ?? "Nenhuma observação registrada."}</p></section>
      {record.body_model_snapshot ? <section className="cast-detail-section cast-reference-snapshot"><h3>Referência utilizada</h3><dl>
        <div><dt>Modelo</dt><dd>{castBodyModelLabel(record.body_model_snapshot)}</dd></div>
        <div><dt>Local</dt><dd>{record.reference_body_region_snapshot && record.reference_laterality_snapshot ? castLocationLabel(record.reference_body_region_snapshot, record.reference_laterality_snapshot) : castLocationLabel(record.body_region, record.laterality)}</dd></div>
        <div><dt>ID</dt><dd>{record.game_reference_snapshot ?? "Nenhuma referência cadastrada"}</dd></div>
        <div><dt>Descrição</dt><dd>{record.reference_description_snapshot ?? "Nenhuma referência cadastrada para esta posição."}</dd></div>
      </dl></section> : null}
      {record.attendance_id ? <section className="cast-detail-section"><h3>Atendimento relacionado</h3><p><strong>#{record.attendance_id}</strong> · {record.attendance_created_at ? formatDateTime(record.attendance_created_at) : "Data não informada"}</p><p>{record.attendance_summary}</p><Link href={`/atendimentos/registro/${record.attendance_id}`} prefetch={false}>Acessar atendimento →</Link></section> : null}
      {record.status === "removed" ? <section className="cast-detail-section"><h3>Retirada</h3><p><strong>{record.removed_at ? formatDateTime(record.removed_at) : "Data não informada"}</strong></p><p>{record.removed_by_name} · {record.removed_by_position ?? "Cargo não informado"}</p><p>{record.removal_notes ?? "Nenhuma observação registrada."}</p></section> : null}
      {record.status === "cancelled" ? <section className="cast-detail-section cast-cancelled-section"><h3>Cancelamento</h3><p><strong>{record.cancelled_at ? formatDateTime(record.cancelled_at) : "Data não informada"}</strong></p><p>{record.cancelled_by_name} · {record.cancelled_by_position ?? "Cargo não informado"}</p><p>{record.cancellation_reason}</p></section> : null}

      {record.status === "in_use" ? <div className="cast-detail-actions">
        {canRemove ? <button className="cast-primary-button" type="button" onClick={() => setAction("remove")}>Registrar retirada</button> : null}
        {canAdjustExpected ? <button className="cast-secondary-button" type="button" onClick={() => setAction("expected")}>Alterar dias de gesso</button> : null}
        {canManage ? <button className="cast-danger-button" type="button" onClick={() => setAction("cancel")}>Cancelar registro</button> : null}
      </div> : null}

      {action ? <form className="cast-action-form" onSubmit={submitAction}>
        <div><p className="eyebrow">{action === "remove" ? "Registrar retirada" : action === "expected" ? "Alterar dias de gesso" : "Cancelar registro"}</p><button type="button" onClick={() => setAction(null)} aria-label="Fechar ação">×</button></div>
        {action === "remove" ? <>
          <label>Data e hora da retirada<input type="datetime-local" value={removedAt} min={localDateTimeValue(new Date(record.applied_at))} onChange={(event) => setRemovedAt(event.target.value)} required /></label>
          <label>Observação da retirada (opcional)<textarea value={notes} onChange={(event) => setNotes(event.target.value)} rows={3} maxLength={1000} /></label>
          {plannedEarlyRemoval ? <p className="cast-early-note">Retirada antecipada em relação à previsão. O registro clínico é permitido normalmente.</p> : null}
        </> : action === "expected" ? <>
          <label>Dias de gesso<select value={castDays} onChange={(event) => setCastDays(event.target.value ? Number(event.target.value) as CastDurationDays : "")} required><option value="">Selecione</option>{CAST_DURATION_DAYS.map((days) => <option key={days} value={days}>{days} {days === 1 ? "dia" : "dias"}</option>)}</select></label>
          <div className="cast-duration-preview" aria-live="polite"><span>Nova retirada prevista</span><strong>{revisedRemovalAt ? formatDateTime(revisedRemovalAt) : "Selecione os dias de gesso"}</strong><small>Calculada a partir da aplicação em {formatDateTime(record.applied_at)}.</small></div>
          <label>Motivo da alteração<textarea value={reason} onChange={(event) => setReason(event.target.value)} rows={3} minLength={2} maxLength={500} required /></label>
        </> : <label>Motivo do cancelamento<textarea value={reason} onChange={(event) => setReason(event.target.value)} rows={3} minLength={2} maxLength={500} required placeholder="Explique por que o registro foi criado indevidamente." /></label>}
        <div className="cast-panel-actions"><button className="cast-secondary-button" type="button" onClick={() => setAction(null)}>Voltar</button><button className={action === "cancel" ? "cast-danger-button" : "cast-primary-button"} type="submit" disabled={working}>{working ? "Salvando…" : action === "remove" ? "Confirmar retirada" : action === "expected" ? "Salvar prazo" : "Confirmar cancelamento"}</button></div>
      </form> : null}
    </div>
  </CastOverlay>;
}

function CastOverlay({ children, onClose, subtitle, title, wide = false }: { children: React.ReactNode; onClose: () => void; subtitle: string; title: string; wide?: boolean }) {
  return <div className="cast-overlay" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}><section className="cast-panel" data-wide={wide} role="dialog" aria-modal="true" aria-label={title}><header><div><h2>{title}</h2><p>{subtitle}</p></div><button type="button" onClick={onClose} aria-label="Fechar">×</button></header>{children}</section></div>;
}

function groupCastPage(items: ClinicalCastPatientPage["items"]) {
  const groups = new Map<number, { patientId: number; name: string; passport: string; casts: ClinicalCastListItem[] }>();
  for (const item of items) {
    let group = groups.get(item.patient_id);
    if (!group) {
      group = { patientId: item.patient_id, name: item.patient_name, passport: item.patient_passport, casts: [] };
      groups.set(item.patient_id, group);
    }
    group.casts.push(item);
  }
  return [...groups.values()];
}

function castDueLabel(item: ClinicalCastListItem) {
  if (item.status === "removed") return { label: "Retirado", tone: "done" };
  if (item.status === "cancelled") return { label: "Cancelado", tone: "muted" };
  const expected = new Date(item.expected_removal_at);
  const now = new Date();
  if (expected < now) return { label: "Atrasado", tone: "late" };
  if (expected.toDateString() === now.toDateString()) return { label: "Retirada hoje", tone: "today" };
  return { label: "No prazo", tone: "current" };
}

function localDateTimeValue(date: Date) {
  const offset = date.getTimezoneOffset() * 60_000;
  return new Date(date.getTime() - offset).toISOString().slice(0, 16);
}

function toIso(value: string) {
  const date = new Date(value);
  return Number.isFinite(date.getTime()) ? date.toISOString() : value;
}

function optionalNumber(value: string) {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : undefined;
}

function formatDate(value: string) {
  return new Intl.DateTimeFormat("pt-BR").format(new Date(value));
}

function formatDateTime(value: string) {
  return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short" }).format(new Date(value));
}

function initials(name: string) {
  return name.split(/\s+/).slice(0, 2).map((part) => part[0]?.toUpperCase()).join("");
}

function messageOf(value: unknown) {
  return value instanceof Error ? value.message : "Não foi possível concluir a operação.";
}

async function fetchCastReferences(includeInactive: boolean) {
  const params = new URLSearchParams({ view: "references" });
  if (includeInactive) params.set("includeInactive", "true");
  const response = await fetch(`/api/casts?${params}`, { cache: "no-store" });
  const payload = await response.json() as { references?: ClinicalCastReference[]; error?: string };
  if (!response.ok) throw new Error(payload.error ?? "Não foi possível consultar as referências de gesso.");
  return payload.references ?? [];
}
