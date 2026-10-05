import type { Metadata } from "next";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { RecruitmentPage } from "../components/recruitment-page";
import { RECRUITMENT_NOTICE_KEY } from "../lib/recruitment";

export const metadata: Metadata = {
  title: "Recrutamento | HPSM",
  description: "Processo seletivo do Hospital Santa Marcelina.",
};

export default async function RecruitmentRoute() {
  const cookieStore = await cookies();
  if (cookieStore.get(RECRUITMENT_NOTICE_KEY)?.value !== "true") redirect("/");
  return <RecruitmentPage />;
}
