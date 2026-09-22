// Teste da AUTOMAÇÃO do backup completo do banco da nuvem.
//
// Prova, com o próprio DataService (a mesma função que o timer chama):
//  1. com a chave de controle vazia, ele GERA e ENVIA o backup completo
//     (todas as tabelas, todas as empresas) para a nuvem e grava o horário;
//  2. chamado de novo logo em seguida, ele NÃO gera outro arquivo — a regra do
//     intervalo (24h por padrão) é respeitada, mesmo reabrindo o app;
//  3. o horário fica persistido no banco local (por isso a regra sobrevive a
//     reiniciar o sistema).
//
// ⚠️ Este teste é LENTO de propósito: a primeira chamada lê o banco da nuvem
// inteiro e envia o arquivo (~1 a 2 minutos, ~5 MB). Ele deixa o último backup
// arquivado em `dumps/_banco_completo/` — que é o comportamento real — e
// LIMPA a chave no fim, para o app fazer o backup automático dele quando rodar.
//
// Rodar: flutter test test/backup_completo_automatico_test.dart

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/database_service.dart';
import 'package:sistema_exodo_novo/services/env_config.dart';
import 'package:sistema_exodo_novo/supabase_config.dart';

/// Mesma chave usada pelo DataService para saber quando foi o último envio.
const _chaveManual = 'appcfg_exodo_ultimo_backup_completo_nuvem';

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

  test('backup completo automático: envia uma vez e respeita o intervalo', () async {
    // Não precisa de empresa selecionada: o backup COMPLETO é do banco inteiro.
    final dataService = DataService();

    print('intervalo configurado (.env BACKUP_COMPLETO_NUVEM_HORAS): '
        '${EnvConfig.backupCompletoNuvemHoras}h');
    expect(EnvConfig.backupCompletoNuvemHoras, greaterThan(0),
        reason: 'o backup completo automático precisa estar ligado por padrão');
    expect(EnvConfig.backupCompletoNuvemAtivo, isTrue);

    // Estado inicial: sem chave (equivale a "nunca enviado").
    await DatabaseService().salvarConfig(_chaveManual, '');

    // 1. Deve gerar e enviar o backup COMPLETO.
    final primeira = await dataService.verificarBackupCompletoNuvem(forcar: true);
    print('1a chamada -> $primeira');
    expect(primeira, contains('ENVIADO'),
        reason: 'a primeira chamada deveria gerar e enviar o backup completo');
    expect(dataService.ultimoBackupCompletoNuvem, isNotNull);

    // 2. Logo em seguida NÃO pode gerar outro (regra do intervalo).
    final segunda = await dataService.verificarBackupCompletoNuvem(forcar: true);
    print('2a chamada -> $segunda');
    expect(segunda, contains('faltam'),
        reason: 'a segunda chamada deveria ser barrada pelo intervalo');

    // 3. O horário ficou persistido no banco local.
    final salvo = await DatabaseService().carregarConfig(_chaveManual);
    print('chave de controle no banco local: $salvo');
    expect(salvo, isNotNull);
    final quando = DateTime.tryParse(salvo.toString());
    expect(quando, isNotNull, reason: 'o horário precisa ser uma data ISO válida');
    expect(DateTime.now().difference(quando!).inMinutes, lessThan(10),
        reason: 'o horário gravado deveria ser de agora');
  }, timeout: const Timeout(Duration(minutes: 20)));

  tearDownAll(() async {
    // Devolve o estado "nunca enviado" para o app: assim o backup automático
    // dele roda na próxima abertura, em vez de esperar 24h.
    await DatabaseService().salvarConfig(_chaveManual, '');
  });
}
