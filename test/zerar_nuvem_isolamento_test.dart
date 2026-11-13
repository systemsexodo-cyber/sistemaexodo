// Travas do "Zerar Nuvem" contra apagar dados de OUTRA empresa.
//
// O acidente: o botão mostrava o nome de `empresaAtual` e o serviço apagava
// com `_currentEmpresaId`. Na janela de troca de empresa (memória já é B, id
// ativo ainda A) os dois divergem — e o catálogo da empresa errada ia embora.
//
// Estes testes travam:
//  1. empresa esperada != empresa em memória -> recusa;
//  2. empresa esperada != empresa ativa (id do sync) -> recusa;
//  3. empresa vazia -> recusa;
//  4. empresa '1' (legada, concentra dados de todas) -> recusa.
//
// Nenhum caso chega a tocar a nuvem: as travas rodam antes.
//
// Rodar: flutter test test/zerar_nuvem_isolamento_test.dart

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/sync_monitor_service.dart';

Empresa _empresa(String id) => Empresa(
      id: id,
      razaoSocial: 'Empresa $id',
      slug: id,
      createdAt: DateTime(2026, 10, 1),
      updatedAt: DateTime(2026, 10, 1),
    );

/// Chama o "Zerar Nuvem" e devolve o erro lançado (o teste falha se não lançar).
Future<Object> _erroAoZerar(
  DataService ds, {
  required String empresaEsperada,
}) async {
  try {
    await ds.deletarTudoNoSupabaseDestaEmpresa(
      empresaIdEsperada: empresaEsperada,
    );
  } catch (e) {
    return e;
  }
  fail('deletarTudoNoSupabaseDestaEmpresa não recusou '
      '"$empresaEsperada" — apagaria dados da empresa errada');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Plugins de plataforma não existem num teste headless.
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    Future<Object?> nulo(MethodCall call) async => null;
    for (final canal in const [
      'dev.fluttercommunity.plus/connectivity',
      'dev.fluttercommunity.plus/connectivity_status',
      'plugins.flutter.io/path_provider',
      'plugins.flutter.io/shared_preferences',
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers.global/events',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(canal), nulo);
    }
  });

  test('janela de troca: memória é B mas o id ativo ainda é A -> recusa',
      () async {
    final ds = DataService();
    ds.setEmpresaAtual(_empresa('emp-b'));
    ds.setEmpresaIdParaTeste('emp-a');

    final erro = await _erroAoZerar(ds, empresaEsperada: 'emp-b');
    expect('$erro', contains('Nada foi apagado'));
    ds.dispose();
    SyncMonitorService.instance.dispose();
  });

  test('id ativo diferente da tela -> recusa', () async {
    final ds = DataService();
    ds.setEmpresaAtual(_empresa('emp-a'));
    ds.setEmpresaIdParaTeste('emp-b');

    final erro = await _erroAoZerar(ds, empresaEsperada: 'emp-a');
    expect('$erro', contains('Nada foi apagado'));
    ds.dispose();
    SyncMonitorService.instance.dispose();
  });

  test('sem empresa em memória -> recusa', () async {
    final ds = DataService();
    ds.setEmpresaAtual(null);
    ds.setEmpresaIdParaTeste('emp-a');

    final erro = await _erroAoZerar(ds, empresaEsperada: 'emp-a');
    expect('$erro', contains('Nada foi apagado'));
    ds.dispose();
    SyncMonitorService.instance.dispose();
  });

  test('empresa vazia -> recusa', () async {
    final ds = DataService();
    ds.setEmpresaAtual(_empresa('emp-a'));
    ds.setEmpresaIdParaTeste('emp-a');

    final erro = await _erroAoZerar(ds, empresaEsperada: '   ');
    expect('$erro', contains('Nenhuma empresa selecionada'));
    ds.dispose();
    SyncMonitorService.instance.dispose();
  });

  test("empresa '1' (legada) -> recusa mesmo sendo a aberta", () async {
    final ds = DataService();
    ds.setEmpresaAtual(_empresa('1'));
    ds.setEmpresaIdParaTeste('1');

    final erro = await _erroAoZerar(ds, empresaEsperada: '1');
    expect('$erro', contains('empresa padrão'));
    ds.dispose();
    SyncMonitorService.instance.dispose();
  });
}
