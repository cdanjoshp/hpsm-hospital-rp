import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("os 14 níveis mantêm seus códigos e recebem exatamente os nomes do RP", async () => {
  const sql = await read("supabase/migrations/20260929190000_rename_official_staff_positions.sql");
  const actual = [...sql.matchAll(/\('([^']+)', (\d+), '([^']+)'\)/g)].map(([, code, level, name]) => [Number(level), code, name]);
  assert.deepEqual(actual, [
    [1, "estagiario_enfermagem", "Estagiário de Enfermagem"],
    [2, "socorrista", "Estagiário de Medicina"],
    [3, "enfermeiro", "Auxiliar de Enfermagem"],
    [4, "residente_i", "Técnico de Enfermagem"],
    [5, "medico_junior", "Enfermeiro"],
    [6, "medico", "Enfermeiro Chefe"],
    [7, "medico_pleno", "Médico 3"],
    [8, "medico_senior", "Médico 2"],
    [9, "especialista", "Médico 1"],
    [10, "especialista_senior", "Médico Cirurgião"],
    [11, "supervisor_clinico", "Médico Chefe"],
    [12, "coordenador_clinico", "Diretor Administrativo"],
    [13, "diretor_clinico", "Diretor Executivo"],
    [14, "diretor_geral", "Diretor Geral"],
  ]);
  assert.match(sql, /set name = names\.name/);
  assert.match(sql, /v_updated <> 14/);
  const renameBlock = sql.split("create or replace function public.appoint_staff_position(", 1)[0];
  assert.doesNotMatch(renameBlock, /update public\.(?:position_permissions|staff_position_permissions|system_permissions|profiles)\b/i);
});

test("a função de nomeação só troca o nome citado na mensagem", async () => {
  const [current, original] = await Promise.all([
    read("supabase/migrations/20260929190000_rename_official_staff_positions.sql"),
    read("supabase/migrations/20260922201203_post_go_cast_references_and_multiple_directors.sql"),
  ]);
  const marker = "create or replace function public.appoint_staff_position(";
  const updated = marker + current.split(marker, 2)[1];
  const baseline = marker + original.split(marker, 2)[1].split("revoke all on function public.override_staff_position(", 1)[0];
  assert.equal(updated.trim(), baseline.replace("Somente o Diretor Geral pode nomear o Diretor Clínico.", "Somente o Diretor Geral pode nomear o Diretor Executivo.").trim());
});
