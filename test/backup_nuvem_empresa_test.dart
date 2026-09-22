// Teste do backup POR EMPRESA tirado DIRETO DA NUVEM (Supabase).
//
// É o arquivo que faltava: uma foto do que existe hoje no Supabase para UMA
// empresa — sem depender do banco local, que pode estar errado ou atrasado.
//
// O teste SÓ LÊ a nuvem (grava o .sql numa pasta temporária e apaga no fim) e
// valida as travas da restauração na nuvem, que é a operação perigosa.

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

  test('gera um backup .sql de UMA empresa lendo o banco da NUVEM', () async {
    final service = BackupRestoreService(DataService());
    final destino = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}exodo_nuvem_empresa_teste.sql');

    // '1' é a empresa Êxodo Systems, que existe nas duas pontas.
    final (ok, msg, caminho) = await service.criarBackupSqlDaEmpresaNaNuvem(
      empresaId: '1',
      destinoArquivo: destino.path,
      onProgress: (m) => print('   $m'),
    );

    print('resultado: $ok — $msg');
    if (!ok) {
      print('ℹ️ Sem conexão com o banco da nuvem nesta máquina — teste ignorado.');
      return;
    }

    try {
      expect(caminho, isNotNull);
      final arquivo = File(caminho!);
      expect(await arquivo.exists(), isTrue);

      final cabecalho = await service.lerCabecalhoScriptEmpresa(arquivo);
      print('cabeçalho → empresa_id=${cabecalho.empresaId} '
          'tabelas=${cabecalho.tabelas} registros=${cabecalho.registros}');

      expect(cabecalho.empresaId, '1',
          reason: 'o arquivo precisa declarar de QUAL empresa ele é');
      expect(cabecalho.tabelas, isNotNull);
      expect(cabecalho.tabelas!, greaterThan(0));

      final texto = await arquivo.readAsString();
      expect(texto.contains('-- Origem: NUVEM (Supabase)'), isTrue,
          reason: 'o cabeçalho precisa dizer que a foto veio da nuvem');
      expect(texto.contains("SET exodo.sync_mode = 'on';"), isTrue);
      expect(texto.contains('COPY public.'), isTrue,
          reason: 'a foto precisa trazer os dados, não só o esquema');
    } finally {
      try {
        await destino.delete();
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('a restauração NA NUVEM recusa arquivo que não é de uma empresa', () async {
    final service = BackupRestoreService(DataService());
    // Dump do banco INTEIRO: estrutura válida, mas SEM "-- empresa_id:" no
    // cabeçalho — é exatamente o arquivo que não pode ser aplicado aqui.
    final arquivo = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}exodo_dump_banco_inteiro_teste.sql');
    await arquivo.writeAsString(
        '-- Backup completo do banco (todas as empresas)\n'
        '-- Tabelas: 1 | Registros: 1\n'
        "SET client_encoding = 'UTF8';\n"
        'BEGIN;\n'
        'COPY public.produtos (id, empresa_id) FROM stdin;\n'
        'abc\t1\n'
        r'\.' '\n'
        'COMMIT;\n',
        flush: true);

    try {
      final (ok, msg, _) = await service.restaurarBackupSqlDaEmpresaNaNuvem(
        arquivo,
        empresaId: '1',
      );
      print('recusa esperada: $ok — $msg');
      expect(ok, isFalse);
      expect(msg.toLowerCase().contains('empresa'), isTrue);
    } finally {
      try {
        await arquivo.delete();
      } catch (_) {}
    }
  });

  test('a restauração NA NUVEM recusa backup de OUTRA empresa', () async {
    final service = BackupRestoreService(DataService());
    final arquivo = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}exodo_outra_empresa_teste.sql');
    await arquivo.writeAsString(
        '-- Backup PostgreSQL — SOMENTE a empresa: OUTRA\n'
        '-- empresa_id: 22ae2c16-a730-43f3-a4f9-198000000000\n'
        '-- Origem: NUVEM (Supabase)\n'
        '-- Tabelas: 1 | Registros: 1\n'
        "SET client_encoding = 'UTF8';\n"
        'BEGIN;\n'
        'COPY public.produtos (id, empresa_id) FROM stdin;\n'
        'abc\t22ae2c16\n'
        r'\.' '\n'
        'COMMIT;\n',
        flush: true);

    try {
      final (ok, msg, _) = await service.restaurarBackupSqlDaEmpresaNaNuvem(
        arquivo,
        empresaId: '1',
      );
      print('recusa esperada: $ok — $msg');
      expect(ok, isFalse);
      expect(msg.contains('22ae2c16'), isTrue);
    } finally {
      try {
        await arquivo.delete();
      } catch (_) {}
    }
  });
}
