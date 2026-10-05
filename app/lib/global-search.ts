export type GlobalSearchCategory =
  | "applications"
  | "attendances"
  | "catalog"
  | "patients"
  | "professionals";

export type GlobalSearchItem = {
  amount: number | null;
  category: GlobalSearchCategory;
  href: string;
  id: string;
  subtitle: string;
  title: string;
};

export type GlobalSearchResponse = {
  items: GlobalSearchItem[];
};

export const GLOBAL_SEARCH_GROUPS: Array<{ category: GlobalSearchCategory; label: string }> = [
  { category: "patients", label: "Pacientes" },
  { category: "professionals", label: "Profissionais" },
  { category: "attendances", label: "Atendimentos" },
  { category: "catalog", label: "Tabela de Preços" },
  { category: "applications", label: "Candidaturas" },
];
