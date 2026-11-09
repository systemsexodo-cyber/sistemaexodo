// Valida o Realtime do Supabase local com o cliente oficial.
// Uso: ANON=<key> SUPABASE_URL=http://localhost:8001 node temp/valida_realtime_official.js
'use strict';
const { createClient } = require('@supabase/supabase-js');

const url = process.env.SUPABASE_URL || 'http://localhost:8001';
const key = process.env.ANON;
if (!key) { console.error('Falta ANON'); process.exit(2); }

const sb = createClient(url, key, { auth: { persistSession: false } });
const t0 = Date.now();
const ms = () => `[${Date.now() - t0}ms]`;
let recebi = false;

const canal = sb.channel('validacao-local', { config: { broadcast: { self: true, private: false } } });

canal.on('broadcast', { event: 'ping' }, (msg) => {
  recebi = true;
  console.log(`${ms()} BROADCAST RECEBIDO:`, JSON.stringify(msg));
  console.log('PASS broadcast round-trip via cliente oficial');
  process.exit(0);
});

canal.subscribe((status, err) => {
  console.log(`${ms()} status do canal: ${status}`, err ? `erro=${JSON.stringify(err)}` : '');
  if (status === 'SUBSCRIBED') {
    console.log('PASS canal SUBSCRIBED');
    canal.send({ type: 'broadcast', event: 'ping', payload: { ts: Date.now() } });
    console.log(`${ms()} -> broadcast enviado (aguardando eco)`);
  }
  if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
    console.log(`FAIL estado ${status}`);
    setTimeout(() => process.exit(1), 300);
  }
});

setTimeout(() => {
  console.log(`--- fim em 20s: recebi=${recebi} estado=${canal.state} ---`);
  console.log(recebi ? 'PASS broadcast' : 'FAIL sem eco de broadcast em 20s');
  process.exit(recebi ? 0 : 1);
}, 20000);
