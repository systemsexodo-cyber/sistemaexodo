// Teste da COMPARAÇÃO de esquema Local × Nuvem (modo "somente comparar").
//
// Este teste NÃO cria nada: ele lê o esquema do PostgreSQL local e o do banco da
// nuvem (Supabase, pela conexão do pooler), mostra o que falta lá e salva o SQL
// gerado em C:\ExodoBackups\CRIAR_TABELAS_NUVEM_*.sql para inspeção.

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

  test('compara o esquema local com a nuvem e gera o SQL (sem criar nada)', () async {
    final service = BackupRestoreService(DataService());

    final (ok, logs) = await service.criarTabelasFaltantesNaNuvem(
      somenteComparar: true,
      onProgress: (m) => print('   $m'),
    );

    print('--- LOG DA COMPARAÇÃO ---');
    for (final linha in logs) {
      print(linha);
    }
    print('--- FIM ---');

    expect(ok, isTrue, reason: 'a comparação deveria concluir');
    expect(logs.join('\n'), isNotEmpty);

    // Se gerou SQL, mostra o começo do arquivo para conferência.
    final pasta = Directory('C:\\ExodoBackups');
    if (await pasta.exists()) {
      final arquivos = pasta
          .listSync()
          .whereType<File>()
          .where((f) => f.path.split(Platform.pathSeparator).last.startsWith('CRIAR_TABELAS_NUVEM_'))
          .toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      if (arquivos.isNotEmpty) {
        print('SQL gerado: ${arquivos.first.path}');
        final linhas = arquivos.first.readAsLinesSync();
        print(linhas.take(40).join('\n'));
      }
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
