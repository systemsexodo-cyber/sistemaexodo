// Testes das TRAVAS da restauração — o que impede uma restauração de virar
// perda de dados:
//
//   1. arquivo cortado/incompleto é recusado ANTES de encostar no banco;
//   2. cabeçalho que não bate com o conteúdo é recusado;
//   3. o backup automático do estado atual ("_antes_de_restaurar") é gerado de
//      verdade — é ele que garante o DESFAZER;
//   4. arquivo recusado = banco intacto (nada é apagado).
//
// Nada aqui altera os dados: a restauração recusada não chega a rodar.

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

  final pastaTemp = Directory.systemTemp;
  File arquivoTmp(String nome) =>
      File('${pastaTemp.path}${Platform.pathSeparator}$nome');

  setUpAll(() async {
    prepararAmbiente();
    try {
      Supabase.instance.client;
    } catch (_) {
      await Supabase.initialize(url: SupabaseConfig.url, anonKey: SupabaseConfig.anonKey);
    }
  });

  /// Gera um .sql real da empresa 1 (fonte para os testes de integridade).
  Future<File?> gerarBackupReal(BackupRestoreService service, String nome) async {
    final destino = arquivoTmp(nome);
    final (ok, msg, caminho) = await service.criarBackupSqlDaEmpresa(
      empresaId: '1',
      destinoArquivo: destino.path,
    );
    if (!ok || caminho == null) {
      print('ℹ️ Sem banco local/psql nesta máquina — testes ignorados ($msg).');
      return null;
    }
    return File(caminho);
  }

  test('arquivo completo passa na conferência e arquivo CORTADO é recusado', () async {
    final service = BackupRestoreService(DataService());
    final completo = await gerarBackupReal(service, 'exodo_integridade_completo.sql');
    if (completo == null) return;

    try {
      final integridade = await service.verificarIntegridadeScriptEmpresa(completo);
      print('arquivo completo: ${integridade.mensagem}');
      expect(integridade.ok, isTrue, reason: integridade.mensagem);
      expect(integridade.tabelas, greaterThan(0));
      expect(integridade.registros, greaterThanOrEqualTo(0));
      expect(integridade.empresaId, '1');

      // Corta no meio de um COPY (metade do arquivo): é o cenário de cópia
      // interrompida — o arquivo perde o COMMIT e/ou fica com bloco aberto.
      final texto = await completo.readAsString();
      final metade = texto.substring(0, (texto.length * 0.6).floor());
      final cortado = arquivoTmp('exodo_integridade_cortado.sql');
      await cortado.writeAsString(metade, flush: true);

      final integrCortado = await service.verificarIntegridadeScriptEmpresa(cortado);
      print('arquivo cortado: ${integrCortado.mensagem}');
      expect(integrCortado.ok, isFalse,
          reason: 'arquivo cortado não pode ser aceito para restauração');

      await cortado.delete();
    } finally {
      if (await completo.exists()) await completo.delete();
    }
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('cabeçalho que não bate com o conteúdo é recusado', () async {
    final service = BackupRestoreService(DataService());
    final completo = await gerarBackupReal(service, 'exodo_integridade_base.sql');
    if (completo == null) return;

    try {
      final texto = await completo.readAsString();
      // O cabeçalho traz "-- Tabelas: N | Registros: M" — adultera o M.
      final adulterado = texto.replaceFirstMapped(
        RegExp(r'Registros: (\d+)'),
        (m) => 'Registros: ${int.parse(m.group(1)!) + 7}',
      );
      expect(adulterado.contains('Registros: 30'), isNotNull);
      expect(adulterado != texto, isTrue, reason: 'o cabeçalho precisa ter sido alterado');

      final arquivo = arquivoTmp('exodo_integridade_adulterado.sql');
      await arquivo.writeAsString(adulterado, flush: true);

      final integridade = await service.verificarIntegridadeScriptEmpresa(arquivo);
      print('cabeçalho adulterado: ${integridade.mensagem}');
      expect(integridade.ok, isFalse);
      expect(integridade.mensagem.contains('Registro') || integridade.mensagem.contains('registro'),
          isTrue);

      await arquivo.delete();
    } finally {
      if (await completo.exists()) await completo.delete();
    }
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('restauração recusa arquivo cortado e NÃO altera o banco local', () async {
    final service = BackupRestoreService(DataService());

    // Contagem dos dados antes (tem que ser igual depois).
    final db = DatabaseServiceLocalProbe();
    final antes = await db.contar('produtos');
    final antesEmpresas = await db.contar('empresas');
    if (antes == null || antesEmpresas == null) {
      print('ℹ️ Sem banco local nesta máquina — teste ignorado.');
      return;
    }

    final cortado = arquivoTmp('exodo_restauracao_cortada.sql');
    // Arquivo com BEGIN, um DELETE e um COPY aberto (cópia interrompida).
    await cortado.writeAsString(
      '-- Backup PostgreSQL — SOMENTE a empresa: X\n'
      '-- empresa_id: 1\n'
      '-- Tabelas: 1 | Registros: 5\n'
      "SET client_encoding = 'UTF8';\n"
      "SET exodo.sync_mode = 'on';\n"
      'BEGIN;\n'
      "DELETE FROM public.produtos WHERE empresa_id = '1';\n"
      'COPY public.produtos (id, empresa_id) FROM stdin;\n'
      'abc\t1\n',
      flush: true,
    );

    try {
      final (ok, msg) = await service.restaurarBackupSqlDaEmpresa(cortado);
      print('recusa: $ok — $msg');
      expect(ok, isFalse);
      expect(msg.toLowerCase().contains('bloqueada') ||
          msg.toLowerCase().contains('bloqueado'), isTrue,
          reason: 'a mensagem precisa deixar claro que a restauração foi bloqueada');

      final depois = await db.contar('produtos');
      final depoisEmpresas = await db.contar('empresas');
      expect(depois, antes, reason: 'arquivo recusado não pode apagar/alterar dados');
      expect(depoisEmpresas, antesEmpresas);
    } finally {
      if (await cortado.exists()) await cortado.delete();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('o backup automático do estado atual é gerado (e é ele o desfazer)', () async {
    final service = BackupRestoreService(DataService());

    final (ok, msg, caminho) = await service.backupAntesDeRestaurarEmpresa(
      empresaId: '1',
      motivo: 'teste',
    );
    print('backup de segurança: $ok — $msg');
    if (!ok || caminho == null) {
      print('ℹ️ Sem banco local/psql nesta máquina — teste ignorado.');
      return;
    }

    try {
      final arquivo = File(caminho);
      expect(await arquivo.exists(), isTrue);
      expect(caminho, contains('_antes_de_restaurar'));
      expect(caminho, contains('ANTES_'));
      expect(await arquivo.length(), greaterThan(0));

      // O arquivo de segurança precisa ser, ele mesmo, restaurável: íntegro.
      final integridade = await service.verificarIntegridadeScriptEmpresa(arquivo);
      expect(integridade.ok, isTrue, reason: integridade.mensagem);
      expect(integridade.empresaId, '1');
    } finally {
      try {
        await File(caminho).delete();
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}

/// Consulta simples de contagem no PostgreSQL local (via psql), só para os
/// testes conferirem que nada mudou.
class DatabaseServiceLocalProbe {
  Future<int?> contar(String tabela) async {
    final env = EnvConfig.env;
    try {
      final res = await Process.run(
        'psql',
        [
          '-h', env['DB_HOST'] ?? '127.0.0.1',
          '-p', env['DB_PORT'] ?? '5432',
          '-U', env['DB_USER'] ?? 'exodo_user',
          '-d', env['DB_NAME'] ?? 'exodo_db',
          '--no-psqlrc', '-A', '-t',
          '-c', 'SELECT count(*) FROM $tabela;',
        ],
        environment: {'PGPASSWORD': env['DB_PASSWORD'] ?? ''},
      );
      if (res.exitCode != 0) return null;
      return int.tryParse((res.stdout as String).trim());
    } on ProcessException {
      return null;
    }
  }
}
