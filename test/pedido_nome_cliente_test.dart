// Edição do nome do cliente no pedido.
//
// O botão "Salvar" do diálogo do PDV precisa conseguir TROCAR e APAGAR o nome.
// `copyWith(clienteNome: null)` não apagava nada (null = "mantém o atual"), então
// limpar o nome era um no-op silencioso — daí o `limparClienteNome`.
//
// Rodar: flutter test test/pedido_nome_cliente_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/models/pedido.dart';

Pedido _pedido({String? clienteNome}) => Pedido(
  id: 'PED-1',
  numero: 'CAIXA1-0006',
  clienteNome: clienteNome,
  dataPedido: DateTime(2026, 11, 3, 23, 32),
  produtos: const [],
  servicos: const [],
);

void main() {
  test('copyWith troca o nome do cliente', () {
    final pedido = _pedido(clienteNome: 'yago');

    final atualizado = pedido.copyWith(
      clienteNome: 'yago zika',
      updatedAt: DateTime(2026, 11, 4, 10),
    );

    expect(atualizado.clienteNome, 'yago zika');
    expect(atualizado.numero, 'CAIXA1-0006');
    expect(atualizado.id, 'PED-1');
    expect(atualizado.updatedAt, DateTime(2026, 11, 4, 10));
  });

  test('copyWith sem nome mantém o atual (comportamento antigo)', () {
    final pedido = _pedido(clienteNome: 'yago');

    expect(pedido.copyWith(clienteNome: null).clienteNome, 'yago');
  });

  test('copyWith só apaga o nome com limparClienteNome', () {
    final pedido = _pedido(clienteNome: 'yago');

    final semNome = pedido.copyWith(limparClienteNome: true);

    expect(semNome.clienteNome, isNull);
    expect(semNome.clienteId, pedido.clienteId);
  });
}
