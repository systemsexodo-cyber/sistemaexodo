// Teste do REENVIO do dump diário.
//
// Cenário real que isto corrige: o app abre sem internet (ou o Supabase ainda
// não subiu), gera o dump local às 08:56, PULA o upload — e gravava a marca de
// 24h de qualquer forma, então aquele dump nunca chegava à nuvem.
//
// Aqui o caminho do dump é marcado como pendente (como o próprio app faz) e o
// `reenviarDumpPendente()` precisa:
//   1. subir o arquivo para a pasta da empresa na nuvem (um arquivo novo);
//   2. limpar a marca de pendência;
//   3. não fazer nada quando não há pendência.
//
// Usa um arquivo minúsculo de teste e APAGA da nuvem o arquivo que subiu.
//
// Rodar: flutter test test/backup_dump_pendente_test.dart

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

  const bmj = '22ae2c16-a730-43f3-a4f9-19f105eb0d13';
  const bucket = 'dumps';
  const chavePendente = 'appcfg_empresa_${bmj}_exodo_dump_pendente_envio';

  late Directory tmp;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('exodo_dump_pendente');
  });

  tearDownAll(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

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

  test('dump pendente é reenviado e a pendência é limpa', () async {
    prepararAmbiente();
    try {
      Supabase.instance.client;
    } catch (_) {
      await Supabase.initialize(url: SupabaseConfig.url, anonKey: SupabaseConfig.anonKey);
    }

    final db = DatabaseService();
    final dataService = DataService();
    await dataService.definirEmpresaAtual(bmj, modoLeve: true);
    final client = Supabase.instance.client;

    Set<String> arquivosDaEmpresa(Set<String> nomes) => nomes;

    final antes = arquivosDaEmpresa(
      (await client.storage.from(bucket).list(path: '$bmj/')).map((f) => f.name).toSet(),
    );
    print('arquivos na pasta da empresa antes: ${antes.length}');

    // Nenhuma pendência: não pode fazer nada.
    await db.salvarConfig(chavePendente, '');
    await dataService.reenviarDumpPendente();
    expect((await db.carregarConfig(chavePendente)).toString(), isEmpty,
        reason: 'sem pendência o método não deveria criar nenhuma');

    // Agora simula o caso real: o dump foi gerado mas não subiu.
    final arquivo = File('${tmp.path}${Platform.pathSeparator}dump_pendente_teste.dump');
    await arquivo.writeAsString('PGDMP-teste-de-reenvio\n${'x' * 300}\n', flush: true);
    await db.salvarConfig(chavePendente, arquivo.path);
    print('pendência marcada: ${await db.carregarConfig(chavePendente)}');

    await dataService.reenviarDumpPendente();

    // 1. Subiu um arquivo novo para a pasta da empresa
    final depois = (await client.storage.from(bucket).list(path: '$bmj/'))
        .map((f) => f.name)
        .toSet();
    final novos = depois.difference(antes);
    print('novos arquivos na nuvem: $novos');
    expect(novos, hasLength(1), reason: 'era para subir exatamente o dump pendente');
    expect(novos.first, contains('_dump_'),
        reason: 'o reenvio precisa continuar identificando o dump como dump');
    expect(novos.first, endsWith('.dump'));

    // 2. A pendência foi limpa
    final pendenteDepois = (await db.carregarConfig(chavePendente)).toString();
    print('pendência depois do reenvio: "$pendenteDepois"');
    expect(pendenteDepois, isEmpty, reason: 'a pendência deveria ter sido limpa');

    // 3. Chamar de novo não faz nada (nem duplica arquivo)
    await dataService.reenviarDumpPendente();
    final depois2 = (await client.storage.from(bucket).list(path: '$bmj/'))
        .map((f) => f.name)
        .toSet();
    expect(depois2, depois, reason: 'a segunda chamada não pode subir outro arquivo');

    // Limpeza: remove da nuvem o arquivo de teste.
    await client.storage.from(bucket).remove(['$bmj/${novos.first}']);
    final final_ = (await client.storage.from(bucket).list(path: '$bmj/'))
        .map((f) => f.name)
        .toSet();
    expect(final_, antes, reason: 'a limpeza do arquivo de teste falhou');
    print('limpeza confirmada — pasta da empresa voltou a ${final_.length} arquivos');
  }, timeout: const Timeout(Duration(minutes: 12)));
}
