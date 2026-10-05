export default function DashboardLoading() {
  return <section className="dashboard-skeleton" aria-label="Carregando Dashboard" aria-live="polite">
    <div className="dashboard-skeleton-grid" aria-hidden="true">
      <article><i /><i /><i /><i /></article>
      <article><i /><i /><i /></article>
      <article><i /><i /><i /></article>
      <article className="wide"><i /><i /><i /></article>
    </div>
    <div className="dashboard-skeleton-secondary" aria-hidden="true"><i /><i /><i /></div>
    <p>Preparando sua semana e suas ações…</p>
  </section>;
}
