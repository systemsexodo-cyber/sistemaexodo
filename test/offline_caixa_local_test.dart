// REGRESSÃO DO MODO OFFLINE — prioridade ao banco local.
//
// Cenário real que isto corrige: o PC ficou sem internet e o sistema abriu
// SEM os dados de abertura de caixa (fluxo de caixa vazio), mesmo com as 56
// aberturas gravadas no PostgreSQL local.
//
// Duas garantias verificadas aqui:
//   1. Um cache local que contém SÓ caixa já é suficiente para liberar a tela
//      inicial — antes, caixa não contava em `cacheLocalTemDados` e o sistema
//      ficava 60s esperando a nuvem (que não chegava).
//   2. Com a empresa definida, a carga local popula as aberturas/fechamentos
//      de caixa direto do banco do computador — sem tocar na nuvem.
//
// Rodar: flutter test test/offline_caixa_local_test.dart

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_exodo_novo/models/caixa.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  const bmj = '22ae2c16-a730-43f3-a4f9-19f105eb0d13';

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

  AberturaCaixa aberturaDeTeste() => AberturaCaixa(
        id: 'offline-teste-1',
        numero: 'CAIXA-999',
        dataAbertura: DateTime.now(),
        valorInicial: 100,
        responsavel: 'teste@email.com',
      );

  test('cache local só com CAIXA já libera o sistema (sem internet)', () {
    prepararAmbiente();
    final ds = DataService();

    expect(ds.cacheLocalTemDados, isFalse,
        reason: 'DataService recém-criado não tem dados');

    ds.aberturasCaixa.add(aberturaDeTeste());

    expect(ds.cacheLocalTemDados, isTrue,
        reason: 'aberturas de caixa devem contar como "cache local com dados": '
            'sem isto o sistema ficava 60s esperando a nuvem e abria vazio '
            'quando não há internet');

    ds.aberturasCaixa.clear();
    ds.fechamentosCaixa.clear();
    ds.sangrias.clear();
    ds.suprimentos.clear();
    expect(ds.cacheLocalTemDados, isFalse);
  });

  test('com empresa definida, o caixa vem do banco LOCAL', () async {
    prepararAmbiente();
    final ds = DataService();

    // Mesmo caminho do app ao abrir a empresa (aqui sem nuvem inicializada:
    // SupabaseService.isAvailable == false, ou seja, EXATAMENTE o modo
    // offline em que o usuário ficou sem dados de caixa).
    await ds.definirEmpresaAtual(bmj, modoLeve: true);

    expect(ds.aberturasCaixa, isNotEmpty,
        reason: 'as aberturas de caixa do PostgreSQL local devem estar em '
            'memória sem nenhuma chamada à nuvem');
    expect(ds.cacheLocalTemDados, isTrue,
        reason: 'o sistema tem de abrir o fluxo de caixa offline');

    // O vínculo fechamento→abertura é o que mantém o histórico coerente.
    final idsAberturas = ds.aberturasCaixa.map((a) => a.id).toSet();
    final vinculosInvalidos = ds.fechamentosCaixa
        .where((f) => !idsAberturas.contains(f.aberturaCaixaId))
        .length;
    print('>>> aberturas=${ds.aberturasCaixa.length} '
        'fechamentos=${ds.fechamentosCaixa.length} '
        'vinculosInvalidos=$vinculosInvalidos '
        'aberturasAbertas=${ds.aberturasCaixaAbertas.length}');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
