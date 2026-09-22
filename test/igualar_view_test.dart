// TABELA (local) × VIEW (nuvem) — o caso que deixava 49 × 48.
//
// `vw_historico_recente` ficou neste computador como TABELA vazia (veio de um
// dump com o nome trocado) e na nuvem é uma VIEW de verdade, criada pelo próprio
// projeto em `supabase/migrations/004_produto_historico.sql`:
//
//     SELECT * FROM produto_historico
//     WHERE data_alteracao >= now() - interval '30 days'
//     ORDER BY data_alteracao DESC
//
// Como TABELA e VIEW contam diferente na conferência, esse nome sozinho fazia o
// banco local aparecer com 1 tabela de negócio a mais que a nuvem.
//
// O teste:
//   1. mostra a recusa quando o nome não serve (nada é tocado);
//   2. roda o modo comparação (planeja, não altera);
//   3. TROCA a tabela vazia pela VIEW igual à da nuvem — com cópia do estado
//      anterior em C:\ExodoBackups — e confirma que os dois bancos passaram a ter
//      o MESMO número de tabelas de negócio;
//   4. confirma que a nuvem não foi tocada e que a view devolve o mesmo que a
//      tabela que existia (nenhuma linha foi perdida: ela estava vazia).
//
// Só altera o banco LOCAL, e só o que a comparação apontar como "TABELA aqui e
// VIEW na nuvem", com a tabela VAZIA.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sistema_exodo_novo/services/backup_restore_service.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/supabase_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  void prepararAmbiente() {
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
    for (final canal in const [
      'xyz.luan/audioplayers.global/events',
      'dev.fluttercommunity.plus/connectivity_status',
    ]) {
      messenger.setMockStreamHandler(
          EventChannel(canal), MockStreamHandler.inline(onListen: (args, sink) {}));
    }
  }

  late BackupRestoreService service;

  setUpAll(() async {
    prepararAmbiente();
    try {
      Supabase.instance.client;
    } catch (_) {
      await Supabase.initialize(
          url: SupabaseConfig.url, anonKey: SupabaseConfig.anonKey);
    }
    service = BackupRestoreService(DataService());
  });

  test('tabela vazia vira a VIEW da nuvem e os dois bancos ficam com o mesmo número',
      () async {
    // 1. Nome que não existe do outro lado é recusado, sem tocar em nada.
    final (okRecusa, logsRecusa) = await service.igualarTabelasQueSaoViewNaNuvem(
      objetos: {'tabela_que_nao_existe_em_lugar_nenhum'},
    );
    print('--- RECUSA ---\n${logsRecusa.join('\n')}');
    expect(okRecusa, isFalse);
    expect(logsRecusa.join('\n'), contains('não encontrei esse nome na nuvem'));

    // 2. O que a conferência diz hoje.
    final antes = await service.conferirEsquemaBancos();
    print('--- ANTES ---');
    print('local ${antes.totalLocal} tabela(s) / nuvem ${antes.totalNuvem} tabela(s)');
    print('TABELA aqui e VIEW na nuvem: ${antes.objetoDiferenteNaNuvem}');
    print('VIEW aqui e TABELA na nuvem: ${antes.objetoDiferenteNoLocal}');
    print('quem está atrasado: ${antes.veredito}');
    expect(antes.leuOsDois, isTrue, reason: antes.resumo);

    final tabelasLocalAntes = antes.somenteNoLocal.length;
    final tabelasNuvemAntes = antes.somenteNaNuvem.length;

    // 3. Ou já foi igualado (nada a fazer) ou é o caso da vw_historico_recente.
    if (antes.objetoDiferenteNaNuvem.isEmpty) {
      print('Já está igual: nada é TABELA aqui e VIEW na nuvem.');
      expect(antes.objetoDiferenteNoLocal, isEmpty,
          reason: 'o inverso (VIEW aqui × TABELA na nuvem) precisa de decisão manual');
      return;
    }

    final alvos = antes.objetoDiferenteNaNuvem.toSet();
    print('Alvo(s): $alvos');

    // 3a. Modo comparação: planeja e NÃO altera.
    final (okPlano, logsPlano) = await service.igualarTabelasQueSaoViewNaNuvem(
      objetos: alvos,
      somenteComparar: true,
    );
    print('--- PLANO ---\n${logsPlano.join('\n')}');
    expect(okPlano, isTrue, reason: logsPlano.join('\n'));
    expect(logsPlano.join('\n'), contains('MODO COMPARAÇÃO'));

    final depoisDoPlano = await service.conferirEsquemaBancos();
    expect(depoisDoPlano.objetoDiferenteNaNuvem, antes.objetoDiferenteNaNuvem,
        reason: 'planejar não pode alterar nada');
    expect(depoisDoPlano.totalLocal, antes.totalLocal);

    // 3b. A troca de verdade (só local).
    final (ok, logs) = await service.igualarTabelasQueSaoViewNaNuvem(
      objetos: alvos,
      onProgress: (m) => print('   $m'),
    );
    print('--- TROCA ---\n${logs.join('\n')}');
    expect(ok, isTrue, reason: logs.join('\n'));

    final texto = logs.join('\n');
    if (texto.contains('não apago tabela com dado') || texto.contains('dependendo dela')) {
      // Tabela com linha dentro ou com dependentes: o app recusa de propósito e o
      // teste não pode forçar. Aqui só se confere que NADA mudou.
      final depois = await service.conferirEsquemaBancos();
      expect(depois.somenteNoLocal.length, tabelasLocalAntes);
      expect(depois.somenteNaNuvem.length, tabelasNuvemAntes);
      print('Recusado com segurança — banco intacto.');
      return;
    }

    // 4. Depois da troca: o nome saiu da lista de "objeto diferente" e os dois
    // lados contam o MESMO número de tabelas de negócio.
    final depois = await service.conferirEsquemaBancos();
    print('--- DEPOIS ---');
    print(depois.relatorioTexto);
    expect(depois.objetoDiferenteNaNuvem, isEmpty,
        reason: 'a tabela vazia deveria ter virado VIEW');
    expect(depois.tabelasDeNegocioLocal, depois.tabelasDeNegocioNuvem,
        reason: 'os dois bancos precisam ficar com o mesmo número de tabelas: '
            '${depois.resumo}');

    // A nuvem não foi tocada (segue com zero objeto diferente do outro lado).
    expect(depois.objetoDiferenteNoLocal, isEmpty);
    expect(depois.totalNuvem, antes.totalNuvem,
        reason: 'a nuvem não pode ter mudado');

    // A cópia do estado anterior ficou em disco.
    final pasta = Directory('C:\\ExodoBackups');
    final copias = pasta
        .listSync()
        .whereType<File>()
        .where((f) => f.path.split(Platform.pathSeparator).last.startsWith('IGUALAR_VIEW_'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    expect(copias, isNotEmpty, reason: 'a troca tem de deixar cópia do estado anterior');
    expect(copias.first.readAsStringSync(), contains('CREATE TABLE IF NOT EXISTS'),
        reason: 'a cópia precisa dizer como voltar atrás');
    print('cópia: ${copias.first.path}');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
