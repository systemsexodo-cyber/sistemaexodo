// A regra dos "5 últimos" dos backups: o que sobe para a nuvem e o que fica
// no computador.
//
// O pedido é direto: os backups LOCAIS sobem para a nuvem e o app guarda sempre
// os 5 mais recentes — na pasta da empresa aqui (`C:\ExodoBackups\<id>`, com os
// `.dump` em `dumps\`) e na pasta dela no bucket `dumps` da nuvem.
//
// Este teste cobre a parte que DECIDE quem sai e quem sobe (funções puras, sem
// tocar em disco nem em rede) e, no fim, poda uma pasta de verdade usando uma
// empresa de teste que é criada e apagada aqui mesmo.
//
// Rodar: flutter test test/backup_cinco_ultimos_test.dart

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_exodo_novo/services/backup_restore_service.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  // Empresas de teste: pastas isoladas dentro de C:\ExodoBackups, apagadas no
  // fim. Nunca usam o id de uma empresa de verdade.
  const idTeste = '__teste_cinco_ultimos__';
  const idOutra = '__teste_cinco_ultimos_outra__';

  final base = DateTime(2026, 9, 1, 8);

  /// Lista de arquivos (nome + data) como o serviço monta a partir do disco.
  List<({String nome, DateTime data})> arquivos(int quantos, {String ext = 'dump'}) =>
      [for (var i = 0; i < quantos; i++)
        (nome: 'b_$i.$ext', data: base.add(Duration(days: i)))];

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

  setUpAll(prepararAmbiente);

  tearDownAll(() async {
    for (final id in const [idTeste, idOutra]) {
      final pasta = Directory(BackupRestoreService.pastaBackupDaEmpresa(id));
      if (await pasta.exists()) await pasta.delete(recursive: true);
    }
  });

  test('o limite da regra são 5 backups por empresa', () {
    expect(BackupRestoreService.maxBackupsPorEmpresa, 5);
  });

  test('com 7 arquivos, saem os 2 mais antigos (e o resto fica)', () {
    final sair = BackupRestoreService.backupsQuePassamDoLimite(arquivos(7));
    expect(sair, ['b_1.dump', 'b_0.dump'],
        reason: 'ficam b_6..b_2 (os 5 últimos) e saem os mais antigos');
  });

  test('até 5 arquivos, nada sai', () {
    expect(BackupRestoreService.backupsQuePassamDoLimite(arquivos(1)), isEmpty);
    expect(BackupRestoreService.backupsQuePassamDoLimite(arquivos(5)), isEmpty);
  });

  test('só sobe o que ainda não está na nuvem — e só entre os 5 últimos', () {
    final locais = arquivos(7);
    final faltam = BackupRestoreService.backupsQueFaltamNaNuvem(
      locais,
      {'b_6.dump', 'b_5.dump'},
    );
    expect(faltam, ['b_4.dump', 'b_3.dump', 'b_2.dump'],
        reason: 'b_6 e b_5 já estão lá; b_1 e b_0 são antigos demais para subir');
    expect(BackupRestoreService.backupsQueFaltamNaNuvem(locais, {
      'b_6.dump',
      'b_5.dump',
      'b_4.dump',
      'b_3.dump',
      'b_2.dump',
    }), isEmpty);
  });

  test('o backup sobe com o MESMO nome que tem no computador (sem acento)', () {
    const dumps = 'E_O_BICHO_PETSHOP_dump_diario_2026-09-25_1031.dump';
    const sql = 'É_O_BICHO_PETSHOP_empresa_2026-09-25_1031.sql';

    expect(BackupRestoreService.nomeNaNuvemPara(dumps, 'E_O_BICHO_PETSHOP', base),
        dumps,
        reason: 'mesmo nome = a tela sabe o que já subiu e reenviar não duplica');
    expect(BackupRestoreService.nomeNaNuvemPara(sql, 'E_O_BICHO_PETSHOP', base),
        'E_O_BICHO_PETSHOP_empresa_2026-09-25_1031.sql',
        reason: 'o acento sai: o Storage recusa chave acentuada');
    // A MESMA transformação vale para o nome que vem da lista da nuvem — é a
    // comparação dos dois lados que diz o que já subiu.
    expect(BackupRestoreService.nomeSeguroParaStorage(sql),
        'E_O_BICHO_PETSHOP_empresa_2026-09-25_1031.sql');
    expect(BackupRestoreService.nomeSeguroParaStorage('É_O_BICHO_PETSHOP'),
        'E_O_BICHO_PETSHOP');

    for (final sujo in const [
      'É_O_BICHO_PETSHOP_empresa.sql',
      'Café & Cia (filial 2)_dump.dump',
      'Ação ção ~ã}*/\\',
    ]) {
      final limpo = BackupRestoreService.nomeSeguroParaStorage(sujo);
      expect(RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(limpo), isTrue,
          reason: 'sobrou caractere recusado pelo Storage em "$limpo"');
    }

    // Nome que não serve para identificar um backup: monta um novo, com data e hora.
    expect(
      BackupRestoreService.nomeNaNuvemPara(
          'sem extensao', 'E_O_BICHO_PETSHOP', DateTime(2026, 9, 26, 14, 5)),
      'E_O_BICHO_PETSHOP_dump_2026-09-26_1405.dump',
    );
    expect(
      BackupRestoreService.nomeNaNuvemPara(
          'empresa_final.sql', 'E_O_BICHO_PETSHOP', DateTime(2026, 9, 26, 14, 5)),
      'empresa_final.sql',
    );
  });

  test('na pasta da empresa ficam os 5 últimos de cada tipo', () async {
    final service = BackupRestoreService(DataService());

    final dumps = Directory(BackupRestoreService.pastaDumpsLocais(idTeste));
    await dumps.create(recursive: true);
    final pasta = Directory(BackupRestoreService.pastaBackupDaEmpresa(idTeste));
    await pasta.create(recursive: true);

    // 7 dumps (i = 0 é o mais antigo) + 7 .sql desta empresa.
    for (var i = 0; i < 7; i++) {
      final dia = (i + 1).toString().padLeft(2, '0');
      final f = File(p.join(dumps.path, 'D${i}_dump_diario_2026-09-${dia}_0800.dump'));
      await f.writeAsString('PGDMP ${'x' * 20}\n');
      await f.setLastModified(DateTime.now().subtract(Duration(days: 10 - i)));

      final s = File(p.join(pasta.path, 'E_empresa_2026-09-${dia}_0900.sql'));
      await s.writeAsString('-- empresa_id: $idTeste\n'
          '-- Tabelas: 42 | Registros: 14277\nSELECT 1;\n');
      await s.setLastModified(DateTime.now().subtract(Duration(days: 10 - i)));
    }

    // Arquivos que NÃO são desta empresa: não entram na conta e não podem sair.
    final daOutra = File(p.join(pasta.path, 'OUTRA_empresa_2026-09-01_0900.sql'));
    await daOutra.writeAsString('-- empresa_id: $idOutra\nSELECT 1;\n');
    final semCabecalho = File(p.join(pasta.path, 'SEM_CABECALHO.sql'));
    await semCabecalho.writeAsString('-- arquivo qualquer\nSELECT 1;\n');

    final antes = await service.listarBackupsLocaisDaEmpresa(idTeste);
    expect(antes.where((b) => b.nome.endsWith('.dump')), hasLength(7));
    expect(antes.where((b) => b.nome.endsWith('.sql')), hasLength(7),
        reason: 'o .sql da OUTRA empresa não é backup desta');
    expect(antes.where((b) => b.nome.startsWith('E_empresa_')).first.nome,
        'E_empresa_2026-09-07_0900.sql',
        reason: 'mais recente primeiro');

    final removidos = await service.manterUltimosBackupsLocais(idTeste);
    expect(removidos, 4, reason: '2 dumps + 2 .sql antigos saem');

    final dumpsRestantes =
        (dumps.listSync().whereType<File>().map((f) => p.basename(f.path)).toList())
          ..sort();
    expect(dumpsRestantes, [
      'D2_dump_diario_2026-09-03_0800.dump',
      'D3_dump_diario_2026-09-04_0800.dump',
      'D4_dump_diario_2026-09-05_0800.dump',
      'D5_dump_diario_2026-09-06_0800.dump',
      'D6_dump_diario_2026-09-07_0800.dump',
    ]);

    final sqlRestantes =
        (pasta.listSync().whereType<File>().map((f) => p.basename(f.path)).toList())
          ..sort();
    expect(sqlRestantes, [
      'E_empresa_2026-09-03_0900.sql',
      'E_empresa_2026-09-04_0900.sql',
      'E_empresa_2026-09-05_0900.sql',
      'E_empresa_2026-09-06_0900.sql',
      'E_empresa_2026-09-07_0900.sql',
      'OUTRA_empresa_2026-09-01_0900.sql',
      'SEM_CABECALHO.sql',
    ], reason: 'arquivos de outras empresas (ou sem cabeçalho) nunca são apagados');

    // Rodar de novo não apaga mais nada: já está dentro da regra.
    expect(await service.manterUltimosBackupsLocais(idTeste), 0);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
