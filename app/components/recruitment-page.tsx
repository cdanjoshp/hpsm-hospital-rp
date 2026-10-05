"use client";

import Link from "next/link";
import { FormEvent, useState } from "react";
import { HpsmLogo } from "./hpsm-logo";
import { PASSPORT_PATTERN, sanitizePassportInput } from "../lib/passport";

const MONTHS = [
  "Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho",
  "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro",
];

const AVAILABILITY_OPTIONS = [
  { code: "morning", label: "Manhã", time: "06h às 12h" },
  { code: "afternoon", label: "Tarde", time: "12h às 18h" },
  { code: "evening", label: "Noite", time: "18h às 00h" },
  { code: "overnight", label: "Madrugada", time: "00h às 06h" },
];

type FormState = {
  acceptCharacterData: boolean;
  acceptContact: boolean;
  acceptRules: boolean;
  availability: string[];
  birthDay: string;
  birthMonth: string;
  cityPhone: string;
  discordId: string;
  experienceSummary: string;
  externalCalls: string;
  fullName: string;
  interestArea: string;
  motivation: string;
  passport: string;
  priorExperience: "" | "yes" | "no";
  website: string;
};

const INITIAL_FORM: FormState = {
  acceptCharacterData: false,
  acceptContact: false,
  acceptRules: false,
  availability: [],
  birthDay: "",
  birthMonth: "",
  cityPhone: "",
  discordId: "",
  experienceSummary: "",
  externalCalls: "",
  fullName: "",
  interestArea: "",
  motivation: "",
  passport: "",
  priorExperience: "",
  website: "",
};

export function RecruitmentPage() {
  const [form, setForm] = useState<FormState>(INITIAL_FORM);
  const [step, setStep] = useState(0);
  const [error, setError] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [protocol, setProtocol] = useState("");

  function update<K extends keyof FormState>(key: K, value: FormState[K]) {
    setForm((current) => ({ ...current, [key]: value }));
    if (error) setError("");
  }

  function nextStep() {
    const validationError = validateStep(step, form);
    if (validationError) {
      setError(validationError);
      return;
    }
    setError("");
    setStep((current) => Math.min(current + 1, 2));
    document.querySelector(".recruitment-form-card")?.scrollIntoView({ behavior: "smooth", block: "start" });
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const validationError = validateStep(2, form);
    if (validationError) {
      setError(validationError);
      return;
    }

    setSubmitting(true);
    setError("");
    try {
      const response = await fetch("/api/recruitment", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          availability: form.availability,
          birthDay: Number(form.birthDay),
          birthMonth: Number(form.birthMonth),
          cityPhone: form.cityPhone,
          discordId: form.discordId,
          experienceSummary: form.experienceSummary,
          externalCalls: form.externalCalls,
          fullName: form.fullName,
          interestArea: form.interestArea,
          motivation: form.motivation,
          passport: form.passport,
          priorExperience: form.priorExperience === "yes",
          website: form.website,
        }),
      });
      const payload = (await response.json()) as { error?: string; protocol?: string };
      if (!response.ok || !payload.protocol) throw new Error(payload.error ?? "Não foi possível enviar a candidatura.");
      setProtocol(payload.protocol);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Não foi possível enviar a candidatura.");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <main className="recruitment-shell">
      <header className="recruitment-header">
        <Link aria-label="Voltar para a página inicial" href="/"><HpsmLogo compact /></Link>
        <span><i aria-hidden="true" /> Processo seletivo</span>
      </header>

      <section className="recruitment-hero">
        <div>
          <p className="eyebrow">Faça parte do Hospital Santa Marcelina</p>
          <h1>Cuidar também é uma forma de construir histórias.</h1>
          <p>Buscamos profissionais comprometidos com atendimento, trabalho em equipe e uma experiência de RP responsável na Cidade dos Anjos.</p>
          <div className="recruitment-hero-tags"><span>Experiência não obrigatória</span><span>Formação acompanhada</span></div>
        </div>
        <ol className="recruitment-process">
          <li><span>01</span><div><strong>Candidatura</strong><small>Preencha seu perfil e disponibilidade.</small></div></li>
          <li><span>02</span><div><strong>Avaliação</strong><small>A Diretoria analisará as informações.</small></div></li>
          <li><span>03</span><div><strong>Entrevista</strong><small>Os selecionados serão chamados no Discord.</small></div></li>
        </ol>
      </section>

      <section className="recruitment-workspace">
        <aside className="recruitment-edict">
          <div className="recruitment-edict-heading"><span aria-hidden="true">✦</span><div><small>Edital HPSM</small><h2>Antes de se candidatar</h2></div></div>
          <p>O processo busca pessoas dispostas a aprender, respeitar a estrutura hospitalar e contribuir ativamente com a rotina da instituição.</p>

          <div className="edict-section">
            <h3>O que esperamos</h3>
            <ul>
              <li>Compromisso com a disponibilidade informada na candidatura.</li>
              <li>Respeito às diretrizes da cidade e às normas internas.</li>
              <li>Postura colaborativa dentro e fora dos atendimentos.</li>
            </ul>
          </div>

          <div className="edict-section">
            <h3>Conduta essencial</h3>
            <ul>
              <li>Armas, violência e atividades ilícitas não pertencem à rotina do hospital.</li>
              <li>Chamados de emergência têm prioridade sobre rotinas administrativas.</li>
              <li>Animações e comandos devem preservar a imersão durante o atendimento.</li>
            </ul>
          </div>

          <div className="recruitment-credential-note">
            <strong>Sobre o acesso ao sistema</strong>
            <p>Você não criará uma senha nesta ficha. Se for aprovado, a Diretoria fornecerá uma credencial temporária com troca obrigatória no primeiro acesso.</p>
          </div>
        </aside>

        <form className="recruitment-form-card" onSubmit={submit}>
          {protocol ? (
            <div className="recruitment-success" role="status">
              <span aria-hidden="true">✓</span>
              <p className="eyebrow">Candidatura recebida</p>
              <h2>Agora é com a nossa equipe.</h2>
              <p>Sua inscrição foi registrada. Guarde o protocolo abaixo e acompanhe o Discord para um possível contato da Diretoria.</p>
              <strong>{protocol}</strong>
              <Link href="/">Voltar para a página inicial</Link>
            </div>
          ) : (
            <>
              <ol className="recruitment-form-progress" aria-label="Etapas da candidatura">
                {["Identificação", "Perfil", "Confirmação"].map((label, index) => (
                  <li data-active={index === step} data-complete={index < step} key={label}>
                    <span>{index < step ? "✓" : index + 1}</span><small>{label}</small>
                  </li>
                ))}
              </ol>

              {step === 0 ? (
                <section className="recruitment-form-step">
                  <div className="recruitment-step-heading"><p>Etapa 1 de 3</p><h2>Identificação do personagem</h2><span>Use os dados da Cidade dos Anjos. Apenas o ID do Discord deve ser real.</span></div>
                  <div className="recruitment-field-grid">
                    <label className="recruitment-field recruitment-field-wide"><span>Nome completo do personagem *</span><input autoComplete="off" maxLength={100} onChange={(event) => update("fullName", event.target.value)} placeholder="Maria Exemplo da Silva" value={form.fullName} /></label>
                    <label className="recruitment-field"><span>Passaporte *</span><input autoComplete="off" inputMode="numeric" minLength={1} maxLength={4} pattern="[0-9]{1,4}" onChange={(event) => update("passport", sanitizePassportInput(event.target.value))} placeholder="Somente números (até 4)" value={form.passport} /></label>
                    <label className="recruitment-field"><span>Telefone na cidade *</span><input autoComplete="off" inputMode="numeric" onChange={(event) => update("cityPhone", formatCityPhone(event.target.value))} placeholder="(055) 123-456" value={form.cityPhone} /></label>
                    <label className="recruitment-field"><span>Dia de nascimento *</span><input inputMode="numeric" max="31" min="1" onChange={(event) => update("birthDay", event.target.value.replace(/\D/g, "").slice(0, 2))} placeholder="15" type="number" value={form.birthDay} /></label>
                    <label className="recruitment-field"><span>Mês de nascimento *</span><select onChange={(event) => update("birthMonth", event.target.value)} value={form.birthMonth}><option value="">Selecione</option>{MONTHS.map((month, index) => <option key={month} value={index + 1}>{month}</option>)}</select></label>
                    <label className="recruitment-field recruitment-field-wide"><span>ID real do Discord *</span><input autoComplete="off" inputMode="numeric" maxLength={20} onChange={(event) => update("discordId", event.target.value.replace(/\D/g, ""))} placeholder="Somente números" value={form.discordId} /><small>Não informe seu apelido ou nome de usuário.</small></label>
                    <label className="recruitment-honeypot" aria-hidden="true"><span>Website</span><input autoComplete="off" onChange={(event) => update("website", event.target.value)} tabIndex={-1} value={form.website} /></label>
                  </div>
                  <details className="recruitment-discord-help"><summary>Como localizar o ID do Discord?</summary><ol><li>Abra as Configurações do Discord.</li><li>Em Avançado, ative o Modo Desenvolvedor.</li><li>Clique com o botão direito em seu perfil e selecione “Copiar ID do usuário”.</li></ol></details>
                </section>
              ) : null}

              {step === 1 ? (
                <section className="recruitment-form-step">
                  <div className="recruitment-step-heading"><p>Etapa 2 de 3</p><h2>Perfil e disponibilidade</h2><span>Conte como você pretende participar da rotina do hospital.</span></div>
                  <fieldset className="recruitment-choice-group"><legend>Em quais períodos você costuma estar disponível? *</legend><div className="recruitment-shift-grid">{AVAILABILITY_OPTIONS.map((option) => { const checked = form.availability.includes(option.code); return <label data-selected={checked} key={option.code}><input checked={checked} onChange={() => update("availability", checked ? form.availability.filter((item) => item !== option.code) : [...form.availability, option.code])} type="checkbox" /><span aria-hidden="true">{checked ? "✓" : "◷"}</span><strong>{option.label}</strong><small>{option.time}</small></label>; })}</div></fieldset>
                  <fieldset className="recruitment-choice-group"><legend>Você possui experiência anterior na área médica? *</legend><div className="recruitment-inline-options"><label data-selected={form.priorExperience === "yes"}><input checked={form.priorExperience === "yes"} name="priorExperience" onChange={() => update("priorExperience", "yes")} type="radio" />Sim</label><label data-selected={form.priorExperience === "no"}><input checked={form.priorExperience === "no"} name="priorExperience" onChange={() => update("priorExperience", "no")} type="radio" />Não</label></div></fieldset>
                  <label className="recruitment-field"><span>Conte brevemente sua experiência</span><textarea maxLength={1000} onChange={(event) => update("experienceSummary", event.target.value)} placeholder="Opcional. Experiência em outros hospitais, funções ou treinamentos." rows={4} value={form.experienceSummary} /></label>
                  <div className="recruitment-field-grid">
                    <label className="recruitment-field"><span>Área de maior interesse *</span><select onChange={(event) => update("interestArea", event.target.value)} value={form.interestArea}><option value="">Selecione</option><option value="clinical_care">Atendimento clínico</option><option value="emergency_rescue">Emergência e resgate</option><option value="nursing">Enfermagem</option><option value="health_management">Gestão hospitalar</option><option value="undecided">Ainda não defini</option></select></label>
                    <label className="recruitment-field"><span>Chamados externos e direção *</span><select onChange={(event) => update("externalCalls", event.target.value)} value={form.externalCalls}><option value="">Selecione</option><option value="full">Disponibilidade total</option><option value="partial">Disponibilidade com restrições</option><option value="unavailable">Sem disponibilidade no momento</option></select></label>
                  </div>
                  <label className="recruitment-field"><span>Por que você quer fazer parte do HPSM? *</span><textarea maxLength={1200} onChange={(event) => update("motivation", event.target.value)} placeholder="Fale sobre seus objetivos, sua forma de trabalhar e o que espera construir conosco." rows={6} value={form.motivation} /><small>{form.motivation.length}/1200 caracteres</small></label>
                </section>
              ) : null}

              {step === 2 ? (
                <section className="recruitment-form-step">
                  <div className="recruitment-step-heading"><p>Etapa 3 de 3</p><h2>Revise e confirme</h2><span>Confira o resumo antes de registrar definitivamente sua candidatura.</span></div>
                  <div className="recruitment-review-grid"><article><small>Personagem</small><strong>{form.fullName}</strong><span>Passaporte {form.passport}</span></article><article><small>Contato</small><strong>{form.cityPhone}</strong><span>Discord final {form.discordId.slice(-4)}</span></article><article><small>Disponibilidade</small><strong>{form.availability.length} período(s)</strong><span>{interestLabel(form.interestArea)}</span></article></div>
                  <div className="recruitment-agreements">
                    <Agreement checked={form.acceptCharacterData} onChange={(checked) => update("acceptCharacterData", checked)}>Confirmo que os dados pessoais da ficha pertencem ao meu personagem e que somente o ID do Discord é real.</Agreement>
                    <Agreement checked={form.acceptRules} onChange={(checked) => update("acceptRules", checked)}>Declaro que li o resumo do edital e concordo em respeitar as normas e a conduta do HPSM.</Agreement>
                    <Agreement checked={form.acceptContact} onChange={(checked) => update("acceptContact", checked)}>Autorizo a Diretoria a utilizar o ID do Discord exclusivamente para contato sobre este processo seletivo.</Agreement>
                  </div>
                  <p className="recruitment-final-note">O envio da ficha não garante aprovação. A análise considera perfil, disponibilidade e necessidades atuais do hospital.</p>
                </section>
              ) : null}

              {error ? <p className="recruitment-form-error" role="alert">{error}</p> : null}

              <footer className="recruitment-form-actions">
                {step > 0 ? <button className="recruitment-form-secondary" onClick={() => { setError(""); setStep((current) => current - 1); }} type="button">← Etapa anterior</button> : <Link className="recruitment-form-secondary" href="/">Cancelar</Link>}
                {step < 2 ? <button className="recruitment-form-primary" onClick={nextStep} type="button">Continuar <span aria-hidden="true">→</span></button> : <button className="recruitment-form-primary" disabled={submitting} type="submit">{submitting ? "Enviando..." : "Enviar candidatura"}</button>}
              </footer>
            </>
          )}
        </form>
      </section>

      <footer className="recruitment-page-footer"><HpsmLogo compact /><p>Hospital Santa Marcelina • Cidade dos Anjos</p></footer>
    </main>
  );
}

function Agreement({ checked, children, onChange }: { checked: boolean; children: React.ReactNode; onChange: (checked: boolean) => void }) {
  return <label data-selected={checked}><input checked={checked} onChange={(event) => onChange(event.target.checked)} type="checkbox" /><span aria-hidden="true">{checked ? "✓" : ""}</span><strong>{children}</strong></label>;
}

function validateStep(step: number, form: FormState) {
  if (step === 0) {
    if (form.fullName.trim().length < 2) return "Informe o nome completo do personagem.";
    if (!PASSPORT_PATTERN.test(form.passport)) return "Informe um passaporte com até 4 números.";
    if (!/^\([0-9]{3}\) [0-9]{3}-[0-9]{3}$/.test(form.cityPhone)) return "O telefone deve seguir o formato (055) 123-456.";
    if (Number(form.birthDay) < 1 || Number(form.birthDay) > 31 || !form.birthMonth) return "Informe o dia e o mês de nascimento.";
    if (!/^[0-9]{17,20}$/.test(form.discordId)) return "Informe um ID válido do Discord, contendo apenas números.";
  }
  if (step === 1) {
    if (!form.availability.length) return "Selecione ao menos um período disponível.";
    if (!form.priorExperience) return "Informe se você possui experiência anterior.";
    if (!form.interestArea || !form.externalCalls) return "Selecione sua área de interesse e disponibilidade para chamados.";
    if (form.motivation.trim().length < 30) return "Conte um pouco mais sobre sua motivação para entrar no HPSM.";
  }
  if (step === 2 && (!form.acceptCharacterData || !form.acceptRules || !form.acceptContact)) {
    return "Confirme as três declarações para enviar sua candidatura.";
  }
  return "";
}

function formatCityPhone(value: string) {
  let digits = value.replace(/\D/g, "");
  if (digits.startsWith("055")) digits = digits.slice(3);
  digits = digits.slice(0, 6);
  if (!digits) return "";
  return `(055) ${digits.slice(0, 3)}${digits.length > 3 ? `-${digits.slice(3)}` : ""}`;
}

function interestLabel(value: string) {
  return ({ clinical_care: "Atendimento clínico", emergency_rescue: "Emergência e resgate", nursing: "Enfermagem", health_management: "Gestão hospitalar", undecided: "Área ainda não definida" } as Record<string, string>)[value] ?? "Área não informada";
}
