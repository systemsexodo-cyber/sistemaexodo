// Garante o contrato central da restauração: ela mexe SÓ no banco LOCAL.
//
// Como a restauração chega à nuvem: o sincronizador de bandeja
// (sincronizar_local_supabase.py) envia para o Supabase EXATAMENTE o que está na
// fila `_exodo_sync_log`. Se a restauração gerar linhas nessa fila, o próximo
// ciclo sobe o conteúdo do backup para a nuvem — e os DELETE da restauração
// apagam lá o registro que só existia na nuvem.
//
// Por isso a restauração roda com `exodo.sync_mode = 'on'` (o trigger
// `log_sync_event` ignora tudo nesse modo). Este teste prova as duas pontas:
//
//   1. o .sql gerado pelo app carrega o `SET exodo.sync_mode = 'on'`;
//   2. o mesmo efeito vale para a sessão do psql via PGOPTIONS (é assim que o
//      app aplica o arquivo), enquanto SEM a opção o DELETE entra na fila.
//
// Tudo roda em transação com ROLLBACK: nenhum dado real é alterado.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sistema_exodo_novo/services/backup_restore_service.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/env_config.dart';
import 'package:sistema_exodo_novo/supabase_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  void prepararAmbiente() {
    HttpOverrides.global = null;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
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

  setUpAll(() async {
    prepararAmbiente();
    try {
      Supabase.instance.client;
    } catch (_) {
      await Supabase.initialize(url: SupabaseConfig.url, anonKey: SupabaseConfig.anonKey);
    }
  });

  Future<ProcessResult?> psql(String sql, {bool protegerNuvem = false}) async {
    final env = EnvConfig.env;
    try {
      return await Process.run(
        'psql',
        [
          '-h', env['DB_HOST'] ?? '127.0.0.1',
          '-p', env['DB_PORT'] ?? '5432',
          '-U', env['DB_USER'] ?? 'exodo_user',
          '-d', env['DB_NAME'] ?? 'exodo_db',
          '--no-psqlrc',
          '-v', 'ON_ERROR_STOP=1',
          '-A', '-t',
          '-c', sql,
        ],
        environment: {
          'PGPASSWORD': env['DB_PASSWORD'] ?? '',
          if (protegerNuvem) 'PGOPTIONS': '-c exodo.sync_mode=on',
        },
      );
    } on ProcessException {
      return null;
    }
  }

  /// Número de linhas de `_exodo_sync_log` para a tabela informada.
  String contagemSql(String tabela) =>
      "(SELECT count(*) FROM _exodo_sync_log WHERE table_name = '$tabela')";

  /// Última contagem impressa pelo psql (os `command tags` como `DELETE 1`
  /// também saem no stdout, então não basta olhar a última linha).
  List<int> contagens(Object? stdout) => (stdout as String? ?? '')
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trim())
      .where((l) => RegExp(r'^\d+$').hasMatch(l))
      .map(int.parse)
      .toList();

  /// (antes do DELETE, depois do DELETE) da fila de envio.
  (int, int) antesEDepois(Object? stdout) {
    final lidos = contagens(stdout);
    if (lidos.length < 2) return (-1, -1);
    return (lidos[lidos.length - 2], lidos.last);
  }

  test('o .sql do backup carrega o SET que desliga a fila de envio', () async {
    final service = BackupRestoreService(DataService());
    final destino = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}exodo_teste_sem_nuvem.sql');

    final (ok, msg, caminho) =
        await service.criarBackupSqlDaEmpresa(destinoArquivo: destino.path, empresaId: '1');
    if (!ok || caminho == null) {
      print('ℹ️ Sem banco local/psql nesta máquina — teste ignorado ($msg).');
      return;
    }

    try {
      final texto = await File(caminho).readAsString();
      final cabecalho = texto.split('\n').take(40).join('\n');
      expect(cabecalho.contains("SET exodo.sync_mode = 'on';"), isTrue,
          reason: 'o script precisa desligar o trigger de fila de envio');
      expect(cabecalho.contains('empresa_id: 1'), isTrue);
    } finally {
      try {
        await destino.delete();
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('DELETE da restauração não entra na fila quando a sessão protege a nuvem', () async {
    // Usa a tabela `empresas` (tem o trigger de sync) e escolhe uma linha que
    // NÃO esteja na fila, senão a contagem não muda (a fila é única por
    // table_name + record_id).
    final alvo = await psql('''
SELECT x.id FROM empresas x
WHERE x.id::text NOT IN (SELECT record_id FROM _exodo_sync_log WHERE table_name = 'empresas')
LIMIT 1;
''');
    if (alvo == null || alvo.exitCode != 0) {
      print('ℹ️ Sem banco local/psql nesta máquina — teste ignorado.');
      return;
    }
    final id = (alvo.stdout as String).trim();
    if (id.isEmpty) {
      print('ℹ️ Nenhuma empresa fora da fila de envio para testar — ignorado.');
      return;
    }

    String cenario() => '''
BEGIN;
SELECT ${contagemSql('empresas')};
DELETE FROM empresas WHERE id = '$id';
SELECT ${contagemSql('empresas')};
ROLLBACK;
''';

    // A) SEM proteção: o DELETE entra na fila (é isto que subia para a nuvem).
    final semProtecao = await psql(cenario());
    expect(semProtecao, isNotNull);
    expect(semProtecao!.exitCode, 0, reason: semProtecao.stderr.toString());
    final (antesA, depoisA) = antesEDepois(semProtecao.stdout);
    print('sem proteção: fila $antesA -> $depoisA');
    expect(depoisA, antesA + 1,
        reason: 'sem proteção o DELETE precisa aparecer na fila de envio');

    // B) COM PGOPTIONS (é assim que o app aplica o backup): a fila fica intacta.
    final comProtecao = await psql(cenario(), protegerNuvem: true);
    expect(comProtecao, isNotNull);
    expect(comProtecao!.exitCode, 0, reason: comProtecao.stderr.toString());
    final (antesB, depoisB) = antesEDepois(comProtecao.stdout);
    print('com sync_mode=on: fila $antesB -> $depoisB');
    expect(depoisB, antesB,
        reason: 'com sync_mode ligado nada entra na fila — a nuvem não pode ser tocada');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
