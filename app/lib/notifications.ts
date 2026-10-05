import { adminRest, callHrRpc } from "./hr-server";
import { getEffectivePermissionCodes } from "./access";
import type { SessionProfile } from "./session";

export type NotificationKind = "announcement" | "personal" | "system";
export type NotificationPriority = "important" | "normal" | "urgent";
export type NotificationAudience = "all" | "directors" | "employees" | null;

export type SystemNotification = {
  action_url: string | null;
  archived_at: string | null;
  audience: NotificationAudience;
  author_name: string;
  author_passport: string | null;
  body: string;
  created_at: string;
  created_by: string | null;
  expires_at: string | null;
  id: number;
  kind: NotificationKind;
  priority: NotificationPriority;
  read_at: string | null;
  recipient_id: string | null;
  required_permission: string | null;
  resolved_at: string | null;
  resolved_by: string | null;
  source_id: string | null;
  source_type: string | null;
  title: string;
};

export type AnnouncementReader = {
  display_name: string;
  passport: string;
  position_name: string;
  read_at: string;
  user_id: string;
};

export type AnnouncementSummary = SystemNotification & {
  eligible_readers: number;
  non_readers: AnnouncementReader[];
  readers: AnnouncementReader[];
};

type NotificationRow = Omit<SystemNotification, "author_name" | "author_passport" | "read_at">;
type ReadRow = { notification_id: number; read_at: string };
type AuthorRow = { display_name: string; passport: string; position_id: number | null; user_id: string };

export async function getNotificationCenterData(profile: SessionProfile): Promise<SystemNotification[]> {
  const [rows, reads, authors, permissionCodes] = await Promise.all([
    adminRest<NotificationRow[]>(
      "notifications?select=id,kind,recipient_id,audience,priority,title,body,action_url,created_by,created_at,expires_at,archived_at,source_type,source_id,required_permission,resolved_at,resolved_by&archived_at=is.null&order=created_at.desc&limit=200",
    ),
    adminRest<ReadRow[]>(
      `notification_reads?select=notification_id,read_at&user_id=eq.${encodeURIComponent(profile.user_id)}&limit=500`,
    ),
    adminRest<AuthorRow[]>("profiles?select=user_id,display_name,passport,position_id&limit=500"),
    getEffectivePermissionCodes(profile.user_id),
  ]);

  const now = Date.now();
  const readById = new Map(reads.map((read) => [read.notification_id, read.read_at]));
  const authorById = new Map(authors.map((author) => [author.user_id, author]));

  return rows
    .filter((row) => (!row.expires_at || new Date(row.expires_at).getTime() > now) && isVisibleTo(row, profile, permissionCodes))
    .map((row) => {
      const author = row.created_by ? authorById.get(row.created_by) : null;
      return {
        ...row,
        author_name: author?.display_name ?? "Sistema HPSM",
        author_passport: author?.passport ?? null,
        read_at: readById.get(row.id) ?? null,
      };
    });
}

export async function getUnreadNotificationCount(profile: SessionProfile): Promise<number> {
  try {
    const rows = await getNotificationCenterData(profile);
    return rows.filter((row) => !row.read_at && !row.resolved_at).length;
  } catch {
    return 0;
  }
}

export async function getAnnouncementReaderData(profile: SessionProfile): Promise<SystemNotification[]> {
  const notifications = await getNotificationCenterData(profile);
  return notifications.filter((notification) => notification.kind === "announcement");
}

export async function callNotificationRpc<T>(name: string, payload: Record<string, unknown>) {
  return callHrRpc<T>(name, payload);
}

export async function getAnnouncementManagementData(profile: SessionProfile): Promise<AnnouncementSummary[]> {
  const [rows, reads, profiles, positions] = await Promise.all([
    adminRest<NotificationRow[]>(
      "notifications?select=id,kind,recipient_id,audience,priority,title,body,action_url,created_by,created_at,expires_at,archived_at,source_type,source_id,required_permission,resolved_at,resolved_by&kind=eq.announcement&order=created_at.desc&limit=250",
    ),
    adminRest<Array<{ notification_id: number; read_at: string; user_id: string }>>("notification_reads?select=notification_id,user_id,read_at&limit=5000"),
    adminRest<Array<{ display_name: string; passport: string; position_id: number | null; status: string; user_id: string }>>("profiles?select=user_id,display_name,passport,position_id,status&limit=500"),
    adminRest<Array<{ id: number; level: number; name: string }>>("staff_positions?select=id,level,name&limit=50"),
  ]);
  const levelByPosition = new Map(positions.map((position) => [position.id, position.level]));
  const nameByPosition = new Map(positions.map((position) => [position.id, position.name]));
  const profileById = new Map(profiles.map((item) => [item.user_id, item]));
  const authorById = profileById;
  const activeProfiles = profiles.filter((item) => item.status === "active");
  const eligibleByAudience = new Map<Exclude<NotificationAudience, null>, typeof profiles>([
    ["all", activeProfiles],
    ["directors", activeProfiles.filter((item) => (levelByPosition.get(item.position_id ?? -1) ?? 0) >= 11)],
    ["employees", activeProfiles.filter((item) => (levelByPosition.get(item.position_id ?? -1) ?? 1) <= 10)],
  ]);
  const eligibleIdsByAudience = new Map([...eligibleByAudience].map(([audience, eligible]) => [audience, new Set(eligible.map((item) => item.user_id))]));
  const readsByNotification = new Map<number, typeof reads>();
  reads.forEach((read) => {
    const grouped = readsByNotification.get(read.notification_id);
    if (grouped) grouped.push(read);
    else readsByNotification.set(read.notification_id, [read]);
  });
  return rows.map((row) => {
    const eligibleProfiles = row.audience ? eligibleByAudience.get(row.audience) ?? [] : [];
    const eligibleIds = row.audience ? eligibleIdsByAudience.get(row.audience) ?? new Set<string>() : new Set<string>();
    const author = row.created_by ? authorById.get(row.created_by) : null;
    const readers = (readsByNotification.get(row.id) ?? []).filter((read) => eligibleIds.has(read.user_id)).flatMap((read) => {
      const reader = profileById.get(read.user_id);
      return reader ? [{ display_name: reader.display_name, passport: reader.passport, position_name: nameByPosition.get(reader.position_id ?? -1) ?? "Cargo não definido", read_at: read.read_at, user_id: reader.user_id }] : [];
    });
    const readerIds = new Set(readers.map((reader) => reader.user_id));
    const nonReaders = eligibleProfiles
      .filter((item) => !readerIds.has(item.user_id))
      .map((item) => ({
        display_name: item.display_name,
        passport: item.passport,
        position_name: nameByPosition.get(item.position_id ?? -1) ?? "Cargo não definido",
        read_at: "",
        user_id: item.user_id,
      }));
    return {
      ...row,
      author_name: author?.display_name ?? "Sistema HPSM",
      author_passport: author?.passport ?? null,
      eligible_readers: eligibleProfiles.length,
      non_readers: nonReaders,
      read_at: readers.find((reader) => reader.user_id === profile.user_id)?.read_at ?? null,
      readers,
    };
  });
}

function isVisibleTo(notification: NotificationRow, profile: SessionProfile, permissionCodes: string[]) {
  if (notification.recipient_id === profile.user_id) return true;
  if (notification.audience === "all") return true;
  if (notification.audience === "directors") {
    return notification.required_permission
      ? permissionCodes.includes(notification.required_permission)
      : permissionCodes.includes("hr.team.view");
  }
  return notification.audience === "employees" && !permissionCodes.includes("hr.team.view");
}
