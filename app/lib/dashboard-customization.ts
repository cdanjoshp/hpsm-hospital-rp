import { visibleAdministrativeAreas } from "./administrative";
import { buildSidebarNavigation, type SidebarIconName } from "./sidebar-navigation";

export const DASHBOARD_CONFIG_VERSION = 1 as const;
export const DASHBOARD_BREAKPOINTS = ["lg", "md", "sm"] as const;
export const DASHBOARD_WIDGET_IDS = [
  "my_week",
  "my_production",
  "career",
  "attention",
  "communications",
  "shortcuts",
  "hospital_overview",
] as const;

export type DashboardBreakpoint = typeof DASHBOARD_BREAKPOINTS[number];
export type DashboardWidgetId = typeof DASHBOARD_WIDGET_IDS[number];
export type DashboardModularWidgetId = Exclude<DashboardWidgetId, "shortcuts">;

export const DASHBOARD_MODULAR_WIDGET_IDS = DASHBOARD_WIDGET_IDS.filter(
  (id): id is DashboardModularWidgetId => id !== "shortcuts",
);

export type DashboardLayoutItem = {
  h: number;
  i: DashboardWidgetId;
  w: number;
  x: number;
  y: number;
};

export type DashboardLayouts = Record<DashboardBreakpoint, DashboardLayoutItem[]>;

export type DashboardPreference = {
  configVersion: typeof DASHBOARD_CONFIG_VERSION;
  hiddenWidgets: DashboardWidgetId[];
  layouts: DashboardLayouts;
  shortcuts: string[];
};

export type DashboardShortcut = {
  description: string;
  href: string;
  icon: SidebarIconName;
  id: string;
  label: string;
};

export type DashboardPreferenceValidation =
  | { valid: true }
  | { error: string; valid: false };

export const DASHBOARD_GRID = {
  breakpoints: { lg: 1100, md: 760, sm: 0 },
  cols: { lg: 12, md: 8, sm: 1 },
  margin: { lg: [16, 16], md: [14, 14], sm: [12, 12] } as const,
  rowHeight: 32,
} as const;

export const DEFAULT_DASHBOARD_LAYOUTS: DashboardLayouts = {
  lg: [
    item("my_week", 0, 0, 4, 10),
    item("my_production", 4, 0, 4, 10),
    item("career", 8, 0, 4, 10),
    item("attention", 0, 10, 12, 6),
    item("communications", 0, 16, 8, 9),
    item("shortcuts", 8, 16, 4, 9),
    item("hospital_overview", 0, 25, 12, 9),
  ],
  md: [
    item("my_week", 0, 0, 4, 9),
    item("attention", 4, 0, 4, 9),
    item("my_production", 0, 9, 4, 10),
    item("career", 4, 9, 4, 10),
    item("communications", 0, 19, 8, 9),
    item("shortcuts", 0, 28, 8, 9),
    item("hospital_overview", 0, 37, 8, 10),
  ],
  sm: [
    item("my_week", 0, 0, 1, 10),
    item("attention", 0, 10, 1, 11),
    item("my_production", 0, 21, 1, 11),
    item("career", 0, 32, 1, 14),
    item("communications", 0, 46, 1, 14),
    item("shortcuts", 0, 60, 1, 16),
    item("hospital_overview", 0, 76, 1, 27),
  ],
};

const ALL_SHORTCUT_IDS = [
  "overview",
  "new_attendance",
  "attendances",
  "patients",
  "consultations",
  "assist",
  "catalog",
  "exams",
  "casts",
  "hospitalizations",
  "certificates",
  "academy",
  "academy_management",
  "my_hr",
  "administrative",
  "pending",
  "rh",
  "career",
  "recruitment",
  "partnerships",
  "team",
  "profiles",
  "reports",
  "records",
  "audit",
  "communications",
] as const;

export const DASHBOARD_SHORTCUT_IDS: readonly string[] = ALL_SHORTCUT_IDS;

const SHORTCUT_DESCRIPTIONS: Record<(typeof ALL_SHORTCUT_IDS)[number], string> = {
  administrative: "Visão administrativa",
  attendances: "Vendas",
  audit: "Histórico de ações",
  career: "Carreira e formação",
  casts: "Aplicações e retiradas",
  certificates: "Atestados e documentos",
  academy: "Cursos e avaliações",
  academy_management: "Gestão de cursos e notas",
  catalog: "Serviços e valores",
  communications: "Mural da diretoria",
  consultations: "Agenda e evolução clínica",
  assist: "Sugestões rápidas para casos RP",
  exams: "Laudos e resultados",
  hospitalizations: "Leitos e acompanhamento",
  my_hr: "Jornada e carreira",
  new_attendance: "Registrar produtos e procedimentos",
  overview: "Resumo do painel",
  patients: "Central de pacientes",
  pending: "Itens para decisão",
  partnerships: "Organizações e beneficiários",
  profiles: "Perfis funcionais",
  recruitment: "Candidaturas",
  records: "Atendimentos e vendas registrados",
  reports: "Indicadores e análises",
  rh: "Gestão de jornada",
  team: "Equipe e acessos",
};

export function defaultDashboardPreference(permissionCodes: readonly string[]): DashboardPreference {
  return {
    configVersion: DASHBOARD_CONFIG_VERSION,
    hiddenWidgets: [],
    layouts: cloneLayouts(DEFAULT_DASHBOARD_LAYOUTS),
    shortcuts: defaultShortcutIds(permissionCodes),
  };
}

export function dashboardShortcutCatalog(permissionCodes: readonly string[]): DashboardShortcut[] {
  const administrativeChildren = visibleAdministrativeAreas(permissionCodes).map((area) => ({
    href: area.href,
    icon: area.id as SidebarIconName,
    id: area.id,
    label: area.label,
  }));
  const sections = buildSidebarNavigation(permissionCodes, 0, administrativeChildren);
  const sidebarItems = sections.flatMap((section) => section.items.flatMap((entry) => entry.children?.length
    ? [
      ...(entry.href ? [{ href: entry.href, icon: entry.icon, id: entry.id === "hr" ? "administrative" : entry.id, label: entry.overviewLabel ?? entry.label }] : []),
      ...entry.children,
    ]
    : entry.href ? [{ href: entry.href, icon: entry.icon, id: entry.id, label: entry.label }] : []));
  const byId = new Map(sidebarItems.map((entry) => [normalizeShortcutId(entry.id), entry]));
  const attendance = byId.get("attendances");
  const result: DashboardShortcut[] = [];

  for (const id of ALL_SHORTCUT_IDS) {
    // The old duplicate remains valid in stored preferences but is no longer offered.
    if (id === "attendances" || id === "overview") continue;
    if (id === "new_attendance") {
      if (attendance) result.push({ description: SHORTCUT_DESCRIPTIONS[id], href: attendance.href, icon: "attendances", id, label: "Nova Venda" });
      continue;
    }
    const entry = byId.get(id);
    if (entry) result.push({ ...entry, description: SHORTCUT_DESCRIPTIONS[id], id });
  }
  return result;
}

export function visibleDashboardShortcuts(selectedIds: readonly string[], permissionCodes: readonly string[]) {
  const catalog = dashboardShortcutCatalog(permissionCodes);
  const byId = new Map(catalog.map((entry) => [entry.id, entry]));
  const orderedIds = [...selectedIds.map((id) => id === "attendances" ? "new_attendance" : id), ...catalog.map((entry) => entry.id)];
  return [...new Set(orderedIds)].map((id) => byId.get(id)).filter((entry): entry is DashboardShortcut => Boolean(entry));
}

export function normalizeDashboardPreference(value: unknown, permissionCodes: readonly string[]): DashboardPreference {
  if (!validateDashboardPreference(value, dashboardInactiveWidgetIds(permissionCodes)).valid) return defaultDashboardPreference(permissionCodes);
  const preference = value as DashboardPreference;
  return {
    configVersion: DASHBOARD_CONFIG_VERSION,
    hiddenWidgets: preference.hiddenWidgets.filter((id) => id !== "shortcuts"),
    layouts: cloneLayouts(preference.layouts),
    shortcuts: [...preference.shortcuts],
  };
}

export function isDashboardPreference(value: unknown): value is DashboardPreference {
  return validateDashboardPreference(value).valid;
}

export function validateDashboardPreference(value: unknown, inactiveWidgets: readonly DashboardWidgetId[] = []): DashboardPreferenceValidation {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return invalid("A configuração recebida está vazia ou corrompida. Recarregue a Dashboard e tente novamente.");
  }
  const candidate = value as Record<string, unknown>;
  const allowedKeys = ["configVersion", "layouts", "hiddenWidgets", "shortcuts"];
  const receivedKeys = Object.keys(candidate);
  if (receivedKeys.length !== allowedKeys.length || receivedKeys.some((key) => !allowedKeys.includes(key))) {
    return invalid("A configuração contém informações que esta versão da Dashboard não reconhece. Recarregue a página antes de salvar.");
  }
  if (candidate.configVersion !== DASHBOARD_CONFIG_VERSION) {
    return invalid("A configuração foi criada por outra versão da Dashboard. Recarregue a página antes de fazer alterações.");
  }

  const hiddenValidation = validateSelection(candidate.hiddenWidgets, DASHBOARD_WIDGET_IDS, "quadros ocultos");
  if (!hiddenValidation.valid) return hiddenValidation;
  const shortcutValidation = validateSelection(candidate.shortcuts, ALL_SHORTCUT_IDS, "atalhos");
  if (!shortcutValidation.valid) return shortcutValidation;

  if (!candidate.layouts || typeof candidate.layouts !== "object" || Array.isArray(candidate.layouts)) {
    return invalid("A organização dos quadros não pôde ser lida. Use “Restaurar padrão” e tente novamente.");
  }
  const layouts = candidate.layouts as Record<string, unknown>;
  const layoutKeys = Object.keys(layouts);
  if (layoutKeys.length !== DASHBOARD_BREAKPOINTS.length || layoutKeys.some((key) => !DASHBOARD_BREAKPOINTS.includes(key as DashboardBreakpoint))) {
    return invalid("A organização precisa conter as versões para computador, tablet e celular. Use “Restaurar padrão” e tente novamente.");
  }
  const hiddenWidgets = new Set([...(candidate.hiddenWidgets as DashboardWidgetId[]), ...inactiveWidgets]);
  for (const breakpoint of DASHBOARD_BREAKPOINTS) {
    const layoutValidation = validateLayout(layouts[breakpoint], DASHBOARD_GRID.cols[breakpoint], breakpoint, hiddenWidgets);
    if (!layoutValidation.valid) return layoutValidation;
  }
  return { valid: true };
}

export function dashboardInactiveWidgetIds(permissionCodes: readonly string[]): DashboardWidgetId[] {
  return permissionCodes.includes("hr.reports.view") ? [] : ["hospital_overview"];
}

export function cloneLayouts(layouts: DashboardLayouts): DashboardLayouts {
  return Object.fromEntries(DASHBOARD_BREAKPOINTS.map((breakpoint) => [
    breakpoint,
    layouts[breakpoint].map((layoutItem) => ({ ...layoutItem })),
  ])) as DashboardLayouts;
}

function defaultShortcutIds(permissionCodes: readonly string[]) {
  return dashboardShortcutCatalog(permissionCodes).map((entry) => entry.id);
}

function validateLayout(value: unknown, cols: number, breakpoint: DashboardBreakpoint, hiddenWidgets: ReadonlySet<DashboardWidgetId>): DashboardPreferenceValidation {
  const viewport = DASHBOARD_BREAKPOINT_LABELS[breakpoint];
  if (!Array.isArray(value) || value.length !== DASHBOARD_WIDGET_IDS.length) {
    return invalid(`O layout para ${viewport} está incompleto. Use “Restaurar padrão” e tente novamente.`);
  }
  const ids = value.map((entry) => entry && typeof entry === "object" ? (entry as { i?: unknown }).i : null);
  const unknownIndex = ids.findIndex((id) => typeof id !== "string" || !DASHBOARD_WIDGET_IDS.includes(id as DashboardWidgetId));
  if (unknownIndex >= 0) {
    return invalid(`O layout para ${viewport} contém um quadro que não existe mais. Use “Restaurar padrão” e tente novamente.`);
  }
  const duplicateId = ids.find((id, index) => ids.indexOf(id) !== index) as DashboardWidgetId | undefined;
  if (duplicateId) {
    return invalid(`O quadro “${DASHBOARD_WIDGET_LABELS[duplicateId]}” aparece mais de uma vez no layout para ${viewport}. Use “Restaurar padrão” e tente novamente.`);
  }

  const entries = value as Array<Record<string, unknown>>;
  for (const entry of entries) {
    const id = entry.i as DashboardWidgetId;
    const keys = Object.keys(entry);
    if (keys.length !== 5 || keys.some((key) => !["i", "x", "y", "w", "h"].includes(key))
      || !Number.isInteger(entry.x) || !Number.isInteger(entry.y) || !Number.isInteger(entry.w) || !Number.isInteger(entry.h)) {
      return invalid(`Os dados do quadro “${DASHBOARD_WIDGET_LABELS[id]}” estão incompletos no layout para ${viewport}. Use “Restaurar padrão” e tente novamente.`);
    }
    const x = Number(entry.x); const y = Number(entry.y); const w = Number(entry.w); const h = Number(entry.h);
    if (w < 1 || w > cols || h < 4 || h > 40) {
      return invalid(`O tamanho do quadro “${DASHBOARD_WIDGET_LABELS[id]}” não é permitido no layout para ${viewport}. Redimensione o quadro ou restaure o padrão.`);
    }
    if (x < 0 || x >= cols || y < 0 || y > 240 || x + w > cols) {
      return invalid(`O quadro “${DASHBOARD_WIDGET_LABELS[id]}” ficou fora da área do layout para ${viewport}. Mova-o para dentro da Dashboard ou restaure o padrão.`);
    }
  }

  const visibleEntries = entries.filter((entry) => entry.i !== "shortcuts" && !hiddenWidgets.has(entry.i as DashboardWidgetId)) as unknown as DashboardLayoutItem[];
  for (let index = 0; index < visibleEntries.length; index += 1) {
    const left = visibleEntries[index];
    const right = visibleEntries.slice(index + 1).find((entry) => overlaps(left, entry));
    if (right) {
      return invalid(`Os quadros “${DASHBOARD_WIDGET_LABELS[left.i]}” e “${DASHBOARD_WIDGET_LABELS[right.i]}” estão sobrepostos no layout para ${viewport}. Separe os quadros ou restaure o padrão.`);
    }
  }
  return { valid: true };
}

function validateSelection(value: unknown, allowed: readonly string[], label: "atalhos" | "quadros ocultos"): DashboardPreferenceValidation {
  if (!Array.isArray(value)) return invalid(`A lista de ${label} não pôde ser lida. Recarregue a Dashboard e tente novamente.`);
  if (value.length > allowed.length) return invalid(`A lista de ${label} possui mais itens do que o permitido. Revise a seleção e tente novamente.`);
  if (value.some((entry) => typeof entry !== "string" || !allowed.includes(entry))) {
    return invalid(`A lista de ${label} contém uma opção que não existe mais. Reabra a personalização e salve novamente.`);
  }
  if (new Set(value).size !== value.length) {
    return invalid(`A lista de ${label} contém itens repetidos. Remova a repetição e tente novamente.`);
  }
  return { valid: true };
}

function overlaps(left: DashboardLayoutItem, right: DashboardLayoutItem) {
  return left.x < right.x + right.w && left.x + left.w > right.x && left.y < right.y + right.h && left.y + left.h > right.y;
}

const DASHBOARD_BREAKPOINT_LABELS: Record<DashboardBreakpoint, string> = {
  lg: "computador",
  md: "tablet",
  sm: "celular",
};

const DASHBOARD_WIDGET_LABELS: Record<DashboardWidgetId, string> = {
  attention: "Atenção",
  career: "Carreira",
  communications: "Comunicados",
  hospital_overview: "Visão do Hospital",
  my_production: "Minha produção",
  my_week: "Minha semana",
  shortcuts: "Acesso Direto",
};

function invalid(error: string): DashboardPreferenceValidation {
  return { error, valid: false };
}

function normalizeShortcutId(id: string) {
  return id === "my-hr" ? "my_hr" : id;
}

function item(i: DashboardWidgetId, x: number, y: number, w: number, h: number): DashboardLayoutItem {
  return { h, i, w, x, y };
}
