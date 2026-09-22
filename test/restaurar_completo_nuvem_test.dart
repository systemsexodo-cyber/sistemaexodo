// Teste da restauração de um backup completo da nuvem → banco da nuvem.
//
// Baixa o backup completo mais recente de `dumps/_banco_completo/` e o
// restaura no banco Supabase via pooler. Como o backup é um snapshot do
// estado ATUAL, os contadores antes e depois devem ser idênticos (delta 0).
// Isso prova que o fluxo inteiro funciona: download → contagens → execução
// do .sql → contagens finais.
//
// ⚠️ Este teste ALTERA o banco da nuvem (restaura o estado atual dele).
// Em produção, a restauração é irreversível — aqui o risco é mínimo porque
// o arquivo é justamente o snapshot do estado presente.
//
// Rodar: flutter test test/restaurar_completo_nuvem_test.dart

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

  test('restaurar o backup completo mais recente e verificar estabilidade', () async {
    final service = BackupRestoreService(DataService());

    // Encontrar o backup mais recente na nuvem
    final lista = await service.listarBackupsCompletosNuvem();
    expect(lista, isNotEmpty, reason: 'nenhum backup completo encontrado na nuvem');
    final maisRecente = lista.first;
    final storagePath = maisRecente['path'] as String;
    final nome = maisRecente['name'] as String;
    final tam = (maisRecente['size'] as num?)?.toInt() ?? 0;
    print('backup selecionado: $nome (${(tam / 1024).toStringAsFixed(0)} KB)');

    // Restaurar (o arquivo é o snapshot do estado atual — os deltas devem ser 0)
    final inicio = DateTime.now();
    final (ok, msg, comparativo) = await service.restaurarBackupCompletoNaNuvem(storagePath);
    final duracao = DateTime.now().difference(inicio).inSeconds;
    print('restauração: ok=$ok | ${duracao}s | $msg');
    expect(ok, isTrue, reason: msg);

    expect(comparativo, isNotNull, reason: 'deveria ter retornado o comparativo');
    print('tabelas comparadas: ${comparativo!.length}');

    // Imprimir e validar o comparativo: deltas devem ser 0 (ou perto)
    int totalDeltas = 0;
    for (final e in comparativo.entries) {
      final d = e.value.delta;
      totalDeltas += d.abs();
      if (d != 0) {
        print('  ${e.key}: ${e.value.antes} → ${e.value.depois} (delta ${d > 0 ? '+' : ''}$d)');
      }
    }
    print('soma dos deltas absolutos: $totalDeltas');

    // O snapshot restaura o estado atual — deltas devem ser 0.
    // Pequenas variações são aceitáveis (ex.: tabelas de log que mudaram entre
    // a geração do backup e a restauração), mas não podem ser > 1% do total.
    final totalLinhas = comparativo.values
        .fold<int>(0, (s, v) => s + v.depois);
    final pctErro = totalLinhas > 0 ? (totalDeltas / totalLinhas * 100) : 0.0;
    print('variação total: ${pctErro.toStringAsFixed(2)}%');
    expect(pctErro, lessThan(1.0),
        reason: 'a restauração de um snapshot não deveria alterar mais de 1% dos dados');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
