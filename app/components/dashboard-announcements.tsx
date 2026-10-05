"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import type { DashboardAnnouncement } from "../lib/dashboard";
import { useShellData } from "./persistent-app-shell";

export function DashboardAnnouncements({ initialAnnouncements }: {
  initialAnnouncements: DashboardAnnouncement[];
}) {
  const shellData = useShellData();
  const [readIds, setReadIds] = useState<Set<number>>(() => new Set());

  useEffect(() => {
    const onRead = (event: Event) => {
      const id = (event as CustomEvent<{ notificationId?: number }>).detail?.notificationId;
      if (typeof id === "number") setReadIds((current) => new Set(current).add(id));
    };
    window.addEventListener("hpsm:notifications-read", onRead);
    return () => window.removeEventListener("hpsm:notifications-read", onRead);
  }, []);

  const source: DashboardAnnouncement[] = initialAnnouncements.length ? initialAnnouncements : shellData.notifications
    .filter((notification) => notification.kind === "announcement")
    .map((notification) => ({
      action_url: notification.action_url,
      author_name: notification.author_name,
      created_at: notification.created_at,
      id: notification.id,
      priority: notification.priority,
      read_at: notification.read_at,
      title: notification.title,
    }));
  const unread = source.filter((item) => !item.read_at && !readIds.has(item.id))
    .sort((left, right) => Number(right.priority === "urgent") - Number(left.priority === "urgent") || right.created_at.localeCompare(left.created_at));
  if (!unread.length) return null;

  const announcement = unread[0];
  return <aside className="dashboard-announcement-strip" aria-label="Comunicados não lidos">
    <span className="dashboard-announcement-strip-icon" aria-hidden="true">i</span>
    <div><strong>{announcement.title}</strong><span>{unread.length > 1 ? `${unread.length} comunicados para você` : `Comunicado de ${announcement.author_name}`}</span></div>
    <Link href="/notificacoes" prefetch={false}>Ler comunicado <span aria-hidden="true">→</span></Link>
  </aside>;
}
