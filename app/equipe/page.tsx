import { redirect } from "next/navigation";
import { hasAnyPermission } from "../lib/access";
import { getSessionProfile } from "../lib/session";

export const dynamic = "force-dynamic";

export default async function TeamPage() {
  const profile = await getSessionProfile();
  if (!profile) redirect("/");
  if (profile.must_change_password) redirect("/primeiro-acesso");
  if (!await hasAnyPermission(profile, ["team.manage", "access.manage"])) redirect("/painel");

  redirect("/administrativo/equipe");
}
