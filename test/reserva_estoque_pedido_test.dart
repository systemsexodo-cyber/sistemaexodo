// RESERVA DE ESTOQUE EM PEDIDOS DE VENDA
//
// Com a configuração `empresa.configuracoes['reservar_estoque_pedidos']`
// ligada, um pedido salvo e ainda em aberto (Pendente / Em Andamento /
// Parcialmente Pago) segura a quantidade dos seus produtos: a unidade não fica
// disponível para outro pedido. Pago/Concluído já deu baixa real; Cancelado não
// vale mais. A reserva é CALCULADA a partir dos pedidos para nunca ficar presa
// nem duplicada no saldo.
//
// Rodar: flutter test test/reserva_estoque_pedido_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/models/item_pedido.dart';
import 'package:sistema_exodo_novo/models/item_servico.dart';
import 'package:sistema_exodo_novo/models/pedido.dart';
import 'package:sistema_exodo_novo/models/produto.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';

Produto _produto({
  required String id,
  double estoque = 100,
  double quantidadeBaixa = 1.0,
}) =>
    Produto(
      id: id,
      nome: 'Produto $id',
      unidade: 'un',
      grupo: 'Teste',
      preco: 10,
      estoque: estoque,
      quantidadeBaixa: quantidadeBaixa,
      createdAt: DateTime(2026, 9, 27),
      updatedAt: DateTime(2026, 9, 27),
    );

ItemPedido _item(
  String produtoId, {
  double quantidade = 1,
  double? quantidadeBaixa,
}) =>
    ItemPedido(
      id: produtoId,
      nome: 'Produto $produtoId',
      quantidade: quantidade,
      preco: 10,
      quantidadeBaixa: quantidadeBaixa,
    );

Pedido _pedido({
  required String id,
  String status = 'Pendente',
  required List<ItemPedido> produtos,
}) =>
    Pedido(
      id: id,
      numero: id,
      status: status,
      produtos: produtos,
      servicos: <ItemServico>[],
    );

void main() {
  test('config ligada só quando reservar_estoque_pedidos é true', () {
    expect(
      DataService.reservaAtivaNaConfig(const {'reservar_estoque_pedidos': true}),
      isTrue,
    );
    expect(
      DataService.reservaAtivaNaConfig(const {'reservar_estoque_pedidos': false}),
      isFalse,
    );
    expect(DataService.reservaAtivaNaConfig(const {}), isFalse);
    expect(DataService.reservaAtivaNaConfig(null), isFalse);
  });

  test('soma as quantidades dos itens do mesmo produto em pedidos abertos', () {
    final pedidos = [
      _pedido(id: 'PED-1', produtos: [_item('A', quantidade: 3)]),
      _pedido(
        id: 'PED-2',
        status: 'Em Andamento',
        produtos: [_item('A', quantidade: 2), _item('B', quantidade: 5)],
      ),
      _pedido(
        id: 'PED-3',
        status: 'Parcialmente Pago',
        produtos: [_item('A', quantidade: 4)],
      ),
    ];

    final reservadoA = DataService.calcularEstoqueReservado(
      produtoId: 'A',
      pedidos: pedidos,
      produtoPorId: (id) => _produto(id: id),
    );
    final reservadoB = DataService.calcularEstoqueReservado(
      produtoId: 'B',
      pedidos: pedidos,
      produtoPorId: (id) => _produto(id: id),
    );

    expect(reservadoA, 9); // 3 + 2 + 4
    expect(reservadoB, 5);
  });

  test('pedido pago, concluído ou cancelado NÃO reserva mais', () {
    final pedidos = [
      _pedido(id: 'PED-PAGO', status: 'Pago', produtos: [_item('A', quantidade: 10)]),
      _pedido(id: 'PED-CONC', status: 'Concluído', produtos: [_item('A', quantidade: 10)]),
      _pedido(id: 'PED-CANC', status: 'Cancelado', produtos: [_item('A', quantidade: 10)]),
      _pedido(id: 'PED-PEND', status: 'Pendente', produtos: [_item('A', quantidade: 2)]),
    ];

    final reservado = DataService.calcularEstoqueReservado(
      produtoId: 'A',
      pedidos: pedidos,
      produtoPorId: (id) => _produto(id: id),
    );

    expect(reservado, 2, reason: 'só o pedido ainda em aberto reserva');
  });

  test('usa o fator de baixa do item (forma de venda) quando informado', () {
    final pedidos = [
      _pedido(
        id: 'PED-1',
        produtos: [_item('A', quantidade: 2, quantidadeBaixa: 12)],
      ),
    ];

    final reservado = DataService.calcularEstoqueReservado(
      produtoId: 'A',
      pedidos: pedidos,
      produtoPorId: (id) => _produto(id: id),
    );

    expect(reservado, 24, reason: '2 caixas × 12 = 24 unidades reservadas');
  });

  test('sem fator no item, cai no fator padrão do produto', () {
    final pedidos = [
      _pedido(id: 'PED-1', produtos: [_item('A', quantidade: 3)]),
    ];

    final reservado = DataService.calcularEstoqueReservado(
      produtoId: 'A',
      pedidos: pedidos,
      produtoPorId: (id) => _produto(id: id, quantidadeBaixa: 6),
    );

    expect(reservado, 18, reason: '3 × 6 (fator do produto) = 18');
  });

  test('produto não encontrado ainda reserva pela quantidade crua', () {
    final pedidos = [
      _pedido(id: 'PED-1', produtos: [_item('FANTASMA', quantidade: 4)]),
    ];

    final reservado = DataService.calcularEstoqueReservado(
      produtoId: 'FANTASMA',
      pedidos: pedidos,
      produtoPorId: (_) => null,
    );

    expect(reservado, 4, reason: 'sem produto, o fator cai em 1.0');
  });
}
