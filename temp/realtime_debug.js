// Depura o handshake do Supabase Realtime local: imprime TODOS os frames crus
// e respostas do servidor, com heartbeat, para ver por que o JOIN não responde.
// Uso: ANON=<key> node temp/realtime_debug.js
'use strict';
const WebSocket = require('ws');
const ANON = process.env.ANON;
const url = `ws://localhost:8001/realtime/v1/websocket?vsn=1.0.0&apikey=${encodeURIComponent(ANON)}`;
const t0 = Date.now();
const ms = () => `[${Date.now() - t0}ms]`;

const ws = new WebSocket(url, { headers: { apikey: ANON } });
ws.on('open', () => {
  console.log(ms(), 'aberto. protocolo:', ws.protocol || '(nenhum)', 'resposta:', JSON.stringify(ws.response?.headers || {}));
  ws.send(JSON.stringify(['1', '1', 'realtime:dbg', 'phx_join',
    { config: { broadcast: { self: true, private: false } }, access_token: ANON }]));
  console.log(ms(), '-> join enviado');
  const hb = setInterval(() => {
    if (ws.readyState !== 1) return clearInterval(hb);
    ws.send(JSON.stringify(['', '2', 'phoenix', 'heartbeat', {}]));
    console.log(ms(), '-> heartbeat');
  }, 3000);
  setTimeout(() => { clearInterval(hb); ws.close(); }, 9000);
});
ws.on('message', (d, isBinary) => console.log(ms(), '<- binario=' + isBinary, d.toString().slice(0, 500)));
ws.on('unexpected-response', (req, res) => console.log(ms(), '<- HTTP inesperado', res.statusCode, res.statusMessage));
ws.on('error', (e) => console.log(ms(), 'ERRO', e.message));
ws.on('close', (c, r) => console.log(ms(), 'fechado', c, r && r.toString()));
