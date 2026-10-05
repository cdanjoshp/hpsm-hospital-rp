"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { AttendanceHistoryPage, AttendanceRecord } from "../lib/operational-data";
import { formatPatientPassport } from "../lib/passport";
import { staffIdentity } from "../lib/staff-identity";

const formatMoney = (value: number | string) => new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(Number(value));
const formatPercent = (value: number) => `${new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 2 }).format(Number(value))}%`;
const formatDate = (value: string) => new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(value));

function focusedAttendanceId() {
  const match = window.location.hash.match(/^#atendimento-(\d+)$/);
  return match ? Number(match[1]) : null;
}

export function AttendanceHistory({ canManage, focusId = null, scope }: { canManage: boolean; focusId?: number | null; scope?: "all" | "mine" }) {
  const [history, setHistory] = useState<AttendanceRecord[]>([]);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);
  const [page, setPage] = useState(1);
  const [total, setTotal] = useState(0);
  const [cancelling, setCancelling] = useState(false);
  const controllerRef = useRef<AbortController | null>(null);

  const loadHistory = useCallback(async (targetPage = 1, focusId: number | null = null) => {
    controllerRef.current?.abort();
    const controller = new AbortController();
    controllerRef.current = controller;
    setLoading(true);
    setError("");
    try {
      const params = new URLSearchParams({ page: String(targetPage), pageSize: "20" });
      if (focusId) params.set("focusId", String(focusId));
      const response = await fetch(`/api/attendances?${params}`, { cache: "no-store", signal: controller.signal });
      const payload = (await response.json()) as { error?: string; history?: AttendanceHistoryPage };
      if (!response.ok || !payload.history) throw new Error(payload.error ?? "Não foi possível consultar o histórico.");
      setHistory(payload.history.items);
      setPage(payload.history.page);
      setTotal(payload.history.total);
    } catch (cause) {
      if (cause instanceof DOMException && cause.name === "AbortError") return;
      setError(cause instanceof Error ? cause.message : "Não foi possível consultar o histórico.");
    } finally {
      if (controllerRef.current === controller) setLoading(false);
    }
  }, []);

  useEffect(() => {
    const timer = window.setTimeout(() => void loadHistory(1, focusId ?? focusedAttendanceId()), 0);
    return () => { window.clearTimeout(timer); controllerRef.current?.abort(); };
  }, [focusId, loadHistory]);

  useEffect(() => {
    const refresh = () => void loadHistory(1);
    window.addEventListener("hpsm:attendance-created", refresh);
    return () => window.removeEventListener("hpsm:attendance-created", refresh);
  }, [loadHistory]);

  useEffect(() => {
    if (!history.length || (!focusId && !window.location.hash.startsWith("#atendimento-"))) return;
    const target = document.getElementById(focusId ? `atendimento-${focusId}` : window.location.hash.slice(1));
    if (!target) return;
    const frame = window.requestAnimationFrame(() => target.scrollIntoView({ behavior: "smooth", block: "center" }));
    return () => window.cancelAnimationFrame(frame);
  }, [focusId, history]);

  const visibleHistory = focusId ? history.filter((record) => record.id === focusId) : history;

  async function cancelAttendance(record: AttendanceRecord) {
    if (cancelling || !window.confirm(`Cancelar o atendimento #${record.id}?`)) return;
    setCancelling(true);
    setError("");
    try {
      const response = await fetch("/api/attendances", {
        method: "PATCH",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ attendanceId: record.id }),
      });
      const payload = (await response.json()) as { error?: string };
      if (!response.ok) { setError(payload.error ?? "Não foi possível cancelar o atendimento."); return; }
      setHistory((current) => current.map((item) => item.id === record.id ? { ...item, status: "cancelled" as const } : item));
    } catch {
      setError("Não foi possível cancelar o atendimento.");
    } finally {
      setCancelling(false);
    }
  }

  return <section className="management-card attendance-history" aria-busy={loading}>
    <div className="section-title"><div><p className="eyebrow">{focusId ? `Registro #${focusId}` : scope === "mine" ? "Seus registros" : scope === "all" ? "Registros da equipe" : "Consulta paginada"}</p><h2>{focusId ? "Atendimento relacionado" : "Histórico de atendimentos e vendas"}</h2></div>{!focusId ? <span className="count-pill">{loading && !history.length ? "…" : total}</span> : null}</div>
    {error ? <p className="form-error" role="alert">{error} <button className="table-action" type="button" onClick={() => void loadHistory(page)}>Tentar novamente</button></p> : null}
    {loading && !history.length ? <div className="compact-empty" role="status"><span>◷</span><strong>Carregando histórico</strong></div> : visibleHistory.length ? <>
      <div className="history-list">{visibleHistory.map((record) => <article id={`atendimento-${record.id}`} key={record.id} data-cancelled={record.status === "cancelled"}>
        <div className="history-main">
          <span className="attendance-id">#{record.id}</span>
          <div><small className="history-record-kind">{record.patient_id === null ? "Venda avulsa" : "Atendimento de paciente"}</small><strong>{record.patient_id === null ? "Venda avulsa" : record.patient_name}</strong><p>{record.patient_id === null ? "Venda sem paciente" : `Passaporte ${formatPatientPassport(record.patient_passport)}`} · {record.professional_name} ({staffIdentity(record.professional_passport, record.professional_position)}){record.plan_name ? ` · ${record.plan_name}` : ""}{record.partnership_name ? ` · ${record.partnership_name}` : ""}</p></div>
          <time>{formatDate(record.created_at)}</time><strong className="history-total">{formatMoney(record.total)}</strong>
        </div>
        <div className="history-items">{record.attendance_items.map((item) => <span key={item.id}>{item.quantity}× {item.service_name}{item.discount_percent > 0 ? ` (−${formatPercent(item.discount_percent)})` : ""}</span>)}</div>
        {record.notes ? <p className="history-note"><strong>Observação:</strong> {record.notes}</p> : null}
        <footer><span data-status={record.status}>{record.status === "cancelled" ? "Cancelado" : record.discount > 0 ? `Desconto ${formatMoney(record.discount)}` : "Concluído"}</span>{canManage && record.status === "completed" ? <button type="button" onClick={() => void cancelAttendance(record)} disabled={cancelling}>Cancelar registro</button> : null}</footer>
      </article>)}</div>
      {!focusId ? <div className="patient-center-pagination attendance-history-pagination" aria-label="Paginação do histórico de atendimentos">
        <button type="button" disabled={loading || page <= 1} onClick={() => void loadHistory(page - 1)}>← Anterior</button>
        <span>Página <strong>{page}</strong> de {Math.max(1, Math.ceil(total / 20))}</span>
        <button type="button" disabled={loading || page * 20 >= total} onClick={() => void loadHistory(page + 1)}>Próxima →</button>
      </div> : null}
    </> : !error ? <div className="empty-state"><span>＋</span><strong>{focusId ? "Registro não encontrado" : "Nenhum atendimento registrado"}</strong><p>{focusId ? "Confira o número do atendimento ou seu acesso a este registro." : "Os registros concluídos aparecerão aqui com seus valores preservados."}</p></div> : null}
  </section>;
}
