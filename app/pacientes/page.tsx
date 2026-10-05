import { redirect } from "next/navigation";
import { AppFrame } from "../components/app-frame";
import { PatientCenter } from "../components/patient-center";
import { getEffectivePermissionCodes } from "../lib/access";
import { getPatientCardPage, type PatientCardFilter } from "../lib/patient-center";
import { getSessionContext } from "../lib/session";

export const dynamic = "force-dynamic";

export default async function PatientsPage({ searchParams }: { searchParams: Promise<{ search?: string; filter?: string; page?: string }> }) {
  const context = await getSessionContext();
  if (!context) redirect("/");
  if (context.profile.must_change_password) redirect("/primeiro-acesso");

  const permissions = await getEffectivePermissionCodes(context.profile.user_id);
  if (!permissions.includes("patients.view")) redirect("/painel");
  const params = await searchParams;
  const allowedFilters: PatientCardFilter[] = ["all", "active", "expired", "partner", "police", "none"];
  const filter = typeof params.filter === "string" && allowedFilters.includes(params.filter as PatientCardFilter) ? params.filter as PatientCardFilter : "all";
  const search = typeof params.search === "string" ? params.search.slice(0, 100) : "";
  const pageNumber = Number(params.page);
  const page = Number.isInteger(pageNumber) && pageNumber >= 1 && pageNumber <= 100000 ? pageNumber : 1;
  const initialData = await getPatientCardPage(context.accessToken, { filter, page, pageSize: 20, search });

  return (
    <AppFrame
      active="patients"
      profile={context.profile}
      title="Central de Pacientes"
      description="Localize pacientes e acesse os fluxos clínicos do HPSM."
    >
      <PatientCenter initialData={initialData} initialFilter={filter} initialSearch={search} permissionCodes={permissions} />
    </AppFrame>
  );
}
