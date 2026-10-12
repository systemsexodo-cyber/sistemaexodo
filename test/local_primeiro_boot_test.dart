// LOCAL-PRIMEIRO — o PostgreSQL deste PC abre o sistema; a nuvem é espelho.
//
// Empresa nova (listas vazias) NÃO pode prender a tela em "baixando a nuvem".
// Só a falha do banco local deixa de liberar — aí a nuvem ainda serve de
// fallback.
//
// Rodar: flutter test test/local_primeiro_boot_test.dart

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_exodo_novo/models/caixa.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

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

  test('Postgres atendeu e está vazio: abre SEM esperar a nuvem', () {
    prepararAmbiente();
    DatabaseService().marcarLeituraLocalOkParaTeste();
    final ds = DataService();

    expect(ds.cacheLocalTemDados, isFalse);
    expect(DatabaseService().bancoLocalAtendeu, isTrue);
    expect(ds.deveLiberarTelaInicialSemNuvem, isTrue,
        reason: 'empresa nova (vazio local) é um estado válido — '
            'não pode travar em "Baixando os dados da nuvem"');
  });

  test('Postgres falhou e não há dados: NÃO libera (nuvem ainda é fallback)', () {
    prepararAmbiente();
    DatabaseService().marcarLeituraLocalFalhouParaTeste(
      'SocketException: Connection refused',
    );
    final ds = DataService();

    expect(ds.cacheLocalTemDados, isFalse);
    expect(DatabaseService().bancoLocalFalhou, isTrue);
    expect(ds.deveLiberarTelaInicialSemNuvem, isFalse);
  });

  test('Há dados em memória: libera mesmo se o Postgres falhou depois', () {
    prepararAmbiente();
    DatabaseService().marcarLeituraLocalFalhouParaTeste(
      'SocketException: Connection refused',
    );
    final ds = DataService();
    ds.aberturasCaixa.add(AberturaCaixa(
      id: 'local-primeiro-1',
      numero: 'CAIXA-1',
      dataAbertura: DateTime.now(),
      valorInicial: 10,
      responsavel: 'teste@local',
    ));

    expect(ds.cacheLocalTemDados, isTrue);
    expect(ds.deveLiberarTelaInicialSemNuvem, isTrue);
  });
}
