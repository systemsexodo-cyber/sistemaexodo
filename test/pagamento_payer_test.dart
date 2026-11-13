import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/models/forma_pagamento.dart';

void main() {
  test('persists the payer name in a payment', () {
    final payment = PagamentoPedido(
      id: 'payment-1',
      tipo: TipoPagamento.dinheiro,
      valor: 5,
      recebido: true,
      nomePagador: 'Maria',
    );

    final restored = PagamentoPedido.fromMap(payment.toMap());

    expect(restored.nomePagador, 'Maria');
    expect(restored.copyWith(valor: 7).nomePagador, 'Maria');
  });

  test('estorno limpa valor recebido, troco, data e pagador', () {
    final payment = PagamentoPedido(
      id: 'payment-2',
      tipo: TipoPagamento.dinheiro,
      valor: 50,
      recebido: true,
      dataRecebimento: DateTime(2026, 11, 10),
      nomePagador: 'João',
      valorRecebido: 60,
      troco: 10,
    );

    final estornado = payment.copyWith(
      recebido: false,
      limparRecebimento: true,
    );

    expect(estornado.recebido, isFalse);
    expect(estornado.dataRecebimento, isNull);
    expect(estornado.nomePagador, isNull);
    expect(estornado.valorRecebido, isNull);
    expect(estornado.troco, isNull);
    expect(estornado.valor, 50, reason: 'O valor da parcela é preservado.');
  });
}
