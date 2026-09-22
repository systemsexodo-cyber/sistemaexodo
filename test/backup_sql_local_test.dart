// Teste do leitor de cabeçalho dos backups .sql POR EMPRESA que ficam em
// C:\ExodoBackups\<empresaId> (gerados por criarBackupSqlDaEmpresa).
//
// É esse cabeçalho que a tela de Backup e Restauração usa para listar somente os
// backups da empresa selecionada — o nome do arquivo pode estar enganoso.

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

  test('lê o empresa_id do cabeçalho dos backups .sql por empresa', () async {
    final service = BackupRestoreService(DataService());
    final pastas = Directory('C:\\ExodoBackups');
    if (!await pastas.exists()) {
      print('ℹ️ C:\\ExodoBackups não existe nesta máquina — teste ignorado.');
      return;
    }

    var lidos = 0;
    var semCabecalho = 0;
    final porEmpresa = <String, int>{};

    for (final pasta in pastas.listSync().whereType<Directory>()) {
      for (final arquivo in pasta.listSync().whereType<File>()) {
        if (!arquivo.path.toLowerCase().endsWith('.sql')) continue;
        final cabecalho = await service.lerCabecalhoScriptEmpresa(arquivo);
        if (cabecalho.empresaId == null) {
          semCabecalho++;
          continue;
        }
        lidos++;
        porEmpresa[cabecalho.empresaId!] = (porEmpresa[cabecalho.empresaId!] ?? 0) + 1;
      }
    }

    print('arquivos .sql com empresa_id: $lidos | sem cabeçalho: $semCabecalho');
    porEmpresa.forEach((id, qtd) => print('  $id → $qtd arquivo(s)'));

    // Só se exige que o leitor funcione quando existem arquivos desse tipo.
    if (lidos + semCabecalho > 0) {
      expect(lidos, greaterThan(0), reason: 'nenhum cabeçalho de empresa reconhecido');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
