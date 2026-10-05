"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { RECRUITMENT_NOTICE_KEY } from "../lib/recruitment";

export function RecruitmentEntry() {
  const [open, setOpen] = useState(false);
  const [acknowledged, setAcknowledged] = useState(false);
  const closeButtonRef = useRef<HTMLButtonElement>(null);
  const router = useRouter();

  useEffect(() => {
    if (!open) return;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    closeButtonRef.current?.focus();

    function closeWithEscape(event: KeyboardEvent) {
      if (event.key === "Escape") {
        setAcknowledged(false);
        setOpen(false);
      }
    }

    window.addEventListener("keydown", closeWithEscape);
    return () => {
      document.body.style.overflow = previousOverflow;
      window.removeEventListener("keydown", closeWithEscape);
    };
  }, [open]);

  function continueToRecruitment() {
    document.cookie = `${RECRUITMENT_NOTICE_KEY}=true; Path=/; Max-Age=14400; SameSite=Lax`;
    router.push("/recrutamento");
  }

  return (
    <>
      <div className="candidate-entry">
        <span>Quer fazer parte da equipe?</span>
        <button className="candidate-entry-button" onClick={() => setOpen(true)} type="button">
          <span aria-hidden="true">✦</span>
          <span><strong>Quero ser um profissional da saúde</strong><small>Conheça o recrutamento do HPSM</small></span>
          <span aria-hidden="true">→</span>
        </button>
      </div>

      {open ? (
        <div
          className="recruitment-notice-overlay"
          onMouseDown={(event) => {
            if (event.target === event.currentTarget) {
              setAcknowledged(false);
              setOpen(false);
            }
          }}
          role="presentation"
        >
          <section
            aria-describedby="recruitment-notice-summary"
            aria-labelledby="recruitment-notice-title"
            aria-modal="true"
            className="recruitment-notice"
            role="dialog"
          >
            <header className="recruitment-notice-header">
              <div className="recruitment-notice-brand">
                <span aria-hidden="true">H</span>
                <div>
                  <small>Hospital Santa Marcelina</small>
                  <h2 id="recruitment-notice-title">Antes de continuar</h2>
                </div>
              </div>
              <button aria-label="Fechar orientação" onClick={() => { setAcknowledged(false); setOpen(false); }} ref={closeButtonRef} type="button">×</button>
            </header>

            <div className="recruitment-notice-body">
              <p className="recruitment-notice-summary" id="recruitment-notice-summary">
                A inscrição representa o seu <strong>personagem dentro da Cidade dos Anjos</strong>. Antes de preencher, confira quais informações devem ser usadas.
              </p>

              <div className="recruitment-guidelines">
                <article>
                  <span aria-hidden="true">01</span>
                  <div><h3>Dados do personagem</h3><p>Nome completo, passaporte, data de nascimento e telefone devem ser os dados utilizados dentro do jogo.</p></div>
                </article>
                <article>
                  <span aria-hidden="true">02</span>
                  <div><h3>Apenas o Discord é real</h3><p>Informe o seu ID real do Discord somente para que a equipe do HPSM possa realizar o contato oficial.</p></div>
                </article>
                <article>
                  <span aria-hidden="true">03</span>
                  <div><h3>Proteja seus dados pessoais</h3><p>Não envie nome, telefone, documentos ou qualquer outra informação pessoal da vida real.</p></div>
                </article>
              </div>

              <details className="discord-id-help">
                <summary><span aria-hidden="true">?</span> Como encontro meu ID do Discord?</summary>
                <ol>
                  <li>Abra as <strong>Configurações</strong> do Discord.</li>
                  <li>Em <strong>Avançado</strong>, ative o Modo Desenvolvedor.</li>
                  <li>Clique com o botão direito em seu perfil e selecione <strong>Copiar ID do usuário</strong>.</li>
                </ol>
              </details>

              <label className="recruitment-confirmation">
                <input
                  checked={acknowledged}
                  onChange={(event) => setAcknowledged(event.target.checked)}
                  type="checkbox"
                />
                <span aria-hidden="true" />
                <strong>Li as orientações e entendi quais dados devo informar.</strong>
              </label>

              <div className="recruitment-notice-actions">
                <button className="recruitment-back-button" onClick={() => { setAcknowledged(false); setOpen(false); }} type="button">Cancelar</button>
                <button
                  className="recruitment-continue-button"
                  disabled={!acknowledged}
                  onClick={continueToRecruitment}
                  type="button"
                >
                  Prosseguir com a candidatura <span aria-hidden="true">→</span>
                </button>
              </div>
            </div>
          </section>
        </div>
      ) : null}
    </>
  );
}
