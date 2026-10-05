export type PlanCode = "plano_saude" | "parceiros_hp" | "policiais_arcanjos";

export const BENEFIT_PLANS: { code: PlanCode; name: string }[] = [
  { code: "plano_saude", name: "Plano de Saúde" },
  { code: "parceiros_hp", name: "Parceiros do HP" },
  { code: "policiais_arcanjos", name: "Policiais/Arcanjos" },
];
