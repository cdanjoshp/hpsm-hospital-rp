import { HpsmLogo } from "../components/hpsm-logo";

export default function PatientPortalLoading() {
  return (
    <main className="patient-portal-page" aria-busy="true" aria-label="Carregando Portal do Paciente">
      <header className="patient-portal-public-header"><HpsmLogo compact /></header>
      <section className="patient-portal-authenticated patient-portal-loading">
        <div className="patient-portal-loading-head"><span /><span /><span /></div>
        <div className="patient-portal-loading-nav" />
        <div className="patient-portal-loading-metrics">{Array.from({ length: 4 }, (_, index) => <span key={index} />)}</div>
        <div className="patient-portal-loading-panels"><span /><span /></div>
      </section>
    </main>
  );
}
