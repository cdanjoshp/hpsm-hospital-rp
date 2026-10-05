"use client";

import { usePathname, useSearchParams } from "next/navigation";
import { createContext, useContext, useEffect, useRef, useState, type ReactNode } from "react";
import type { WeeklyProgress } from "../lib/hr";
import type { SystemNotification } from "../lib/notifications";
import type { SessionProfile } from "../lib/session";
import { AppSidebar } from "./app-sidebar";
import { GlobalSearchLauncher } from "./global-search-launcher";
import { HrWeekCompact } from "./hr-week-compact";
import { NotificationBell } from "./notification-bell";
import { ProfessionalIdentityInitializer } from "./professional-identity-initializer";

type ShellData = {
  notifications: SystemNotification[];
  pendingCount: number;
  unreadCount: number;
  weeklyProgress: WeeklyProgress | null;
};

const EMPTY_SHELL_DATA: ShellData = { notifications: [], pendingCount: 0, unreadCount: 0, weeklyProgress: null };
const ShellDataContext = createContext<ShellData>(EMPTY_SHELL_DATA);

export function useShellData() {
  return useContext(ShellDataContext);
}

type CachedShellData = ShellData & { fetchedAt: number };
const SHELL_CACHE_MS = 30_000;

export function PersistentAppShell({ children, dashboardGreeting, permissionCodes, positionDisplayName, profile }: {
  children: ReactNode;
  dashboardGreeting: string;
  permissionCodes: string[];
  positionDisplayName: string | null;
  profile: SessionProfile;
}) {
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const cache = useRef<CachedShellData | null>(null);
  const portalRoute = isPortalRoute(pathname);
  const [live, setLive] = useState<ShellData>(EMPTY_SHELL_DATA);
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);

  useEffect(() => {
    if (!portalRoute) return;
    let active = true;
    let pending: AbortController | null = null;
    async function load(force = false) {
      if (!force && cache.current && Date.now() - cache.current.fetchedAt < SHELL_CACHE_MS) {
        setLive(cache.current);
        return;
      }
      if (pending && !force) return;
      pending?.abort();
      const controller = new AbortController();
      pending = controller;
      try {
        const response = await fetch("/api/shell", { cache: "no-store", signal: controller.signal });
        if (!active || controller.signal.aborted) return;
        if (response.status === 401) {
          document.documentElement.dataset.professionalRestoring = "true";
          window.location.replace("/?access=professional");
          return;
        }
        if (!response.ok) throw new Error("shell");
        const data = await response.json() as ShellData;
        if (!active || controller.signal.aborted) return;
        cache.current = { ...data, fetchedAt: Date.now() };
        setLive(data);
      } catch {
        // Keep the last valid counters during a transient failure.
      } finally {
        if (pending === controller) pending = null;
      }
    }
    function refreshShell() { void load(true); }
    function onFocus() { void load(); }
    function restoreSession(event: PageTransitionEvent) {
      if (!event.persisted) return;
      document.documentElement.dataset.professionalRestoring = "true";
      window.location.replace(window.location.href);
    }
    function markNotificationRead(event: Event) {
      const detail = (event as CustomEvent<{ count?: number; notificationId?: number }>).detail;
      const count = Math.max(1, Number(detail?.count) || 1);
      const readAt = new Date().toISOString();
      const update = (current: ShellData): ShellData => ({
        ...current,
        notifications: detail?.notificationId
          ? current.notifications.map((item) => item.id === detail.notificationId ? { ...item, read_at: item.read_at ?? readAt } : item)
          : current.notifications,
        unreadCount: Math.max(0, current.unreadCount - count),
      });
      setLive((current) => {
        const next = update(current);
        const cached = cache.current;
        if (cached) cache.current = { ...update(cached), fetchedAt: cached.fetchedAt };
        return next;
      });
    }
    void load();
    window.addEventListener("pageshow", restoreSession);
    window.addEventListener("focus", onFocus);
    window.addEventListener("hpsm:shell-refresh", refreshShell);
    window.addEventListener("hpsm:notifications-read", markNotificationRead);
    return () => {
      active = false;
      pending?.abort();
      window.removeEventListener("pageshow", restoreSession);
      window.removeEventListener("focus", onFocus);
      window.removeEventListener("hpsm:shell-refresh", refreshShell);
      window.removeEventListener("hpsm:notifications-read", markNotificationRead);
    };
  }, [portalRoute]);

  if (!portalRoute) return children;

  const active = activeSection(pathname);
  const heading = routeHeading(pathname, profile, positionDisplayName, dashboardGreeting);

  return <ShellDataContext.Provider value={live}><main className="app-shell" data-sidebar={sidebarCollapsed ? "collapsed" : "expanded"}>
    {!permissionCodes.includes("sr.directors.view") ? <ProfessionalIdentityInitializer /> : null}
    <AppSidebar
      active={active}
      onCollapsedChange={setSidebarCollapsed}
      pathname={pathname}
      pendingCount={live.pendingCount}
      permissionCodes={permissionCodes}
      positionDisplayName={positionDisplayName}
      profile={profile}
    />
    <section className="app-content">
      <header className="app-header">
        <div><p className="eyebrow">HPSM · Sistema profissional</p><h1>{heading.title}</h1><p>{heading.description}</p></div>
        <div className="app-header-actions">
          <GlobalSearchLauncher />
          {pathname !== "/painel" && live.weeklyProgress ? <HrWeekCompact progress={live.weeklyProgress} /> : null}
          <NotificationBell initialNotifications={live.notifications} initialUnreadCount={live.unreadCount} />
          <div className="header-secure"><span className="status-dot" /> Sessão protegida</div>
        </div>
      </header>
      {searchParams.get("sessionError") === "logout" ? <p role="alert" className="form-error">Não foi possível encerrar sua sessão. Aguarde um momento e tente sair novamente.</p> : null}
      {searchParams.get("identity") === "pending" && !permissionCodes.includes("sr.directors.view") ? <p role="status" className="identity-pending-notice">Sua senha foi criada. A identidade profissional permanece pendente e será reprocessada automaticamente com segurança.</p> : null}
      {children}
    </section>
  </main></ShellDataContext.Provider>;
}

function isPortalRoute(pathname: string) {
  return ["/painel", "/academia", "/pacientes", "/consultas", "/atendimentos", "/hpsm-assist", "/exames", "/gessos", "/internacoes", "/atestados", "/catalogo", "/meu-rh", "/administrativo", "/rh", "/auditoria", "/notificacoes"].some((route) => pathname === route || pathname.startsWith(`${route}/`));
}

function activeSection(pathname: string) {
  if (pathname.startsWith("/academia/gestao")) return "academy_management";
  if (pathname.startsWith("/academia")) return "academy";
  if (pathname.startsWith("/pacientes")) return "patients";
  if (pathname.startsWith("/hpsm-assist")) return "assist";
  if (pathname.startsWith("/consultas")) return "consultations";
  if (pathname.startsWith("/atendimentos")) return "attendances";
  if (pathname.startsWith("/exames")) return "exams";
  if (pathname.startsWith("/gessos")) return "casts";
  if (pathname.startsWith("/internacoes")) return "hospitalizations";
  if (pathname.startsWith("/atestados")) return "certificates";
  if (pathname.startsWith("/catalogo")) return "catalog";
  if (pathname.startsWith("/meu-rh")) return "my-hr";
  if (pathname.startsWith("/administrativo") || pathname.startsWith("/rh")) return "hr";
  if (pathname.startsWith("/auditoria")) return "audit";
  if (pathname.startsWith("/notificacoes")) return "communications";
  return "dashboard";
}

function routeHeading(pathname: string, profile: SessionProfile, positionDisplayName: string | null, dashboardGreeting: string) {
  if (pathname.startsWith("/academia/gestao")) return { title: "Gestão da Academia", description: "Organize cursos, avaliações e resultados da equipe." };
  if (pathname.startsWith("/academia")) return { title: "Academia HPSM", description: "Acompanhe seus cursos, aulas e avaliações." };
  if (pathname.startsWith("/pacientes/")) return { title: "Perfil do paciente", description: "Consulte o histórico e as informações vinculadas a este paciente." };
  if (pathname.startsWith("/pacientes")) return { title: "Pacientes", description: "Consulte cadastros, atendimentos, compras, procedimentos e o histórico do Plano de Saúde." };
  if (pathname.startsWith("/hpsm-assist")) return { title: "HPSM Assist", description: "Descreva o caso e receba sugestões rápidas de avaliação, exames, medicamentos e conduta." };
  if (pathname.startsWith("/consultas/")) return { title: "Consulta clínica", description: "Registre a evolução do paciente em uma página clínica contínua e segura." };
  if (pathname.startsWith("/consultas")) return { title: "Consultas e Agendamentos", description: "Organize a agenda e consulte o histórico clínico sem vínculo com vendas." };
  if (pathname.startsWith("/atendimentos/registro/")) return { title: "Registro de atendimento", description: "Consulte os itens, o profissional e os valores do atendimento." };
  if (pathname.startsWith("/atendimentos")) return { title: "Vendas", description: "Selecione o paciente, adicione produtos e procedimentos e conclua o atendimento." };
  if (pathname.startsWith("/exames")) return { title: "Central de Exames", description: "Solicite, execute, revise e consulte exames clínicos com rastreabilidade completa." };
  if (pathname.startsWith("/gessos")) return { title: "Controle de Gesso", description: "Registre aplicações, acompanhe previsões e documente retiradas com segurança clínica." };
  if (pathname.startsWith("/internacoes")) return { title: "Internações e Leitos", description: "Acompanhe os dez leitos compartilhados pelo HPSM e HP Norte, com histórico completo." };
  if (pathname.startsWith("/atestados")) return { title: "Atestados Médicos", description: "Crie, revise, finalize e consulte atestados vinculados a atendimentos ou consultas clínicas." };
  if (pathname.startsWith("/catalogo")) return { title: "Tabela de Preços", description: "Administre o catálogo, os preços, os descontos e as imagens dos itens." };
  if (pathname.startsWith("/meu-rh")) return { title: "Meu RH", description: "Acompanhe sua meta semanal, solicitações, justificativas e histórico funcional." };
  if (pathname.startsWith("/administrativo/pendencias")) return { title: "Pendências", description: "Analise decisões administrativas consolidadas sem duplicar os registros de origem." };
  if (pathname.startsWith("/administrativo/rh")) return { title: "RH e Jornada", description: "Administre horas, afastamentos, justificativas, disciplina e advertências." };
  if (pathname.startsWith("/administrativo/carreira")) return { title: "Carreira e Formação", description: "Acompanhe progressões, nomeações e cursos." };
  if (pathname.startsWith("/administrativo/recrutamento")) return { title: "Recrutamento", description: "Analise candidaturas e consulte o histórico das decisões." };
  if (pathname.startsWith("/administrativo/parcerias")) return { title: "Parcerias e Convênios", description: "Gerencie organizações, responsáveis, beneficiários e vínculos com rastreabilidade." };
  if (pathname.startsWith("/administrativo/equipe")) return { title: "Equipe e Acessos", description: "Gerencie contas, cargos e permissões conforme sua autorização." };
  if (pathname.startsWith("/administrativo/perfis")) return { title: "Perfis Funcionais", description: "Consulte a trajetória administrativa completa dos colaboradores." };
  if (pathname.startsWith("/administrativo/relatorios")) return { title: "Relatórios", description: "Analise jornada, equipe e produção do período." };
  if (pathname.startsWith("/administrativo/registros")) return { title: "Registros de atendimento", description: "Consulte atendimentos, vendas e seus valores." };
  if (pathname.startsWith("/administrativo") || pathname.startsWith("/rh")) return { title: "Administrativo", description: "Centralize a gestão interna do Hospital Santa Marcelina." };
  if (pathname.startsWith("/auditoria")) return { title: "Auditoria", description: "Consulte as operações sensíveis registradas pelo sistema." };
  if (pathname.startsWith("/notificacoes")) return { title: "Comunicados", description: "Consulte os comunicados institucionais e acompanhe novas orientações." };
  const firstName = profile.display_name.trim().split(/\s+/)[0] || "profissional";
  return {
    title: `${dashboardGreeting}, ${firstName}.`,
    description: `${positionDisplayName ? `${positionDisplayName} · ` : ""}Veja como está sua semana no Hospital Santa Marcelina.`,
  };
}
