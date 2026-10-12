// Resumo por forma de pagamento na IMPRESSÃO do fechamento de caixa.
//
// O papel precisa usar a mesma regra do card "Entradas por Forma de Pagamento":
// vendas com pagamento dividido somam cada parte (não só a forma principal) e a
// forma personalizada (Caju/VR) mantém o nome cadastrado.
//
// Rodar: flutter test test/caixa_pdf_resumo_forma_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/models/forma_pagamento.dart';
import 'package:sistema_exodo_novo/models/venda_balcao.dart';
import 'package:sistema_exodo_novo/services/caixa_pdf_service.dart';

void main() {
  final base = DateTime(2026, 10, 11, 9);

  VendaBalcao venda({
    required String id,
    required TipoPagamento tipo,
    required double total,
    List<PagamentoPedido>? pagamentos,
    bool cancelada = false,
  }) =>
      VendaBalcao(
        id: id,
        numero: 'V-$id',
        dataVenda: base,
        itens: const [],
        tipoPagamento: tipo,
        pagamentos: pagamentos,
        valorTotal: total,
        cancelado: cancelada,
      );

  test('venda com pagamento dividido entra por cada parte', () {
    final resumo = CaixaPDFService.resumoPorForma([
      venda(id: '1', tipo: TipoPagamento.dinheiro, total: 50),
      venda(
        id: '2',
        tipo: TipoPagamento.dinheiro,
        total: 100,
        pagamentos: [
          PagamentoPedido(id: 'p1', tipo: TipoPagamento.pix, valor: 60),
          PagamentoPedido(
              id: 'p2', tipo: TipoPagamento.cartaoCredito, valor: 40),
        ],
      ),
    ]);

    final porRotulo = {for (final r in resumo) r.rotulo: r.valor};
    expect(porRotulo['Dinheiro'], 50);
    expect(porRotulo['PIX'], 60);
    expect(porRotulo['Cartão Crédito'], 40);
    expect(resumo.fold<double>(0, (s, r) => s + r.valor), 150);
  });

  test('ignora vendas canceladas', () {
    final resumo = CaixaPDFService.resumoPorForma([
      venda(id: '1', tipo: TipoPagamento.pix, total: 70),
      venda(id: '2', tipo: TipoPagamento.pix, total: 999, cancelada: true),
    ]);
    expect(resumo.length, 1);
    expect(resumo.first.valor, 70);
  });

  test('forma personalizada preserva o nome e a ordem é do maior para o menor',
      () {
    final resumo = CaixaPDFService.resumoPorForma([
      venda(id: '1', tipo: TipoPagamento.dinheiro, total: 20),
      venda(
        id: '2',
        tipo: TipoPagamento.outro,
        total: 45,
        pagamentos: [
          PagamentoPedido(
              id: 'p3', tipo: TipoPagamento.outro, nomeForma: 'Caju', valor: 45),
        ],
      ),
    ]);
    expect(resumo.map((r) => r.rotulo).toList(), ['Caju', 'Dinheiro']);
  });

  test('lista vazia devolve resumo vazio', () {
    expect(CaixaPDFService.resumoPorForma(const []), isEmpty);
  });
}
