"use client";

import { useEffect, useState, type FormEvent } from "react";
import Link from "next/link";
import { sanitizePassportInput } from "../lib/passport";
import { RecruitmentEntry } from "./recruitment-entry";

export type PublicAccessMode = "patient" | "professional";

type LoginFormProps = {
  initialAccess?: PublicAccessMode | null;
  initialPatientError?: string;
  initialProfessionalError?: string;
};

type PatientAccessStep = "passport" | "create-pin" | "pin";

export function LoginForm({
  initialAccess = null,
  initialPatientError = "",
  initialProfessionalError = "",
}: LoginFormProps) {
  const [access, setAccess] = useState<PublicAccessMode | null>(
    initialProfessionalError ? "professional" : initialPatientError ? "patient" : initialAccess,
  );
  const [professionalPassport, setProfessionalPassport] = useState("");
  const [patientPassport, setPatientPassport] = useState("");
  const [password, setPassword] = useState("");
  const [patientStep, setPatientStep] = useState<PatientAccessStep>("passport");
  const [pin, setPin] = useState("");
  const [pinConfirmation, setPinConfirmation] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [professionalError, setProfessionalError] = useState(initialProfessionalError);
  const [patientError, setPatientError] = useState(initialPatientError);

  useEffect(() => {
    function clearRestoredCredentials() {
      setProfessionalPassport("");
      setPatientPassport("");
      setPassword("");
      setPatientStep("passport");
      setPin("");
      setPinConfirmation("");
      setShowPassword(false);
      setLoading(false);
    }

    window.addEventListener("pageshow", clearRestoredCredentials);
    return () => window.removeEventListener("pageshow", clearRestoredCredentials);
  }, []);

  function chooseAccess(nextAccess: PublicAccessMode) {
    clearFormState();
    setAccess(nextAccess);
  }

  function chooseAnotherAccess() {
    clearFormState();
    setAccess(null);
  }

  function clearFormState() {
    setProfessionalPassport("");
    setPatientPassport("");
    setPassword("");
    setPatientStep("passport");
    setPin("");
    setPinConfirmation("");
    setShowPassword(false);
    setLoading(false);
    setProfessionalError("");
    setPatientError("");
  }

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    if (loading) {
      event.preventDefault();
      return;
    }
    setLoading(true);
  }

  async function handlePatientSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (loading) return;
    setLoading(true);
    setPatientError("");
    try {
      const action = patientStep === "passport" ? "check" : patientStep === "create-pin" ? "create" : "login";
      const response = await fetch("/api/patient-portal/login", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          action,
          passport: patientPassport,
          ...(action === "check" ? {} : { pin }),
          ...(action === "create" ? { pinConfirmation } : {}),
        }),
      });
      const payload = await response.json() as { code?: string; error?: string; hasPin?: boolean; ok?: boolean; passport?: string };
      if (!response.ok || payload.ok !== true) {
        if (payload.code === "first_access") setPatientStep("create-pin");
        if (payload.code === "pin_exists") setPatientStep("pin");
        throw new Error(payload.error ?? "Não foi possível concluir o acesso.");
      }
      if (action === "check") {
        setPatientPassport(payload.passport ?? patientPassport);
        setPatientStep(payload.hasPin ? "pin" : "create-pin");
        setPin("");
        setPinConfirmation("");
        return;
      }
      window.location.assign("/portal-paciente");
    } catch (cause) {
      setPatientError(cause instanceof Error ? cause.message : "Não foi possível concluir o acesso.");
    } finally {
      setLoading(false);
    }
  }

  function restartPatientAccess() {
    setPatientStep("passport");
    setPatientPassport("");
    setPin("");
    setPinConfirmation("");
    setPatientError("");
  }

  return (
    <div className="public-access-flow" data-access={access ?? "selection"}>
      <header className="public-access-copy">
        <p className="eyebrow">
          {access === "professional" ? "Sistema interno" : access === "patient" ? "Acesso do paciente" : "Hospital Santa Marcelina"}
        </p>
        <h1 id="public-access-title">
          {access === "professional" ? "Acesso Profissional" : access === "patient" ? "Portal do Paciente" : "Bem-vindo ao HPSM"}
        </h1>
        <p>
          {access === "professional"
            ? "Entre com seu passaporte ou matrícula e a senha institucional."
            : access === "patient"
              ? "Informe seu passaporte e use um PIN pessoal de 4 números."
              : "Escolha como deseja acessar."}
        </p>
      </header>

      {access === null ? (
        <div className="public-access-view public-access-selection" aria-labelledby="public-access-title">
          <div className="public-access-options" aria-label="Escolha o tipo de acesso">
            <button className="public-access-option" onClick={() => chooseAccess("professional")} type="button">
              <AccessIcon kind="professional" />
              <span><strong>Sou Profissional</strong><small>Acesso ao sistema interno</small></span>
              <span className="public-access-arrow" aria-hidden="true">→</span>
            </button>

            <button className="public-access-option" onClick={() => chooseAccess("patient")} type="button">
              <AccessIcon kind="patient" />
              <span><strong>Sou Paciente</strong><small>Acesse seus registros e exames</small></span>
              <span className="public-access-arrow" aria-hidden="true">→</span>
            </button>
          </div>

          <RecruitmentEntry />
          <div className="public-institutional-entry">
            <span className="public-institutional-label">Informações institucionais</span>
            <Link className="public-access-option public-regiment-entry" href="/regimento">
              <span aria-hidden="true" className="public-access-option-icon">▤</span>
              <span><strong>Regimento Interno</strong><small>Normas de Boas Práticas do HPSM</small></span>
              <span aria-hidden="true" className="public-access-arrow">→</span>
            </Link>
          </div>
        </div>
      ) : access === "professional" ? (
        <div className="public-access-view" id="professional-login-panel">
          <form action="/api/auth/login" aria-busy={loading} className="login-form public-login-form" method="post" onSubmit={handleSubmit}>
            <label htmlFor="professional-passport">Passaporte / Matrícula</label>
            <div className="field-wrap">
              <span className="field-icon" aria-hidden="true">ID</span>
              <input
                aria-describedby={professionalError ? "professional-login-error" : undefined}
                aria-disabled={loading}
                aria-invalid={professionalError ? true : undefined}
                autoComplete="username"
                autoFocus
                id="professional-passport"
                inputMode="numeric"
                maxLength={4}
                minLength={1}
                name="passport"
                onChange={(event) => setProfessionalPassport(sanitizePassportInput(event.target.value))}
                pattern="[0-9]{1,4}"
                placeholder="Ex.: 0532"
                readOnly={loading}
                required
                type="text"
                value={professionalPassport}
              />
            </div>

            <div className="password-label">
              <label htmlFor="professional-password">Senha</label>
              <span>Uso pessoal e intransferível</span>
            </div>
            <div className="field-wrap">
              <span className="field-icon lock-icon" aria-hidden="true">●</span>
              <input
                aria-describedby={professionalError ? "professional-login-error" : undefined}
                aria-disabled={loading}
                aria-invalid={professionalError ? true : undefined}
                autoComplete="current-password"
                id="professional-password"
                maxLength={128}
                minLength={8}
                name="password"
                onChange={(event) => setPassword(event.target.value)}
                placeholder="Digite sua senha"
                readOnly={loading}
                required
                type={showPassword ? "text" : "password"}
                value={password}
              />
              <button
                aria-label={showPassword ? "Ocultar senha" : "Mostrar senha"}
                aria-pressed={showPassword}
                className="reveal-button"
                disabled={loading}
                onClick={() => setShowPassword((value) => !value)}
                type="button"
              >
                {showPassword ? "Ocultar" : "Mostrar"}
              </button>
            </div>

            {professionalError ? <p className="form-error" id="professional-login-error" role="alert">{professionalError}</p> : null}

            <button className="submit-button public-access-submit" disabled={loading} type="submit">
              <span>{loading ? "Entrando…" : "Entrar"}</span>
              <span aria-hidden="true">→</span>
            </button>
          </form>
          <AccessBackButton disabled={loading} onClick={chooseAnotherAccess} />
        </div>
      ) : (
        <div className="public-access-view" id="patient-login-panel">
          <form aria-busy={loading} className="patient-portal-form public-login-form" onSubmit={handlePatientSubmit}>
            {patientStep === "create-pin" ? <div className="patient-first-access-copy"><span>PRIMEIRO ACESSO</span><strong>Crie seu PIN de 4 números</strong><p>Ele será solicitado nos próximos acessos. Escolha uma combinação pessoal e não compartilhe.</p></div> : null}
            {patientStep === "pin" ? <div className="patient-first-access-copy"><span>ACESSO DO PACIENTE</span><strong>Digite seu PIN</strong></div> : null}

            <label htmlFor="patient-passport">Passaporte</label>
            <input
              aria-describedby={patientError ? "patient-login-error" : undefined}
              aria-disabled={loading}
              aria-invalid={patientError ? true : undefined}
              autoComplete="username"
              autoFocus={patientStep === "passport"}
              id="patient-passport"
              inputMode="numeric"
              maxLength={4}
              minLength={1}
              name="passport"
              onChange={(event) => setPatientPassport(sanitizePassportInput(event.target.value))}
              pattern="[0-9]{1,4}"
              placeholder="Ex.: 0532"
              readOnly={loading || patientStep !== "passport"}
              required
              type="text"
              value={patientPassport}
            />

            {patientStep !== "passport" ? <>
              <label htmlFor="patient-pin">PIN</label>
              <input
                aria-describedby={patientError ? "patient-login-error" : "patient-pin-hint"}
                aria-disabled={loading}
                aria-invalid={patientError ? true : undefined}
                autoComplete={patientStep === "create-pin" ? "new-password" : "current-password"}
                autoFocus
                id="patient-pin"
                inputMode="numeric"
                maxLength={4}
                minLength={4}
                name="pin"
                onChange={(event) => setPin(sanitizePassportInput(event.target.value))}
                pattern="[0-9]{4}"
                placeholder="••••"
                readOnly={loading}
                required
                type="password"
                value={pin}
              />
              <small id="patient-pin-hint">Exatamente 4 números.</small>
            </> : null}

            {patientStep === "create-pin" ? <>
              <label htmlFor="patient-pin-confirmation">Confirme o PIN</label>
              <input
                aria-describedby={patientError ? "patient-login-error" : undefined}
                aria-disabled={loading}
                aria-invalid={patientError ? true : undefined}
                autoComplete="new-password"
                id="patient-pin-confirmation"
                inputMode="numeric"
                maxLength={4}
                minLength={4}
                name="pinConfirmation"
                onChange={(event) => setPinConfirmation(sanitizePassportInput(event.target.value))}
                pattern="[0-9]{4}"
                placeholder="••••"
                readOnly={loading}
                required
                type="password"
                value={pinConfirmation}
              />
            </> : null}

            {patientError ? <p className="form-error" id="patient-login-error" role="alert">{patientError}</p> : null}

            <button className="patient-portal-submit public-access-submit" disabled={loading} type="submit">
              <span>{loading ? "Aguarde…" : patientStep === "passport" ? "Continuar" : patientStep === "create-pin" ? "Criar PIN e entrar" : "Entrar"}</span>
              <span aria-hidden="true">→</span>
            </button>
            {patientStep !== "passport" ? <button className="patient-access-restart" disabled={loading} onClick={restartPatientAccess} type="button">Usar outro passaporte</button> : null}
          </form>
          <AccessBackButton disabled={loading} onClick={chooseAnotherAccess} />
        </div>
      )}
    </div>
  );
}

function AccessBackButton({ disabled, onClick }: { disabled: boolean; onClick: () => void }) {
  return (
    <button className="public-access-back" disabled={disabled} onClick={onClick} type="button">
      <span aria-hidden="true">←</span> Escolher outro acesso
    </button>
  );
}

function AccessIcon({ kind }: { kind: PublicAccessMode }) {
  return kind === "professional" ? (
    <span className="public-access-option-icon" aria-hidden="true">
      <svg fill="none" viewBox="0 0 24 24">
        <rect height="16" rx="3" stroke="currentColor" strokeWidth="1.8" width="18" x="3" y="4" />
        <circle cx="8.5" cy="10" r="2" stroke="currentColor" strokeWidth="1.8" />
        <path d="M6 15.5c.7-1.3 1.6-2 2.5-2s1.8.7 2.5 2M14 9h4M14 13h4" stroke="currentColor" strokeLinecap="round" strokeWidth="1.8" />
      </svg>
    </span>
  ) : (
    <span className="public-access-option-icon" aria-hidden="true">
      <svg fill="none" viewBox="0 0 24 24">
        <path d="M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.6-7 10-7 10Z" stroke="currentColor" strokeLinejoin="round" strokeWidth="1.8" />
        <path d="M8.5 12h2l1-2.2 1.4 4 1-1.8h1.6" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="1.6" />
      </svg>
    </span>
  );
}
