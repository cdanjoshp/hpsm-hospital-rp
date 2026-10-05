export default function AdministrativeLoading() {
  return <div className="administrative-loading" role="status" aria-label="Carregando área administrativa">
    <section className="administrative-loading-heading"><span /><div><i /><i /></div></section>
    <section className="administrative-loading-grid">{Array.from({ length: 4 }, (_, index) => <article key={index}><span /><div><i /><i /></div></article>)}</section>
  </div>;
}
