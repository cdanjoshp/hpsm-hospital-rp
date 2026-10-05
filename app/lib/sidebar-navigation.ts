export type SidebarIconName =
  | "academy"
  | "academy-management"
  | "administrative"
  | "assist"
  | "attendances"
  | "audit"
  | "career"
  | "casts"
  | "certificates"
  | "catalog"
  | "communications"
  | "consultations"
  | "dashboard"
  | "exams"
  | "hospitalizations"
  | "my-hr"
  | "patients"
  | "partnerships"
  | "pending"
  | "profiles"
  | "recruitment"
  | "records"
  | "reports"
  | "rh"
  | "team";

export type SidebarNavigationChild = {
  href: string;
  icon: SidebarIconName;
  id: string;
  label: string;
};

export type SidebarNavigationItem = {
  children?: SidebarNavigationChild[];
  count?: number;
  href?: string;
  icon: SidebarIconName;
  id: string;
  label: string;
  overviewLabel?: string;
};

export type SidebarNavigationSection = {
  id: "overview" | "assistance" | "management";
  items: SidebarNavigationItem[];
  label: string;
};

export function buildSidebarNavigation(permissionCodes: readonly string[], pendingCount: number, administrativeChildren: SidebarNavigationChild[]): SidebarNavigationSection[] {
  const permissions = new Set(permissionCodes);
  const has = (...codes: string[]) => codes.some((code) => permissions.has(code));

  return compactSections([
    {
      id: "overview",
      items: compactNavigation([
        { href: "/painel", icon: "dashboard", id: "dashboard", label: "Página Inicial" },
        has("hr.self.view") && { href: "/meu-rh", icon: "my-hr", id: "my-hr", label: "Meu RH" },
        has("courses.study") && { href: "/academia", icon: "academy", id: "academy", label: "Academia HPSM" },
      ]),
      label: "Visão geral",
    },
    {
      id: "assistance",
      items: compactNavigation([
        has("patients.view") && { href: "/pacientes", icon: "patients", id: "patients", label: "Pacientes" },
        has("attendances.create", "attendances.manage", "sr.directors.view") && { href: "/atendimentos", icon: "attendances", id: "attendances", label: "Vendas" },
        has("hpsm.assist.use") && { href: "/hpsm-assist", icon: "assist", id: "assist", label: "HPSM Assist" },
        has("exams.view") && { href: "/exames", icon: "exams", id: "exams", label: "Central de Exames" },
        has("casts.view") && { href: "/gessos", icon: "casts", id: "casts", label: "Controle de Gesso" },
        has("atestados.view") && { href: "/atestados", icon: "certificates", id: "certificates", label: "Atestados Médicos" },
        has("hospitalizations.view") && { href: "/internacoes", icon: "hospitalizations", id: "hospitalizations", label: "Internação e Leitos" },
        has("consultations.view") && { href: "/consultas", icon: "consultations", id: "consultations", label: "Consultas e Agendamentos" },
      ]),
      label: "Assistência",
    },
    {
      id: "management",
      items: compactNavigation([
        administrativeChildren.length > 0 && {
          children: administrativeChildren,
          count: pendingCount,
          href: "/administrativo",
          icon: "administrative",
          id: "hr",
          label: "Administrativo",
          overviewLabel: "Visão geral administrativa",
        },
        has("courses.academy.manage") && { href: "/academia/gestao", icon: "academy-management", id: "academy_management", label: "Gestão da Academia" },
        has("catalog.view", "catalog.manage") && { href: "/catalogo", icon: "catalog", id: "catalog", label: "Tabela de Preços" },
        has("audit.view") && { href: "/auditoria", icon: "audit", id: "audit", label: "Auditoria" },
        { href: "/notificacoes", icon: "communications", id: "communications", label: "Comunicados" },
      ]),
      label: "Gestão",
    },
  ]);
}

export function isSidebarNavigationItemActive(item: SidebarNavigationItem, active: string, pathname: string) {
  if (!item.children?.length) return item.id === active || Boolean(item.href && isPathActive(pathname, item.href));
  return Boolean(item.href && pathname === item.href) || item.children.some((child) => isPathActive(pathname, child.href));
}

function compactNavigation(items: Array<SidebarNavigationItem | false>): SidebarNavigationItem[] {
  return items.filter((item): item is SidebarNavigationItem => Boolean(item));
}

function compactSections(sections: SidebarNavigationSection[]): SidebarNavigationSection[] {
  return sections.filter((section) => section.items.length > 0);
}

function isPathActive(pathname: string, href: string) {
  if (href === "/academia" && (pathname === "/academia/gestao" || pathname.startsWith("/academia/gestao/"))) return false;
  return pathname === href || pathname.startsWith(`${href}/`);
}
