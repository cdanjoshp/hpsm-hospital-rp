import Link from "next/link";

export default function NotFound() {
  return <main className="public-access-page"><section className="management-card">
    <h1>Página não encontrada</h1>
    <p>Confira o endereço ou volte à entrada do hospital.</p>
    <Link className="submit-button" href="/">Voltar ao início</Link>
  </section></main>;
}
