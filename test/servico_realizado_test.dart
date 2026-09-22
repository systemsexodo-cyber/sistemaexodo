import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/models/forma_pagamento.dart';
import 'package:sistema_exodo_novo/models/item_servico.dart';
import 'package:sistema_exodo_novo/models/servico_realizado.dart';

ServicoRealizado _servico({
  String status = ServicoRealizado.statusEmAberto,
  List<PagamentoPedido> pagamentos = const [],
  DateTime? validade,
}) {
  return ServicoRealizado(
    id: 'srv-1',
    numero: 'SRV-0001',
    clienteId: 'c1',
    clienteNome: 'Cliente Teste',
    clienteTelefone: '11999999999',
    clienteEndereco: 'Rua A, 10',
    operador: 'Operador',
    dataServico: DateTime(2026, 9, 19, 10, 30),
    status: status,
    total: 100,
    validadeOrcamento: validade,
    servicos: [
      ItemServico(id: 'is1', descricao: 'Banho', valor: 80, valorAdicional: 20),
    ],
    pagamentos: pagamentos,
  );
}

void main() {
  test('Em Aberto: total, pendente e classificação pelas parcelas', () {
    final servico = _servico(pagamentos: [
      PagamentoPedido(id: 'p1', tipo: TipoPagamento.pix, valor: 30, recebido: true),
      PagamentoPedido(id: 'p2', tipo: TipoPagamento.dinheiro, valor: 70),
    ]);

    expect(servico.totalServicos, 100);
    expect(servico.totalGeral, 100);
    expect(servico.totalRecebido, 30);
    expect(servico.valorPendente, 70);
    expect(servico.totalmenteRecebido, isFalse);
    expect(servico.emAberto, isTrue);
    expect(servico.statusExibicao, 'EM ABERTO');
    expect(servico.parcelasPendentes, 1);
    expect(servico.parcelasPagas, 1);
    expect(servico.statusParcelamento, 'Parcialmente pago');
  });

  test('Recebido: quitado quando o total recebido cobre o total geral', () {
    final servico = _servico(pagamentos: [
      PagamentoPedido(id: 'p1', tipo: TipoPagamento.pix, valor: 100, recebido: true),
    ]);

    expect(servico.valorPendente, 0);
    expect(servico.totalmenteRecebido, isTrue);
    expect(servico.emAberto, isFalse);
    expect(servico.statusExibicao, 'RECEBIDO');
    expect(servico.statusParcelamento, 'Quitado');
  });

  test('Orçamento nunca conta como recebido, mesmo com pagamento lançado', () {
    final servico = _servico(
      status: ServicoRealizado.statusOrcamento,
      pagamentos: [
        PagamentoPedido(id: 'p1', tipo: TipoPagamento.pix, valor: 100, recebido: true),
      ],
    );

    expect(servico.ehOrcamento, isTrue);
    expect(servico.emAberto, isFalse);
    expect(servico.totalmenteRecebido, isFalse);
    expect(servico.statusExibicao, 'ORÇAMENTO');
  });

  test('Orçamento vencido é sinalizado pela validade', () {
    final vencido = _servico(
      status: ServicoRealizado.statusOrcamento,
      validade: DateTime.now().subtract(const Duration(days: 2)),
    );
    final valido = _servico(
      status: ServicoRealizado.statusOrcamento,
      validade: DateTime.now().add(const Duration(days: 2)),
    );

    expect(vencido.orcamentoVencido, isTrue);
    expect(valido.orcamentoVencido, isFalse);
  });

  test('Cancelado fica fora de Em Aberto, Recebido e Orçamento', () {
    final servico = _servico(status: ServicoRealizado.statusCancelado);

    expect(servico.cancelado, isTrue);
    expect(servico.emAberto, isFalse);
    expect(servico.totalmenteRecebido, isFalse);
    expect(servico.statusExibicao, 'CANCELADO');
  });

  test('toMap/fromMap preserva dados e volta com o MESMO status', () {
    final original = _servico(
      status: ServicoRealizado.statusOrcamento,
      validade: DateTime(2026, 9, 30),
      pagamentos: [
        PagamentoPedido(id: 'p1', tipo: TipoPagamento.pix, valor: 50),
      ],
    );

    final restaurado = ServicoRealizado.fromMap(original.toMap());

    expect(restaurado.id, 'srv-1');
    expect(restaurado.numero, 'SRV-0001');
    expect(restaurado.clienteNome, 'Cliente Teste');
    expect(restaurado.status, ServicoRealizado.statusOrcamento);
    expect(restaurado.validadeOrcamento, DateTime(2026, 9, 30));
    expect(restaurado.servicos.single.descricao, 'Banho');
    expect(restaurado.pagamentos.single.valor, 50);
    expect(restaurado.totalGeral, 100);
  });

  test('toMap serializa datas com fuso explícito (UTC)', () {
    final mapa = _servico().toMap();

    expect(mapa['data_servico'].toString(), endsWith('Z'));
    expect(mapa['created_at'].toString(), endsWith('Z'));
  });

  test('toPedido() adapta para impressão/detalhes sem perder itens', () {
    final servico = _servico(pagamentos: [
      PagamentoPedido(id: 'p1', tipo: TipoPagamento.pix, valor: 30, recebido: true),
    ]);

    final pedido = servico.toPedido();

    expect(pedido.numero, 'SRV-0001');
    expect(pedido.servicos.single.descricao, 'Banho');
    expect(pedido.pagamentos.single.valor, 30);
    expect(pedido.totalGeral, 100);
    expect(pedido.produtos, isEmpty);
  });
}
