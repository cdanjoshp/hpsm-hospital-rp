import Link from "next/link";
import { administrativeArea, type AdministrativeAreaId } from "../lib/administrative";

export function AdministrativeBreadcrumb({ current }: { current: AdministrativeAreaId }) {
  const area = administrativeArea(current);

  return (
    <nav aria-label="Breadcrumb" className="administrative-breadcrumb">
      <ol>
        <li><Link href="/administrativo" prefetch={false}>Administrativo</Link></li>
        <li aria-hidden="true">/</li>
        <li aria-current="page">{area.label}</li>
      </ol>
    </nav>
  );
}
