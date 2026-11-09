const http = require('http');
const WebSocket = require('ws');
const { spawn } = require('child_process');

const chromePath = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const profile = 'C:\\Users\\charles\\AppData\\Local\\Temp\\cdp_exodo_profile';
const port = 9229;

const chrome = spawn(chromePath, [
  '--headless=new', '--disable-gpu', '--no-first-run',
  `--user-data-dir=${profile}`, `--remote-debugging-port=${port}`,
  'about:blank'
], { stdio: 'ignore' });

function get(path) {
  return new Promise((resolve, reject) => {
    http.get({ host: '127.0.0.1', port, path }, (r) => {
      let d = '';
      r.on('data', (c) => (d += c));
      r.on('end', () => { try { resolve(JSON.parse(d)); } catch (e) { reject(e); } });
    }).on('error', reject);
  });
}

async function waitChrome() {
  for (let i = 0; i < 60; i++) {
    try { return await get('/json/list'); } catch (e) { await new Promise((r) => setTimeout(r, 250)); }
  }
  throw new Error('Chrome nao respondeu');
}

(async () => {
  const tabs = await waitChrome();
  const target = tabs.find((t) => t.type === 'page') || tabs[0];
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  let id = 0;
  const pending = new Map();
  const events = [];
  const requests = new Map();

  function send(method, params = {}) {
    return new Promise((resolve, reject) => {
      const i = ++id;
      pending.set(i, { resolve, reject });
      ws.send(JSON.stringify({ id: i, method, params }));
    });
  }

  ws.on('message', (raw) => {
    const m = JSON.parse(raw);
    if (m.id && pending.has(m.id)) {
      const p = pending.get(m.id);
      pending.delete(m.id);
      if (m.error) p.reject(m.error); else p.resolve(m.result);
      return;
    }
    if (m.method === 'Runtime.consoleAPICalled') {
      events.push({ kind: 'console.' + m.params.type, text: m.params.args.map((a) => a.value ?? a.description ?? a.type).join(' ') });
    }
    if (m.method === 'Log.entryAdded') {
      const e = m.params.entry;
      events.push({ kind: 'log.' + e.level, text: e.text, url: e.url });
    }
    if (m.method === 'Network.requestWillBeSent') {
      requests.set(m.params.requestId, m.params.request.url);
    }
    if (m.method === 'Network.responseReceived') {
      const r = m.params.response;
      if (/servidorsupabase|neonauth|rest\/v1|empresas|auth|token|app\.env/.test(r.url)) {
        events.push({ kind: 'http', status: r.status, url: r.url });
      }
    }
    if (m.method === 'Network.loadingFailed') {
      events.push({ kind: 'failed', error: m.params.errorText, url: requests.get(m.params.requestId) });
    }
  });

  ws.on('open', async () => {
    await send('Runtime.enable');
    await send('Log.enable');
    await send('Network.enable');
    await send('Page.enable');
    await send('Page.navigate', { url: 'https://exodosystems-1541d.web.app/loja/e-o-bicho-petshop' });
    await new Promise((r) => setTimeout(r, 30000));
    console.log(JSON.stringify(events, null, 2));
    ws.close();
    chrome.kill();
  });
})().catch((e) => { console.error(e); chrome.kill(); process.exit(1); });
