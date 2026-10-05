import Link from "next/link";
import { redirect } from "next/navigation";
import { AppFrame } from "../components/app-frame";
import { getAuditEntries } from "../lib/admin-data";
import { hasPermission } from "../lib/access";
import type { AuditPage } from "../lib/admin-data";
import { getSessionContext } from "../lib/session";
import { staffIdentity } from "../lib/staff-identity";

export const dynamic = "force-dynamic";

const AUDIT_ENTITIES = [
  ["profiles", "Contas profissionais"],
  ["patients", "Pacientes"],
  ["attendances", "Atendimentos"],
  ["clinical_exams", "Exames clínicos"],
  ["clinical_casts", "Controle de gesso"],
  ["professional_identities", "Identidades profissionais"],
  ["notifications", "Comunicados"],
  ["staff_positions", "Cargos"],
  ["user_permission_grants", "Permissões individuais"],
] as const;

type AuditSearchParams = { action?: string | string[]; entity?: string | string[]; page?: string | string[]; search?: string | string[] };

export default async function AuditPage({ searchParams }: { searchParams: Promise<AuditSearchParams> }) {
  const [context, query] = await Promise.all([getSessionContext(), searchParams]);
  if (!context) redirect("/");
  const { profile } = context;
  if (profile.must_change_password) redirect("/primeiro-acesso");
  if (!await hasPermission(profile, "audit.view")) redirect("/painel");

  const action = scalar(query.action).slice(0, 80);
  const entity = scalar(query.entity).slice(0, 80);
  const search = scalar(query.search).slice(0, 100);
  const requestedPage = positivePage(scalar(query.page));
  let auditPage: AuditPage = { items: [], page: requestedPage, pageSize: 25, total: 0 };
  try { auditPage = await getAuditEntries(context.accessToken, { action, entity, page: requestedPage, search }); } catch { /* estado vazio seguro */ }
  const totalPages = Math.max(1, Math.ceil(auditPage.total / auditPage.pageSize));
  const first = auditPage.total ? (auditPage.page - 1) * auditPage.pageSize + 1 : 0;
  const last = Math.min(auditPage.total, auditPage.page * auditPage.pageSize);

  return (
    <AppFrame active="audit" profile={profile} title="Auditoria" description="Histórico imutável das ações sensíveis realizadas no sistema.">
      <section className="management-card audit-card">
        <div className="section-title"><div><p className="eyebrow">Consulta paginada</p><h2>Registro de atividades</h2></div><span className="count-pill">{auditPage.total}</span></div>
        <form className="audit-filters" method="get" role="search">
          <label>Busca<input defaultValue={search} maxLength={100} name="search" placeholder="Responsável ou registro" /></label>
          <label>Ação<select defaultValue={action} name="action"><option value="">Todas</option><option value="INSERT">Criação</option><option value="UPDATE">Alteração</option><option value="DELETE">Exclusão</option><option value="IDENTITY_CRM_CREATED">CRM criado</option><option value="IDENTITY_SIGNATURE_CREATED">Assinatura criada</option><option value="IDENTITY_RUBRIC_CREATED">Rubrica criada</option><option value="IDENTITY_CRM_CORRECTED">CRM corrigido</option><option value="IDENTITY_SIGNATURE_REGENERATED">Assinatura regenerada</option><option value="IDENTITY_RUBRIC_REGENERATED">Rubrica regenerada</option><option value="IDENTITY_UNLOCKED">Identidade desbloqueada</option></select></label>
          <label>Área<select defaultValue={entity} name="entity"><option value="">Todas</option>{AUDIT_ENTITIES.map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label>
          <button type="submit">Filtrar</button>
          {action || entity || search ? <Link href="/auditoria" prefetch={false}>Limpar</Link> : null}
        </form>
        <div className="audit-result-meta">{auditPage.total ? `${first}–${last} de ${auditPage.total}` : "Nenhum resultado"}</div>
        {auditPage.items.length ? (
          <div className="audit-list">
            {auditPage.items.map((entry) => (
              <article key={entry.id}>
                <span className="audit-symbol">{actionSymbol(entry.action)}</span>
                <div><strong>{actionLabel(entry.action)} em {entityLabel(entry.entity_name)}</strong><p>Responsável: {entry.actor_passport ? staffIdentity(entry.actor_passport, entry.actor_position) : "Sistema"}{entry.entity_id ? ` · Registro ${entry.entity_id.slice(0, 8)}` : ""}</p></div>
                <time dateTime={entry.created_at}>{formatDate(entry.created_at)}</time>
              </article>
            ))}
          </div>
        ) : (
          <div className="empty-state"><span>≡</span><strong>Nenhum evento registrado</strong><p>As alterações sensíveis aparecerão aqui quando o sistema entrar em operação.</p></div>
        )}
        <div className="patient-center-pagination audit-pagination" aria-label="Paginação da auditoria">
          {auditPage.page > 1 ? <Link href={auditHref(auditPage.page - 1, { action, entity, search })} prefetch={false}>← Anterior</Link> : <span aria-disabled="true">← Anterior</span>}
          <span>Página <strong>{auditPage.page}</strong> de {totalPages}</span>
          {auditPage.page < totalPages ? <Link href={auditHref(auditPage.page + 1, { action, entity, search })} prefetch={false}>Próxima →</Link> : <span aria-disabled="true">Próxima →</span>}
        </div>
      </section>
    </AppFrame>
  );
}

function scalar(value: string | string[] | undefined) { return typeof value === "string" ? value.trim() : ""; }
function positivePage(value: string) { const parsed = Number(value); return Number.isSafeInteger(parsed) && parsed > 0 ? Math.min(parsed, 10_000) : 1; }
function auditHref(page: number, filters: { action: string; entity: string; search: string }) {
  const params = new URLSearchParams({ page: String(page) });
  if (filters.action) params.set("action", filters.action);
  if (filters.entity) params.set("entity", filters.entity);
  if (filters.search) params.set("search", filters.search);
  return `/auditoria?${params}`;
}

function actionLabel(action: string) {
  return ({ INSERT: "Criação", UPDATE: "Alteração", DELETE: "Exclusão", IDENTITY_CRM_CREATED: "CRM criado", IDENTITY_SIGNATURE_CREATED: "Assinatura criada", IDENTITY_RUBRIC_CREATED: "Rubrica criada", IDENTITY_CRM_CORRECTED: "CRM corrigido", IDENTITY_SIGNATURE_REGENERATED: "Assinatura regenerada", IDENTITY_RUBRIC_REGENERATED: "Rubrica regenerada", IDENTITY_UNLOCKED: "Identidade desbloqueada" } as Record<string, string>)[action] ?? action;
}
function actionSymbol(action: string) { return action === "INSERT" || action.endsWith("_CREATED") ? "+" : action === "DELETE" ? "−" : "↻"; }
function entityLabel(entity: string) { return ({ profiles: "conta profissional", professional_identities: "identidade profissional", patients: "paciente", system_settings: "configuração", service_catalog: "preço do catálogo", plan_discounts: "desconto de plano", attendances: "atendimento", attendance_items: "item do atendimento", clinical_exams: "exame clínico", recruitment_applications: "candidatura", recruitment_decisions: "decisão de recrutamento", rh_hour_snapshots: "lançamento de horas", rh_absence_requests: "afastamento", rh_leave_week_adjustments: "abatimento de afastamento", rh_week_closures: "fechamento semanal", rh_week_reopen_events: "reabertura semanal", rh_weekly_records: "apuração semanal", rh_hour_justifications: "justificativa de horas", rh_warnings: "advertência", rh_disciplinary_reviews: "análise disciplinar", notifications: "comunicado ou notificação", staff_positions: "cargo da equipe", staff_position_permissions: "permissões do cargo", user_permission_grants: "permissão temporária" } as Record<string, string>)[entity] ?? entity; }
function formatDate(value: string) { return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(value)); }
