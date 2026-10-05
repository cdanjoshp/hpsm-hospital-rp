import { requireChatGPTUser } from "../chatgpt-auth";
import { BootstrapForm } from "../components/bootstrap-form";
import { HpsmLogo } from "../components/hpsm-logo";

export const dynamic = "force-dynamic";

export default async function SetupPage() {
  await requireChatGPTUser("/configurar");

  return (
    <main className="setup-shell">
      <section className="setup-card">
        <HpsmLogo className="large-mark" markOnly />
        <p className="eyebrow">Configuração restrita</p>
        <h1>Inicializar o HPSM</h1>
        <p>Este procedimento cria a única conta semente de Diretor Geral. Reexecutá-lo não cria outro administrador nem gera uma nova senha.</p>
        <BootstrapForm />
        <div className="access-help"><span className="help-icon">i</span><p>A página é protegida pela identidade proprietária do Site e deixa de produzir credenciais após a inicialização.</p></div>
      </section>
    </main>
  );
}
