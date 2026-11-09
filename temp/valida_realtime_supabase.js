// Valida o Realtime do Supabase local (VM Ubuntu-Supabase, Kong :8001).
// Uso: ANON=<anon key> node temp/valida_realtime_supabase.js
// Fases: 1) WebSocket abre  2) JOIN do canal ok  3) broadcast ecoa de volta.
'use strict';
const WebSocket = require('ws');

const ANON = process.env.ANON;
if (!ANON) { console.error('Falta a variavel ANON (SUPABASE_ANON_KEY).'); process.exit(2); }

const base = process.env.SUPABASE_WS || 'ws://localhost:8001/realtime/v1/websocket';
const url = `${base}?vsn=1.0.0&apikey=${encodeURIComponent(ANON)}`;
const canal = 'realtime:validacao:supabase-local';

const resultados = { abre_websocket: false, join_ok: false, broadcast_eco: false };
let ref = 0;
const enviados = [];
const t0 = Date.now();
const ms = () => `${Date.now() - t0}ms`;

function fim(codigo, motivo) {
  console.log(`\n--- ${motivo} ---`);
  for (const [k, v] of Object.entries(resultados)) console.log(`${v ? 'PASS' : 'FAIL'}  ${k}`);
  try { ws.close(); } catch (_) {}
  setTimeout(() => process.exit(codigo), 200);
}

const ws = new WebSocket(url, {
  headers: { apikey: ANON, 'User-Agent': 'validacao-realtime-local' },
});

const timer = setTimeout(() => fim(1, 'tempo esgotado'), 15000);

ws.on('open', () => {
  resultados.abre_websocket = true;
  console.log(`[${ms()}] WebSocket aberto (subprotocolo ${ws.protocol || 'nenhum'})`);
  ref += 1;
  const msg = ['1', String(ref), canal, 'phx_join',
    { config: { broadcast: { self: true, private: false } }, access_token: ANON }];
  enviados.push({ ref: String(ref), tipo: 'join' });
  ws.send(JSON.stringify(msg));
  console.log(`[${ms()}] enviado phx_join -> ${canal}`);
});

ws.on('message', (buf) => {
  let m;
  try { m = JSON.parse(buf.toString()); } catch (e) { console.log(`[${ms()}] frame nao-JSON: ${buf.toString().slice(0, 120)}`); return; }
  const [joinRef, refSrv, topic, event, payload] = m;
  const resumo = JSON.stringify(payload).slice(0, 200);

  if (event === 'phx_reply' && payload && payload.status === 'ok' && enviados.some(e => e.ref === refSrv && e.tipo === 'join')) {
    resultados.join_ok = true;
    console.log(`[${ms()}] JOIN confirmado no topico ${topic}`);
    // fase 3: broadcast para o proprio canal (self: true)
    if (enviados.some(e => e.tipo === 'broadcast')) return;
    ref += 1;
    enviados.push({ ref: String(ref), tipo: 'broadcast' });
    ws.send(JSON.stringify(['1', String(ref), canal, 'broadcast',
      { type: 'broadcast', event: 'ping-validacao', payload: { ts: Date.now() } }]));
    console.log(`[${ms()}] enviado broadcast ping-validacao`);
    return;
  }

  if (event === 'broadcast') {
    resultados.broadcast_eco = true;
    console.log(`[${ms()}] broadcast recebido: ${resumo}`);
    console.log(`\n--- realtime local validado em ${ms()} ---`);
    for (const [k, v] of Object.entries(resultados)) console.log(`${v ? 'PASS' : 'FAIL'}  ${k}`);
    clearTimeout(timer);
    try { ws.close(); } catch (_) {}
    setTimeout(() => process.exit(0), 200);
    return;
  }

  console.log(`[${ms()}] ${topic} ${event}: ${resumo}`);
});

ws.on('error', (e) => { console.log(`[${ms()}] ERRO WebSocket: ${e.message}`); clearTimeout(timer); fim(1, 'erro de socket'); });
ws.on('close', (c, r) => { if (!resultados.broadcast_eco) { console.log(`[${ms()}] socket fechado: ${c} ${r}`); clearTimeout(timer); fim(1, 'socket fechado antes do eco'); } });
