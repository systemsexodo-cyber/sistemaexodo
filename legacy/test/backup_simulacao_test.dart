// Teste da SIMULAÇÃO de restauração de dump (modo "ensaiar").
//
// A simulação lê o dump numa base temporária, compara os registros de cada
// tabela da empresa (hoje × como o backup deixaria) e NÃO altera o banco local.
// Este teste usa um dump real de C:\ExodoBackups\<empresaId>\dumps e confere que
// a resposta traz o comparativo e que o banco local fica intacto.

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

  test('simulação compara os registros e não altera o banco local', () async {
    final backupDir = Directory('C:\\ExodoBackups');
    if (!await backupDir.exists()) {
      print('ℹ️ C:\\ExodoBackups não existe nesta máquina — teste ignorado.');
      return;
    }

    // Junta os dumps de todas as empresas e usa o mais recente (o maior em caso
    // de empate — assim o teste roda sobre a empresa com dados de verdade).
    final candidatos = <({File dump, String empresaId})>[];
    for (final pasta in backupDir.listSync().whereType<Directory>()) {
      final dumps = Directory('${pasta.path}\\dumps');
      if (!await dumps.exists()) continue;
      final empresaId = pasta.uri.pathSegments.where((s) => s.isNotEmpty).last;
      for (final arquivo in dumps.listSync().whereType<File>()) {
        if (!arquivo.path.toLowerCase().endsWith('.dump')) continue;
        candidatos.add((dump: arquivo, empresaId: empresaId));
      }
    }
    candidatos.sort((a, b) {
      final porData = b.dump.lastModifiedSync().compareTo(a.dump.lastModifiedSync());
      return porData != 0 ? porData : b.dump.lengthSync().compareTo(a.dump.lengthSync());
    });

    // O teste roda sobre a empresa com mais produtos (dados de verdade), para a
    // comparação ter números relevantes.
    ({File dump, String empresaId})? escolhido = candidatos.isEmpty ? null : candidatos.first;
    var maisProdutos = -1;
    final vistas = <String>{};
    for (final candidato in candidatos) {
      if (!vistas.add(candidato.empresaId)) continue;
      final qtd = await _contarProdutos(candidato.empresaId);
      if (qtd > maisProdutos) {
        maisProdutos = qtd;
        escolhido = candidato;
      }
    }

    final dump = escolhido?.dump;
    final empresaId = escolhido?.empresaId;

    if (dump == null || empresaId == null) {
      print('ℹ️ Nenhum dump .dump encontrado — teste ignorado.');
      return;
    }

    print('dump: ${dump.path}');
    print('empresa: $empresaId');

    final service = BackupRestoreService(DataService());
    final antesDoDump = await _somarRegistros(empresaId);

    final (ok, msg, comparativo) = await service.simularRestauracaoDumpSomenteEmpresa(
      dumpFile: dump,
      empresaId: empresaId,
      onProgress: (m) => print('   $m'),
    );

    expect(ok, isTrue, reason: msg);
    expect(comparativo, isNotNull);
    expect(comparativo, isNotEmpty);

    final somaAntes = comparativo!.values.fold<int>(0, (s, v) => s + v.antes);
    final somaDepois = comparativo.values.fold<int>(0, (s, v) => s + v.depois);
    print('tabelas comparadas: ${comparativo.length}');
    print('registros hoje: $somaAntes | com o backup: $somaDepois');
    print(msg);

    final piores = comparativo.entries.toList()
      ..sort((a, b) => a.value.delta.compareTo(b.value.delta));
    for (final e in piores.take(5)) {
      print('   ${e.key}: ${e.value.antes} → ${e.value.depois} (${e.value.delta})');
    }

    // O banco local continua exatamente como estava.
    final depoisDoDump = await _somarRegistros(empresaId);
    expect(depoisDoDump, antesDoDump,
        reason: 'a simulação NÃO pode alterar o banco local');
    print('banco local intacto: $antesDoDump registros');
  }, timeout: const Timeout(Duration(minutes: 10)));
}

/// Quantos produtos a empresa tem no banco local (proxy para escolher a empresa
/// com dados de verdade no teste). 0 quando não dá para consultar.
Future<int> _contarProdutos(String empresaId) async {
  final psql = _acharPsql();
  if (psql == null) return 0;
  final ambiente = Map<String, String>.from(Platform.environment);
  ambiente['PGPASSWORD'] = _env('DB_PASSWORD');
  ambiente['PGCLIENTENCODING'] = 'UTF8';
  try {
    final result = await Process.run(
      psql,
      [
        '-h', _env('DB_HOST', '127.0.0.1'),
        '-p', _env('DB_PORT', '5432'),
        '-U', _env('DB_USER', 'exodo_user'),
        '-d', _env('DB_NAME', 'exodo_db'),
        '--no-psqlrc', '-A', '-t',
        '-c', "SELECT count(*) FROM public.produtos WHERE empresa_id = '$empresaId';",
      ],
      environment: ambiente,
    );
    return int.tryParse((result.stdout as String).trim()) ?? 0;
  } catch (_) {
    return 0;
  }
}

/// Soma os registros da empresa em todas as tabelas do banco local que têm
/// empresa_id (mesma lista que o serviço usa), para provar que nada mudou.
Future<int> _somarRegistros(String empresaId) async {
  final psql = _acharPsql();
  if (psql == null) return -1;
  final ambiente = Map<String, String>.from(Platform.environment);
  ambiente['PGPASSWORD'] = _env('DB_PASSWORD');
  ambiente['PGCLIENTENCODING'] = 'UTF8';

  final tabelas = await Process.run(
    psql,
    [
      '-h', _env('DB_HOST', '127.0.0.1'),
      '-p', _env('DB_PORT', '5432'),
      '-U', _env('DB_USER', 'exodo_user'),
      '-d', _env('DB_NAME', 'exodo_db'),
      '--no-psqlrc', '-A', '-t',
      '-c', "SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace "
          "WHERE n.nspname='public' AND c.relkind='r' AND EXISTS (SELECT 1 FROM pg_attribute e "
          "WHERE e.attrelid=c.oid AND e.attname='empresa_id' AND e.attnum>0 AND NOT e.attisdropped) "
          "AND c.relname NOT IN ('sync_logs','sync_status');",
    ],
    environment: ambiente,
  );

  var total = 0;
  for (final tabela in (tabelas.stdout as String).split(RegExp(r'\r?\n'))) {
    final nome = tabela.trim();
    if (nome.isEmpty) continue;
    final result = await Process.run(
      psql,
      [
        '-h', _env('DB_HOST', '127.0.0.1'),
        '-p', _env('DB_PORT', '5432'),
        '-U', _env('DB_USER', 'exodo_user'),
        '-d', _env('DB_NAME', 'exodo_db'),
        '--no-psqlrc', '-A', '-t',
        '-c', "SELECT count(*) FROM public.\"$nome\" WHERE empresa_id = '$empresaId';",
      ],
      environment: ambiente,
    );
    total += int.tryParse((result.stdout as String).trim()) ?? 0;
  }
  return total;
}

String _env(String chave, [String padrao = '']) {
  try {
    final linhas = File('.env').readAsLinesSync();
    for (final linha in linhas) {
      if (linha.startsWith('$chave=')) {
        return linha.substring(chave.length + 1).trim();
      }
    }
  } catch (_) {}
  return padrao;
}

String? _acharPsql() {
  for (final caminho in [
    'C:\\SistemaExodo\\postgresql\\bin\\psql.exe',
    'psql.exe',
  ]) {
    if (caminho == 'psql.exe' || File(caminho).existsSync()) return caminho;
  }
  return null;
}
