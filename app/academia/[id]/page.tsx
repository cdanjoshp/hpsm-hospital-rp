import { redirect, notFound } from "next/navigation";
import { AppFrame } from "../../components/app-frame";
import { AcademyCourseView } from "../../components/academy-course";
import { readAcademy, type AcademyCourseDetail } from "../../lib/academy";
import { getSessionBootstrap } from "../../lib/session";
import { SupabaseUserRpcError } from "../../lib/supabase-user";
import "../academy.css";

export const dynamic = "force-dynamic";
export default async function AcademyCoursePage({ params }: { params: Promise<{ id: string }> }) {
  const context = await getSessionBootstrap();
  if (!context) redirect("/");
  if (context.profile.must_change_password) redirect("/primeiro-acesso");
  if (!context.permissionCodes.includes("courses.study")) redirect("/painel");
  const id = Number((await params).id);
  if (!Number.isSafeInteger(id) || id < 1) notFound();
  let data: AcademyCourseDetail;
  try { data = await readAcademy<AcademyCourseDetail>(context.accessToken,"course",id); }
  catch (error) {
    if (error instanceof SupabaseUserRpcError && error.rpcMessage?.includes("não encontrado")) notFound();
    throw error;
  }
  return <AppFrame active="my-hr" profile={context.profile} title={data.course.name} description="Academia HPSM">
    <AcademyCourseView initial={data} canTakeExam={context.permissionCodes.includes("courses.takeexam")} />
  </AppFrame>;
}
