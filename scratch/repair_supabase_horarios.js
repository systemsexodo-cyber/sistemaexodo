const https = require('https');
const { URL } = require('url');
const URLBASE = 'https://febffvlpvxtiihvnfuts.supabase.co';
const KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZlYmZmdmxwdnh0aWlodm5mdXRzIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NjA1MjA3NSwiZXhwIjoyMDkxNjI4MDc1fQ.r7-IAXHz7hAEjmYIM4pO9uqIaFYwaOZQucKw6DoblhE';

function req(method, path, body, extraHeader) {
  return new Promise((resolve, reject) => {
    const u = new URL(URLBASE + path);
    const data = body ? JSON.stringify(body) : null;
    const headers = {
      'apikey': KEY,
      'Authorization': 'Bearer ' + KEY,
      'Content-Type': 'application/json',
      'Prefer': 'return=minimal'
    };
    if (extraHeader) {
      const idx = extraHeader.indexOf(':');
      headers[extraHeader.slice(0, idx).trim()] = extraHeader.slice(idx + 1).trim();
    }
    const r = https.request(u, {
      method: method,
      headers: headers
    }, (resp) => {
      let d = '';
      resp.on('data', (c) => d += c);
      resp.on('end', () => resolve({ status: resp.statusCode, body: d }));
    });
    r.on('error', reject);
    if (data) r.write(data);
    r.end();
  });
}

function diffMin(a, b) {
  const da = new Date(a), db = new Date(b);
  if (isNaN(da) || isNaN(db)) return null;
  return Math.round((da - db) / 60000);
}

async function getRows(t) {
  const out = [];
  let from = 0;
  while (true) {
    const r = await req('GET', `/rest/v1/${t}?select=*&order=created_at.asc`, null, `Range: ${from}-${from + 999}`);
    if (r.status !== 200) {
      throw new Error(`GET ${t} HTTP ${r.status}: ${r.body.slice(0, 300)}`);
    }
    let rows;
    try {
      rows = JSON.parse(r.body);
    } catch (e) {
      throw new Error(`GET ${t} JSON invalido: ${r.body.slice(0, 300)}`);
    }
    if (!Array.isArray(rows)) {
      throw new Error(`GET ${t} resposta nao-array: ${JSON.stringify(rows).slice(0, 300)}`);
    }
    out.push(...rows);
    if (rows.length < 1000) break;
    from += 1000;
  }
  return out;
}

(async () => {
  const configs = [
    { t: 'aberturas_caixa', f: 'data_abertura', camel: ['dataAbertura'] },
    { t: 'fechamentos_caixa', f: 'data_fechamento', camel: ['dataFechamento'] },
    { t: 'sangrias_caixa', f: 'data_operacao', camel: ['dataOperacao'] },
    { t: 'suprimentos_caixa', f: 'data_operacao', camel: ['dataOperacao'] },
  ];
  for (const cfg of configs) {
    const rows = await getRows(cfg.t);
    let fixed = 0, skipped = 0;
    for (const row of rows) {
      const dv = row[cfg.f], ref = row.created_at;
      if (dv == null || ref == null) { skipped++; continue; }
      const d = diffMin(dv, ref);
      if (d === 0) { skipped++; continue; }
      if (d % 180 !== 0) {
        console.log(`  WARN ${cfg.t} ${row.id}: desvio ${d}min nao multiplo de 3h — NAO alterado`);
        skipped++;
        continue;
      }
      const body = {};
      body[cfg.f] = ref;
      for (const c of cfg.camel) if (row[c] != null) body[c] = ref;
      const resp = await req('PATCH', `/rest/v1/${cfg.t}?id=eq.${encodeURIComponent(row.id)}`, body);
      if (resp.status >= 200 && resp.status < 300) {
        fixed++;
        console.log(`  OK ${cfg.t} ${row.id}: ${cfg.f} ${dv} -> ${ref}`);
      } else {
        console.log(`  ERR ${cfg.t} ${row.id}: HTTP ${resp.status} ${resp.body.slice(0, 150)}`);
      }
    }
    console.log(`= ${cfg.t}: ${fixed} corrigidos, ${skipped} ok`);
  }
})();
