#!/usr/bin/env node
'use strict';

// Gera CÓDIGOS DE ATIVAÇÃO por venda (uso único, em um computador).
//
// Uso:
//   node tools/licencas/gerar_codigos_ativacao.js --quantidade 5
//   node tools/licencas/gerar_codigos_ativacao.js --quantidade 1 --empresa <uuid>
//   node tools/licencas/gerar_codigos_ativacao.js --quantidade 1 --maquina <64 hex>
//   node tools/licencas/gerar_codigos_ativacao.js --quantidade 10 --dias 90
//   node tools/licencas/gerar_codigos_ativacao.js --quantidade 5 --sql
//
// Sem `--sql` o script grava direto na nuvem (tabela licencas_ativacao) usando
// SUPABASE_URL + chave de serviço. A chave é lida das variáveis de ambiente ou
// do `.env` do projeto (nunca fica no código).
//
// Cada código pode ser usado UMA vez. Sem `--maquina` ele vale para QUALQUER
// computador (o primeiro a ativar consome). Com `--maquina <ID da tela de
// ativação>` ele só é aceito por aquela máquina, em qualquer outra a nuvem
// responde 403 `codigo_outra_maquina`.

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const ALFABETO = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ'; // sem 0/O/1/I
const TAMANHO = 12;

function lerArgs(argv) {
  const args = { quantidade: 1, empresa: '', maquina: '', dias: 0, sql: false };
  for (let i = 0; i < argv.length; i++) {
    const atual = argv[i];
    const proximo = argv[i + 1];
    if (atual === '--quantidade' || atual === '-q') {
      args.quantidade = Number.parseInt(proximo, 10);
      i++;
    } else if (atual === '--empresa' || atual === '-e') {
      args.empresa = String(proximo || '').trim();
      i++;
    } else if (atual === '--maquina' || atual === '-m') {
      args.maquina = String(proximo || '').trim().toLowerCase();
      i++;
    } else if (atual === '--dias' || atual === '-d') {
      args.dias = Number.parseInt(proximo, 10);
      i++;
    } else if (atual === '--sql') {
      args.sql = true;
    } else if (atual === '--help' || atual === '-h') {
      args.help = true;
    }
  }
  return args;
}

function lerEnv(caminho) {
  const valores = {};
  if (!fs.existsSync(caminho)) return valores;
  for (const linha of fs.readFileSync(caminho, 'utf8').split(/\r?\n/)) {
    const texto = linha.trim();
    if (!texto || texto.startsWith('#')) continue;
    const indice = texto.indexOf('=');
    if (indice <= 0) continue;
    const chave = texto.slice(0, indice).trim();
    let valor = texto.slice(indice + 1).trim();
    if (
      (valor.startsWith('"') && valor.endsWith('"')) ||
      (valor.startsWith("'") && valor.endsWith("'"))
    ) {
      valor = valor.slice(1, -1);
    }
    valores[chave] = valor;
  }
  return valores;
}

function gerarCodigo() {
  let bruto = '';
  for (let i = 0; i < TAMANHO; i++) {
    bruto += ALFABETO[crypto.randomInt(ALFABETO.length)];
  }
  return bruto;
}

function formatarCodigo(bruto) {
  return `EXO-${bruto.slice(0, 4)}-${bruto.slice(4, 8)}-${bruto.slice(8, 12)}`;
}

function escaparSql(valor) {
  return `'${String(valor).replace(/'/g, "''")}'`;
}

async function inserirNaNuvem(url, chave, linhas) {
  const resposta = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/licencas_ativacao`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: chave,
      Authorization: `Bearer ${chave}`,
      Prefer: 'return=minimal',
    },
    body: JSON.stringify(linhas),
  });

  if (!resposta.ok) {
    const detalhe = await resposta.text();
    throw new Error(`A nuvem recusou os códigos (HTTP ${resposta.status}): ${detalhe}`);
  }
}

async function main() {
  const args = lerArgs(process.argv.slice(2));

  if (args.help) {
    console.log(
      '\nGerador de códigos de ativação Êxodo\n\n' +
        '  --quantidade, -q  quantos códigos gerar (padrão 1)\n' +
        '  --empresa, -e     amarra o código a uma empresa (UUID)\n' +
        '  --maquina, -m     amarra o código a UM computador (ID de 64 hex da tela de ativação)\n' +
        '  --dias, -d        prazo para o código ser usado (0 = sem prazo)\n' +
        '  --sql             só imprime o SQL (para colar no Supabase)\n',
    );
    return;
  }

  if (!Number.isInteger(args.quantidade) || args.quantidade < 1 || args.quantidade > 500) {
    throw new Error('Informe --quantidade entre 1 e 500.');
  }

  if (args.maquina && !/^[a-f0-9]{64}$/.test(args.maquina)) {
    throw new Error(
      '--maquina deve ser o ID de 64 caracteres hexadecimais exibido na tela de ativação.',
    );
  }

  const projetoRoot = path.resolve(__dirname, '..', '..');
  const env = {
    ...lerEnv(path.join(projetoRoot, '.env')),
    ...process.env,
  };
  const supabaseUrl = (env.SUPABASE_URL || '').trim();
  const chave =
    (env.SUPABASE_SERVICE_ROLE_KEY || env.SUPABASE_ANON_KEY || '').trim();

  const expiraEm =
    args.dias > 0
      ? new Date(Date.now() + args.dias * 86400000).toISOString()
      : null;

  const observacoes = [];
  if (args.empresa) observacoes.push('venda com empresa vinculada');
  if (args.maquina) observacoes.push(`preso ao computador ${args.maquina}`);
  const observacao = observacoes.join(' | ');

  const gerados = [];
  for (let i = 0; i < args.quantidade; i++) {
    const bruto = gerarCodigo();
    gerados.push({
      bruto,
      exibicao: formatarCodigo(bruto),
      linha: {
        codigo: bruto,
        empresa_id: args.empresa || null,
        machine_id: args.maquina || null,
        expira_em: expiraEm,
        observacao,
      },
    });
  }

  if (args.sql) {
    console.log('\n-- Cole no Supabase SQL Editor:\n');
    for (const item of gerados) {
      console.log(
        'INSERT INTO public.licencas_ativacao (codigo, empresa_id, machine_id, expira_em, observacao) VALUES (' +
          `${escaparSql(item.linha.codigo)}, ` +
          `${item.linha.empresa_id ? escaparSql(item.linha.empresa_id) : 'NULL'}, ` +
          `${item.linha.machine_id ? escaparSql(item.linha.machine_id) : 'NULL'}, ` +
          `${item.linha.expira_em ? `${escaparSql(item.linha.expira_em)}::timestamptz` : 'NULL'}, ` +
          `${escaparSql(item.linha.observacao)}` +
          ') ON CONFLICT (codigo) DO NOTHING;',
      );
    }
    console.log('');
  } else {
    if (!supabaseUrl || !chave) {
      throw new Error(
        'Sem SUPABASE_URL/chave para gravar na nuvem. Configure no .env do ' +
          'projeto ou use --sql para gerar os INSERTs.',
      );
    }
    await inserirNaNuvem(
      supabaseUrl,
      chave,
      gerados.map((item) => item.linha),
    );
    console.log(`\n${gerados.length} código(s) gravado(s) na nuvem.`);
  }

  const pastaSaida = path.join(
    process.env.USERPROFILE || process.env.HOME || '.',
    'Documents',
    'LicencasEmitidasExodo',
  );
  fs.mkdirSync(pastaSaida, { recursive: true });
  const arquivo = path.join(
    pastaSaida,
    `codigos_ativacao_${new Date().toISOString().replace(/[:.]/g, '-')}.txt`,
  );

  const linhasArquivo = [
    'CÓDIGOS DE ATIVAÇÃO ÊXODO — uso único, um por computador',
    `Gerados em: ${new Date().toLocaleString('pt-BR')}`,
    args.empresa ? `Empresa: ${args.empresa}` : 'Empresa: (vinculada no primeiro login)',
    args.maquina
      ? `Computador: ${args.maquina} (só ele pode usar estes códigos)`
      : 'Computador: qualquer um (o primeiro a ativar consome)',
    expiraEm
      ? `Usar até: ${new Date(expiraEm).toLocaleString('pt-BR')}`
      : 'Sem prazo para usar',
    '',
    ...gerados.map((item) => item.exibicao),
    '',
    args.maquina
      ? 'Cada código ativa SOMENTE o computador acima, por 30 dias. Entregue um código por venda.'
      : 'Cada código ativa UM computador por 30 dias. Entregue um código por venda.',
  ];
  fs.writeFileSync(arquivo, linhasArquivo.join('\n'), { flag: 'wx' });

  console.log('\nCódigos gerados:');
  for (const item of gerados) console.log('  ' + item.exibicao);
  console.log(
    args.maquina
      ? `\nPreso ao computador: ${args.maquina}`
      : '\nSem vínculo de computador: qualquer PC pode usar (uso único). Use --maquina para prender a um PC.',
  );
  console.log('\nArquivo salvo em: ' + arquivo + '\n');
}

main().catch((erro) => {
  console.error('\nERRO: ' + erro.message + '\n');
  process.exitCode = 1;
});
