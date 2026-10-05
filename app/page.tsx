import { redirect } from "next/navigation";
import { HpsmLogo } from "./components/hpsm-logo";
import { LoginForm, type PublicAccessMode } from "./components/login-form";
import { ThemeToggle } from "./components/theme-toggle";
import { getSessionProfile } from "./lib/session";

export const dynamic = "force-dynamic";

export default async function Home({
  searchParams,
}: {
  searchParams: Promise<{
    access?: string | string[];
    loginError?: string | string[];
    portalError?: string | string[];
  }>;
}) {
  const profile = await getSessionProfile();
  if (profile) {
    redirect(profile.must_change_password ? "/primeiro-acesso" : "/painel");
  }

  const params = await searchParams;
  const professionalErrorCode = firstParam(params.loginError);
  const patientErrorCode = firstParam(params.portalError);
  const initialAccess = normalizeAccess(firstParam(params.access));

  return (
    <main className="public-access-page">
      <div className="public-access-toolbar">
        <ThemeToggle userId="public-entry" />
      </div>

      <div className="public-access-layout">
        <aside className="public-access-story" aria-labelledby="public-access-story-title">
          <div>
            <p className="eyebrow">Hospital Santa Marcelina</p>
            <h2 id="public-access-story-title">Cuidado que orienta.</h2>
            <span className="public-access-story-rule" aria-hidden="true" />
            <p>
              Gestão clínica e administrativa do Hospital Santa Marcelina em um
              ambiente reservado, seguro e organizado para toda a equipe.
            </p>
          </div>
        </aside>

        <section className="public-access-card" aria-labelledby="public-access-title">
          <div className="public-access-brand">
            <HpsmLogo className="public-access-logo" />
          </div>

          <LoginForm
            initialAccess={initialAccess}
            initialPatientError={patientErrorCode ? "Não foi possível validar seus dados." : ""}
            initialProfessionalError={loginErrorMessage(professionalErrorCode)}
          />
        </section>
      </div>
    </main>
  );
}

function firstParam(value?: string | string[]) {
  return Array.isArray(value) ? value[0] : value;
}

function normalizeAccess(value?: string): PublicAccessMode | null {
  return value === "professional" || value === "patient" ? value : null;
}

function loginErrorMessage(code?: string) {
  if (code === "inactive") return "A conta não está liberada. Procure a diretoria.";
  if (code === "timeout") return "O serviço de acesso demorou para responder. Tente novamente.";
  if (code === "configuration") return "A conexão segura com o hospital está sendo configurada.";
  if (code === "invalid_request") return "Informe matrícula e senha.";
  if (code) return "Matrícula ou senha inválida.";
  return "";
}
