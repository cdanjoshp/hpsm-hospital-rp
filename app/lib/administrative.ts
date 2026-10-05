import type { PendingCenterData } from "./pending";

export type AdministrativeAreaId = "pending" | "rh" | "career" | "recruitment" | "partnerships" | "team" | "profiles" | "reports" | "records";

export type AdministrativeArea = {
  description: string;
  href: string;
  icon: string;
  id: AdministrativeAreaId;
  label: string;
  observerPermissionCodes?: readonly string[];
  permissionCodes: readonly string[];
};

export const ADMINISTRATIVE_AREAS: readonly AdministrativeArea[] = [
  {
    description: "Decisões que aguardam análise",
    href: "/administrativo/pendencias",
    icon: "!",
    id: "pending",
    label: "Pendências",
    observerPermissionCodes: ["sr.directors.view"],
    permissionCodes: ["admin.pending.manage", "casts.manage", "healthplans.review", "hr.absences.review", "hr.discipline.manage", "hr.discipline.review", "hr.justifications.review", "progression.review", "recruitment.manage"],
  },
  {
    description: "Horas, afastamentos e disciplina",
    href: "/administrativo/rh",
    icon: "◷",
    id: "rh",
    label: "RH e Jornada",
    observerPermissionCodes: ["sr.directors.view"],
    permissionCodes: ["hr.team.view", "hr.hours.manage", "hr.hours.import", "hr.weeks.close", "hr.weeks.reopen", "hr.absences.review", "hr.justifications.review", "hr.discipline.manage", "hr.discipline.review", "hr.warnings.issue", "hr.warnings.annul", "hr.warnings.progression"],
  },
  {
    description: "Progressão, nomeações e cursos",
    href: "/administrativo/carreira",
    icon: "↗",
    id: "career",
    label: "Carreira e Formação",
    observerPermissionCodes: ["sr.directors.view"],
    permissionCodes: ["progression.review", "appointments.manage", "succession.manage", "courses.manage", "courses.completions.manage"],
  },
  {
    description: "Candidaturas e histórico de decisões",
    href: "/administrativo/recrutamento",
    icon: "+",
    id: "recruitment",
    label: "Recrutamento",
    observerPermissionCodes: ["sr.directors.view"],
    permissionCodes: ["recruitment.manage"],
  },
  {
    description: "Organizações, responsáveis e beneficiários",
    href: "/administrativo/parcerias",
    icon: "⌁",
    id: "partnerships",
    label: "Parcerias",
    observerPermissionCodes: ["sr.directors.view"],
    permissionCodes: ["partnerships.view", "partnerships.manage"],
  },
  {
    description: "Equipe, cargos e permissões",
    href: "/administrativo/equipe",
    icon: "♙",
    id: "team",
    label: "Equipe e Acessos",
    observerPermissionCodes: ["sr.directors.view"],
    permissionCodes: ["team.manage", "access.manage"],
  },
  {
    description: "Histórico completo dos colaboradores",
    href: "/administrativo/perfis",
    icon: "◇",
    id: "profiles",
    label: "Perfis Funcionais",
    observerPermissionCodes: ["sr.directors.view"],
    permissionCodes: ["hr.team.view", "hr.reports.view", "team.manage", "access.manage"],
  },
  {
    description: "Jornada, produção e visão individual",
    href: "/administrativo/relatorios",
    icon: "▤",
    id: "reports",
    label: "Relatórios",
    observerPermissionCodes: ["sr.directors.view"],
    permissionCodes: ["hr.reports.view"],
  },
  {
    description: "Atendimentos, vendas e cancelamentos",
    href: "/administrativo/registros",
    icon: "▧",
    id: "records",
    label: "Registros de atendimento",
    permissionCodes: ["attendances.manage"],
  },
] as const;

export const EMPTY_PENDING_CENTER_DATA: PendingCenterData = {
  absences: [],
  career: [],
  casts: [],
  counts: { absences: 0, casts: 0, discipline: 0, healthPlans: 0, justifications: 0, promotions: 0, recruitment: 0 },
  discipline: [],
  healthPlans: [],
  recruitment: [],
  total: 0,
};

export function administrativeArea(areaId: AdministrativeAreaId) {
  return ADMINISTRATIVE_AREAS.find((area) => area.id === areaId)!;
}

export function canAccessAdministrativeArea(permissionCodes: readonly string[], areaId: AdministrativeAreaId) {
  const area = administrativeArea(areaId);
  return [...area.permissionCodes, ...(area.observerPermissionCodes ?? [])].some((code) => permissionCodes.includes(code));
}

export function visibleAdministrativeAreas(permissionCodes: readonly string[]) {
  return ADMINISTRATIVE_AREAS.filter((area) => [...area.permissionCodes, ...(area.observerPermissionCodes ?? [])].some((code) => permissionCodes.includes(code)));
}
