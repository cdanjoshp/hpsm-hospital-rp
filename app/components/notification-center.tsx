"use client";

import { FormEvent, useCallback, useMemo, useState } from "react";
import { useAppRefresh } from "../lib/client-refresh";
import type { AnnouncementSummary, SystemNotification } from "../lib/notifications";
import { staffIdentity } from "../lib/staff-identity";
import { useModalFocus } from "./use-modal-focus";

type AnnouncementCenterItem = SystemNotification | AnnouncementSummary;

export function NotificationCenter({ canManage, initialAnnouncements, referenceTime }: {
  canManage: boolean;
  initialAnnouncements: AnnouncementCenterItem[];
  referenceTime: string;
}) {
  const refreshApp = useAppRefresh();
  const [announcements, setAnnouncements] = useState<AnnouncementCenterItem[]>(initialAnnouncements);
  const [selectedAnnouncement, setSelectedAnnouncement] = useState<AnnouncementCenterItem | null>(null);
  const [showComposer, setShowComposer] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const active = useMemo(
    () => announcements.filter((item) => !item.archived_at && (!item.expires_at || item.expires_at > referenceTime)),
    [announcements, referenceTime],
  );
  const managedAnnouncements = announcements.filter(isManagedAnnouncement);
  const totalViews = managedAnnouncements.reduce((total, item) => total + item.readers.length, 0);
  const totalUnread = managedAnnouncements.reduce((total, item) => total + item.non_readers.length, 0);
  const closeAnnouncement = useCallback(() => setSelectedAnnouncement(null), []);

  async function publish(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!canManage || saving) return;
    setSaving(true); setError("");
    const form = new FormData(event.currentTarget);
    try {
      const response = await fetch("/api/notifications/announcements", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({
        audience: form.get("audience"), body: form.get("body"), expiresOn: form.get("expiresOn") || null,
        priority: form.get("priority"), title: form.get("title"),
      }) });
      const payload = (await response.json()) as { error?: string };
      if (!response.ok) { setError(payload.error ?? "Não foi possível publicar o comunicado."); return; }
      setShowComposer(false);
      refreshApp();
    } catch { setError("Não foi possível publicar o comunicado."); }
    finally { setSaving(false); }
  }

  async function archive(notificationId: number) {
    if (!canManage || saving || !window.confirm("Arquivar este comunicado? O histórico e as leituras serão preservados.")) return;
    setSaving(true); setError("");
    try {
      const response = await fetch("/api/notifications/announcements/archive", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ notificationId }) });
      const payload = (await response.json()) as { error?: string };
      if (!response.ok) { setError(payload.error ?? "Não foi possível arquivar o comunicado."); return; }
      const archivedAt = new Date().toISOString();
      setAnnouncements((current) => current.map((item) => item.id === notificationId ? { ...item, archived_at: archivedAt } : item));
    } catch { setError("Não foi possível arquivar o comunicado."); }
    finally { setSaving(false); }
  }

  async function openAnnouncement(announcement: AnnouncementCenterItem) {
    setSelectedAnnouncement(announcement);
    if (announcement.read_at) return;

    const readAt = new Date().toISOString();
    const opened = { ...announcement, read_at: readAt };
    setSelectedAnnouncement(opened);
    setAnnouncements((current) => current.map((item) => item.id === announcement.id ? { ...item, read_at: readAt } : item));
    window.dispatchEvent(new CustomEvent("hpsm:notifications-read", { detail: { count: 1, notificationId: announcement.id } }));

    try {
      const response = await fetch("/api/notifications/read", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ notificationId: announcement.id }),
      });
      if (!response.ok) throw new Error("read_failed");
      if (canManage) refreshApp();
    } catch {
      setError("O comunicado foi aberto, mas não foi possível registrar a leitura.");
    }
  }

  return <div className="notification-workspace communication-admin">
    {canManage ? <section className="notification-summary">
      <article><span>▣</span><div><p>Comunicados ativos</p><strong>{active.length}</strong></div></article>
      <article><span>◉</span><div><p>Visualizações</p><strong>{totalViews}</strong></div></article>
      <article><span>◌</span><div><p>Leituras pendentes</p><strong>{totalUnread}</strong></div></article>
      <article><span>✓</span><div><p>Arquivados/encerrados</p><strong>{announcements.length - active.length}</strong></div></article>
      <div className="notification-summary-actions"><button className="submit-button" type="button" onClick={() => setShowComposer((value) => !value)}>{showComposer ? "Fechar editor" : "Novo comunicado"}</button></div>
    </section> : null}

    {canManage && showComposer ? <section className="management-card notification-composer">
      <div className="section-title"><div><p className="eyebrow">Comunicado institucional</p><h2>Novo aviso</h2></div><span className="count-pill">Diretoria</span></div>
      <form onSubmit={publish}>
        <label className="notification-title-field">Título<input name="title" minLength={4} maxLength={120} required placeholder="Ex.: Reunião geral da equipe" /></label>
        <label>Público<select name="audience" defaultValue="all"><option value="all">Todo o hospital</option><option value="employees">Colaboradores</option><option value="directors">Somente gestão</option></select></label>
        <label>Prioridade<select name="priority" defaultValue="normal"><option value="normal">Informativa</option><option value="important">Importante</option><option value="urgent">Urgente</option></select></label>
        <label>Exibir até (opcional)<input name="expiresOn" type="date" min={new Date().toISOString().slice(0, 10)} /></label>
        <label className="notification-body-field">Mensagem<textarea name="body" minLength={10} maxLength={2000} rows={6} required placeholder="Escreva uma orientação objetiva para a equipe." /></label>
        {error ? <p className="form-error" role="alert">{error}</p> : null}
        <div className="notification-composer-actions"><span>Autor, data e hora serão registrados automaticamente.</span><button className="submit-button" disabled={saving} type="submit">{saving ? "Publicando…" : "Publicar comunicado"}</button></div>
      </form>
    </section> : null}

    {error && !showComposer ? <p className="form-error" role="alert">{error}</p> : null}
    {canManage ? <ManagementBoard
      announcements={managedAnnouncements}
      onArchive={archive}
      onOpen={openAnnouncement}
      referenceTime={referenceTime}
      saving={saving}
    /> : <ReaderBoard announcements={active} onOpen={openAnnouncement} />}

    {selectedAnnouncement ? <AnnouncementDialog
      announcement={selectedAnnouncement}
      onClose={closeAnnouncement}
      referenceTime={referenceTime}
    /> : null}
  </div>;
}

function ManagementBoard({ announcements, onArchive, onOpen, referenceTime, saving }: {
  announcements: AnnouncementSummary[];
  onArchive: (notificationId: number) => Promise<void>;
  onOpen: (announcement: AnnouncementSummary) => Promise<void>;
  referenceTime: string;
  saving: boolean;
}) {
  return <section className="management-card communication-board">
    <div className="section-title"><div><p className="eyebrow">Resumo administrativo</p><h2>Comunicados publicados</h2></div><span className="count-pill">{announcements.length}</span></div>
    <div className="communication-table">
      <div className="communication-row communication-head"><span>Comunicado</span><span>Publicação</span><span>Leituras</span><span>Situação</span><span>Ação</span></div>
      {announcements.map((announcement) => {
        const ended = Boolean(announcement.archived_at || (announcement.expires_at && announcement.expires_at <= referenceTime));
        return <article className="communication-row" key={announcement.id} data-ended={ended}>
          <span><button className="communication-open-button" type="button" onClick={() => void onOpen(announcement)}><strong>{announcement.title}</strong><small>{announcement.body}</small><em data-priority={announcement.priority}>{priorityLabel(announcement.priority)} · {audienceLabel(announcement.audience)}</em><b>Visualizar comunicado completo</b></button></span>
          <span><strong>{formatDateTime(announcement.created_at)}</strong><small>{announcement.author_name}</small></span>
          <span className="announcement-read-status">
            <strong>{announcement.readers.length} visualizaram · {announcement.non_readers.length} pendentes</strong>
            <small>{announcement.eligible_readers ? `${Math.round((announcement.readers.length / announcement.eligible_readers) * 100)}% do público atual` : "Sem público elegível"}</small>
            <details><summary>Quem visualizou ({announcement.readers.length})</summary><div>{announcement.readers.map((reader) => <span key={reader.user_id}><b>{reader.display_name}</b><small>{staffIdentity(reader.passport, reader.position_name)} · {formatDateTime(reader.read_at)}</small></span>)}{!announcement.readers.length ? <p>Nenhuma visualização registrada.</p> : null}</div></details>
            <details><summary>Ainda não visualizaram ({announcement.non_readers.length})</summary><div>{announcement.non_readers.map((reader) => <span key={reader.user_id}><b>{reader.display_name}</b><small>{staffIdentity(reader.passport, reader.position_name)}</small></span>)}{!announcement.non_readers.length ? <p>Todos os usuários elegíveis visualizaram.</p> : null}</div></details>
          </span>
          <span><em data-status={ended ? "inactive" : "active"}>{announcement.archived_at ? "Arquivado" : ended ? "Encerrado" : "Ativo"}</em>{announcement.expires_at ? <small>Até {formatDate(announcement.expires_at)}</small> : <small>Sem validade</small>}</span>
          <span>{!announcement.archived_at ? <button className="table-action" type="button" disabled={saving} onClick={() => void onArchive(announcement.id)}>Arquivar</button> : "—"}</span>
        </article>;
      })}
      {!announcements.length ? <div className="compact-empty"><span>▣</span><strong>Nenhum comunicado publicado</strong><p>Use “Novo comunicado” para enviar o primeiro aviso.</p></div> : null}
    </div>
  </section>;
}

function ReaderBoard({ announcements, onOpen }: {
  announcements: AnnouncementCenterItem[];
  onOpen: (announcement: AnnouncementCenterItem) => Promise<void>;
}) {
  return <section className="management-card notification-board">
    <div className="section-title"><div><p className="eyebrow">Mural institucional</p><h2>Comunicados para você</h2></div><span className="count-pill">{announcements.length}</span></div>
    {announcements.length ? <div className="notification-list">
      {announcements.map((announcement) => <button
        className="notification-card notification-reader-card"
        data-priority={announcement.priority}
        data-unread={!announcement.read_at}
        key={announcement.id}
        onClick={() => void onOpen(announcement)}
        type="button"
      >
        <span className="notification-icon" aria-hidden="true">{announcement.priority === "urgent" ? "!" : announcement.priority === "important" ? "i" : "●"}</span>
        <span className="notification-copy"><span className="notification-reader-title"><strong>{announcement.title}</strong>{!announcement.read_at ? <em>Novo</em> : null}</span><p>{announcement.body}</p><small>Publicado por {announcement.author_name} · {formatDateTime(announcement.created_at)}</small></span>
        <aside><span>{priorityLabel(announcement.priority)}</span><b>Ler completo</b></aside>
      </button>)}
    </div> : <div className="compact-empty notification-empty"><span>✓</span><strong>Nenhum comunicado disponível</strong><p>Novos avisos destinados a você aparecerão aqui.</p></div>}
  </section>;
}

function AnnouncementDialog({ announcement, onClose, referenceTime }: {
  announcement: AnnouncementCenterItem;
  onClose: () => void;
  referenceTime: string;
}) {
  const dialogRef = useModalFocus(onClose);
  const ended = Boolean(announcement.archived_at || (announcement.expires_at && announcement.expires_at <= referenceTime));
  const titleId = `communication-dialog-title-${announcement.id}`;
  const descriptionId = `communication-dialog-body-${announcement.id}`;
  return <div className="communication-modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.currentTarget === event.target) onClose(); }}>
    <section aria-describedby={descriptionId} aria-labelledby={titleId} aria-modal="true" className="communication-modal management-card" ref={dialogRef} role="dialog" tabIndex={-1}>
      <header><div><p className="eyebrow">Comunicado institucional</p><h2 id={titleId}>{announcement.title}</h2></div><button aria-label="Fechar comunicado" onClick={onClose} type="button">×</button></header>
      <div className="communication-modal-meta"><em data-priority={announcement.priority}>{priorityLabel(announcement.priority)}</em><span>{audienceLabel(announcement.audience)}</span><span>{announcement.archived_at ? "Arquivado" : ended ? "Encerrado" : "Ativo"}</span></div>
      <p className="communication-modal-body" id={descriptionId}>{announcement.body}</p>
      <footer><div><strong>Publicado por {announcement.author_name}</strong><span>{formatDateTime(announcement.created_at)}</span></div><span>{announcement.expires_at ? `Disponível até ${formatDate(announcement.expires_at)}` : "Sem data de encerramento"}</span></footer>
    </section>
  </div>;
}

function isManagedAnnouncement(item: AnnouncementCenterItem): item is AnnouncementSummary {
  return "readers" in item && "non_readers" in item && "eligible_readers" in item;
}

function priorityLabel(value: SystemNotification["priority"]) { return value === "urgent" ? "Urgente" : value === "important" ? "Importante" : "Informativo"; }
function audienceLabel(value: SystemNotification["audience"]) { return value === "directors" ? "Gestão" : value === "employees" ? "Colaboradores" : "Todo o hospital"; }
function formatDate(value: string) { return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(value)); }
function formatDateTime(value: string) { return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(value)); }
