#!/usr/bin/env node
'use strict';

// Painel local de contingencia. Escuta somente em loopback; nao depende do
// Portal, Supabase, Tailscale ou internet para emitir uma licenca assinada.
//
// Emite os dois documentos aceitos pelo aplicativo:
//   - instalacao: libera o primeiro boot de um computador (o gate do sistema);
//   - emergencial: libera uma empresa bloqueada por falta de mensalidade.
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const HOST = '127.0.0.1';
const PORT = 8797;
const home = process.env.USERPROFILE || process.env.HOME;
const arquivoChave = path.join(
  home, 'Documents', 'ExodoLicencasPrivadas', 'chave_privada_exodo.pem',
);
const pastaSaida = path.join(home, 'Documents', 'LicencasEmitidasExodo');

const pagina = String.raw`<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Êxodo | Painel de licenças</title>
<style>
*{box-sizing:border-box}body{margin:0;min-height:100vh;background:#0b0d12;color:#f4f5f7;font:15px Segoe UI,Arial,sans-serif;display:grid;place-items:center;padding:24px}
main{width:min(100%,620px);background:#171b24;border:1px solid #303746;border-radius:20px;padding:28px;box-shadow:0 22px 70px #0008}
h1{margin:0 0 8px;font-size:25px}p{color:#aab3c2;line-height:1.5}.tag{display:inline-block;color:#f2b84b;background:#3a2c13;padding:6px 10px;border-radius:20px;font-size:12px;font-weight:700;margin-bottom:14px}
.tipos{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:14px}
.tipo{display:block;padding:12px;border-radius:10px;border:1px solid #424b5c;background:#0e121a;cursor:pointer;margin:0;font-weight:400}
.tipo:has(input:checked){border-color:#d99126;background:#1d2027}
.tipo input{accent-color:#d99126;margin-right:6px}
.tipo b{display:block;margin:6px 0 3px;font-size:13px}
.tipo span{display:block;color:#8994a5;font-size:11px;line-height:1.35}
label{display:block;margin:16px 0 7px;font-weight:600}input,select{width:100%;padding:12px;border-radius:9px;border:1px solid #424b5c;background:#0e121a;color:#fff;font:inherit}
button{margin-top:22px;width:100%;padding:14px;border:0;border-radius:10px;background:#d99126;color:#17120a;font-weight:800;font-size:14px;cursor:pointer}
button:disabled{opacity:.55;cursor:wait}.hint{font-size:12px;color:#8994a5}.result{display:none;margin-top:18px;padding:14px;border-radius:10px;background:#102b20;border:1px solid #276b48;color:#a9f0c5;white-space:pre-wrap}.error{background:#32191b;border-color:#79363b;color:#ffb9bd}
footer{border-top:1px solid #303746;margin-top:22px;padding-top:14px;color:#8994a5;font-size:12px}
</style></head><body><main>
<div class="tag">MODO DE CONTINGÊNCIA · SEM INTERNET</div>
<h1>Painel de licenças Êxodo</h1>
<p>Gere a licença neste computador administrativo. Ela é assinada localmente e vinculada à máquina informada; nenhum dado sai deste PC.</p>
<form id="form">
<div class="tipos">
<label class="tipo"><input type="radio" name="tipo" value="instalacao" checked><b>Ativar computador</b><span>Licença de instalação, exigida no boot. Não precisa de empresa.</span></label>
<label class="tipo"><input type="radio" name="tipo" value="emergencial"><b>Liberar empresa</b><span>Licença emergencial para a tela de bloqueio. Exige a empresa.</span></label>
</div>
<label for="empresa" id="rotulo-empresa">ID da empresa (opcional)</label><input id="empresa" autocomplete="off" placeholder="UUID da empresa">
<label for="maquina">ID da máquina (64 caracteres)</label><input id="maquina" required minlength="64" maxlength="64" pattern="[a-fA-F0-9]{64}" autocomplete="off" placeholder="Exibido na tela de licença do cliente">
<label for="nome">Nome do computador</label><input id="nome" required maxlength="100" placeholder="Ex.: CAIXA-01">
<label for="dias">Validade</label><select id="dias"><option value="7">7 dias</option><option value="15">15 dias</option><option value="30" selected>30 dias</option></select>
<button id="emitir" type="submit">ASSINAR E GERAR ARQUIVO</button>
</form>
<div id="resultado" class="result" role="status"></div>
<footer>A chave privada permanece neste computador e não é enviada ao cliente. O painel aceita somente conexões locais.</footer>
</main>
<script>
const form=document.getElementById('form'),btn=document.getElementById('emitir'),box=document.getElementById('resultado');
const empresa=document.getElementById('empresa'),rotulo=document.getElementById('rotulo-empresa');
function tipoAtual(){return document.querySelector('input[name="tipo"]:checked').value}
function atualizarTipo(){const inst=tipoAtual()==='instalacao';rotulo.textContent=inst?'ID da empresa (opcional)':'ID da empresa';empresa.required=!inst;empresa.placeholder=inst?'Pode ficar vazio':'UUID da empresa';}
document.querySelectorAll('input[name="tipo"]').forEach(r=>r.addEventListener('change',atualizarTipo));atualizarTipo();
form.addEventListener('submit',async e=>{
 e.preventDefault();btn.disabled=true;btn.textContent='ASSINANDO...';box.style.display='none';box.className='result';
 try{
  const dados={tipo:tipoAtual(),empresaId:empresa.value.trim(),maquinaId:document.getElementById('maquina').value.trim(),maquinaNome:document.getElementById('nome').value.trim(),dias:Number(document.getElementById('dias').value)};
  const resposta=await fetch('/emitir',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(dados)});
  const resultado=await resposta.json();if(!resposta.ok)throw new Error(resultado.erro||'Falha ao gerar licença.');
  const blob=new Blob([JSON.stringify(resultado.documento,null,2)],{type:'application/json'});
  const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=resultado.nome;a.click();URL.revokeObjectURL(url);
  const expira=new Date(resultado.documento.payload.expires_at).toLocaleString('pt-BR');
  const instrucao=resultado.tipo==='instalacao'
    ?'No cliente, abra o sistema, clique em "Sem internet? Aplicar licença offline" e escolha este arquivo.'
    :'No cliente, na tela de bloqueio, cole o conteúdo deste arquivo em "Licença emergencial (JSON)".';
  box.textContent='Licença assinada e salva na pasta de licenças emitidas.\nExpira em: '+expira+'\n'+instrucao;box.style.display='block';
 }catch(err){box.className='result error';box.textContent=err.message;box.style.display='block';}
 finally{btn.disabled=false;btn.textContent='ASSINAR E GERAR ARQUIVO';}
});
</script></body></html>`;

function responder(res, status, dados, tipo = 'application/json; charset=utf-8') {
  const corpo = typeof dados === 'string' ? dados : JSON.stringify(dados);
  res.writeHead(status, {
    'Content-Type': tipo,
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
    'Content-Length': Buffer.byteLength(corpo),
  });
  res.end(corpo);
}

const servidor = http.createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/') {
    return responder(res, 200, pagina, 'text/html; charset=utf-8');
  }
  if (req.method !== 'POST' || req.url !== '/emitir') {
    return responder(res, 404, { erro: 'Rota nao encontrada.' });
  }

  const origem = req.headers.origin;
  if (origem && !['http://127.0.0.1:' + PORT, 'http://localhost:' + PORT].includes(origem)) {
    return responder(res, 403, { erro: 'Origem nao autorizada.' });
  }

  let corpo = '';
  req.on('data', parte => {
    corpo += parte;
    if (Buffer.byteLength(corpo) > 8192) {
      req.destroy();
    }
  });
  req.on('end', () => {
    try {
      if (!fs.existsSync(arquivoChave)) {
        return responder(res, 503, { erro: 'Chave privada não encontrada na pasta protegida do administrador.' });
      }
      const dados = JSON.parse(corpo || '{}');
      const tipo = dados.tipo === 'instalacao' ? 'instalacao' : 'emergencial';
      const empresaId = String(dados.empresaId || '').trim();
      const maquinaId = String(dados.maquinaId || '').trim().toLowerCase();
      const maquinaNome = String(dados.maquinaNome || '').trim().slice(0, 100);
      const dias = Number(dados.dias);
      if (!empresaId && tipo === 'emergencial') {
        return responder(res, 400, { erro: 'Informe o ID da empresa para a licença emergencial.' });
      }
      if (!/^[a-f0-9]{64}$/.test(maquinaId) || !maquinaNome) {
        return responder(res, 400, { erro: 'Confira o ID de máquina e o nome do computador.' });
      }
      if (![7, 15, 30].includes(dias)) {
        return responder(res, 400, { erro: 'Validade não permitida.' });
      }

      // A ordem das propriedades e o JSON compacto fazem parte da assinatura:
      // o aplicativo remonta o payload nesta mesma ordem para validar.
      const emitida = new Date();
      const expira = new Date(emitida.getTime() + dias * 86400000);
      const payload = {
        version: 1,
        type: tipo,
        company_id: empresaId,
        machine_id: maquinaId,
        machine_name: maquinaNome,
        issued_at: emitida.toISOString(),
        expires_at: expira.toISOString(),
        license_id: crypto.randomUUID(),
      };
      const assinatura = crypto.sign(
        'RSA-SHA256',
        Buffer.from(JSON.stringify(payload), 'utf8'),
        fs.readFileSync(arquivoChave, 'utf8'),
      ).toString('base64');
      const documento = { payload, assinatura };
      fs.mkdirSync(pastaSaida, { recursive: true });
      const prefixo = tipo === 'instalacao' ? 'EXODO-INSTALACAO-' : 'EXODO-LICENCA-';
      const nome = prefixo + payload.license_id + '.json';
      fs.writeFileSync(path.join(pastaSaida, nome), JSON.stringify(documento, null, 2), { flag: 'wx' });
      return responder(res, 200, { nome, tipo, documento });
    } catch (erro) {
      return responder(res, 400, { erro: erro.message || 'Dados inválidos.' });
    }
  });
});

servidor.listen(PORT, HOST, () => {
  console.log('Painel de licenças Êxodo aberto em http://' + HOST + ':' + PORT);
  console.log('Chave privada: ' + arquivoChave);
  console.log('Somente conexões locais são aceitas. Feche com Ctrl+C.');
});
