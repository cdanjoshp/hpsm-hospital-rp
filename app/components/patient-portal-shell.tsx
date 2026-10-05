import Link from "next/link";
import type { ReactNode } from "react";
import { getPatientPortalSession, type PatientPortalIdentity } from "../lib/patient-portal";
import { formatPatientPassport } from "../lib/passport";
import { HpsmLogo } from "./hpsm-logo";
import { PatientPortalSessionGuard } from "./patient-portal-session-guard";
import { ThemeToggle } from "./theme-toggle";

const PORTAL_AREAS = [
  { href: "/portal-paciente", key: "summary", label: "Resumo" },
  { href: "/portal-paciente/meus-dados", key: "profile", label: "Meus Dados" },
  { href: "/portal-paciente/historico", key: "history", label: "Histórico" },
  { href: "/portal-paciente/atendimentos", key: "attendances", label: "Atendimentos" },
  { href: "/portal-paciente/consultas", key: "consultations", label: "Consultas" },
  { href: "/portal-paciente/internacoes", key: "hospitalizations", label: "Internações" },
  { href: "/portal-paciente/exames", key: "exams", label: "Exames" },
  { href: "/portal-paciente/plano-saude", key: "health-plan", label: "Plano de Saúde" },
  { href: "/portal-paciente/gessos", key: "casts", label: "Gessos" },
  { href: "/portal-paciente/atestados", key: "certificates", label: "Atestados" },
  { href: "/portal-paciente/parcerias", key: "partnerships", label: "Parcerias" },
  { href: "/portal-paciente/historico-norte", key: "legacy", label: "Histórico HP Norte" },
] as const;

export type PatientPortalArea = typeof PORTAL_AREAS[number]["key"];

export function PatientPortalFrame({ children }: { children: ReactNode }) {
  return (
    <main className="patient-portal-page">
      <PatientPortalSessionGuard />
      <header className="patient-portal-public-header">
        <Link aria-label="Voltar ao início do HPSM" href="/"><HpsmLogo compact /></Link>
        <ThemeToggle userId="patient-portal" />
      </header>
      {children}
    </main>
  );
}

export function PatientPortalError({
  message = "Tente novamente em alguns instantes.",
  title = "Não foi possível carregar seus dados agora.",
}: {
  message?: string;
  title?: string;
}) {
  return (
    <section className="patient-portal-error" role="alert">
      <span aria-hidden="true">!</span>
      <h1>{title}</h1>
      <p>{message}</p>
      <Link href="/portal-paciente">Voltar ao Portal</Link>
    </section>
  );
}

export async function PatientPortalShell({
  active,
  children,
  description,
  patient,
  title,
  managesPartnerships = false,
  partnershipArea = false,
}: {
  active: PatientPortalArea;
  children: ReactNode;
  description: string;
  patient: PatientPortalIdentity;
  title?: string;
  managesPartnerships?: boolean;
  partnershipArea?: boolean;
}) {
  const firstName = patient.name.trim().split(/\s+/)[0] || "Paciente";
  const session = await getPatientPortalSession();
  const showPartnerships = managesPartnerships || session?.managesPartnerships === true;

  return (
    <section className="patient-portal-authenticated" aria-labelledby="patient-portal-welcome">
      <div className="patient-portal-shell-head">
        <div>
          <p className="eyebrow">Portal do Paciente</p>
          <h1 id="patient-portal-welcome">{title ?? `Olá, ${firstName}.`}</h1>
          <p>{description}</p>
          <span className="patient-portal-passport">Passaporte {formatPatientPassport(patient.passport)}</span>
        </div>
        <form action="/api/patient-portal/logout" method="post">
          <button type="submit">Sair</button>
        </form>
      </div>

      <nav className="patient-portal-nav" aria-label="Áreas do Portal do Paciente">
        {PORTAL_AREAS.filter((area) => area.key !== "partnerships" || showPartnerships).map((area) => (
          <Link aria-current={active === area.key ? "page" : undefined} href={area.href} key={area.key} prefetch={false}>
            {area.label}
          </Link>
        ))}
      </nav>

      {children}

      <p className="patient-portal-readonly-note">{
        partnershipArea
          ? "Neste espaço, você pode alterar somente a composição das parcerias sob sua responsabilidade."
          : active === "profile"
            ? "Somente os dados cadastrais desta página podem ser alterados. Passaporte e registros clínicos, financeiros e administrativos permanecem protegidos."
            : "Os registros clínicos, financeiros e administrativos são somente para consulta. Seus dados cadastrais podem ser atualizados em Meus Dados."
      }</p>
    </section>
  );
}

export { formatPortalDate, formatPortalMoney } from "../lib/patient-portal-format";
