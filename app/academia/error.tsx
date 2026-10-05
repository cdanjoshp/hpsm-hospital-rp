"use client";
import Link from "next/link";
import "./academy.css";
export default function AcademyError({ reset }: { error: Error; reset: () => void }) {
  return <div className="academy-page"><div className="academy-empty" role="alert"><strong>Não foi possível carregar a Academia.</strong>
    <p>Confira a conexão e tente novamente.</p><div className="academy-form-actions"><button className="academy-button" onClick={reset}>Tentar novamente</button><Link className="academy-button academy-button-secondary" href="/painel" prefetch={false}>Página inicial</Link></div>
  </div></div>;
}
