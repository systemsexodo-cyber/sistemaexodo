// GRAVAÇÃO LOCAL POR REGISTRO — prova do caminho rápido.
//
// As coleções críticas (caixa, vendas, pedidos) deixaram de reescrever a TABELA
// INTEIRA a cada edição: cada alteração grava só a LINHA mexida pelo
// `upsertItem`/`removerItemPostgres`, e o flush completo continua como rede de
// segurança (fechar o app, recargas totais e falha da gravação por registro).
//
// Este teste grava UMA abertura de caixa de teste com id próprio, confirma que
// ela aparece no banco local e depois a remove, deixando a base como estava.
//
// Rodar: flutter test test/gravacao_local_por_registro_test.dart

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_exodo_novo/services/database_service.dart';
import 'package:sistema_exodo_novo/services/local_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  const bmj = '22ae2c16-a730-43f3-a4f9-19f105eb0d13';
  const idTeste = 'teste-gravacao-por-registro-1';

  void prepararAmbiente() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final canal in const [
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers',
      'dev.fluttercommunity.plus/connectivity',
    ]) {
      messenger.setMockMethodCallHandler(
          MethodChannel(canal), (call) async => null);
    }
    for (final canal in const [
      'xyz.luan/audioplayers.global/events',
      'dev.fluttercommunity.plus/connectivity_status',
    ]) {
      messenger.setMockStreamHandler(EventChannel(canal),
          MockStreamHandler.inline(onListen: (args, sink) {}));
    }
  }

  test('upsertItem grava e removerItemPostgres apaga UMA linha de caixa', () async {
    prepararAmbiente();
    final db = DatabaseService();
    db.setEmpresaId(bmj);

    // Contrato que faz o caminho rápido escolher (ou não) a tabela real.
    expect(db.temTabelaPara(LocalStorageService.keyAberturasCaixa), isTrue);
    expect(db.temTabelaPara(LocalStorageService.keyVendasBalcao), isTrue);
    expect(db.temTabelaPara(LocalStorageService.keyPedidos), isTrue);
    expect(db.temTabelaPara('exodo_chave_sem_tabela_propria'), isFalse);

    await db.upsertItem(
      LocalStorageService.keyAberturasCaixa,
      <String, dynamic>{
        'id': idTeste,
        'numero': 'CAIXA-TESTE-REGISTRO',
        'dataAbertura': DateTime.now().toIso8601String(),
        'valorInicial': 1.0,
        'responsavel': 'teste@por-registro.local',
        'empresa_id': bmj,
      },
      lancarSeFalhar: true,
    );

    final aposGravar =
        await db.carregarLista(LocalStorageService.keyAberturasCaixa);
    expect(aposGravar.any((r) => r['id'].toString() == idTeste), isTrue,
        reason: 'a linha gravada por registro deve estar no banco local '
            'sem esperar o flush de tabela inteira');

    await db.removerItemPostgres(
      LocalStorageService.keyAberturasCaixa,
      idTeste,
      bmj,
      lancarSeFalhar: true,
    );

    final aposRemover =
        await db.carregarLista(LocalStorageService.keyAberturasCaixa);
    expect(aposRemover.any((r) => r['id'].toString() == idTeste), isFalse,
        reason: 'a remoção por registro deve apagar só esta linha');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
