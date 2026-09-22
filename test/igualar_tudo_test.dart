// 100% IGUAIS — o teste que fecha a conta entre o banco local e a nuvem.
//
// Junta os três tipos de diferença que sobravam e prova que, ao fim, a
// conferência não aponta NADA:
//
//   1. COLUNAS que faltam no local, inclusive as que só entram com autorização
//      (`usuarios.senha` — a nuvem tem a mesma senha que o app já usa por padrão)
//      e as duplicadas em camelCase de `fechamentos_caixa`, que antes o app
//      APAGAVA (tipo errado numa migração antiga) e agora ele REPARA;
//   2. TIPOS de coluna diferentes (`produtos.*`: text aqui × numeric/integer lá),
//      conferindo todos os valores antes de converter;
//   3. Nome que era TABELA aqui e VIEW na nuvem (`vw_historico_recente`) — que
//      agora é VIEW dos dois lados.
//
// Tudo só no banco LOCAL: a nuvem nunca é alterada. As reversões ficam em
// C:\ExodoBackups (IGUALAR_*.sql).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sistema_exodo_novo/services/backup_restore_service.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/database_service.dart';
import 'package:sistema_exodo_novo/supabase_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  setUpAll(() async {
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
    try {
      Supabase.instance.client;
    } catch (_) {
      await Supabase.initialize(
          url: SupabaseConfig.url, anonKey: SupabaseConfig.anonKey);
    }
  });

  test('igualar colunas, tipos e VIEW deixa os dois bancos iguais', () async {
    final service = BackupRestoreService(DataService());

    final antes = await service.conferirEsquemaBancos();
    expect(antes.leuOsDois, isTrue, reason: antes.resumo);
    print('===== ANTES =====');
    print(antes.relatorioTexto);

    // 1. Colunas que faltam (todas: as comuns + as que exigem autorização).
    final tabelas = <String>{
      ...antes.somenteNaNuvem,
      ...antes.colunasFaltandoNoLocal.map((c) => c.tabela),
    };
    print('tabelas a ajustar no local: $tabelas');
    final (okColunas, logsColunas) = await service.criarEstruturaFaltanteNoLocal(
      tabelas: tabelas,
      criarColunasAutorizadas: true,
      onProgress: (m) => print('   $m'),
    );
    print('===== COLUNAS =====\n${logsColunas.join('\n')}');
    expect(okColunas, isTrue, reason: logsColunas.join('\n'));

    // 2. Tipos de coluna (as 9 de produtos).
    final tipos = antes.tiposDiferentes.toSet();
    print('tipos a igualar: $tipos');
    if (tipos.isNotEmpty) {
      final (okPlano, logsPlano) = await service.igualarTiposDeColunaNoLocal(
        colunas: tipos,
        somenteComparar: true,
      );
      print('===== PLANO DOS TIPOS =====\n${logsPlano.join('\n')}');
      expect(okPlano, isTrue, reason: logsPlano.join('\n'));

      final (okTipos, logsTipos) = await service.igualarTiposDeColunaNoLocal(
        colunas: tipos,
        onProgress: (m) => print('   $m'),
      );
      print('===== TIPOS =====\n${logsTipos.join('\n')}');
      expect(okTipos, isTrue, reason: logsTipos.join('\n'));
      expect(
          Directory('C:\\ExodoBackups')
              .listSync()
              .whereType<File>()
              .any((f) => f.path
                  .split(Platform.pathSeparator)
                  .last
                  .startsWith('IGUALAR_TIPO_')),
          isTrue,
          reason: 'a conversão de tipos precisa deixar a reversão em disco');
    }

    // 3. O resultado: nada mais apontado pela conferência.
    final depois = await service.conferirEsquemaBancos();
    print('===== DEPOIS =====');
    print(depois.relatorioTexto);

    expect(depois.somenteNoLocal, isEmpty);
    expect(depois.somenteNaNuvem, isEmpty);
    expect(depois.colunasFaltandoNoLocal, isEmpty);
    expect(depois.colunasFaltandoNaNuvem, isEmpty);
    expect(depois.tiposDiferentes, isEmpty);
    expect(depois.objetoDiferenteNaNuvem, isEmpty);
    expect(depois.objetoDiferenteNoLocal, isEmpty);
    expect(depois.divergenciasReais, 0);
    expect(depois.iguais, isTrue,
        reason: 'os dois bancos deveriam ficar equivalentes: ${depois.resumo}');
    expect(depois.tabelasDeNegocioLocal, depois.tabelasDeNegocioNuvem);

    // A nuvem não foi tocada: o mesmo número de tabelas/colunas de antes.
    expect(depois.totalNuvem, antes.totalNuvem);
    expect(depois.colunasFaltandoNaNuvem, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 15)));

  test('as colunas duplicadas de fechamentos_caixa não alimentam a leitura',
      () async {
    final db = DatabaseService();
    final linhas = await db.carregarLista('fechamentos_caixa');
    print('fechamentos_caixa lidos: ${linhas.length}');
    if (linhas.isEmpty) return;

    // O mapa tem `aberturaCaixaId` (vem de abertura_caixa_id) e NUNCA o valor da
    // coluna duplicada em camelCase: é essa duplicata que, com tipo errado,
    // sobrescrevia o id por uma DATA e deixava o caixa "sempre aberto".
    final primeira = linhas.first;
    expect(primeira.containsKey('aberturaCaixaId'), isTrue,
        reason: 'o vínculo fechamento→abertura precisa chegar pela coluna snake');
    final valor = primeira['aberturaCaixaId']?.toString() ?? '';
    expect(valor.contains('T00:'), isFalse,
        reason: 'aberturaCaixaId não pode ser uma DATA (bug do caixa que nunca fecha)');
    expect(valor.contains(':'), isFalse);
    print('aberturaCaixaId (via abertura_caixa_id): $valor');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
