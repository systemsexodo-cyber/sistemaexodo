// Valida o caminho CDC do Realtime local: INSERT via PostgREST -> evento postgres_changes.
// Uso: SUPABASE_URL=http://localhost:8001 SERVICE_KEY=<service role> node temp/valida_postgres_changes.js
'use strict';
const { createClient } = require('@supabase/supabase-js');

const url = process.env.SUPABASE_URL || 'http://localhost:8001';
const key = process.env.SERVICE_KEY;
if (!key) { console.error('Falta SERVICE_KEY (SUPABASE_SERVICE_ROLE_KEY).'); process.exit(2); }

const TABELA = '_teste_agente';
const marcador = `validacao-realtime-${Date.now()}`;
const sb = createClient(url, key, { auth: { persistSession: false } });
const t0 = Date.now();
const ms = () => `[${Date.now() - t0}ms]`;
let concluido = false;

async function limpar() {
  try {
    const { error } = await sb.from(TABELA).delete().eq('nome', marcador);
    if (error) console.log(`${ms()} limpeza: ${error.message}`);
    else console.log(`${ms()} linha de teste removida.`);
  } catch (e) { console.log(`${ms()} limpeza falhou: ${e.message}`); }
}

const canal = sb.channel('validacao-cdc', {
  // WAIT=1 (padrão) -> SUBSCRIBED só quando o servidor confirma a assinatura
  // postgres_changes. WAIT=0 reproduz o comportamento padrão (pode assinar
  // antes de a assinatura estar ativa -> corrida documentada).
  config: process.env.WAIT === '0'
    ? {}
    : { postgres_changes_options: { wait: true, timeout: 10000 } },
});
canal.on('postgres_changes', { event: 'INSERT', schema: 'public', table: TABELA }, async (payload) => {
  console.log(`${ms()} EVENTO RECEBIDO: ${JSON.stringify(payload.new).slice(0, 200)}`);
  if (payload.new && payload.new.nome === marcador) {
    concluido = true;
    console.log('PASS postgres_changes (INSERT chegou via Realtime)');
    await limpar();
    process.exit(0);
  }
});

canal.subscribe(async (status, err) => {
  console.log(`${ms()} status: ${status}`, err ? `erro=${JSON.stringify(err)}` : '');
  if (status === 'SUBSCRIBED') {
    const atraso = Number(process.env.ATRASO || 0);
    console.log(`${ms()} -> SUBSCRIBED; INSERT em ${atraso}ms (marcador ${marcador})`);
    setTimeout(async () => {
      const { error } = await sb.from(TABELA).insert({ nome: marcador });
      if (error) { console.log(`${ms()} FAIL insert: ${error.message}`); process.exit(1); }
      console.log(`${ms()} -> INSERT enviado via PostgREST`);
    }, atraso);
  }
  if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
    console.log(`${ms()} FAIL estado do canal: ${status}`);
    await limpar();
    process.exit(1);
  }
});

setTimeout(async () => {
  if (concluido) return;
  console.log(`--- fim em 25s sem evento (estado=${canal.state}) ---`);
  console.log('FAIL nenhum evento postgres_changes recebido');
  await limpar();
  process.exit(1);
}, 25000);
