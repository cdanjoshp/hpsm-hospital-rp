import "jsr:@supabase/functions-js/edge-runtime.d.ts";

Deno.serve(() => new Response(
  JSON.stringify({ error: "Função temporária encerrada." }),
  { status: 410, headers: { "content-type": "application/json", "cache-control": "no-store" } },
));
