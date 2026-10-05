"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import type { SystemNotification } from "../lib/notifications";

export function NotificationBell({ initialNotifications, initialUnreadCount }: { initialNotifications: SystemNotification[]; initialUnreadCount: number }) {
  const [dismissedIds, setDismissedIds] = useState<Set<number>>(() => new Set());
  const [open, setOpen] = useState(false);
  const root = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function close(event: MouseEvent) { if (!root.current?.contains(event.target as Node)) setOpen(false); }
    function escape(event: KeyboardEvent) { if (event.key === "Escape") setOpen(false); }
    document.addEventListener("mousedown", close);
    document.addEventListener("keydown", escape);
    return () => { document.removeEventListener("mousedown", close); document.removeEventListener("keydown", escape); };
  }, []);

  const notifications = initialNotifications.filter((item) => !item.read_at && !item.resolved_at && !dismissedIds.has(item.id));

  const unread = initialUnreadCount;
  const label = unread ? `${unread} notificação${unread === 1 ? "" : "ões"} não lida${unread === 1 ? "" : "s"}` : "Nenhuma notificação não lida";

  async function markRead(notificationId: number) {
    setDismissedIds((current) => new Set(current).add(notificationId));
    window.dispatchEvent(new CustomEvent("hpsm:notifications-read", { detail: { count: 1, notificationId } }));
    try {
      await fetch("/api/notifications/read", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ notificationId }),
      });
    } catch { /* O destino continua acessível mesmo se a confirmação de leitura falhar. */ }
  }

  return (
    <div className="notification-bell-wrap" ref={root}>
      <button className="notification-bell" type="button" aria-expanded={open} aria-haspopup="menu" aria-label={label} title={label} onClick={() => setOpen((value) => !value)}>
        <svg aria-hidden="true" viewBox="0 0 24 24"><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4" /></svg>
        {unread ? <span aria-hidden="true">{unread > 99 ? "99+" : unread}</span> : null}
      </button>
      {open ? <section className="notification-popover" role="menu" aria-label="Notificações não lidas">
        <header><div><strong>Notificações</strong><span>{unread ? `${unread} não lida${unread === 1 ? "" : "s"}` : "Tudo em dia"}</span></div><button type="button" aria-label="Fechar notificações" onClick={() => setOpen(false)}>×</button></header>
        <div className="notification-popover-list">
          {notifications.slice(0, 8).map((notification) => {
            const content = <><span className="notification-popover-icon" data-priority={notification.priority}>{notification.priority === "urgent" ? "!" : notification.priority === "important" ? "i" : "●"}</span><div><strong>{notification.title}</strong><p>{notification.body}</p><small>{formatDateTime(notification.created_at)}</small></div></>;
            return notification.action_url
              ? <Link key={notification.id} role="menuitem" href={notification.action_url} onClick={() => { setOpen(false); void markRead(notification.id); }}>{content}</Link>
              : <button key={notification.id} role="menuitem" type="button" onClick={() => void markRead(notification.id)}>{content}</button>;
          })}
          {!unread ? <div className="notification-popover-empty"><span>✓</span><strong>Nenhuma notificação nova</strong><p>As próximas atualizações aparecerão aqui.</p></div> : null}
        </div>
      </section> : null}
    </div>
  );
}

function formatDateTime(value: string) {
  return new Intl.DateTimeFormat("pt-BR", { day: "2-digit", hour: "2-digit", minute: "2-digit", month: "2-digit", timeZone: "America/Sao_Paulo" }).format(new Date(value));
}
