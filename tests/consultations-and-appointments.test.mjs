import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const migrationPath = new URL("../supabase/migrations/20260923224020_post_go_consultations_and_appointments.sql", import.meta.url);
const workspacePath = new URL("../app/components/consultation-workspace.tsx", import.meta.url);
const centerPath = new URL("../app/components/consultation-center.tsx", import.meta.url);
const edgePath = new URL("../supabase/functions/consultation-ai/index.ts", import.meta.url);
const apiPath = new URL("../app/api/consultations/route.ts", import.meta.url);
const hardeningPath = new URL("../supabase/migrations/20260924014500_harden_consultation_ai_and_extension.sql", import.meta.url);
const prescriptionMigrationPath = new URL("../supabase/migrations/20260924214600_clinical_protocol_learning_and_prescription_documents.sql", import.meta.url);

test("agenda clínica bloqueia sobreposição no banco e não depende de venda", async () => {
  const sql = await readFile(migrationPath, "utf8");
  assert.match(sql, /exclude using gist[\s\S]*professional_id with =[\s\S]*tstzrange\(scheduled_start, scheduled_end, '\[\)'\) with &&/i);
  assert.match(sql, /where \(status in \('scheduled', 'confirmed', 'in_progress'\)\)/i);
  assert.doesNotMatch(sql, /insert into public\.attendances/i);
  assert.doesNotMatch(sql, /insert into public\.attendance_items/i);
  assert.match(sql, /Agenda clínica e prontuário longitudinal independentes do fluxo financeiro/i);
});

test("consultas têm RLS, snapshot imutável e permissão somente de leitura para Diretores do SR", async () => {
  const sql = await readFile(migrationPath, "utf8");
  assert.match(sql, /alter table public\.clinical_consultations force row level security/i);
  assert.match(sql, /Uma consulta concluída é imutável/i);
  assert.match(sql, /final_snapshot = v_snapshot/i);
  assert.match(sql, /where position\.code = 'diretores_sr'/i);
  assert.match(sql, /select position\.id, 'consultations\.view'/i);
  assert.doesNotMatch(sql, /select position\.id, 'consultations\.(?:create|complete|manage)'[\s\S]*where position\.code = 'diretores_sr'/i);
});

test("assistência de IA é idempotente, protegida e limita sugestões ao catálogo validado", async () => {
  const [sql, edge, hardening, prescription] = await Promise.all([readFile(migrationPath, "utf8"), readFile(edgePath, "utf8"), readFile(hardeningPath, "utf8"), readFile(prescriptionMigrationPath, "utf8")]);
  assert.match(sql, /unique \(consultation_id, action_type\)/i);
  assert.match(sql, /status = 'failed'[\s\S]*status = 'pending'/i);
  assert.match(sql, /jsonb_array_length\(p_response_payload->'options'\) <> 3/i);
  assert.match(edge, /store: false/);
  assert.match(edge, /const MODEL = "gpt-5\.6-luna"/);
  assert.match(edge, /exclusivamente por medication_id do catálogo fornecido/i);
  assert.match(edge, /Não invente medicamento, dose, frequência, duração ou via/i);
  assert.match(edge, /begin_consultation_ai_generation/);
  assert.match(edge, /complete_consultation_ai_generation/);
  assert.match(edge, /SUPABASE_SERVICE_ROLE_KEY/);
  assert.match(edge, /consultation\.can_edit !== true/);
  assert.match(hardening, /revoke all on function public\.begin_consultation_ai_generation[\s\S]*authenticated/i);
  assert.match(hardening, /grant execute on function public\.begin_consultation_ai_generation[\s\S]*service_role/i);
  assert.match(prescription, /complete_consultation_ai_generation_v3/);
  assert.match(prescription, /rp_medication_context_compatible/);
});

test("One Page implementa as nove etapas e mantém decisão humana", async () => {
  const workspace = await readFile(workspacePath, "utf8");
  for (const number of ["01", "02", "03", "04", "05", "06", "07", "08", "09"]) {
    assert.match(workspace, new RegExp(`number="${number}"`));
  }
  assert.match(workspace, /type="range" min=\{0\} max=\{10\}/);
  assert.match(workspace, /Continuar para o formulário/);
  assert.match(workspace, /Os dias são definidos manualmente pelo profissional/);
  assert.match(workspace, /Após a conclusão, o prontuário ficará imutável/);
});

test("Central oferece lista, dia, semana, minhas e demanda espontânea", async () => {
  const [center, api] = await Promise.all([readFile(centerPath, "utf8"), readFile(apiPath, "utf8")]);
  assert.match(center, /"list" \| "day" \| "week"/);
  assert.match(center, /> Minhas</);
  assert.match(center, /Consulta sem agendamento/);
  assert.match(api, /start_walk_in_consultation/);
  assert.match(api, /create_patient_appointment/);
  assert.match(api, /set_patient_appointment_status/);
});
