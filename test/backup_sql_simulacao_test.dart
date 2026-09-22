// Teste do 🔎 SIMULAR de um backup `.sql` POR EMPRESA — o mesmo caminho que a
// lista da nuvem usa depois de baixar o arquivo.
//
// O que este arquivo prova:
//   1. a simulação lê as linhas de cada tabela DENTRO do arquivo (blocos COPY) e
//      compara com o banco local, sem criar base temporária;
//   2. o total de linhas lido bate com o cabeçalho do arquivo (mesma conta que a
//      conferência de integridade faz);
//   3. rodar duas vezes dá exatamente o mesmo resultado — ou seja, SIMULAR NÃO
//      ALTERA NADA no banco local;
//   4. arquivo cortado é recusado com o motivo, antes de qualquer coisa.
//
// Usa os backups .sql que já existem na máquina (C:\ExodoBackups), então roda
// contra dados reais sem precisar de empresa aberta no app.

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

  late BackupRestoreService service;

  setUpAll(() async {
    prepararAmbiente();
    try {
      Supabase.instance.client;
    } catch (_) {
      await Supabase.initialize(url: SupabaseConfig.url, anonKey: SupabaseConfig.anonKey);
    }
    service = BackupRestoreService(DataService());
  });

  /// O `.sql` por empresa mais recente da máquina (o mesmo tipo de arquivo que
  /// fica na nuvem: o da nuvem é este arquivo enviado para o bucket).
  File? arquivoDeEmpresa() {
    final pasta = Directory('C:\\ExodoBackups');
    if (!pasta.existsSync()) return null;
    final arquivos = pasta
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.sql'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    for (final f in arquivos) {
      final linhas = f.readAsLinesSync().take(40);
      if (linhas.any((l) => l.trimLeft().startsWith('-- empresa_id:'))) return f;
    }
    return null;
  }

  test('simulação lê as linhas por tabela do arquivo e compara com o banco local', () async {
    final arquivo = arquivoDeEmpresa();
    expect(arquivo, isNotNull,
        reason: 'precisa de um backup .sql por empresa em C:\\ExodoBackups para este teste');

    final cabecalho = await service.lerCabecalhoScriptEmpresa(arquivo!);
    expect(cabecalho.empresaId, isNotNull);

    // Leitura por tabela (o que a simulação usa).
    final porTabela = await service.contarLinhasDoScriptEmpresa(arquivo);
    expect(porTabela, isNotEmpty);

    final somaArquivo = porTabela.values.fold<int>(0, (s, v) => s + v);
    // ignore: avoid_print
    print('Arquivo: ${arquivo.path}');
    // ignore: avoid_print
    print('Tabelas: ${porTabela.length} | linhas lidas: $somaArquivo | '
        'cabeçalho: ${cabecalho.tabelas} tabela(s) / ${cabecalho.registros} registro(s)');

    expect(porTabela.length, cabecalho.tabelas,
        reason: 'a leitura por tabela tem de achar o mesmo número de tabelas do cabeçalho');
    expect(somaArquivo, cabecalho.registros,
        reason: 'a soma das linhas por tabela tem de bater com o total do cabeçalho');

    // Simulação completa.
    final (ok, msg, comparativo) = await service.simularRestauracaoBackupSqlDaEmpresa(arquivo);
    // ignore: avoid_print
    print('--- SIMULAÇÃO ---\n$msg');
    for (final e in (comparativo ?? {}).entries) {
      // ignore: avoid_print
      print('  ${e.key.padRight(24)} hoje=${e.value.antes.toString().padLeft(6)} '
          'arquivo=${e.value.depois.toString().padLeft(6)} Δ=${e.value.delta}');
    }

    expect(ok, isTrue, reason: msg);
    expect(comparativo, isNotNull);
    expect(comparativo!, isNotEmpty);

    // Toda tabela comparada tem de estar no arquivo, e o "depois" é a contagem
    // do próprio arquivo.
    for (final entry in comparativo.entries) {
      expect(porTabela.containsKey(entry.key), isTrue);
      expect(entry.value.depois, porTabela[entry.key]);
      expect(entry.value.delta, entry.value.depois - entry.value.antes);
    }

    // Explica o que ficou fora da conta (tabelas sem empresa_id no banco local).
    final foraDaConta = porTabela.keys.where((t) => !comparativo.containsKey(t)).toList();
    // ignore: avoid_print
    print('Fora da conta (sem empresa_id no local): ${foraDaConta.join(', ')}');
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('simular duas vezes dá o mesmo resultado (não altera o banco local)', () async {
    final arquivo = arquivoDeEmpresa();
    expect(arquivo, isNotNull);

    final (ok1, msg1, primeira) = await service.simularRestauracaoBackupSqlDaEmpresa(arquivo!);
    expect(ok1, isTrue, reason: msg1);
    final (ok2, msg2, segunda) = await service.simularRestauracaoBackupSqlDaEmpresa(arquivo);
    expect(ok2, isTrue, reason: msg2);

    expect((segunda ?? {}).keys.toSet(), (primeira ?? {}).keys.toSet());
    for (final tabela in primeira!.keys) {
      expect(segunda![tabela]!.antes, primeira[tabela]!.antes,
          reason: 'o banco local não pode ter mudado em $tabela (simular não grava nada)');
      expect(segunda[tabela]!.depois, primeira[tabela]!.depois);
    }
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('backup que está NA NUVEM: baixar e simular (o caminho do 🔎/↺ da lista)', () async {
    // Este é exatamente o caminho do botão da nuvem: descobre o arquivo no
    // bucket, baixa para C:\ExodoBackups\nuvem\baixados e roda a simulação em
    // cima do arquivo baixado. O que NÃO é feito aqui é o "aplicar" — isso
    // mudaria o banco local, e é uma decisão do usuário na tela.
    final cliente = SupabaseClient(SupabaseConfig.url, SupabaseConfig.anonKey);
    final bucket = cliente.storage.from('dumps');

    final raiz = await bucket.list();
    final pastas = raiz
        .where((e) => (e.id == null && e.name.isNotEmpty) || e.name.endsWith('/'))
        .map((e) => e.name.endsWith('/') ? e.name : '${e.name}/')
        .toList();
    // ignore: avoid_print
    print('Pastas no bucket dumps: $pastas');

    final candidatos = <({String pasta, String nome, String path})>[];
    for (final pasta in pastas) {
      final arquivos = await bucket.list(path: pasta);
      for (final a in arquivos) {
        if (a.name.toLowerCase().endsWith('.sql')) {
          candidatos.add((pasta: pasta, nome: a.name, path: '$pasta${a.name}'));
        }
      }
    }
    expect(candidatos, isNotEmpty,
        reason: 'não há backup .sql por empresa no bucket — faça um "Fazer Backup da Empresa Agora"');

    final escolhido = candidatos.first;
    // ignore: avoid_print
    print('Baixando da nuvem: ${escolhido.path}');

    final (okDown, msgDown, localPath) = await service.downloadDumpDaNuvem(
      escolhido.path,
      destino: BackupRestoreService.pastaNuvemBaixados,
    );
    expect(okDown, isTrue, reason: msgDown);
    expect(localPath, isNotNull);
    expect(File(localPath!).existsSync(), isTrue);
    expect(localPath, contains('nuvem\\baixados'));

    // O arquivo baixado é um backup por empresa completo (passa na conferência) e
    // a simulação roda em cima dele.
    final cabecalho = await service.lerCabecalhoScriptEmpresa(File(localPath));
    expect(cabecalho.empresaId, isNotNull,
        reason: 'o .sql da nuvem tem de dizer de qual empresa ele é');

    final (okSim, msgSim, comparativo) =
        await service.simularRestauracaoBackupSqlDaEmpresa(File(localPath));
    // ignore: avoid_print
    print('--- SIMULAÇÃO DO ARQUIVO DA NUVEM ---\n$msgSim');

    expect(okSim, isTrue, reason: msgSim);
    expect(comparativo, isNotNull);
    expect(comparativo!, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('arquivo cortado é recusado na simulação, com o motivo', () async {
    final arquivo = arquivoDeEmpresa();
    expect(arquivo, isNotNull);

    // Cópia truncada em 60% — cenário de download/cópia interrompida.
    final texto = arquivo!.readAsStringSync();
    final pasta = Directory.systemTemp.createTempSync('exodo_sim_');
    final cortado = File('${pasta.path}${Platform.pathSeparator}cortado.sql');
    cortado.writeAsStringSync(texto.substring(0, (texto.length * 0.6).round()));

    final (ok, msg, comparativo) =
        await service.simularRestauracaoBackupSqlDaEmpresa(cortado);
    // ignore: avoid_print
    print('Arquivo cortado → $msg');

    expect(ok, isFalse);
    expect(comparativo, isNull);
    expect(msg, contains('recusado'));

    pasta.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
