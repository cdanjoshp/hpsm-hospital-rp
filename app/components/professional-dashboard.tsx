"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useMemo, useRef, useState } from "react";
import {
  dashboardShortcutCatalog, defaultDashboardPreference, normalizeDashboardPreference,
  visibleDashboardShortcuts, type DashboardPreference, type DashboardShortcut,
} from "../lib/dashboard-customization";
import type { ProfessionalDashboardData } from "../lib/dashboard";
import type { WeeklyProgress } from "../lib/hr";
import { DashboardAnnouncements } from "./dashboard-announcements";
import { useShellData } from "./persistent-app-shell";
import { SidebarIcon } from "./sidebar-icon";

export function ProfessionalDashboard({ data, dateLabel, firstName, permissionCodes }: {
  data: ProfessionalDashboardData | null;
  dateLabel: string;
  firstName: string;
  permissionCodes: string[];
}) {
  const router = useRouter();
  const shell = useShellData();
  const initialPreference = useMemo(() => normalizeDashboardPreference(data?.preferences, permissionCodes), [data?.preferences, permissionCodes]);
  const [savedPreference, setSavedPreference] = useState<DashboardPreference>(initialPreference);
  const [draftShortcuts, setDraftShortcuts] = useState<string[]>(() => visibleDashboardShortcuts(initialPreference.shortcuts, permissionCodes).map((entry) => entry.id));
  const [editing, setEditing] = useState(false);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState("");
  const catalog = useMemo(() => dashboardShortcutCatalog(permissionCodes), [permissionCodes]);
  const shortcuts = visibleDashboardShortcuts(editing ? draftShortcuts : savedPreference.shortcuts, permissionCodes);
  const saleShortcut = catalog.find((shortcut) => shortcut.id === "new_attendance");
  const consultations = catalog.find((shortcut) => shortcut.id === "consultations");
  const weeklyProgress = shell.weeklyProgress ?? data?.weeklyProgress;

  function openEditor() {
    setDraftShortcuts(visibleDashboardShortcuts(savedPreference.shortcuts, permissionCodes).map((entry) => entry.id));
    setMessage(""); setEditing(true);
  }
  function closeEditor() { setEditing(false); setMessage(""); }
  function moveShortcut(id: string, target: number) {
    setDraftShortcuts((current) => {
      const next = [...current];
      const index = next.indexOf(id);
      if (index < 0 || target < 0 || target >= next.length || index === target) return current;
      next.splice(index, 1);
      next.splice(target, 0, id);
      return next;
    });
  }
  async function save() {
    if (saving) return;
    setSaving(true); setMessage("");
    try {
      const availableIds = new Set(catalog.map((entry) => entry.id));
      const unavailable = savedPreference.shortcuts.filter((id) => !availableIds.has(id) && id !== "overview" && id !== "attendances");
      const preference = { ...defaultDashboardPreference(permissionCodes), shortcuts: [...draftShortcuts, ...unavailable] };
      const response = await fetch("/api/dashboard-preferences", {
        method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(preference),
      });
      const payload = await response.json().catch(() => null) as { error?: string; preferences?: unknown } | null;
      if (!response.ok) { setMessage(payload?.error ?? "Não foi possível salvar a ordem dos atalhos."); return; }
      const next = normalizeDashboardPreference(payload?.preferences, permissionCodes);
      setSavedPreference(next); setDraftShortcuts(visibleDashboardShortcuts(next.shortcuts, permissionCodes).map((entry) => entry.id));
      setEditing(false); setMessage("Ordem dos atalhos salva.");
      router.refresh();
    } catch { setMessage("Não foi possível salvar a ordem dos atalhos."); }
    finally { setSaving(false); }
  }

  return <div className="professional-dashboard professional-home">
    <section className="dashboard-hero" aria-labelledby="dashboard-welcome-title">
      <div className="dashboard-hero-content">
        <p className="dashboard-hero-eyebrow">Seu espaço de trabalho</p>
        <h2 id="dashboard-welcome-title">Olá, {firstName}.</h2>
        <p>Acompanhe suas prioridades e acesse os módulos do hospital.</p>
        <div className="dashboard-hero-actions">
          {saleShortcut ? <Link href={saleShortcut.href} prefetch={false} className="dashboard-hero-primary">Nova Venda</Link> : null}
          {consultations ? <Link href={consultations.href} prefetch={false} className="dashboard-hero-secondary">Ir para consultas</Link> : null}
        </div>
      </div>
      <div className="dashboard-hero-side">
        {weeklyProgress ? <DashboardHeroGoal progress={weeklyProgress} /> : null}
        <div className="dashboard-hero-date" aria-label="Data de hoje"><span>HPSM</span><strong>{dateLabel}</strong><small>Visão do dia</small></div>
      </div>
    </section>

    <DashboardAnnouncements initialAnnouncements={data?.announcements ?? []} />
    <ShortcutCard onCustomize={openEditor} shortcuts={shortcuts} />
    {message ? <p className="dashboard-save-message" role="status" data-error={message !== "Ordem dos atalhos salva."}>{message}</p> : null}

    {editing ? <DashboardDialog title="Organizar atalhos" onClose={closeEditor} wide>
      <p className="dashboard-order-help">Escolha a posição de cada módulo. Todos os seus acessos continuam visíveis.</p>
      <ol className="dashboard-order-list">{shortcuts.map((shortcut, index) => <li key={shortcut.id}>
        <span className="dashboard-order-icon"><SidebarIcon name={shortcut.icon} /></span>
        <strong>{shortcut.label}</strong>
        <label>Posição <select value={index + 1} onChange={(event) => moveShortcut(shortcut.id, Number(event.target.value) - 1)} aria-label={`Posição de ${shortcut.label}`}>{shortcuts.map((_, position) => <option key={position} value={position + 1}>{position + 1}</option>)}</select></label>
        <button type="button" disabled={index === 0} onClick={() => moveShortcut(shortcut.id, index - 1)} aria-label={`Mover ${shortcut.label} para cima`}>↑</button>
        <button type="button" disabled={index === shortcuts.length - 1} onClick={() => moveShortcut(shortcut.id, index + 1)} aria-label={`Mover ${shortcut.label} para baixo`}>↓</button>
      </li>)}</ol>
      <div className="dashboard-dialog-actions"><button type="button" onClick={() => setDraftShortcuts(catalog.map((entry) => entry.id))}>Restaurar ordem</button><button type="button" onClick={closeEditor}>Cancelar</button><button type="button" className="primary" disabled={saving} onClick={() => void save()}>{saving ? "Salvando…" : "Salvar ordem"}</button></div>
      {message ? <p className="form-error" role="alert">{message}</p> : null}
    </DashboardDialog> : null}
  </div>;
}

function DashboardHeroGoal({ progress }: { progress: WeeklyProgress }) {
  const target = progress.counterTargetMinutes;
  const current = progress.monthlyAccumulated;
  const remaining = target === null || current === null ? null : Math.max(0, target - current);
  const weekEnd = new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "2-digit", timeZone: "UTC" })
    .format(new Date(`${progress.weekEnd}T00:00:00Z`));
  return <Link className="dashboard-hero-goal" href="/meu-rh" prefetch={false} aria-label={`Meta no contador da cidade: ${target === null ? "aguardando leitura" : formatGoalMinutes(target)}. Atual: ${formatGoalMinutes(current)}. Meta da semana: mais ${formatGoalMinutes(progress.requiredMinutes)}.`}>
    <span className="dashboard-hero-goal-heading"><span><SidebarIcon name="my-hr" /> Meta da semana</span><em>+{formatGoalMinutes(progress.requiredMinutes)}</em></span>
    <strong data-pending={target === null}>{target === null ? "Aguardando leitura" : formatGoalMinutes(target)}</strong>
    <small>Atual {formatGoalMinutes(current)}{remaining !== null ? ` · ${remaining === 0 ? "meta atingida" : `faltam ${formatGoalMinutes(remaining)}`}` : ""}</small>
    <small>Até dom. {weekEnd}</small>
  </Link>;
}

function formatGoalMinutes(value: number | null) {
  if (value === null || !Number.isFinite(value)) return "—";
  const minutes = Math.max(0, Math.round(value));
  return `${Math.floor(minutes / 60)}h${String(minutes % 60).padStart(2, "0")}`;
}

function ShortcutCard({ onCustomize, shortcuts }: { onCustomize: () => void; shortcuts: DashboardShortcut[] }) {
  return <section className="dashboard-direct-access" aria-labelledby="dashboard-shortcuts-title">
    <header className="dashboard-direct-access-header"><h2 id="dashboard-shortcuts-title">Módulos</h2><button type="button" className="dashboard-customize-button" onClick={onCustomize}>Organizar atalhos</button></header>
    {shortcuts.length ? <nav className="dashboard-shortcut-grid" aria-label="Módulos do sistema">{shortcuts.map((shortcut) => <Link className="dashboard-shortcut-card" href={shortcut.href} key={shortcut.id} prefetch={false}><span className="dashboard-shortcut-card-icon" aria-hidden="true"><SidebarIcon name={shortcut.icon} /></span><strong>{shortcut.label}</strong></Link>)}</nav> : <div className="dashboard-direct-access-empty"><strong>Nenhum módulo disponível.</strong><p>Seu cargo ainda não possui acessos liberados.</p></div>}
  </section>;
}

function DashboardDialog({ children, onClose, title, wide = false }: { children: React.ReactNode; onClose: () => void; title: string; wide?: boolean }) {
  const dialogRef = useRef<HTMLElement>(null);
  useEffect(() => {
    const previous = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    dialogRef.current?.querySelector<HTMLElement>("button:not(:disabled), [href], input, select, textarea, [tabindex]:not([tabindex='-1'])")?.focus();
    return () => previous?.focus();
  }, []);
  function handleKeyDown(event: React.KeyboardEvent<HTMLElement>) {
    if (event.key === "Escape") { event.preventDefault(); onClose(); return; }
    if (event.key !== "Tab") return;
    const focusable = Array.from(event.currentTarget.querySelectorAll<HTMLElement>("button:not(:disabled), [href], input, select, textarea, [tabindex]:not([tabindex='-1'])"));
    if (!focusable.length) { event.preventDefault(); return; }
    const first = focusable[0]; const last = focusable[focusable.length - 1];
    if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
    else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
  }
  return <div className="dashboard-dialog-backdrop" role="presentation" onMouseDown={(event) => { if (event.currentTarget === event.target) onClose(); }}><section ref={dialogRef} aria-labelledby="dashboard-dialog-title" aria-modal="true" className="dashboard-dialog" data-wide={wide} role="dialog" tabIndex={-1} onKeyDown={handleKeyDown}><header><h2 id="dashboard-dialog-title">{title}</h2><button type="button" onClick={onClose} aria-label="Fechar">×</button></header>{children}</section></div>;
}
