#!/usr/bin/env node
'use strict';

// Ferramenta de contingencia OFFLINE. A chave privada fica fora do repositorio
// em %USERPROFILE%\\Documents\\ExodoLicencasPrivadas.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const readline = require('node:readline/promises');

const home = process.env.USERPROFILE || process.env.HOME;
const pastaPrivada = path.join(home, 'Documents', 'ExodoLicencasPrivadas');
const arquivoChave = path.join(pastaPrivada, 'chave_privada_exodo.pem');
const pastaSaida = path.join(home, 'Documents', 'LicencasEmitidasExodo');

async function perguntar(rl, rotulo, padrao = '') {
  const resposta = (await rl.question(padrao ? `${rotulo} [${padrao}]: ` : `${rotulo}: `)).trim();
  return resposta || padrao;
}

async function main() {
  if (!fs.existsSync(arquivoChave)) {
    console.error('CHAVE PRIVADA NAO ENCONTRADA: ' + arquivoChave);
    console.error('Nao copie essa chave para computadores de clientes.');
    process.exitCode = 2;
    return;
  }

  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  try {
    console.log('\n=== GERADOR OFFLINE DE LICENCA EMERGENCIAL - EXODO ===\n');
    console.log('O cliente deve informar o ID da empresa e o ID desta maquina exibido na tela de bloqueio.\n');
    const companyId = await perguntar(rl, 'ID da empresa (UUID)');
    const machineId = await perguntar(rl, 'ID da maquina (64 caracteres hexadecimais)');
    const machineName = await perguntar(rl, 'Nome do computador', 'Computador autorizado');
    const dias = Number.parseInt(await perguntar(rl, 'Validade em dias (1 a 30)', '30'), 10);

    if (!companyId || !/^[a-f0-9]{64}$/i.test(machineId)) {
      throw new Error('Informe o ID da empresa e um ID de maquina valido.');
    }
    if (!Number.isInteger(dias) || dias < 1 || dias > 30) {
      throw new Error('A validade deve ser de 1 a 30 dias.');
    }

    const emitida = new Date();
    const expira = new Date(emitida.getTime() + dias * 86400000);
    const payload = {
      version: 1,
      type: 'emergencial',
      company_id: companyId,
      machine_id: machineId.toLowerCase(),
      machine_name: machineName,
      issued_at: emitida.toISOString(),
      expires_at: expira.toISOString(),
      license_id: crypto.randomUUID(),
    };

    // A ordem das propriedades e o JSON compacto fazem parte do formato assinado.
    const assinatura = crypto.sign(
      'RSA-SHA256',
      Buffer.from(JSON.stringify(payload), 'utf8'),
      fs.readFileSync(arquivoChave, 'utf8'),
    ).toString('base64');

    fs.mkdirSync(pastaSaida, { recursive: true });
    const destino = path.join(pastaSaida, `EXODO-LICENCA-${payload.license_id}.json`);
    fs.writeFileSync(destino, JSON.stringify({ payload, assinatura }, null, 2), { flag: 'wx' });

    console.log('\nLICENCA GERADA COM SUCESSO.');
    console.log('Empresa: ' + companyId);
    console.log('Computador: ' + machineName);
    console.log('Validade: ' + dias + ' dia(s)');
    console.log('Expira em: ' + expira.toLocaleString('pt-BR'));
    console.log('Arquivo: ' + destino);
    console.log('\nEnvie SOMENTE esse arquivo ao cliente. Nunca envie a chave privada.');
  } finally {
    rl.close();
  }
}

main().catch((erro) => {
  console.error('\nERRO: ' + erro.message);
  process.exitCode = 1;
});
