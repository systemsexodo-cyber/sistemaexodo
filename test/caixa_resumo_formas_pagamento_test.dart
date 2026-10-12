// Separação do fluxo de caixa por forma de pagamento (Dinheiro, PIX, Cartão...).
//
// O gestor precisa saber quanto entrou de cada forma em um caixa. O resumo é
// derivado de `getVendasDoCaixa` (mesma base do saldo e do card de entradas),
// então a soma das formas tem de bater com o total de vendas do caixa.
//
// Rodar: flutter test test/caixa_resumo_formas_pagamento_test.dart

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_exodo_novo/models/caixa.dart';
import 'package:sistema_exodo_novo/models/forma_pagamento.dart';
import 'package:sistema_exodo_novo/models/venda_balcao.dart';
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

  VendaBalcao venda({
    required String id,
    required TipoPagamento tipo,
    required double total,
    List<PagamentoPedido>? pagamentos,
    bool cancelada = false,
    String? operadorVenda,
  }) =>
      VendaBalcao(
        id: id,
        numero: 'CX1-$id',
        dataVenda: inicio.add(const Duration(hours: 1)),
        itens: const [],
        tipoPagamento: tipo,
        pagamentos: pagamentos,
        valorTotal: total,
        operador: operadorVenda ?? operador,
        cancelado: cancelada,
      );

  test('separa as entradas por forma e ignora canceladas e de outro operador',
      () {
    final ds = DataService();
    final ab = abertura();
    ds.aberturasCaixa.add(ab);

    ds.vendasBalcao
        .add(venda(id: '1', tipo: TipoPagamento.dinheiro, total: 50));
    // Venda com pagamento dividido: o resumo tem de usar as partes, não o tipo
    // principal (senão os R$ 100 iriam todos como Dinheiro).
    ds.vendasBalcao.add(venda(
      id: '2',
      tipo: TipoPagamento.dinheiro,
      total: 100,
      pagamentos: [
        PagamentoPedido(id: 'p1', tipo: TipoPagamento.pix, valor: 60),
        PagamentoPedido(
            id: 'p2', tipo: TipoPagamento.cartaoCredito, valor: 40),
      ],
    ));
    ds.vendasBalcao.add(venda(
        id: '3', tipo: TipoPagamento.pix, total: 999, cancelada: true));
    ds.vendasBalcao.add(venda(
        id: '4',
        tipo: TipoPagamento.pix,
        total: 77,
        operadorVenda: 'outro@exodo.com'));

    final resumo = ds.calcularResumoFormaPagamentoDoCaixa(ab);
    final porRotulo = {for (final r in resumo) r.rotulo: r.valor};

    expect(porRotulo['Dinheiro'], 50);
    expect(porRotulo['PIX'], 60);
    expect(porRotulo['Cartão de Crédito'], 40);
    expect(porRotulo.containsKey('Outro'), isFalse,
        reason: 'não pode aparecer forma sem movimento');

    final totalResumo = resumo.fold<double>(0, (s, r) => s + r.valor);
    final totalVendas =
        ds.getVendasDoCaixa(ab).fold<double>(0, (s, v) => s + v.valorTotal);
    expect(totalResumo, totalVendas,
        reason: 'a soma das formas tem de bater com o total de vendas');
    expect(totalResumo, 150);

    expect(resumo.map((r) => r.rotulo).toList(),
        ['PIX', 'Dinheiro', 'Cartão de Crédito'],
        reason: 'ordenado do maior para o menor');
    ds.dispose();
  });

  test('forma personalizada (Caju/VR) usa o nome cadastrado', () {
    final ds = DataService();
    final ab = abertura();
    ds.aberturasCaixa.add(ab);
    ds.vendasBalcao.add(venda(
      id: '5',
      tipo: TipoPagamento.outro,
      total: 30,
      pagamentos: [
        PagamentoPedido(
            id: 'p9', tipo: TipoPagamento.outro, nomeForma: 'Caju', valor: 30),
      ],
    ));

    final resumo = ds.calcularResumoFormaPagamentoDoCaixa(ab);
    expect(resumo.length, 1);
    expect(resumo.first.rotulo, 'Caju');
    expect(resumo.first.valor, 30);
    expect(resumo.first.tipo, TipoPagamento.outro);
    ds.dispose();
  });

  test('caixa sem vendas devolve resumo vazio', () {
    final ds = DataService();
    final ab = abertura();
    ds.aberturasCaixa.add(ab);
    expect(ds.calcularResumoFormaPagamentoDoCaixa(ab), isEmpty);
    ds.dispose();
  });
}
