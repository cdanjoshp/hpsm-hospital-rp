import { adminRest } from "./hr-server";
import { createProfessionalIdentitySignedUrl, type ProfessionalIdentityRow } from "./professional-identity";

export type FunctionalTimelineEvent = {
  description: string;
  id: string;
  occurredAt: string;
  title: string;
  tone: "danger" | "info" | "neutral" | "positive" | "warning";
  type: string;
};

export type FunctionalProfileData = {
  absences: Array<{
    endDate: string;
    id: number;
    reason: string;
    requestedAt: string;
    reviewedAt: string | null;
    reviewerName: string | null;
    startDate: string;
    status: string;
  }>;
  courses: Array<{
    assignedAt: string;
    assignedByName: string;
    completedAt: string | null;
    completedByName: string | null;
    id: number;
    name: string;
    status: "completed" | "pending";
  }>;
  justifications: Array<{
    creditedMinutes: number | null;
    deficitMinutes: number;
    id: number;
    reason: string;
    reviewedAt: string | null;
    reviewerName: string | null;
    status: string;
    submittedAt: string;
  }>;
  identity: {
    crmCode: string;
    generatedAt: string | null;
    generatedByName: string | null;
    generationVersion: number;
    identityLocked: boolean;
    lastFailureCode: string | null;
    regeneratedAt: string | null;
    regeneratedByName: string | null;
    regenerationReason: string | null;
    registrationDate: string;
    rubricUrl: string | null;
    signatureUrl: string | null;
    status: "pending" | "generating" | "active" | "failed";
  } | null;
  permissions: Array<{
    expiresAt: string | null;
    grantKind: "individual" | "temporary";
    grantedAt: string;
    grantedByName: string;
    id: number;
    label: string;
    module: string;
    reason: string | null;
    revokedAt: string | null;
    status: "active" | "expired" | "revoked" | "scheduled";
    validFrom: string;
  }>;
  positionHistory: Array<{
    decidedByName: string;
    effectiveAt: string;
    eventType: string;
    fromPosition: string | null;
    id: number;
    note: string | null;
    toPosition: string;
  }>;
  profile: {
    admittedAt: string;
    currentPosition: string;
    currentPositionLevel: number | null;
    currentPositionSince: string;
    displayName: string;
    passport: string;
    status: string;
    userId: string;
  };
  summary: {
    activeTemporaryPermissions: number;
    activeWarningsInCycle: number;
    attendanceCount: number;
    attendanceValue: number;
    completedCourses: number;
    pendingCourses: number;
    workedMinutes: number;
  };
  timeline: FunctionalTimelineEvent[];
  warnings: Array<{
    annulledAt: string | null;
    category: string;
    cycleMonth: string;
    id: number;
    impactsProgression: boolean;
    issuedAt: string;
    issuedByName: string;
    reason: string;
    sequence: number;
    status: string;
  }>;
};

type ProfileRow = {
  created_at: string;
  display_name: string;
  passport: string;
  position_id: number | null;
  status: string;
  user_id: string;
};
type PositionRow = { id: number; level: number; name: string };
type PositionHistoryRow = {
  decided_by: string;
  effective_at: string;
  employee_id: string;
  event_type: string;
  from_position_id: number | null;
  id: number;
  note: string | null;
  to_position_id: number;
};
type HourSnapshotRow = { reference_month: string; reading_date: string; total_minutes: number; updated_at: string };
type AttendanceRow = { created_at: string; id: number; total: number | null };
type CourseRow = { id: number; name: string };
type CourseRecordRow = {
  assigned_at: string;
  assigned_by: string;
  completed_at: string | null;
  completed_by: string | null;
  course_id: number;
  id: number;
  status: "completed" | "pending";
};
type WarningRow = {
  annulled_at: string | null;
  annulled_by: string | null;
  category: string;
  cycle_month: string;
  id: number;
  impacts_progression: boolean;
  issued_at: string;
  issued_by: string;
  reason: string;
  sequence_in_cycle: number;
  status: string;
};
type AbsenceRow = {
  cancelled_at: string | null;
  end_date: string;
  id: number;
  reason: string;
  requested_at: string;
  reviewed_at: string | null;
  reviewed_by: string | null;
  start_date: string;
  status: string;
};
type JustificationRow = {
  credited_minutes: number | null;
  deficit_minutes: number;
  id: number;
  reason: string;
  reviewed_at: string | null;
  reviewed_by: string | null;
  status: string;
  submitted_at: string;
};
type DisciplineRow = {
  decided_at: string | null;
  decided_by: string | null;
  id: number;
  status: string;
  triggered_at: string;
};
type PermissionGrantRow = {
  expires_at: string | null;
  grant_kind: "individual" | "temporary";
  granted_at: string;
  granted_by: string;
  id: number;
  permission_code: string;
  reason: string | null;
  revoked_at: string | null;
  valid_from: string;
};
type PermissionRow = { code: string; label: string; module: string };

export async function getFunctionalProfile(employeeId: string): Promise<FunctionalProfileData | null> {
  const employeeFilter = encodeURIComponent(employeeId);
  const [profiles, positions, positionHistory, snapshots, attendances, courseRecords, courses, warnings, absences, justifications, discipline, grants, systemPermissions, identities] = await Promise.all([
    adminRest<ProfileRow[]>("profiles?select=user_id,display_name,passport,position_id,status,created_at&order=display_name.asc&limit=500"),
    adminRest<PositionRow[]>("staff_positions?select=id,name,level&order=level.asc&limit=50"),
    adminRest<PositionHistoryRow[]>(`staff_position_history?select=id,employee_id,from_position_id,to_position_id,event_type,decided_by,effective_at,note&employee_id=eq.${employeeFilter}&order=effective_at.desc&limit=250`),
    adminRest<HourSnapshotRow[]>(`rh_hour_snapshots?select=reference_month,reading_date,total_minutes,updated_at&employee_id=eq.${employeeFilter}&order=reference_month.asc,reading_date.asc,updated_at.asc&limit=1000`),
    adminRest<AttendanceRow[]>(`attendances?select=id,total,created_at&performed_by=eq.${employeeFilter}&status=eq.completed&order=created_at.desc&limit=1000`),
    adminRest<CourseRecordRow[]>(`staff_course_records?select=id,course_id,status,assigned_by,assigned_at,completed_by,completed_at&employee_id=eq.${employeeFilter}&order=assigned_at.desc&limit=500`),
    adminRest<CourseRow[]>("courses?select=id,name&order=name.asc&limit=500"),
    adminRest<WarningRow[]>(`rh_warnings?select=id,cycle_month,sequence_in_cycle,reason,status,issued_by,issued_at,annulled_by,annulled_at,category,impacts_progression&employee_id=eq.${employeeFilter}&order=issued_at.desc&limit=500`),
    adminRest<AbsenceRow[]>(`rh_absence_requests?select=id,start_date,end_date,reason,status,reviewed_by,reviewed_at,cancelled_at,requested_at&employee_id=eq.${employeeFilter}&order=requested_at.desc&limit=500`),
    adminRest<JustificationRow[]>(`rh_hour_justifications?select=id,deficit_minutes,reason,status,credited_minutes,reviewed_by,reviewed_at,submitted_at&employee_id=eq.${employeeFilter}&order=submitted_at.desc&limit=500`),
    adminRest<DisciplineRow[]>(`rh_disciplinary_reviews?select=id,status,triggered_at,decided_by,decided_at&employee_id=eq.${employeeFilter}&order=triggered_at.desc&limit=250`),
    adminRest<PermissionGrantRow[]>(`user_permission_grants?select=id,permission_code,valid_from,expires_at,reason,granted_by,granted_at,revoked_at,grant_kind&user_id=eq.${employeeFilter}&order=granted_at.desc&limit=500`),
    adminRest<PermissionRow[]>("system_permissions?select=code,module,label&order=sort_order.asc&limit=500"),
    adminRest<ProfessionalIdentityRow[]>(`professional_identities?select=user_id,crm_code,registration_date,signature_image_path,rubric_image_path,status,generation_version,identity_locked,last_failure_code,signature_file_size,rubric_file_size,signature_generated_at,signature_generated_by,signature_regenerated_at,signature_regenerated_by,signature_regeneration_reason,updated_at&user_id=eq.${employeeFilter}&limit=1`),
  ]);
  const profile = profiles.find((item) => item.user_id === employeeId);
  if (!profile) return null;

  const positionById = new Map(positions.map((position) => [position.id, position]));
  const profileById = new Map(profiles.map((item) => [item.user_id, item]));
  const courseById = new Map(courses.map((course) => [course.id, course]));
  const permissionByCode = new Map(systemPermissions.map((permission) => [permission.code, permission]));
  const actorName = (id: string | null) => id ? profileById.get(id)?.display_name ?? "Responsável não identificado" : null;
  const currentPosition = profile.position_id ? positionById.get(profile.position_id) ?? null : null;
  const initialAssignment = [...positionHistory].reverse().find((event) => event.event_type === "initial_assignment");
  const currentPositionEvent = positionHistory.find((event) => event.to_position_id === profile.position_id);
  const admittedAt = initialAssignment?.effective_at ?? profile.created_at;
  const currentPositionSince = currentPositionEvent?.effective_at ?? admittedAt;
  const now = new Date();
  const currentCycle = saoPauloMonth(now);
  const identity = identities[0] ?? null;
  const [signatureUrl, rubricUrl] = identity?.status === "active" && identity.signature_image_path && identity.rubric_image_path
    ? await Promise.all([
      createProfessionalIdentitySignedUrl(identity.signature_image_path).catch(() => null),
      createProfessionalIdentitySignedUrl(identity.rubric_image_path).catch(() => null),
    ])
    : [null, null];

  const latestSnapshotByMonth = new Map<string, HourSnapshotRow>();
  for (const snapshot of snapshots) latestSnapshotByMonth.set(snapshot.reference_month.slice(0, 7), snapshot);
  const workedMinutes = [...latestSnapshotByMonth.values()].reduce((total, snapshot) => total + Number(snapshot.total_minutes), 0);

  const normalizedCourses: FunctionalProfileData["courses"] = courseRecords.map((record) => ({
    assignedAt: record.assigned_at,
    assignedByName: actorName(record.assigned_by) ?? "Responsável não identificado",
    completedAt: record.completed_at,
    completedByName: actorName(record.completed_by),
    id: record.id,
    name: courseById.get(record.course_id)?.name ?? "Curso não identificado",
    status: record.status,
  }));
  const normalizedPermissions: FunctionalProfileData["permissions"] = grants.map((grant) => {
    const permission = permissionByCode.get(grant.permission_code);
    return {
      expiresAt: grant.expires_at,
      grantKind: grant.grant_kind,
      grantedAt: grant.granted_at,
      grantedByName: actorName(grant.granted_by) ?? "Responsável não identificado",
      id: grant.id,
      label: permission?.label ?? grant.permission_code,
      module: permission?.module ?? "Sistema",
      reason: grant.reason,
      revokedAt: grant.revoked_at,
      status: grantStatus(grant, now),
      validFrom: grant.valid_from,
    };
  });
  const normalizedWarnings: FunctionalProfileData["warnings"] = warnings.map((warning) => ({
    annulledAt: warning.annulled_at,
    category: warning.category,
    cycleMonth: warning.cycle_month,
    id: warning.id,
    impactsProgression: warning.impacts_progression,
    issuedAt: warning.issued_at,
    issuedByName: actorName(warning.issued_by) ?? "Responsável não identificado",
    reason: warning.reason,
    sequence: warning.sequence_in_cycle,
    status: warning.status,
  }));
  const normalizedAbsences: FunctionalProfileData["absences"] = absences.map((absence) => ({
    endDate: absence.end_date,
    id: absence.id,
    reason: absence.reason,
    requestedAt: absence.requested_at,
    reviewedAt: absence.reviewed_at,
    reviewerName: actorName(absence.reviewed_by),
    startDate: absence.start_date,
    status: absence.status,
  }));
  const normalizedJustifications: FunctionalProfileData["justifications"] = justifications.map((justification) => ({
    creditedMinutes: justification.credited_minutes,
    deficitMinutes: justification.deficit_minutes,
    id: justification.id,
    reason: justification.reason,
    reviewedAt: justification.reviewed_at,
    reviewerName: actorName(justification.reviewed_by),
    status: justification.status,
    submittedAt: justification.submitted_at,
  }));
  const normalizedHistory: FunctionalProfileData["positionHistory"] = positionHistory.map((event) => ({
    decidedByName: actorName(event.decided_by) ?? "Responsável não identificado",
    effectiveAt: event.effective_at,
    eventType: event.event_type,
    fromPosition: event.from_position_id ? positionById.get(event.from_position_id)?.name ?? "Cargo anterior" : null,
    id: event.id,
    note: event.note,
    toPosition: positionById.get(event.to_position_id)?.name ?? "Cargo não identificado",
  }));

  const timeline: FunctionalTimelineEvent[] = [];
  const addEvent = (event: FunctionalTimelineEvent) => timeline.push(event);
  for (const event of normalizedHistory) {
    const label = positionEventLabel(event.eventType);
    addEvent({
      description: event.eventType === "initial_assignment"
        ? `Ingresso registrado no cargo de ${event.toPosition}.`
        : `${event.fromPosition ?? "Cargo anterior"} → ${event.toPosition}. Decisão de ${event.decidedByName}.`,
      id: `position-${event.id}`,
      occurredAt: event.effectiveAt,
      title: event.eventType === "initial_assignment" ? `Admitido como ${event.toPosition}` : `${label} para ${event.toPosition}`,
      tone: "positive",
      type: "position",
    });
  }
  if (!normalizedHistory.some((event) => event.eventType === "initial_assignment")) {
    addEvent({ description: "Data de admissão preservada no cadastro funcional.", id: "profile-admission", occurredAt: profile.created_at, title: "Admitido no HPSM", tone: "positive", type: "admission" });
  }
  for (const course of normalizedCourses) {
    addEvent({ description: `Curso ${course.name} vinculado por ${course.assignedByName}.`, id: `course-assigned-${course.id}`, occurredAt: course.assignedAt, title: "Curso vinculado", tone: "info", type: "course" });
    if (course.completedAt) addEvent({ description: `${course.name} · conclusão registrada por ${course.completedByName ?? "responsável não identificado"}.`, id: `course-completed-${course.id}`, occurredAt: course.completedAt, title: "Curso concluído", tone: "positive", type: "course" });
  }
  for (const warning of normalizedWarnings) {
    addEvent({ description: `${warning.sequence}ª advertência do ciclo · ${warning.reason}`, id: `warning-issued-${warning.id}`, occurredAt: warning.issuedAt, title: "Advertência registrada", tone: "danger", type: "warning" });
    if (warning.annulledAt) addEvent({ description: `A ${warning.sequence}ª advertência do ciclo deixou de contar, mas permanece no histórico.`, id: `warning-annulled-${warning.id}`, occurredAt: warning.annulledAt, title: "Advertência anulada", tone: "neutral", type: "warning" });
  }
  for (const absence of normalizedAbsences) {
    addEvent({ description: `${formatIsoPeriod(absence.startDate, absence.endDate)} · ${absence.reason}`, id: `absence-requested-${absence.id}`, occurredAt: absence.requestedAt, title: "Afastamento solicitado", tone: "info", type: "absence" });
    const decisionAt = absence.reviewedAt;
    if (decisionAt && absence.status !== "pending") addEvent({ description: `${formatIsoPeriod(absence.startDate, absence.endDate)} · decisão de ${absence.reviewerName ?? "responsável não identificado"}.`, id: `absence-decision-${absence.id}`, occurredAt: decisionAt, title: absence.status === "approved" ? "Afastamento aprovado" : "Afastamento recusado", tone: absence.status === "approved" ? "positive" : "danger", type: "absence" });
    if (absence.status === "cancelled") {
      const original = absences.find((row) => row.id === absence.id);
      if (original?.cancelled_at) addEvent({ description: formatIsoPeriod(absence.startDate, absence.endDate), id: `absence-cancelled-${absence.id}`, occurredAt: original.cancelled_at, title: "Afastamento cancelado", tone: "neutral", type: "absence" });
    }
  }
  for (const justification of normalizedJustifications) {
    addEvent({ description: `Déficit informado: ${formatMinutes(justification.deficitMinutes)} · ${justification.reason}`, id: `justification-submitted-${justification.id}`, occurredAt: justification.submittedAt, title: "Justificativa de horas enviada", tone: "info", type: "justification" });
    if (justification.reviewedAt) addEvent({ description: justification.status === "approved" ? `${formatMinutes(justification.creditedMinutes ?? 0)} abonada(s) por ${justification.reviewerName ?? "responsável não identificado"}.` : `Recusada por ${justification.reviewerName ?? "responsável não identificado"}.`, id: `justification-decision-${justification.id}`, occurredAt: justification.reviewedAt, title: justification.status === "approved" ? "Justificativa aprovada" : "Justificativa recusada", tone: justification.status === "approved" ? "positive" : "danger", type: "justification" });
  }
  for (const review of discipline) {
    addEvent({ description: "Terceira advertência do ciclo abriu análise disciplinar.", id: `discipline-triggered-${review.id}`, occurredAt: review.triggered_at, title: "Suspensão para análise", tone: "danger", type: "discipline" });
    if (review.decided_at) addEvent({ description: `Decisão registrada por ${actorName(review.decided_by) ?? "responsável não identificado"}.`, id: `discipline-decided-${review.id}`, occurredAt: review.decided_at, title: disciplineDecisionLabel(review.status), tone: review.status === "reactivated" ? "positive" : review.status === "dismissed" ? "danger" : "warning", type: "discipline" });
  }
  for (const permission of normalizedPermissions) {
    addEvent({ description: `${permission.label} · ${permission.grantKind === "temporary" ? "permissão temporária" : "permissão individual"} concedida por ${permission.grantedByName}.`, id: `permission-granted-${permission.id}`, occurredAt: permission.grantedAt, title: "Permissão concedida", tone: "info", type: "permission" });
    if (permission.revokedAt) addEvent({ description: permission.label, id: `permission-revoked-${permission.id}`, occurredAt: permission.revokedAt, title: "Permissão revogada", tone: "neutral", type: "permission" });
    else if (permission.status === "expired" && permission.expiresAt) addEvent({ description: permission.label, id: `permission-expired-${permission.id}`, occurredAt: permission.expiresAt, title: "Permissão temporária expirada", tone: "neutral", type: "permission" });
  }
  timeline.sort((a, b) => b.occurredAt.localeCompare(a.occurredAt));

  return {
    absences: normalizedAbsences,
    courses: normalizedCourses,
    identity: identity ? {
      crmCode: identity.crm_code,
      generatedAt: identity.signature_generated_at,
      generatedByName: actorName(identity.signature_generated_by),
      generationVersion: identity.generation_version,
      identityLocked: identity.identity_locked,
      lastFailureCode: identity.last_failure_code,
      regeneratedAt: identity.signature_regenerated_at,
      regeneratedByName: actorName(identity.signature_regenerated_by),
      regenerationReason: identity.signature_regeneration_reason,
      registrationDate: identity.registration_date,
      rubricUrl,
      signatureUrl,
      status: identity.status,
    } : null,
    justifications: normalizedJustifications,
    permissions: normalizedPermissions,
    positionHistory: normalizedHistory,
    profile: {
      admittedAt,
      currentPosition: currentPosition?.name ?? "Cargo não definido",
      currentPositionLevel: currentPosition?.level ?? null,
      currentPositionSince,
      displayName: profile.display_name,
      passport: profile.passport,
      status: profile.status,
      userId: profile.user_id,
    },
    summary: {
      activeTemporaryPermissions: normalizedPermissions.filter((permission) => permission.grantKind === "temporary" && permission.status === "active").length,
      activeWarningsInCycle: normalizedWarnings.filter((warning) => warning.status === "active" && warning.cycleMonth.slice(0, 7) === currentCycle).length,
      attendanceCount: attendances.length,
      attendanceValue: attendances.reduce((total, attendance) => total + Number(attendance.total ?? 0), 0),
      completedCourses: normalizedCourses.filter((course) => course.status === "completed").length,
      pendingCourses: normalizedCourses.filter((course) => course.status === "pending").length,
      workedMinutes,
    },
    timeline: timeline.slice(0, 600),
    warnings: normalizedWarnings,
  };
}

function grantStatus(grant: PermissionGrantRow, now: Date): FunctionalProfileData["permissions"][number]["status"] {
  if (grant.revoked_at) return "revoked";
  if (new Date(grant.valid_from) > now) return "scheduled";
  if (grant.expires_at && new Date(grant.expires_at) <= now) return "expired";
  return "active";
}

function positionEventLabel(type: string) {
  return ({ appointment: "Nomeado", promotion: "Promovido", succession: "Sucessão registrada", override: "Cargo alterado pela Direção Geral" } as Record<string, string>)[type] ?? "Cargo alterado";
}

function disciplineDecisionLabel(status: string) {
  return ({ dismissed: "Colaborador desligado", reactivated: "Retorno de suspensão", suspension_maintained: "Suspensão mantida" } as Record<string, string>)[status] ?? "Análise disciplinar concluída";
}

function saoPauloMonth(date: Date) {
  const parts = new Intl.DateTimeFormat("en-US", { month: "2-digit", timeZone: "America/Sao_Paulo", year: "numeric" }).formatToParts(date);
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${values.year}-${values.month}`;
}

function formatIsoPeriod(start: string, end: string) {
  const format = (value: string) => value.split("-").reverse().join("/");
  return start === end ? format(start) : `${format(start)} a ${format(end)}`;
}

function formatMinutes(total: number) {
  return `${Math.floor(total / 60)}h${String(total % 60).padStart(2, "0")}`;
}
