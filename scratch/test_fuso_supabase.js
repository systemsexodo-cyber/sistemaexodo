const https = require('https');
const { URL } = require('url');
const URLBASE = 'https://febffvlpvxtiihvnfuts.supabase.co';
const KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZlYmZmdmxwdnh0aWlodm5mdXRzIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NjA1MjA3NSwiZXhwIjoyMDkxNjI4MDc1fQ.r7-IAXHz7hAEjmYIM4pO9uqIaFYwaOZQucKw6DoblhE';

function req(method, path, body) {
  return new Promise((resolve, reject) => {
    const u = new URL(URLBASE + path);
    const data = body ? JSON.stringify(body) : null;
    const r = https.request(u, {
      method: method,
      headers: {
        'apikey': KEY,
        'Authorization': 'Bearer ' + KEY,
        'Content-Type': 'application/json'
      }
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

(async () => {
  const naive = '2026-08-14T14:30:00.000000'; // 14:30 BRT = 17:30 UTC
  const utc = '2026-08-14T17:30:00.000Z';
  const id = 'teste-fuso-' + Date.now();
  const EMP = '22ae2c16-a730-43f3-a4f9-19f105eb0d13';
  const ra = await req('POST', '/rest/v1/aberturas_caixa', { id: id + 'a', numero: 'TESTE-A', empresa_id: EMP, data_abertura: naive });
  console.log('POST naive status', ra.status, ra.body.slice(0, 120));
  const rb = await req('POST', '/rest/v1/aberturas_caixa', { id: id + 'b', numero: 'TESTE-B', empresa_id: EMP, data_abertura: utc });
  console.log('POST utc status', rb.status, rb.body.slice(0, 120));
  const chk = await req('GET', `/rest/v1/aberturas_caixa?id=like.teste-fuso-*&select=id,data_abertura`);
  console.log('Linhas de teste:');
  console.log(JSON.stringify(JSON.parse(chk.body), null, 1));
  await req('DELETE', '/rest/v1/aberturas_caixa?id=like.teste-fuso-*');
  console.log('Limpeza ok.');
})();
