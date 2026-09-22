// RESTAURAR AS EMPRESAS QUE FALTAM NO BANCO LOCAL
//
// O banco local guardava 2 empresas e a nuvem tem 4. As duas que faltavam eram
// justamente as que têm `empresa_id` NULL — e é aí que mora o defeito:
//
//   `sincronizar_local_supabase.py` roda a cada ciclo com a empresa aberta e
//   fazia `DELETE FROM empresas WHERE empresa_id IS DISTINCT FROM <ativa>`.
//   NULL é "distinct from" qualquer empresa, então as empresas sem `empresa_id`
//   eram apagadas da base local TODA VEZ. A nuvem nunca foi tocada (o DELETE
//   roda com exodo.sync_mode = 'on'), mas a lista de empresas do app encolhia
//   sozinha — e o botão de restaurar seria desfeito no ciclo seguinte.
//
// Este teste cobre as duas coisas:
//   1. TRILHA NOVA: `planejarEmpresasFaltantesNoLocal` só lê (não grava);
//      `restaurarEmpresasFaltantesNoLocal(simular: true)` só conta;
//      `restaurarEmpresasFaltantesNoLocal()` insere SÓ o que falta.
//   2. AS TRAVAS: empresa que já existe no local fica byte a byte igual; empresa
//      que existe só no local continua existindo; a NUVEM não muda; e rodar de
//      novo não insere nada (idempotente).
//
// Não é teste de mentira: ele abre os DOIS bancos reais (leitura na nuvem,
// leitura+escrita no local). A nuvem é aberta só para conferir que continua
// igual no fim.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart';
import 'package:sistema_exodo_novo/services/conferencia_nuvem_service.dart';
import 'package:sistema_exodo_novo/services/env_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    HttpOverrides.global = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final canal in const [
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers',
      'dev.fluttercommunity.plus/connectivity',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(canal), (call) async => null);
    }
  });

  test('restaura só as empresas que faltam, sem apagar nem alterar as existentes',
      () async {
    expect(EnvConfig.backupBancoNuvemConfigurado, isTrue,
        reason: 'este teste precisa da nuvem configurada no .env');

    final local = await Connection.open(
      Endpoint(
        host: EnvConfig.dbHost.toLowerCase() == 'localhost'
            ? '127.0.0.1'
            : EnvConfig.dbHost,
        port: EnvConfig.dbPort,
        database: EnvConfig.dbName,
        username: EnvConfig.dbUser,
        password: EnvConfig.dbPassword,
      ),
      settings: const ConnectionSettings(sslMode: SslMode.disable),
    );
    final nuvem = await Connection.open(
      Endpoint(
        host: EnvConfig.supabasePoolerHost,
        port: EnvConfig.supabasePoolerPort,
        database: EnvConfig.supabaseDbNameFinal,
        username: EnvConfig.supabasePoolerUser,
        password: EnvConfig.supabasePoolerPassword,
      ),
      settings: const ConnectionSettings(sslMode: SslMode.require),
    );

    /// `id -> conteúdo` da tabela `empresas` (as colunas que identificam a
    /// linha; se qualquer uma mudar, a empresa foi alterada).
    Future<Map<String, String>> lerEmpresas(Connection conn) async {
      final res = await conn.execute(
        'SELECT id, razao_social, nome_fantasia, cnpj FROM empresas',
      );
      final mapa = <String, String>{};
      for (final row in res) {
        final m = row.toColumnMap();
        mapa[m['id'].toString()] = [
          m['razao_social'],
          m['nome_fantasia'],
          m['cnpj'],
        ].map((v) => v?.toString() ?? '').join('|');
      }
      return mapa;
    }

    try {
      final localAntes = await lerEmpresas(local);
      final nuvemAntes = await lerEmpresas(nuvem);
      print('antes: local=${localAntes.length} nuvem=${nuvemAntes.length}');
      expect(nuvemAntes.length, greaterThanOrEqualTo(localAntes.length),
          reason: 'a nuvem é a referência: ela não pode ter menos empresas');

      final faltandoDeVerdade =
          nuvemAntes.keys.toSet().difference(localAntes.keys.toSet());

      // ── 1. Planejar: só leitura ──────────────────────────────────────────
      final service = ConferenciaNuvemService.instance;
      final resumo = await service.planejarEmpresasFaltantesNoLocal();

      expect(await lerEmpresas(local), localAntes,
          reason: 'planejar não pode gravar nada no banco local');
      expect(resumo.totalLocal, localAntes.length);
      expect(resumo.totalNuvem, nuvemAntes.length);
      expect(resumo.faltantes.map((e) => e.id).toSet(), faltandoDeVerdade,
          reason: 'o resumo precisa listar exatamente as empresas que faltam');
      expect(resumo.idsJaExistentes.toSet(), localAntes.keys.toSet(),
          reason: 'as que já existem aparecem como preservadas no resumo');
      // O texto do resumo é o que o usuário lê antes de aplicar. Ele muda de
      // forma quando não há nada a fazer — que é o caso depois da primeira
      // restauração (o banco fica completo, e aí o teste precisa continuar
      // valendo: ele vira a prova da rodada idempotente).
      expect(resumo.texto, contains('nuvem: ${nuvemAntes.length} empresa(s)'));
      expect(resumo.texto, contains('A NUVEM não é tocada'));
      if (faltandoDeVerdade.isEmpty) {
        expect(resumo.temOQueRestaurar, isFalse);
        expect(resumo.texto, contains('Nada a restaurar'));
      } else {
        expect(resumo.temOQueRestaurar, isTrue);
        expect(resumo.texto, contains('ENTRAM no banco local'));
        expect(resumo.texto,
            contains('passa de ${localAntes.length} para ${nuvemAntes.length}'));
        expect(resumo.podeRestaurar, isTrue);
      }
      print(resumo.texto.replaceAll('\n', '\n  '));

      // ── 2. Simular: conta e não grava ────────────────────────────────────
      final (okSim, msgSim, totalSim) =
          await service.restaurarEmpresasFaltantesNoLocal(simular: true);
      expect(okSim, isTrue, reason: msgSim);
      expect(totalSim, faltandoDeVerdade.length, reason: msgSim);
      expect(await lerEmpresas(local), localAntes,
          reason: 'a simulação não pode gravar nada');
      print('simulação: $msgSim'.replaceAll('\n', '\n  '));

      // ── 3. Aplicar de verdade ────────────────────────────────────────────
      final (ok, msg, total) =
          await service.restaurarEmpresasFaltantesNoLocal();
      expect(ok, isTrue, reason: msg);
      expect(total, faltandoDeVerdade.length, reason: msg);
      if (faltandoDeVerdade.isEmpty) {
        expect(msg, contains('Nada a restaurar'),
            reason: 'banco já completo: nada pode ser inserido');
      } else {
        expect(msg, contains('restaurada(s) no banco local'),
            reason: 'a mensagem precisa dizer que gravou');
        expect(msg, contains('não foi alterada nem apagada'));
        expect(msg, contains('A NUVEM não foi tocada'));
      }
      print('aplicado: $msg'.replaceAll('\n', '\n  '));

      final localDepois = await lerEmpresas(local);
      // (a) as que já existiam continuam EXATAMENTE iguais
      for (final id in localAntes.keys) {
        expect(localDepois[id], localAntes[id],
            reason: 'a empresa $id já existia e não podia ser alterada');
      }
      // (b) as que faltavam agora existem, com o mesmo conteúdo da nuvem
      for (final id in faltandoDeVerdade) {
        expect(localDepois[id], nuvemAntes[id],
            reason: 'a empresa $id deveria ter vindo igual à nuvem');
      }
      // (c) nada a mais, nada a menos. Só dá para exigir igualdade quando o
      // local não tem empresa que a nuvem não tem (senão aquela continua aqui,
      // de propósito — o local nunca perde cadastro).
      if (resumo.idsSoNoLocal.isEmpty) {
        expect(localDepois.keys.toSet(), nuvemAntes.keys.toSet(),
            reason: 'local e nuvem precisam ter as mesmas empresas agora');
      } else {
        expect(localDepois.keys.toSet(),
            {...nuvemAntes.keys, ...localAntes.keys},
            reason: 'nada pode sumir do local');
      }
      print('depois: local=${localDepois.length} nuvem=${(await lerEmpresas(nuvem)).length}');

      // ── 4. A nuvem não foi tocada ────────────────────────────────────────
      expect(await lerEmpresas(nuvem), nuvemAntes,
          reason: 'a restauração é nuvem → local: a nuvem não pode mudar');

      // ── 5. Idempotente: rodar de novo não insere nada ────────────────────
      final (ok2, msg2, total2) =
          await service.restaurarEmpresasFaltantesNoLocal();
      expect(ok2, isTrue, reason: msg2);
      expect(total2, 0, reason: 'segunda rodada: $msg2');
      expect(await lerEmpresas(local), localDepois,
          reason: 'rodar de novo não pode mexer no banco local');
    } finally {
      await local.close();
      await nuvem.close();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
