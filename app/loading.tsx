export default function PortalLoading() {
  return (
    <section className="route-loading" aria-label="Carregando área" aria-live="polite">
      <div className="route-loading-heading">
        <span aria-hidden="true">◇</span>
        <div><i /><i /></div>
      </div>
      <div className="route-loading-grid" aria-hidden="true">
        <article><i /><i /><i /></article>
        <article><i /><i /><i /></article>
        <article><i /><i /><i /></article>
      </div>
      <p>Carregando apenas os dados desta área…</p>
    </section>
  );
}
