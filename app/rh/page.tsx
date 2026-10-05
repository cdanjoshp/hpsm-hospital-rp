import { redirect } from "next/navigation";

export const dynamic = "force-dynamic";

export default async function HrPage({ searchParams }: { searchParams: Promise<{ aba?: string; selecionar?: string }> }) {
  const query = await searchParams;
  const selected = query.selecionar ? `?selecionar=${encodeURIComponent(query.selecionar)}` : "";
  if (query.aba === "pendencias" || query.aba === "pending") redirect("/administrativo/pendencias");
  if (query.aba === "candidaturas" || query.aba === "applications") redirect(`/administrativo/recrutamento${selected}`);
  if (query.aba === "equipe" || query.aba === "team") redirect("/administrativo/equipe");
  if (query.aba === "perfis" || query.aba === "profiles") redirect("/administrativo/perfis");
  if (query.aba === "career") redirect("/administrativo/carreira");
  if (query.aba === "reports") redirect("/administrativo/relatorios");
  if (query.aba === "hours" || query.aba === "absences" || query.aba === "discipline") redirect(`/administrativo/rh?aba=${query.aba}`);
  redirect("/administrativo");
}
