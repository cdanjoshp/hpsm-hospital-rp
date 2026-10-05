"use client";

import Link from "next/link";
import { useState } from "react";
import type {
  PatientPortalAttendanceDetail,
  PatientPortalAttendanceListItem,
  PatientPortalAttendancePage,
} from "../lib/patient-portal";
import { formatPortalDate, formatPortalMoney } from "../lib/patient-portal-format";
import { SidebarIcon } from "./sidebar-icon";

export function PatientPortalAttendanceList({ initialPage }: { initialPage: PatientPortalAttendancePage }) {
  const [items, setItems] = useState(initialPage.items);
  const [cursor, setCursor] = useState(initialPage.nextCursor);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  async function loadMore() {
    if (!cursor || loading) return;
    setLoading(true);
    setError("");
    try {
      const query = new URLSearchParams({ cursorAt: cursor.occurredAt, cursorId: String(cursor.id) });
      const response = await fetch(`/api/patient-portal/attendances?${query}`, { cache: "no-store" });
      if (response.status === 401) {
        window.location.assign("/portal-paciente");
        return;
      }
      if (!response.ok) throw new Error("attendance_request_failed");
      const page = await response.json() as PatientPortalAttendancePage;
      setItems((current) => {
        const known = new Set(current.map((item) => item.id));
        return [...current, ...page.items.filter((item) => !known.has(item.id))];
      });
      setCursor(page.nextCursor);
    } catch {
      setError("Não foi possível carregar mais atendimentos agora.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <>
      <section className="patient-portal-financial-summary" aria-label="Resumo dos atendimentos">
        <article>
          <span><SidebarIcon name="catalog" /></span>
          <div><p>Total gasto no hospital</p><strong>{formatPortalMoney(initialPage.metrics.lifetimeSpent)}</strong></div>
        </article>
        <article>
          <span><SidebarIcon name="attendances" /></span>
          <div><p>Atendimentos realizados</p><strong>{initialPage.metrics.totalAttendances}</strong></div>
        </article>
      </section>

      {!items.length ? (
        <p className="patient-portal-empty patient-portal-empty-page">Nenhum atendimento registrado até o momento.</p>
      ) : (
        <div className="patient-portal-attendance-wrap">
          <div className="patient-portal-attendance-list">
            {items.map((attendance) => <AttendanceCard attendance={attendance} key={attendance.id} />)}
          </div>
          {error ? <p className="patient-portal-inline-error" role="alert">{error}</p> : null}
          {cursor ? <button className="patient-portal-load-more" disabled={loading} onClick={loadMore} type="button">{loading ? "Carregando…" : "Carregar mais"}</button> : null}
        </div>
      )}
    </>
  );
}
export function PatientPortalAttendanceDetailView({ data }: { data: PatientPortalAttendanceDetail }) {
  const attendance = data.attendance;
  return (
    <div className="patient-portal-attendance-detail">
      <Link className="patient-portal-back-link" href="/portal-paciente/atendimentos" prefetch={false}>← Voltar aos atendimentos</Link>

      <section className="patient-portal-detail-card" aria-labelledby="patient-portal-detail-title">
        <header>
          <div>
            <p>Atendimento</p>
            <h2 id="patient-portal-detail-title">{formatPortalDate(attendance.occurredAt, true)}</h2>
          </div>
          <strong>{formatPortalMoney(attendance.total)}</strong>
        </header>
        <dl className="patient-portal-detail-meta">
          <div><dt>Profissional</dt><dd>{professionalLabel(attendance)}</dd></div>
          <div><dt>Benefício utilizado</dt><dd>{benefitLabel(attendance)}</dd></div>
        </dl>
      </section>

      <section className="patient-portal-detail-card" aria-labelledby="patient-portal-items-title">
        <header><div><p>Valores históricos</p><h2 id="patient-portal-items-title">Itens do atendimento</h2></div></header>
        <div className="patient-portal-detail-items">
          {attendance.items.map((item, index) => {
            const original = item.unitPrice * item.quantity;
            return (
              <article key={`${item.name}-${index}`}>
                <div className="patient-portal-detail-item-head"><strong>{item.name}</strong><strong>{formatPortalMoney(item.lineTotal)}</strong></div>
                <dl>
                  <div><dt>Quantidade</dt><dd>{item.quantity}</dd></div>
                  <div><dt>Valor unitário</dt><dd>{formatPortalMoney(item.unitPrice)}</dd></div>
                  <div><dt>Valor original</dt><dd>{formatPortalMoney(original)}</dd></div>
                  <div><dt>Desconto aplicado</dt><dd>{item.discountPercent > 0 ? `${formatPercent(item.discountPercent)} · −${formatPortalMoney(item.discountAmount)}` : "Sem desconto"}</dd></div>
                </dl>
              </article>
            );
          })}
        </div>
      </section>

      <section className="patient-portal-detail-card patient-portal-detail-totals" aria-label="Totais do atendimento">
        <dl>
          <div><dt>Subtotal</dt><dd>{formatPortalMoney(attendance.subtotal)}</dd></div>
          <div><dt>Desconto total</dt><dd>{attendance.discount > 0 ? `−${formatPortalMoney(attendance.discount)}` : formatPortalMoney(0)}</dd></div>
          <div><dt>Total final</dt><dd>{formatPortalMoney(attendance.total)}</dd></div>
        </dl>
      </section>
    </div>
  );
}

function AttendanceCard({ attendance }: { attendance: PatientPortalAttendanceListItem }) {
  return (
    <article>
      <div className="patient-portal-attendance-card-main">
        <time dateTime={attendance.occurredAt}>{formatPortalDate(attendance.occurredAt, true)}</time>
        <h2>{professionalLabel(attendance)}</h2>
        <p>{benefitLabel(attendance)} · {attendance.itemCount} {attendance.itemCount === 1 ? "item" : "itens"}</p>
      </div>
      <div className="patient-portal-attendance-card-action">
        <strong>{formatPortalMoney(attendance.total)}</strong>
        <Link href={`/portal-paciente/atendimentos/${attendance.id}`} prefetch={false}>Ver detalhes</Link>
      </div>
    </article>
  );
}

function benefitLabel(attendance: Pick<PatientPortalAttendanceListItem, "benefitCode" | "benefitName">) {
  return attendance.benefitName || (attendance.benefitCode ? "Benefício aplicado" : "Sem benefício");
}

function professionalLabel(attendance: Pick<PatientPortalAttendanceListItem, "professionalName" | "professionalPosition">) {
  const name = attendance.professionalName || "Profissional não informado";
  return attendance.professionalPosition ? `${name} · ${attendance.professionalPosition}` : name;
}

function formatPercent(value: number) {
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 2 }).format(value) + "%";
}
