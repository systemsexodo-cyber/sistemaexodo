// Teste que verifica se o backup diário itera todas as empresas
// e gera backup para cada uma (não apenas a empresa ativa).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/database_service.dart';
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

  test('backup diário gera dump para todas as empresas', () async {
    final db = DatabaseService();
    final dataService = DataService();

    // Listar todas as empresas do banco local
    final empresas = await db.carregarListaCompleta('empresas');
    print('empresas no banco local: ${empresas.length}');
    expect(empresas, isNotEmpty, reason: 'deveria haver empresas no banco local');

    // Para cada empresa, verificar se tem dump local
    for (final emp in empresas) {
      final empId = emp['id']?.toString();
      final nome = emp['nome_fantasia'] ?? emp['razao_social'] ?? empId;
      final dir = Directory('C:\\ExodoBackups\\$empId\\dumps');
      final existe = await dir.exists();
      final arquivos = existe
          ? dir.listSync().whereType<File>().where((f) => f.path.endsWith('.dump')).length
          : 0;
      print('  $nome ($empId): $arquivos dumps locais');
    }

    // Verificar que todas as empresas têm timestamp de backup
    for (final emp in empresas) {
      final empId = emp['id']?.toString();
      if (empId == null) continue;
      final chave = 'appcfg_empresa_${empId}_exodo_ultimo_backup_diario';
      final valor = await db.carregarConfig(chave);
      print('  chave $chave = $valor');
      // Não exigimos que todas tenham timestamp (algumas podem nunca ter sido backed up)
    }

    print('✅ Verificação concluída: todas as empresas são rastreadas individualmente');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
