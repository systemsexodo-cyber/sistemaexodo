#!/usr/bin/env node
'use strict';

// Gera o CÓDIGO CURTO de liberação offline (EXO-OFF-XXXXXX-XXXXXX).
//
// Use quando a nuvem de licenças não responde e o cliente precisa liberar a
// tela de ativação. O código é preso ao ID do computador mostrado na tela,
// vale até a data informada (máximo 30 dias) e é conferido pelo app sem
// internet.
//
// Uso:
//   node tools/licencas/gerar_codigo_offline.js <ID_DO_COMPUTADOR> [dias]
//
// Exemplo:
//   node tools/licencas/gerar_codigo_offline.js a1b2...64caracteres... 30
const crypto = require('node:crypto');

// Mesmo segredo do app (lib/services/licenca_instalacao_service.dart).
const SEGREDO = Buffer.from(
  '650f736c0e4bb27c2673aa00ddeff3376fb0ec72e275afdc695b207ac3857d48',
  'hex',
);
const ALFABETO = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const EPOCA = Date.UTC(2020, 0, 1);
const PREFIXO = 'EXO-OFF';
const MAX_DIAS = 30;

function gerarCodigo(maquinaId, dias) {
  const agora = new Date();
  const expira = new Date(agora.getTime() + dias * 86400000);
  const dia = Math.floor((Date.UTC(
    expira.getUTCFullYear(),
    expira.getUTCMonth(),
    expira.getUTCDate(),
  ) - EPOCA) / 86400000);

  const mac = crypto
    .createHmac('sha256', SEGREDO)
    .update(`EXODO-OFFLINE-V1|${maquinaId}|${dia}`)
    .digest()
    .subarray(0, 5);

  let valor = BigInt(dia);
  for (const byte of mac) valor = (valor << 8n) | BigInt(byte);

  const caracteres = Array(12).fill('0');
  for (let i = 11; i >= 0; i--) {
    caracteres[i] = ALFABETO[Number(valor & 31n)];
    valor >>= 5n;
  }
  const corpo = caracteres.join('');
  return {
    codigo: `${PREFIXO}-${corpo.slice(0, 6)}-${corpo.slice(6)}`,
    expira,
  };
}

function main() {
  const maquinaId = String(process.argv[2] || '').trim().toLowerCase();
  const dias = Number.parseInt(process.argv[3] || String(MAX_DIAS), 10);

  if (!/^[a-f0-9]{64}$/.test(maquinaId)) {
    console.error(
      'Informe o ID do computador mostrado na tela de ativação (64 caracteres hexadecimais).',
    );
    console.error(
      'Uso: node tools/licencas/gerar_codigo_offline.js <ID_DO_COMPUTADOR> [dias]',
    );
    process.exitCode = 2;
    return;
  }
  if (!Number.isInteger(dias) || dias < 1 || dias > MAX_DIAS) {
    console.error(`A validade deve ser de 1 a ${MAX_DIAS} dias.`);
    process.exitCode = 2;
    return;
  }

  const { codigo, expira } = gerarCodigo(maquinaId, dias);
  console.log('\nCODIGO DE LIBERACAO OFFLINE');
  console.log('Computador: ' + maquinaId);
  console.log('Valido ate: ' + expira.toLocaleDateString('pt-BR'));
  console.log('\n  ' + codigo + '\n');
  console.log(
    'No cliente: tela de ativacao > campo "Código de ativação" > cole o codigo > ATIVAR.',
  );
  console.log('O codigo so funciona nesse computador e ate a data acima.\n');
}

main();
