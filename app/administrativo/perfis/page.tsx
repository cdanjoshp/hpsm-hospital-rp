import { AdministrativeBreadcrumb } from "../../components/administrative-breadcrumb";
import { FunctionalProfile } from "../../components/functional-profile";
import { getStaffPositions } from "../../lib/access";
import { getManagedProfiles } from "../../lib/admin-data";
import { requireAdministrativeContext } from "../../lib/administrative-server";

export const dynamic = "force-dynamic";

export default async function AdministrativeProfilesPage({ searchParams }: { searchParams: Promise<{ selecionar?: string }> }) {
  const { context } = await requireAdministrativeContext("profiles");
  const initialSelectedId = (await searchParams).selecionar;
  const [profiles, positions] = await Promise.all([getManagedProfiles().catch(() => []), getStaffPositions().catch(() => [])]);

  return <div className="administrative-domain">
    <AdministrativeBreadcrumb current="profiles" />
    <FunctionalProfile canManageIdentity={context.positionLevel === 14} initialSelectedId={initialSelectedId} profiles={profiles} positions={positions} />
  </div>;
}
