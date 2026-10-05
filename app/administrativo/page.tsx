import { AdministrativeHome } from "../components/administrative-home";
import { requireAdministrativeContext } from "../lib/administrative-server";

export const dynamic = "force-dynamic";

export default async function AdministrativePage() {
  const { permissionCodes } = await requireAdministrativeContext();
  return <AdministrativeHome permissionCodes={permissionCodes} />;
}
