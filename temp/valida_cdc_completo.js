// Valida INSERT + UPDATE + DELETE no Realtime local (postgres_changes, event '*').
// Uso: SUPABASE_URL=http://localhost:8001 SERVICE_KEY=<service role> node temp/valida_cdc_completo.js
'use strict';
const { createClient } = require('@supabase/supabase-js');

const url = process.env.SUPABASE_URL || 'http://localhost:8001';
const key = process.env.SERVICE_KEY;
const TABELA = '_teste_agente';
const marcador = `validacao-cdc-${Date.now()}`;
const sb = createClient(url, key, { auth: { persistSession: false } });
const t0 = Date.now();
const ms = () => `[${Date.now() - t0}ms]`;

const vistos = { INSERT: false, UPDATE: false, DELETE: false };

async function limpar() {
  try { await sb.from(TABELA).delete().eq('nome', marcador); } catch (_) {}
}

const canal = sb.channel('validacao-cdc-completo', {
  config: { postgres_changes_options: { wait: true, timeout: 10000 } },
});

canal.on('postgres_changes', { event: '*', schema: 'public', table: TABELA }, async (payload) => {
  const ev = payload.eventType;
  if (!vistos[ev]) {
    vistos[ev] = true;
    console.log(`${ms()} evento ${ev}: ${JSON.stringify(payload.new || payload.old).slice(0, 160)}`);
  }
  if (vistos.INSERT && vistos.UPDATE && vistos.DELETE) {
    console.log('PASS INSERT + UPDATE + DELETE recebidos via Realtime');
    await limpar();
    process.exit(0);
  }
  if (ev === 'INSERT') {
    await sb.from(TABELA).update({ nome: marcador + '-u' }).eq('nome', marcador);
    console.log(`${ms()} -> UPDATE enviado`);
  }
  if (ev === 'UPDATE') {
    await sb.from(TABELA).delete().eq('nome', marcador + '-u');
    console.log(`${ms()} -> DELETE enviado`);
  }
});

canal.subscribe(async (status, err) => {
  console.log(`${ms()} status: ${status}`, err ? `erro=${JSON.stringify(err)}` : '');
  if (status === 'SUBSCRIBED') {
    const { error } = await sb.from(TABELA).insert({ nome: marcador });
    if (error) { console.log(`${ms()} FAIL insert: ${error.message}`); process.exit(1); }
    console.log(`${ms()} -> INSERT enviado`);
  }
  if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
    console.log(`${ms()} FAIL estado do canal: ${status}`);
    await limpar();
    process.exit(1);
  }
});

setTimeout(async () => {
  console.log(`--- fim em 25s: ${JSON.stringify(vistos)} ---`);
  console.log(vistos.INSERT && vistos.UPDATE && vistos.DELETE
    ? 'PASS' : 'FAIL nem todos os eventos chegaram');
  await limpar();
  process.exit(vistos.INSERT && vistos.UPDATE && vistos.DELETE ? 0 : 1);
}, 25000);
