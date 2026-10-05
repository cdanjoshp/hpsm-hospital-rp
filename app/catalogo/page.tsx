import { redirect } from "next/navigation";
import { AppFrame } from "../components/app-frame";
import { CatalogManagement } from "../components/catalog-management";
import { getEffectivePermissionCodes } from "../lib/access";
import { getServiceCatalog } from "../lib/operational-data";
import type { CatalogService } from "../lib/operational-data";
import { getSessionContext } from "../lib/session";

export const dynamic = "force-dynamic";

export default async function CatalogPage({ searchParams }: { searchParams: Promise<{ item?: string }> }) {
  const context = await getSessionContext();
  if (!context) redirect("/");
  if (context.profile.must_change_password) redirect("/primeiro-acesso");
  const permissionCodes = await getEffectivePermissionCodes(context.profile.user_id);
  const canManage = permissionCodes.includes("catalog.manage");
  if (!canManage && !permissionCodes.includes("catalog.view")) redirect("/painel");

  const focusedItem = Number((await searchParams).item);
  let services: CatalogService[] = [];
  try { services = await getServiceCatalog(context.accessToken); } catch { services = []; }

  return (
    <AppFrame
      active="catalog"
      profile={context.profile}
      title="Tabela de Preços"
      description={canManage ? "Administre o catálogo, os preços, os descontos e as imagens dos itens." : "Consulte preços, descontos e benefícios vigentes."}
    >
      <CatalogManagement canManage={canManage} initialEditingId={canManage && Number.isSafeInteger(focusedItem) ? focusedItem : undefined} initialServices={services} />
    </AppFrame>
  );
}
