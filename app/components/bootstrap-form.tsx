"use client";

import { FormEvent, useState } from "react";
import Link from "next/link";
import { sanitizePassportInput } from "../lib/passport";

type BootstrapResult = { error?: string; passport?: string; temporaryPassword?: string };

export function BootstrapForm() {
  const [result, setResult] = useState<BootstrapResult | null>(null);
  const [loading, setLoading] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setLoading(true);
    setResult(null);
    const form = new FormData(event.currentTarget);
    try {
      const response = await fetch("/api/bootstrap", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ displayName: form.get("displayName"), passport: form.get("passport") }),
      });
      setResult((await response.json()) as BootstrapResult);
    } catch {
      setResult({ error: "Não foi possível inicializar o sistema." });
    } finally {
      setLoading(false);
    }
  }

  if (result?.temporaryPassword && result.passport) {
    return (
      <div className="bootstrap-result">
        <div className="phase-badge">Inicialização concluída</div>
        <h2>Conta do Diretor Geral criada</h2>
        <p>Esta senha temporária será exibida apenas agora. Anote antes de fechar esta página.</p>
        <div className="credential-field"><span>Matrícula</span><strong>{result.passport}</strong></div>
        <div className="credential-field"><span>Senha temporária</span><strong>{result.temporaryPassword}</strong></div>
        <Link className="submit-button setup-link" href="/"><span>Ir para o acesso</span><span>→</span></Link>
      </div>
    );
  }

  return (
    <form className="create-user-form" onSubmit={submit}>
      <label htmlFor="setup-name">Nome do Diretor Geral</label>
      <input id="setup-name" name="displayName" minLength={2} maxLength={80} required placeholder="José Exemplo de Ribeiro" />
      <label htmlFor="setup-passport">Passaporte / Matrícula</label>
      <input id="setup-passport" name="passport" type="text" inputMode="numeric" minLength={1} maxLength={4} pattern="[0-9]{1,4}" required placeholder="Somente números (até 4)" onInput={(event) => { event.currentTarget.value = sanitizePassportInput(event.currentTarget.value); }} />
      {result?.error ? <p className="form-error" role="alert">{result.error}</p> : null}
      <button className="submit-button" type="submit" disabled={loading}><span>{loading ? "Inicializando…" : "Criar conta semente"}</span><span>→</span></button>
    </form>
  );
}
