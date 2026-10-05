"use client";

import { useMemo, useState } from "react";
import { useAppRefresh } from "../lib/client-refresh";
import { staffIdentity } from "../lib/staff-identity";

type PreviewRow = {
  differenceMinutes: number | null;
  line: number;
  message: string;
  name: string | null;
  passport: string;
  positionName: string | null;
  previousMinutes: number | null;
  status: "found" | "invalid" | "unknown";
  totalMinutes: number | null;
};

type Preview = {
  counts: { found: number; invalid: number; unknown: number };
  rows: PreviewRow[];
};

export function HoursBulkImport() {
  const refreshApp = useAppRefresh();
  const [readingDate, setReadingDate] = useState(todayIso());
  const [source, setSource] = useState("");
  const [preview, setPreview] = useState<Preview | null>(null);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState<{ kind: "error" | "success"; text: string } | null>(null);
  const assistedPreview = useMemo(() => analyzeSource(source), [source]);

  function organizeInput() {
    setSource(source.split(/\r?\n/).map(normalizeImportLine).join("\n"));
    setPreview(null);
    setMessage({ kind: "success", text: "Formato organizado. Confira a lista e clique em Verificar lista." });
  }

  async function run(action: "preview" | "confirm") {
    if (loading) return;
    setLoading(true);
    setMessage(null);
    try {
      const response = await fetch("/api/hr/hours/import", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ action, readingDate, text: source }),
      });
      const payload = (await response.json()) as Preview & { error?: string };
      if (!response.ok) {
        setMessage({ kind: "error", text: payload.error ?? "Não foi possível processar a lista." });
        if (payload.rows) setPreview(payload);
        return;
      }
      setPreview(payload);
      if (action === "confirm") {
        setMessage({ kind: "success", text: `${payload.counts.found} leitura(s) salva(s). Os acumulados e a virada do mês foram tratados automaticamente.` });
        refreshApp(900);
      }
    } catch {
      setMessage({ kind: "error", text: "Não foi possível processar a lista. Verifique sua conexão." });
    } finally {
      setLoading(false);
    }
  }

  return (
    <details className="management-card bulk-hours-import">
      <summary><span><strong>Importar horas em lote</strong><small>Cole a lista do sistema da cidade e confira antes de salvar</small></span><b>＋</b></summary>
      <div className="bulk-import-body">
        <div className="bulk-import-fields">
          <label>Data da leitura<input type="date" max={todayIso()} value={readingDate} onChange={(event) => { setReadingDate(event.target.value); setPreview(null); }} /></label>
          <label>Leituras acumuladas<textarea rows={7} value={source} onChange={(event) => { setSource(event.target.value); setPreview(null); setMessage(null); }} placeholder={"0532 37:42\n0781 29:10\n1142 41:27"} /></label>
          <p>Uma linha por colaborador. Aceitamos espaço, tabulação ou ponto e vírgula; as horas podem vir como <strong>37:42</strong>, <strong>37h42</strong> ou <strong>37.42</strong>.</p>
          {source.trim() ? <div className="bulk-assisted-status" role="status"><span>{assistedPreview.lines} linha(s)</span><span data-status={assistedPreview.invalid ? "invalid" : "found"}>{assistedPreview.invalid ? `${assistedPreview.invalid} precisa(m) de correção` : "Formato reconhecido"}</span></div> : null}
          <div className="bulk-import-actions"><button className="secondary-button" type="button" disabled={loading || !source.trim()} onClick={organizeInput}>Organizar formato</button><button className="secondary-button" type="button" disabled={loading || !source.trim()} onClick={() => run("preview")}>{loading ? "Verificando…" : "Verificar lista"}</button></div>
        </div>
        {preview ? <div className="bulk-import-preview">
          <div className="bulk-import-counts"><span data-status="found">{preview.counts.found} encontrados</span><span data-status="invalid">{preview.counts.invalid} inválidos</span><span data-status="unknown">{preview.counts.unknown} desconhecidos</span></div>
          <div className="bulk-import-table"><div className="bulk-import-row bulk-import-head"><span>Linha</span><span>Colaborador</span><span>Novo total</span><span>Diferença</span><span>Situação</span></div>{preview.rows.map((row) => <div className="bulk-import-row" key={`${row.line}-${row.passport}`} data-status={row.status}><span>{row.line}</span><span><strong>{row.name ?? (row.passport ? `Passaporte ${row.passport}` : "Formato inválido")}</strong><small>{row.name ? staffIdentity(row.passport, row.positionName) : row.message}</small>{row.name ? <small>{row.message}</small> : null}</span><span>{formatMinutes(row.totalMinutes)}</span><span>{row.differenceMinutes === null ? "—" : `+${formatMinutes(row.differenceMinutes)}`}</span><span><em>{statusLabel(row.status)}</em></span></div>)}</div>
          <div className="bulk-import-confirm"><p>Somente os registros encontrados serão gravados.</p><button className="submit-button" type="button" disabled={loading || !preview.counts.found} onClick={() => run("confirm")}>{loading ? "Salvando…" : `Confirmar ${preview.counts.found} leitura(s)`}</button></div>
        </div> : null}
      </div>
      {message ? <p className={message.kind === "success" ? "form-success" : "form-error"} role="status">{message.text}</p> : null}
    </details>
  );
}

function statusLabel(status: PreviewRow["status"]) { return ({ found: "Pronto", invalid: "Inválido", unknown: "Não encontrado" } as const)[status]; }
function normalizeImportLine(line: string) {
  const value = line.trim().replace(/\t+/g, " ").replace(/\s*;\s*/g, " ").replace(/\s+/g, " ");
  const match = value.match(/^(\d{1,4})\s+(\d{1,3})\s*[hH.:]\s*([0-5]\d)$/);
  return match ? `${match[1]} ${match[2]}:${match[3]}` : value;
}
function analyzeSource(value: string) {
  const rows = value.split(/\r?\n/).filter((line) => line.trim());
  return { lines: rows.length, invalid: rows.filter((line) => !/^(\d{1,4})\s+(\d{1,3}):([0-5]\d)$/.test(normalizeImportLine(line))).length };
}
function formatMinutes(total: number | null) { if (total === null) return "—"; return `${Math.floor(total / 60)}h${String(total % 60).padStart(2, "0")}`; }
function todayIso() { const parts = new Intl.DateTimeFormat("en-US", { day: "2-digit", month: "2-digit", timeZone: "America/Sao_Paulo", year: "numeric" }).formatToParts(new Date()); const values = Object.fromEntries(parts.map((part) => [part.type, part.value])); return `${values.year}-${values.month}-${values.day}`; }
