import { redirect } from "next/navigation";
import { ADMIN_PERMISSION_CODES, getEffectivePermissionCodes } from "./access";
import { canAccessAdministrativeArea, type AdministrativeAreaId } from "./administrative";
import { getSessionBootstrap } from "./session";

export async function requireAdministrativeContext(areaId?: AdministrativeAreaId) {
  const context = await getSessionBootstrap();
  if (!context) redirect("/");
  if (context.profile.must_change_password) redirect("/primeiro-acesso");

  const permissionCodes = await getEffectivePermissionCodes(context.profile.user_id);
  if (!ADMIN_PERMISSION_CODES.some((code) => permissionCodes.includes(code))) redirect("/painel");
  if (areaId && !canAccessAdministrativeArea(permissionCodes, areaId)) redirect("/administrativo");

  return { context, permissionCodes };
}
