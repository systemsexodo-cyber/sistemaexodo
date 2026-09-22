// Teste REAL do "backup completo da nuvem guardado na própria nuvem".
//
// Prova, contra o bucket de verdade (Supabase Storage, bucket 'dumps'):
//  1. o arquivo é enviado para a pasta '_banco_completo/' — fora das pastas por
//     empresa, porque um backup completo contém TODAS as empresas;
//  2. ele aparece na listagem (e nenhum item da lista vem de fora dessa pasta);
//  3. o download devolve exatamente os mesmos bytes;
//  4. a remoção é RECUSADA para caminhos fora de '_banco_completo/';
//  5. os dumps por empresa (ex.: da empresa '1') não são tocados em momento algum.
//
// Rodar: flutter test test/backup_completo_nuvem_test.dart
//
// Usa um arquivo pequeno de teste (parâmetro arquivoLocal), então NÃO gera o
// backup completo do banco: nenhum dado é lido ou alterado, só o arquivo de
// teste, que é enviado, baixado, conferido e apagado da nuvem no fim.

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

  // O binding de teste responde TODO HTTP com 400 e os canais dos plugins não
  // existem aqui. Sem isto não daria para falar com a nuvem de verdade:
  //  - HttpOverrides null => rede real (o SDK do Supabase precisa);
  //  - os 4 canais abaixo são só os do som/notificação do DataService.
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
        EventChannel(canal),
        MockStreamHandler.inline(onListen: (args, sink) {}),
      );
    }
  }

  const bucket = 'dumps';
  const pastaCompleto = '_banco_completo/';
  // Empresa '1' já tem backups por empresa no bucket — é o grupo que NÃO pode
  // ser alterado por este fluxo.
  const pastaEmpresa = '66a880c8-51c7-496f-826b-d2ff9ab8ed2d/';

  late BackupRestoreService service;
  late Directory tmp;

  setUpAll(() async {
    prepararAmbiente();

    try {
      Supabase.instance.client;
    } catch (_) {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        anonKey: SupabaseConfig.anonKey,
      );
    }

    service = BackupRestoreService(DataService());
    tmp = await Directory.systemTemp.createTemp('exodo_backup_completo');
  });

  tearDownAll(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('backup completo da nuvem: enviar, listar, baixar, remover', () async {
    final client = Supabase.instance.client;
    final dumpsEmpresaAntes = await client.storage.from(bucket).list(path: pastaEmpresa);
    print('dumps da empresa antes: ${dumpsEmpresaAntes.length}');

    // Arquivo de teste pequeno (não é o backup completo de verdade).
    final nomeTeste = 'teste_banco_completo_${DateTime.now().millisecondsSinceEpoch}.sql';
    final arquivoTeste = File('${tmp.path}${Platform.pathSeparator}$nomeTeste');
    final conteudo = '-- teste de ida e volta\nSELECT 1;\n${'x' * 800}\n';
    await arquivoTeste.writeAsString(conteudo, flush: true);

    // 1. ENVIAR para a nuvem
    final (okEnviou, msgEnviou, caminhoLocal) =
        await service.enviarBackupCompletoParaNuvem(arquivoLocal: arquivoTeste.path);
    print('envio: ok=$okEnviou | $msgEnviou');
    expect(okEnviou, isTrue, reason: msgEnviou);
    expect(caminhoLocal, arquivoTeste.path);

    // 2. LISTAR — o arquivo precisa estar lá, e TODOS os itens da lista têm que
    // vir da pasta do backup completo.
    final lista = await service.listarBackupsCompletosNuvem();
    print('arquivos completos na nuvem: ${lista.map((a) => a['name']).toList()}');
    final meu = lista.where((a) => a['name'] == nomeTeste).toList();
    expect(meu, hasLength(1), reason: 'o arquivo enviado não apareceu na listagem');
    expect(meu.first['path'], '$pastaCompleto$nomeTeste');
    expect((meu.first['size'] as num).toInt(), greaterThan(0));
    expect(
      lista.every((a) => (a['path'] as String).startsWith(pastaCompleto)),
      isTrue,
      reason: 'a listagem trouxe arquivo fora da pasta _banco_completo',
    );

    // 3. BAIXAR — os bytes têm que ser idênticos.
    final (okBaixou, msgBaixou, destino) =
        await service.baixarBackupCompletoDaNuvem(meu.first['path'] as String);
    print('download: ok=$okBaixou | $msgBaixou | $destino');
    expect(okBaixou, isTrue, reason: msgBaixou);
    final baixado = await File(destino!).readAsString();
    expect(baixado, conteudo, reason: 'o conteúdo baixado difere do enviado');
    await File(destino).delete(); // não deixa sobra em C:\ExodoBackups\nuvem

    // 4. GUARDA: não pode remover nada fora de _banco_completo/
    final recusou = await service.removerBackupCompletoNuvem('${pastaEmpresa}qualquer.dump');
    print('recusou remover caminho de empresa: ${!recusou}');
    expect(recusou, isFalse);
    final eBaixarRecusado = await service.baixarBackupCompletoDaNuvem('${pastaEmpresa}qualquer.dump');
    expect(eBaixarRecusado.$1, isFalse);
    final dumpsEmpresaDepoisDaRecusa =
        await client.storage.from(bucket).list(path: pastaEmpresa);
    expect(dumpsEmpresaDepoisDaRecusa.length, dumpsEmpresaAntes.length,
        reason: 'a tentativa recusada mexeu nos dumps de empresa');

    // 5. REMOVER o arquivo de teste
    final removeu = await service.removerBackupCompletoNuvem('$pastaCompleto$nomeTeste');
    print('removeu o arquivo de teste: $removeu');
    expect(removeu, isTrue);
    final depois = await service.listarBackupsCompletosNuvem();
    expect(depois.any((a) => a['name'] == nomeTeste), isFalse,
        reason: 'o arquivo continua na nuvem');

    // 6. Nenhum dump por empresa foi tocado em todo o fluxo.
    final dumpsEmpresaDepois = await client.storage.from(bucket).list(path: pastaEmpresa);
    print('dumps da empresa depois: ${dumpsEmpresaDepois.length}');
    expect(dumpsEmpresaDepois.length, dumpsEmpresaAntes.length,
        reason: 'os dumps por empresa não podem ser alterados por este fluxo');
  });
}
