"use client";

import { FormEvent, useState } from "react";
import { useRouter } from "next/navigation";

export function ChangePasswordForm() {
  const router = useRouter();
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  const requirements = {
    length: password.length >= 10,
    letter: /[A-Za-z]/.test(password),
    number: /\d/.test(password),
    symbol: /[^A-Za-z0-9]/.test(password),
  };
  const valid = Object.values(requirements).every(Boolean);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");

    if (!valid) {
      setError("A nova senha ainda não atende aos requisitos de segurança.");
      return;
    }
    if (password !== confirmation) {
      setError("As senhas informadas não são iguais.");
      return;
    }

    setLoading(true);
    try {
      const response = await fetch("/api/auth/change-password", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ password }),
      });
      const payload = (await response.json()) as { error?: string; identityStatus?: string };
      if (!response.ok) {
        setError(payload.error ?? "Não foi possível atualizar a senha.");
        return;
      }
      router.push(payload.identityStatus === "active" ? "/painel" : "/painel?identity=pending");
      router.refresh();
    } catch {
      setError("Não foi possível concluir a troca de senha.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <form className="password-form" onSubmit={handleSubmit}>
      <label htmlFor="new-password">Nova senha</label>
      <div className="field-wrap">
        <span className="field-icon lock-icon" aria-hidden="true">●</span>
        <input
          id="new-password"
          type={showPassword ? "text" : "password"}
          autoComplete="new-password"
          value={password}
          onChange={(event) => setPassword(event.target.value)}
          minLength={10}
          maxLength={128}
          required
          disabled={loading}
        />
        <button
          className="reveal-button"
          type="button"
          onClick={() => setShowPassword((value) => !value)}
        >
          {showPassword ? "Ocultar" : "Mostrar"}
        </button>
      </div>

      <ul className="password-rules" aria-label="Requisitos da senha">
        <li data-valid={requirements.length}>10 ou mais caracteres</li>
        <li data-valid={requirements.letter}>Ao menos uma letra</li>
        <li data-valid={requirements.number}>Ao menos um número</li>
        <li data-valid={requirements.symbol}>Ao menos um símbolo</li>
      </ul>

      <label htmlFor="confirm-password">Confirmar nova senha</label>
      <div className="field-wrap">
        <span className="field-icon lock-icon" aria-hidden="true">●</span>
        <input
          id="confirm-password"
          type={showPassword ? "text" : "password"}
          autoComplete="new-password"
          value={confirmation}
          onChange={(event) => setConfirmation(event.target.value)}
          minLength={10}
          maxLength={128}
          required
          disabled={loading}
        />
      </div>

      {error ? <p className="form-error" role="alert">{error}</p> : null}

      <button className="submit-button" type="submit" disabled={loading}>
        <span>{loading ? "Atualizando…" : "Definir nova senha"}</span>
        <span aria-hidden="true">→</span>
      </button>
    </form>
  );
}
