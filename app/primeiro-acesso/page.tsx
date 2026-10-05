import { redirect } from "next/navigation";
import { ChangePasswordForm } from "../components/change-password-form";
import { HpsmLogo } from "../components/hpsm-logo";
import { getSessionProfile } from "../lib/session";

export const dynamic = "force-dynamic";

export default async function FirstAccessPage() {
  const profile = await getSessionProfile();
  if (!profile) redirect("/");
  if (!profile.must_change_password) redirect("/painel");

  return (
    <main className="first-access-shell">
      <section className="first-access-card">
        <div className="phase-badge">Primeiro acesso</div>
        <HpsmLogo className="large-mark" markOnly />
        <p className="eyebrow">Proteção obrigatória</p>
        <h1>Crie sua senha pessoal</h1>
        <p className="first-access-intro">
          Olá, {profile.display_name}. A senha temporária precisa ser substituída
          antes que você possa acessar o sistema.
        </p>
        <ChangePasswordForm />
        <p className="privacy-line">
          Sua senha não é exibida nem armazenada pelo Hospital Santa Marcelina.
        </p>
      </section>
    </main>
  );
}
