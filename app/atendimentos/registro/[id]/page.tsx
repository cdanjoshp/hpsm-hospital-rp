import { redirect } from "next/navigation";
import { AttendanceHistory } from "../../../components/attendance-history";
import { getEffectivePermissionCodes } from "../../../lib/access";
import { getSessionContext } from "../../../lib/session";

export const dynamic = "force-dynamic";

export default async function AttendanceRecordPage({ params }: { params: Promise<{ id: string }> }) {
  const context = await getSessionContext();
  if (!context) redirect("/");
  if (context.profile.must_change_password) redirect("/primeiro-acesso");
  const permissionCodes = await getEffectivePermissionCodes(context.profile.user_id);
  if (!["attendances.create", "attendances.manage", "patients.view", "sr.directors.view"].some((code) => permissionCodes.includes(code))) redirect("/painel");
  const { id } = await params;
  const recordId = Number(id);
  if (!Number.isSafeInteger(recordId) || recordId < 1) redirect("/atendimentos");
  return <AttendanceHistory canManage={permissionCodes.includes("attendances.manage")} focusId={recordId} />;
}
