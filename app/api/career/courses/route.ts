// Registros legados permanecem disponíveis para consulta. Novos cursos e notas
// seguem exclusivamente o fluxo autenticado e auditado da Academia HPSM.
export async function POST() {
  return Response.json({ error: "Use a Gestão da Academia HPSM para cursos e resultados." }, { status: 410 });
}
