"use client";

import { useState } from "react";
import type { HrAdminData, HrHourSnapshot, HrProfile, HrWeeklyRecord } from "../lib/hr";
import type { StaffPosition } from "../lib/access";
import { useAppRefresh } from "../lib/client-refresh";
import { positionName } from "../lib/staff-position";
import { staffIdentity } from "../lib/staff-identity";
import {
  addIsoDays,
  calculateGuidedWeekMinutes,
  clockValueToMinutes,
  getGuidedWeekSegments,
  isoMonthStart,
  minutesToClockValue,
  normalizeClockInput,
} from "../lib/hr-guided";
import { HoursBulkImport } from "./hours-bulk-import";

type Props = {
  actorId: string;
  initialData: HrAdminData;
  positions: StaffPosition[];
};

type ApiResult = {
  employeeId: string;
  error?: string;
  status?: string;
};

type EntryState = {
  calculation: ReturnType<typeof calculateGuidedWeekMinutes>;
  closedRecord: HrWeeklyRecord | null;
  leaveDeductionMinutes: number;
  isSelf: boolean;
  profile: HrProfile;
  readings: Array<{ date: string; minutes: number; referenceMonth: string }>;
};

export function GuidedHoursControl({ actorId, initialData, positions }: Props) {
  const refreshApp = useAppRefresh();
  const today = todayIso();
  const currentWeekStart = mondayOf(today);
  const weekOptions = Array.from({ length: 9 }, (_, index) => addIsoDays(currentWeekStart, index * -7));
  const [weekStart, setWeekStart] = useState(currentWeekStart);
  const [values, setValues] = useState<Record<string, string>>({});
  const [reviewing, setReviewing] = useState(false);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState<{ kind: "error" | "success"; text: string } | null>(null);
  const [reopenReason, setReopenReason] = useState("");

  const weekEnd = addIsoDays(weekStart, 6);
  const canClose = weekEnd <= today;
  const throughDate = canClose ? weekEnd : today;
  const segments = getGuidedWeekSegments(weekStart, throughDate);
  const selectedClosure = initialData.closures.find((closure) => closure.week_start === weekStart) ?? null;
  const closureLocked = selectedClosure?.status === "closed";
  const profiles = initialData.profiles.filter((profile) => (
    profile.role_code !== "diretor_geral"
    && profile.status === "active"
  ));

  const states = profiles.map((profile) => buildEntryState(profile));
  const apuratedCount = states.filter((state) => Boolean(state.closedRecord)).length;
  const actionable = states.filter((state) => (
    !closureLocked
    && (!state.closedRecord || selectedClosure?.status === "reopened")
    && state.calculation.complete
    && !state.calculation.invalid
    && (canClose || state.readings.length > 0)
    && (!canClose || !state.isSelf)
  ));
  const readyToClose = canClose ? actionable : [];
  const metCount = readyToClose.filter((state) => state.calculation.minutes >= 600).length;
  const adjustedCount = readyToClose.filter((state) => state.leaveDeductionMinutes > 0).length;
  const deficitCount = readyToClose.filter((state) => state.calculation.minutes < Math.max(0, 600 - state.leaveDeductionMinutes)).length;
  const unresolvedCount = states.length - readyToClose.length;

  function buildEntryState(profile: HrProfile): EntryState {
    const employeeSnapshots = initialData.snapshots.filter((snapshot) => snapshot.employee_id === profile.user_id);
    const getSnapshot = (date: string) => latestSnapshotForDate(employeeSnapshots, date);
    const getValue = (date: string) => {
      const key = inputKey(profile.user_id, date);
      const snapshot = getSnapshot(date);
      const raw = values[key] ?? (snapshot ? minutesToClockValue(snapshot.total_minutes) : "");
      return clockValueToMinutes(raw);
    };
    const calculation = calculateGuidedWeekMinutes(segments, getValue);
    const readings = uniqueDates(segments.flatMap((segment) => [segment.baselineDate, segment.endDate]))
      .filter((date) => Object.prototype.hasOwnProperty.call(values, inputKey(profile.user_id, date)) || !getSnapshot(date))
      .map((date) => ({ date, minutes: getValue(date), referenceMonth: isoMonthStart(date) }))
      .filter((reading): reading is { date: string; minutes: number; referenceMonth: string } => reading.minutes !== null);
    const leaveDeductionMinutes = Math.min(600, initialData.leaveAdjustments
      .filter((adjustment) => adjustment.employee_id === profile.user_id && adjustment.week_start === weekStart)
      .reduce((total, adjustment) => total + adjustment.deducted_minutes, 0));
    return {
      calculation,
      closedRecord: initialData.weeklyRecords.find((record) => record.employee_id === profile.user_id && record.week_start === weekStart) ?? null,
      leaveDeductionMinutes,
      isSelf: profile.user_id === actorId,
      profile,
      readings,
    };
  }

  function valueFor(profileId: string, date: string, snapshot: HrHourSnapshot | null) {
    return values[inputKey(profileId, date)] ?? (snapshot ? minutesToClockValue(snapshot.total_minutes) : "");
  }

  function changeValue(profileId: string, date: string, raw: string) {
    setReviewing(false);
    setMessage(null);
    setValues((current) => ({ ...current, [inputKey(profileId, date)]: normalizeClockInput(raw) }));
  }

  async function submit(action: "close" | "update") {
    const selected = action === "close" ? readyToClose : actionable;
    if (!selected.length || loading) return;
    setLoading(true);
    setMessage(null);
    try {
      const response = await fetch("/api/hr/guided-hours", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          action,
          entries: selected.map((state) => ({ employeeId: state.profile.user_id, readings: state.readings })),
          weekStart,
        }),
      });
      const payload = (await response.json()) as { error?: string; results?: ApiResult[]; successCount?: number };
      const failures = payload.results?.filter((result) => result.error) ?? [];
      if (!response.ok || !payload.successCount) {
        setMessage({ kind: "error", text: payload.error ?? failures[0]?.error ?? "Não foi possível concluir a operação." });
        return;
      }
      if (failures.length) {
        const first = failures[0];
        const name = profiles.find((profile) => profile.user_id === first.employeeId)?.display_name ?? "Um profissional";
        setMessage({ kind: "error", text: `${payload.successCount} registro(s) concluído(s). ${name}: ${first.error}` });
        refreshApp(1800);
        return;
      }
      setMessage({
        kind: "success",
        text: action === "close"
          ? `${payload.successCount} apuração(ões) concluída(s). Os déficits já podem ser justificados.`
          : `${payload.successCount} acompanhamento(s) atualizado(s) com sucesso.`,
      });
      refreshApp(800);
    } catch {
      setMessage({ kind: "error", text: "Não foi possível salvar. Verifique sua conexão e tente novamente." });
    } finally {
      setLoading(false);
    }
  }

  async function changeClosure(action: "finalize" | "reopen") {
    if (loading) return;
    setLoading(true);
    setMessage(null);
    try {
      const response = await fetch(`/api/hr/weeks/${action}`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ weekStart, reason: reopenReason }) });
      const payload = (await response.json()) as { error?: string };
      if (!response.ok) { setMessage({ kind: "error", text: payload.error ?? "Não foi possível alterar o fechamento." }); return; }
      setMessage({ kind: "success", text: action === "finalize" ? "Semana fechada pela Diretoria. Nenhuma advertência foi criada automaticamente." : "Semana reaberta e registrada na auditoria." });
      refreshApp(700);
    } catch { setMessage({ kind: "error", text: "Não foi possível alterar o fechamento." }); }
    finally { setLoading(false); }
  }

  return (
    <div className="guided-hours">
      <HoursBulkImport />
      <section className="management-card guided-week-header">
        <div>
          <p className="eyebrow">Passo 1 de 2</p>
          <h2>Escolha a semana</h2>
          <p>Depois, copie apenas o total acumulado mostrado no sistema da cidade.</p>
        </div>
        <label>
          Semana acompanhada
          <select value={weekStart} onChange={(event) => { setWeekStart(event.target.value); setReviewing(false); setMessage(null); }}>
            {weekOptions.map((value, index) => <option key={value} value={value}>{index === 0 ? "Semana atual" : "Semana concluída"} · {formatPeriod(value, addIsoDays(value, 6))}</option>)}
          </select>
        </label>
        <div className="guided-week-mode" data-mode={canClose ? "close" : "update"}>
          <span>{canClose ? "✓" : "◷"}</span>
          <div><strong>{closureLocked ? "Semana fechada" : canClose ? "Pronta para apuração" : "Acompanhamento em andamento"}</strong><small>{closureLocked ? `Fechada por ${nameOf(initialData, positions, selectedClosure!.closed_by ?? "")}` : canClose ? "A apuração não aplica advertências." : `Atualização considerada até ${formatDate(throughDate)}.`}</small></div>
        </div>
      </section>

      <section className="guided-instruction" role="note">
        <span>i</span>
        <div><strong>O que devo preencher?</strong><p>Digite o número exatamente como aparece no controle mensal da cidade. Exemplo fictício: <b>38:03</b>. A leitura anterior e o cálculo semanal ficam por conta do HPSM.</p></div>
      </section>

      <section className="management-card guided-entry-card">
        <div className="section-title">
          <div><p className="eyebrow">Passo 2 de 2</p><h2>Informe os acumulados</h2></div>
          <span className="count-pill">{profiles.length} profissional(is)</span>
        </div>

        <div className="guided-employee-list">
          {states.map((state) => (
            <GuidedEmployeeRow
              key={state.profile.user_id}
              initialData={initialData}
              positions={positions}
              segments={segments}
              state={state}
              valueFor={valueFor}
              onChange={changeValue}
              canClose={canClose}
              closureLocked={closureLocked || Boolean(state.closedRecord && selectedClosure?.status === "open")}
            />
          ))}
          {!states.length ? <div className="empty-state"><span>◇</span><strong>Nenhum profissional disponível</strong><p>Não há colaboradores ativos para acompanhar nesta semana.</p></div> : null}
        </div>
      </section>

      {message ? <p className={message.kind === "success" ? "form-success" : "form-error"} role="status">{message.text}</p> : null}

      {canClose && reviewing ? (
        <section className="management-card guided-review" aria-label="Revisão do fechamento">
          <div className="section-title"><div><p className="eyebrow">Revisão final</p><h2>Confira antes de confirmar</h2></div><span className="count-pill">{readyToClose.length} fechamento(s)</span></div>
          <div className="guided-review-grid">
            <ReviewMetric label="Meta cumprida" value={metCount} tone="met" />
            <ReviewMetric label="Com afastamento" value={adjustedCount} tone="justified" />
            <ReviewMetric label="Déficit a justificar" value={deficitCount} tone="warning" />
            <ReviewMetric label="Não será fechada" value={unresolvedCount} tone="waiting" />
          </div>
          {deficitCount ? <div className="guided-warning-note"><span>!</span><p><strong>Próxima etapa:</strong> {deficitCount} profissional(is) receberão uma pendência para justificar o déficit. Nenhuma advertência será criada nesta apuração.</p></div> : null}
          <div className="guided-final-actions">
            <button className="secondary-button" type="button" disabled={loading} onClick={() => setReviewing(false)}>Voltar e corrigir</button>
            <button className="submit-button" type="button" disabled={loading || !readyToClose.length} onClick={() => submit("close")}>{loading ? "Processando…" : `Apurar ${readyToClose.length} colaborador(es)`}</button>
          </div>
        </section>
      ) : (
        <section className="guided-action-bar">
        <div><strong>{canClose ? `${readyToClose.length} profissional(is) prontos` : `${actionable.length} atualização(ões) prontas`}</strong><p>{canClose ? "A apuração calcula meta, afastamentos e déficit. A confirmação final acontece separadamente." : "Salvar a atualização não gera advertências."}</p></div>
          {canClose ? (
            <button className="submit-button" type="button" disabled={loading || !readyToClose.length || closureLocked} onClick={() => setReviewing(true)}>Conferir apuração</button>
          ) : (
            <button className="submit-button" type="button" disabled={loading || !actionable.length} onClick={() => submit("update")}>{loading ? "Salvando…" : "Salvar atualização da semana"}</button>
          )}
        </section>
      )}

      {canClose && selectedClosure ? <section className="management-card week-closure-panel" data-status={selectedClosure.status}><div><p className="eyebrow">Ação da Diretoria · {apuratedCount}/{profiles.length} apurados</p><h2>{selectedClosure.status === "closed" ? "Fechamento confirmado" : "Confirmar fechamento semanal"}</h2><p>{selectedClosure.status === "closed" ? `Registrado em ${formatDateTime(selectedClosure.closed_at!)}. Para corrigir, informe o motivo da reabertura.` : apuratedCount < profiles.length ? "Conclua a apuração de todos os colaboradores ativos antes de fechar a semana." : "Revise afastamentos e justificativas. A confirmação registra autoria, data, hora e período; não aplica advertências."}</p></div>{selectedClosure.status === "closed" ? <div className="closure-reopen"><textarea value={reopenReason} onChange={(event) => setReopenReason(event.target.value)} rows={2} maxLength={2000} placeholder="Motivo da reabertura (mínimo de 10 caracteres)" /><button className="secondary-button" type="button" disabled={loading || reopenReason.trim().length < 10} onClick={() => changeClosure("reopen")}>Reabrir semana</button></div> : <button className="submit-button" type="button" disabled={loading || apuratedCount < profiles.length} onClick={() => changeClosure("finalize")}>{loading ? "Confirmando…" : "Confirmar fechamento"}</button>}</section> : null}

      <details className="management-card guided-technical-history">
        <summary><span>Histórico técnico de leituras</span><small>Consulte apenas para correções ou conferência</small></summary>
        <div className="hr-team-table">
          <div className="hr-team-row hr-snapshot-head"><span>Profissional</span><span>Competência</span><span>Leitura</span><span>Acumulado</span><span>Atualização</span></div>
          {initialData.snapshots.slice(0, 30).map((snapshot) => <div className="hr-team-row hr-snapshot-head" key={snapshot.id}><span><strong>{nameOf(initialData, positions, snapshot.employee_id)}</strong></span><span>{monthLabel(snapshot.reference_month)}</span><span>{formatDate(snapshot.reading_date)}</span><span><b>{formatMinutes(snapshot.total_minutes)}</b></span><span><small>{formatDateTime(snapshot.updated_at)}</small></span></div>)}
          {!initialData.snapshots.length ? <div className="compact-empty"><span>◷</span><strong>Nenhuma leitura registrada</strong><p>As atualizações aparecerão aqui.</p></div> : null}
        </div>
      </details>
    </div>
  );
}

function GuidedEmployeeRow({
  canClose,
  closureLocked,
  initialData,
  positions,
  onChange,
  segments,
  state,
  valueFor,
}: {
  canClose: boolean;
  closureLocked: boolean;
  initialData: HrAdminData;
  positions: StaffPosition[];
  onChange: (profileId: string, date: string, value: string) => void;
  segments: ReturnType<typeof getGuidedWeekSegments>;
  state: EntryState;
  valueFor: (profileId: string, date: string, snapshot: HrHourSnapshot | null) => string;
}) {
  const snapshots = initialData.snapshots.filter((snapshot) => snapshot.employee_id === state.profile.user_id);
  const status = entryStatus(state, canClose);
  const disabled = closureLocked || (canClose && state.isSelf);
  return (
    <article className="guided-employee" data-status={status.code}>
      <div className="guided-person">
        <span>{initials(state.profile.display_name)}</span>
        <div><strong>{state.profile.display_name}</strong><small>{staffIdentity(state.profile.passport, positionName(state.profile, positions))}</small></div>
      </div>
      <div className="guided-readings">
        {segments.map((segment) => {
          const baselineSnapshot = segment.baselineDate ? latestSnapshotForDate(snapshots, segment.baselineDate) : null;
          const endSnapshot = latestSnapshotForDate(snapshots, segment.endDate);
          return (
            <div className="guided-segment" key={segment.referenceMonth}>
              {segment.baselineDate ? baselineSnapshot ? (
                <div className="guided-saved-reading"><small>Leitura anterior · {formatDate(segment.baselineDate)}</small><strong>{formatMinutes(baselineSnapshot.total_minutes)}</strong><span>Já registrada</span></div>
              ) : (
                <label className="guided-input missing">Primeiro uso · total anterior <small>{formatDate(segment.baselineDate)}</small><input aria-label={`Total anterior de ${state.profile.display_name}`} disabled={disabled} inputMode="numeric" maxLength={6} placeholder="00:00" value={valueFor(state.profile.user_id, segment.baselineDate, null)} onChange={(event) => onChange(state.profile.user_id, segment.baselineDate!, event.target.value)} /></label>
              ) : (
                <div className="guided-saved-reading"><small>Início do mês</small><strong>0h00</strong><span>Cálculo automático</span></div>
              )}
              <span className="guided-math" aria-hidden="true">→</span>
              <label className="guided-input">{segments.length > 1 && segment.endDate !== segments.at(-1)?.endDate ? `Fechamento de ${monthShort(segment.referenceMonth)}` : "Total atual"}<small>Leitura de {formatDate(segment.endDate)}</small><input aria-label={`Total atual de ${state.profile.display_name} em ${formatDate(segment.endDate)}`} disabled={disabled} inputMode="numeric" maxLength={6} placeholder="00:00" value={valueFor(state.profile.user_id, segment.endDate, endSnapshot)} onChange={(event) => onChange(state.profile.user_id, segment.endDate, event.target.value)} /></label>
            </div>
          );
        })}
      </div>
      <div className="guided-result">
        <small>Horas · meta {formatMinutes(Math.max(0, 600 - state.leaveDeductionMinutes))}</small>
        <strong>{state.calculation.complete && !state.calculation.invalid ? formatMinutes(state.calculation.minutes) : "—"}</strong>
        <em data-status={status.code}>{status.label}</em>
      </div>
    </article>
  );
}

function ReviewMetric({ label, tone, value }: { label: string; tone: string; value: number }) {
  return <article data-tone={tone}><strong>{value}</strong><span>{label}</span></article>;
}

function entryStatus(state: EntryState, canClose: boolean) {
  if (state.closedRecord?.closure_status === "closed") return { code: "closed", label: weekStatus(state.closedRecord.status) };
  if (state.isSelf && canClose) return { code: "self", label: "Outro diretor deve fechar" };
  if (state.calculation.invalid) return { code: "invalid", label: "Total menor que o anterior" };
  if (!state.calculation.complete) return { code: "incomplete", label: "Preencha os totais" };
  const target = Math.max(0, 600 - state.leaveDeductionMinutes);
  if (state.calculation.minutes >= target) return { code: "met", label: state.leaveDeductionMinutes ? "Meta ajustada cumprida" : "Meta cumprida" };
  return canClose ? { code: "warning", label: "Déficit a justificar" } : { code: "progress", label: `Faltam ${formatMinutes(target - state.calculation.minutes)}` };
}

function latestSnapshotForDate(snapshots: HrHourSnapshot[], date: string) {
  return snapshots
    .filter((snapshot) => snapshot.reading_date === date)
    .sort((a, b) => b.updated_at.localeCompare(a.updated_at))[0] ?? null;
}

function uniqueDates(values: Array<string | null>): string[] {
  return [...new Set(values.filter((value): value is string => Boolean(value)))];
}

function inputKey(profileId: string, date: string) { return `${profileId}:${date}`; }
function todayIso() {
  const parts = new Intl.DateTimeFormat("en-US", { day: "2-digit", month: "2-digit", timeZone: "America/Sao_Paulo", year: "numeric" }).formatToParts(new Date());
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}`;
}
function mondayOf(value: string) {
  const date = new Date(`${value}T00:00:00.000Z`);
  return addIsoDays(value, -((date.getUTCDay() + 6) % 7));
}
function formatDate(value: string) { return value.split("-").reverse().join("/"); }
function formatPeriod(start: string, end: string) { return `${formatDate(start)} a ${formatDate(end)}`; }
function formatMinutes(total: number) { const safe = Math.max(0, Math.round(total)); return `${Math.floor(safe / 60)}h${String(safe % 60).padStart(2, "0")}`; }
function formatDateTime(value: string) { return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(value)); }
function monthLabel(value: string) { return new Intl.DateTimeFormat("pt-BR", { month: "long", timeZone: "UTC", year: "numeric" }).format(new Date(`${value.slice(0, 10)}T00:00:00.000Z`)); }
function monthShort(value: string) { return new Intl.DateTimeFormat("pt-BR", { month: "long", timeZone: "UTC" }).format(new Date(`${value.slice(0, 10)}T00:00:00.000Z`)); }
function initials(value: string) { return value.split(/\s+/).slice(0, 2).map((part) => part[0]?.toUpperCase()).join(""); }
function nameOf(data: HrAdminData, positions: StaffPosition[], id: string) {
  const profile = data.profiles.find((item) => item.user_id === id);
  return profile ? `${profile.display_name} · ${staffIdentity(profile.passport, positionName(profile, positions))}` : "Sistema";
}
function weekStatus(status: string) { return ({ met: "Meta cumprida", justified: "Déficit abonado", deficit: "Déficit mantido", warning_issued: "Advertência aplicada", warning_annulled: "Advertência anulada" } as Record<string, string>)[status] ?? "Apurada"; }
