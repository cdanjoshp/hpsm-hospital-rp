"use client";

export default function PageError() {
  return <section className="management-card" role="alert">
    <h2>Não foi possível carregar esta página</h2>
    <p>Tente novamente em instantes. Os dados já registrados continuam salvos.</p>
    <button className="submit-button" onClick={() => window.location.replace(window.location.href)} type="button">Tentar novamente</button>
  </section>;
}
