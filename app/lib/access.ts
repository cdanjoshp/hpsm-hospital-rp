import { cache } from "react";
import { adminRest, callHrRpc } from "./hr-server";
import { getSessionBootstrap, type SessionProfile } from "./session";

export { ADMIN_PERMISSION_CODES } from "./permission-codes";
export { positionLevel, positionName } from "./staff-position";

export type SystemPermission = {
  code: string;
  description: string;
  label: string;
  module: string;
  sort_order: number;
};

export type StaffPosition = {
  advancement_mode: "progression" | "appointment" | "succession" | "external";
  active: boolean;
  code: string;
  created_at: string;
  id: number;
  level: number | null;
  name: string;
  official: boolean;
  sort_order: number;
  updated_at: string;
};

export type StaffPositionPermission = {
  permission_code: string;
  position_id: number;
};

export type UserPermissionGrant = {
  expires_at: string | null;
  grant_kind: "individual" | "temporary";
  granted_at: string;
  granted_by: string;
  id: number;
  permission_code: string;
  reason: string | null;
  revoked_at: string | null;
  revoked_by: string | null;
  revoked_reason: string | null;
  user_id: string;
  valid_from: string;
};

export type AccessManagementData = {
  grants: UserPermissionGrant[];
  permissions: SystemPermission[];
  positionPermissions: StaffPositionPermission[];
  positions: StaffPosition[];
};

const STAFF_POSITION_SELECT = "id,code,name,level,sort_order,official,active,advancement_mode,created_at,updated_at";
const SYSTEM_PERMISSION_SELECT = "code,module,label,description,sort_order";
const USER_PERMISSION_GRANT_SELECT = "id,user_id,permission_code,grant_kind,valid_from,expires_at,reason,granted_by,granted_at,revoked_at,revoked_by,revoked_reason";

async function loadEffectivePermissionCodes(userId: string): Promise<string[]> {
  const bootstrap = await getSessionBootstrap();
  if (bootstrap?.profile.user_id === userId) return bootstrap.permissionCodes;
  return callHrRpc<string[]>("effective_permission_codes", { p_user_id: userId });
}

// Uma navegação costuma consultar permissões no layout e novamente na rota.
// A memoização é request-scoped e preserva a invalidação entre requisições.
export const getEffectivePermissionCodes = cache(loadEffectivePermissionCodes);

export async function hasPermission(profile: SessionProfile, permissionCode: string) {
  if (profile.must_change_password) return false;
  return (await getEffectivePermissionCodes(profile.user_id)).includes(permissionCode);
}

export async function hasAnyPermission(profile: SessionProfile, permissionCodes: readonly string[]) {
  if (profile.must_change_password) return false;
  const effective = new Set(await getEffectivePermissionCodes(profile.user_id));
  return permissionCodes.some((code) => effective.has(code));
}

export async function getAccessManagementData(): Promise<AccessManagementData> {
  const [positions, permissions, positionPermissions, grants] = await Promise.all([
    adminRest<StaffPosition[]>(`staff_positions?select=${STAFF_POSITION_SELECT}&order=sort_order.asc,name.asc`),
    adminRest<SystemPermission[]>(`system_permissions?select=${SYSTEM_PERMISSION_SELECT}&order=sort_order.asc`),
    adminRest<StaffPositionPermission[]>("staff_position_permissions?select=position_id,permission_code"),
    adminRest<UserPermissionGrant[]>(`user_permission_grants?select=${USER_PERMISSION_GRANT_SELECT}&order=granted_at.desc&limit=250`),
  ]);
  return { grants, permissions, positionPermissions, positions };
}

export async function getStaffPositions(): Promise<StaffPosition[]> {
  return adminRest<StaffPosition[]>(`staff_positions?select=${STAFF_POSITION_SELECT}&order=sort_order.asc,name.asc`);
}

export async function callAccessRpc<T>(name: string, payload: Record<string, unknown>) {
  return callHrRpc<T>(name, payload);
}

async function loadPositionDisplayName(positionId: number | null) {
  if (!positionId) return null;
  const bootstrap = await getSessionBootstrap();
  if (bootstrap?.profile.position_id === positionId) return bootstrap.positionDisplayName;
  const rows = await adminRest<Array<{ name: string }>>(`staff_positions?select=name&id=eq.${positionId}&limit=1`);
  return rows[0]?.name ?? null;
}

export const getPositionDisplayName = cache(loadPositionDisplayName);
