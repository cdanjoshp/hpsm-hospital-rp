import { redirect } from "next/navigation";
import { hasPermission } from "../lib/access";
import { getSessionContext } from "../lib/session";

export const dynamic = "force-dynamic";

export default async function ApplicationsPage({ searchParams }: { searchParams: Promise<{ selecionar?: string }> }) {
  const context = await getSessionContext();
  if (!context) redirect("/");
  if (context.profile.must_change_password) redirect("/primeiro-acesso");
  if (!await hasPermission(context.profile, "recruitment.manage")) redirect("/painel");

  const query = await searchParams;
  const selected = query.selecionar ? `?selecionar=${encodeURIComponent(query.selecionar)}` : "";
  redirect(`/administrativo/recrutamento${selected}`);
}
