import { redirect } from "next/navigation";
import { hasAnyPermission } from "../lib/access";
import { getSessionProfile } from "../lib/session";

export const dynamic = "force-dynamic";

export default async function PendingPage() {
  const profile = await getSessionProfile();
  if (!profile) redirect("/");
  if (profile.must_change_password) redirect("/primeiro-acesso");
  if (!await hasAnyPermission(profile, [
    "admin.pending.manage",
    "healthplans.review",
    "hr.absences.review",
    "hr.discipline.manage",
    "hr.discipline.review",
    "hr.justifications.review",
    "progression.review",
    "recruitment.manage",
  ])) redirect("/painel");

  redirect("/administrativo/pendencias");
}
