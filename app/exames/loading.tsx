export default function ExamsLoading() {
  return <section className="management-card exam-loading" aria-label="Carregando Central de Exames">
    <div><i /><i /></div>
    <div className="exam-loading-filters"><i /><i /><i /><i /></div>
    {Array.from({ length: 6 }, (_, index) => <article key={index}><i /><i /><i /><i /></article>)}
  </section>;
}
