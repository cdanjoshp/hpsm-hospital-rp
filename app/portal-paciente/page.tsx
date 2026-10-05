import { redirect } from "next/navigation";
import { PatientPortalError, PatientPortalFrame } from "../components/patient-portal-shell";
import { PatientPortalSummaryView } from "../components/patient-portal-summary";
import { getPatientPortalSummary } from "../lib/patient-portal";

export const dynamic = "force-dynamic";

export default async function PatientPortalPage({
  searchParams,
}: {
  searchParams: Promise<{ portalError?: string | string[] }>;
}) {
  const params = await searchParams;
  const errorCode = Array.isArray(params.portalError) ? params.portalError[0] : params.portalError;
  let summary = null;
  let summaryFailed = false;
  try {
    summary = await getPatientPortalSummary();
  } catch {
    summaryFailed = true;
  }

  if (!summary && !summaryFailed) {
    redirect(errorCode ? "/?access=patient&portalError=invalid" : "/?access=patient");
  }

  const logoutFailed = errorCode === "logout" && summary;
  return (
    <PatientPortalFrame>
      {logoutFailed
        ? <PatientPortalError
            message="Sua sessão continua protegida e ativa. Volte ao Portal e tente sair novamente."
            title="Não foi possível encerrar sua sessão com segurança."
          />
        : summary ? <PatientPortalSummaryView data={summary} /> : <PatientPortalError />}
    </PatientPortalFrame>
  );
}
