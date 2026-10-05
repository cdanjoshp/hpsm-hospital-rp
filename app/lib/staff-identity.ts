export function staffIdentity(passport: string, positionName: string | null | undefined) {
  return `${passport} · ${positionName?.trim() || "Cargo não definido"}`;
}

export function roleLabel(role: string): string {
  const labels: Record<string, string> = {
    diretor_geral: "Diretor Geral",
    diretoria: "Diretoria",
    funcionario: "Funcionário",
  };
  return labels[role] ?? role.replaceAll("_", " ");
}
