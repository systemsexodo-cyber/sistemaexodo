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
}
