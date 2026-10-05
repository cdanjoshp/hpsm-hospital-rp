"use client";

import Link from "next/link";
import { visibleAdministrativeAreas } from "../lib/administrative";
import { useShellData } from "./persistent-app-shell";

export function AdministrativeHome({ permissionCodes }: { permissionCodes: string[] }) {
  const areas = visibleAdministrativeAreas(permissionCodes);
  const shell = useShellData();

  return (
    <div className="administrative-home">
      <section className="administrative-home-intro">
        <div><p className="eyebrow">Gestão interna</p><h2>Central Administrativa</h2><p>Escolha uma área para carregar somente as informações necessárias àquela atividade.</p></div>
        <span aria-hidden="true">▤</span>
      </section>
      <section className="administrative-area-grid" aria-label="Áreas administrativas disponíveis">
        {areas.map((area) => {
          const pendingCount = area.id === "pending" ? shell.pendingCount : 0;
          return <Link className="administrative-area-card" href={area.href} key={area.id} prefetch={false}>
            <span className="administrative-area-icon" aria-hidden="true">{area.icon}</span>
            <div><strong>{area.label}</strong><p>{area.description}</p></div>
            {pendingCount ? <em aria-label={`${pendingCount} pendências`}>{pendingCount}</em> : <b aria-hidden="true">→</b>}
          </Link>;
        })}
      </section>
      {!areas.length ? <section className="management-card compact-empty"><span>◇</span><strong>Nenhuma área disponível</strong><p>Seu acesso atual não inclui funções administrativas.</p></section> : null}
    </div>
  );
}
