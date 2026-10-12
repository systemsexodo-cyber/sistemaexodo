// Recebimentos de PEDIDOS/MESAS por forma de pagamento dentro de um caixa.
//
// O fechamento (tela e impressão) precisa separar o que veio de venda de balcão
// do que veio de pedido/mesa. A regra tem de ser a mesma nos dois lugares: só
// pedidos do MESMO operador do caixa, com pagamento já recebido e dentro da
// janela do caixa.
//
// Rodar: flutter test test/caixa_recebimentos_pedidos_test.dart

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_exodo_novo/models/caixa.dart';
import 'package:sistema_exodo_novo/models/forma_pagamento.dart';
import 'package:sistema_exodo_novo/models/pedido.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    Future<Object?> nulo(MethodCall call) async => null;
    for (final canal in const [
      'dev.fluttercommunity.plus/connectivity',
      'dev.fluttercommunity.plus/connectivity_status',
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers.global/events',
      'plugins.flutter.io/path_provider',
      'plugins.flutter.io/shared_preferences',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(canal), nulo);
    }
  });

  const operador = 'carlos@exodo.com';
  final inicio = DateTime(2026, 10, 11, 8);

  AberturaCaixa abertura() => AberturaCaixa(
        id: 'ab-1',
        numero: 'CX1-0001',
        dataAbertura: inicio,
        valorInicial: 100,
        responsavel: operador,
      );

  PagamentoPedido pagamento({
    required String id,
    required double valor,
    required DateTime? recebidoEm,
    TipoPagamento tipo = TipoPagamento.pix,
  }) =>
      PagamentoPedido(
        id: id,
        tipo: tipo,
        valor: valor,
        recebido: recebidoEm != null,
        dataRecebimento: recebidoEm,
      );

  Pedido pedido({
    required String id,
    String? vendedor,
    List<PagamentoPedido> pagamentos = const [],
  }) =>
      Pedido(
        id: id,
        numero: 'PED-$id',
        dataPedido: inicio,
        vendedorNome: vendedor ?? operador,
        produtos: const [],
        servicos: const [],
        pagamentos: pagamentos,
      );

  test('soma os recebimentos do mesmo operador por forma', () {
    final ds = DataService();
    final ab = abertura();
    ds.aberturasCaixa.add(ab);
    ds.pedidos.add(pedido(
      id: '1',
      pagamentos: [
        pagamento(id: 'p1', valor: 60, recebidoEm: inicio.add(const Duration(hours: 1))),
        pagamento(
          id: 'p2',
          valor: 40,
          tipo: TipoPagamento.dinheiro,
          recebidoEm: inicio.add(const Duration(hours: 2)),
        ),
      ],
    ));

    final totais = ds.calcularRecebimentosDePedidosDoCaixa(ab);
    expect(totais[TipoPagamento.pix], 60);
    expect(totais[TipoPagamento.dinheiro], 40);
    ds.dispose();
  });

  test('ignora pedidos de outro operador, não recebidos e fora da janela', () {
    final ds = DataService();
    final ab = abertura();
    ds.aberturasCaixa.add(ab);

    // Outro operador.
    ds.pedidos.add(pedido(
      id: '2',
      vendedor: 'outro@exodo.com',
      pagamentos: [
        pagamento(id: 'p3', valor: 999, recebidoEm: inicio.add(const Duration(hours: 1))),
      ],
    ));
    // Ainda não recebido.
    ds.pedidos.add(pedido(
      id: '3',
      pagamentos: [pagamento(id: 'p4', valor: 50, recebidoEm: null)],
    ));
    // Recebido ANTES da abertura do caixa.
    ds.pedidos.add(pedido(
      id: '4',
      pagamentos: [
        pagamento(
          id: 'p5',
          valor: 70,
          recebidoEm: inicio.subtract(const Duration(hours: 3)),
        ),
      ],
    ));

    expect(ds.calcularRecebimentosDePedidosDoCaixa(ab), isEmpty);
    ds.dispose();
  });

  test('limite superior corta recebimentos depois do fechamento', () {
    final ds = DataService();
    final ab = abertura();
    ds.aberturasCaixa.add(ab);
    final fechamento = inicio.add(const Duration(hours: 8));

    ds.pedidos.add(pedido(
      id: '5',
      pagamentos: [
        pagamento(id: 'p6', valor: 30, recebidoEm: inicio.add(const Duration(hours: 2))),
        pagamento(id: 'p7', valor: 500, recebidoEm: fechamento.add(const Duration(hours: 1))),
      ],
    ));

    final totais = ds.calcularRecebimentosDePedidosDoCaixa(ab, limite: fechamento);
    expect(totais[TipoPagamento.pix], 30);
    ds.dispose();
  });
}
