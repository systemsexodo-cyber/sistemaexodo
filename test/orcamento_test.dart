import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/models/item_pedido.dart';
import 'package:sistema_exodo_novo/models/orcamento.dart';

Orcamento _orcamento({
  String status = Orcamento.statusOrcamento,
  DateTime? validade,
  double desconto = 0,
}) {
  return Orcamento(
    id: 'orc-1',
    numero: 'ORC-0001',
    clienteId: 'c1',
    clienteNome: 'Cliente Teste',
    clienteTelefone: '11999999999',
    operador: 'Operador',
    dataOrcamento: DateTime(2026, 9, 19, 9, 0),
    validadeOrcamento: validade,
    status: status,
    descontoTotal: desconto,
    itens: [
      ItemPedido(id: 'p1', nome: 'Ração 15kg', quantidade: 2, preco: 100),
      ItemPedido(id: 'p2', nome: 'Brinquedo', quantidade: 1, preco: 30),
    ],
  );
}

void main() {
  test('total da proposta soma os itens e aplica o desconto', () {
    final orcamento = _orcamento();

    expect(orcamento.totalProdutos, 230);
    expect(orcamento.totalGeral, 230);
    expect(orcamento.quantidadeItens, 3);
    expect(orcamento._itensNomes, ['Ração 15kg', 'Brinquedo']);
  });

  test('desconto reduz o total da proposta', () {
    expect(_orcamento(desconto: 30).totalGeral, 200);
  });

  test('situação exibida: aberto, vencido, aprovado, recusado e cancelado', () {
    expect(_orcamento().statusExibicao, 'ORÇAMENTO');
    expect(_orcamento().aberto, isTrue);

    final vencido = _orcamento(
      validade: DateTime.now().subtract(const Duration(days: 1)),
    );
    expect(vencido.statusExibicao, 'ORÇAMENTO VENCIDO');
    expect(vencido.orcamentoVencido, isTrue);

    final aprovado = _orcamento(status: Orcamento.statusAprovado);
    expect(aprovado.aprovado, isTrue);
    expect(aprovado.orcamentoVencido, isFalse);

    expect(_orcamento(status: Orcamento.statusRecusado).statusExibicao,
        'RECUSADO');
    expect(_orcamento(status: Orcamento.statusCancelado).statusExibicao,
        'CANCELADO');
  });

  test('aprovar não gera pedido: só depois de aprovado é que se gera o pedido', () {
    final aberto = _orcamento();
    expect(aberto.podeGerarPedido, isFalse,
        reason: 'orçamento em aberto ainda não pode virar pedido');

    final aprovado = _orcamento(status: Orcamento.statusAprovado);
    expect(aprovado.aprovado, isTrue);
    expect(aprovado.temPedidoGerado, isFalse);
    expect(aprovado.podeGerarPedido, isTrue);
    expect(aprovado.statusExibicao, 'APROVADO');

    final comPedido = aprovado.copyWith(
      pedidoGeradoId: 'ped-9',
      pedidoGeradoNumero: 'PED-0009',
    );
    expect(comPedido.podeGerarPedido, isFalse,
        reason: 'um orçamento nunca gera pedido duas vezes');
    expect(comPedido.numero, 'ORC-0001',
        reason: 'o número do orçamento é separado do número do pedido');
    expect(comPedido.pedidoGeradoNumero, 'PED-0009');
  });

  test('reabrir limpa a aprovação', () {
    final aprovado = _orcamento(status: Orcamento.statusAprovado)
        .copyWith(dataAprovacao: DateTime(2026, 9, 20));
    final reaberto = aprovado.copyWith(
      status: Orcamento.statusOrcamento,
      limparAprovacao: true,
    );

    expect(reaberto.aberto, isTrue);
    expect(reaberto.dataAprovacao, isNull);
  });

  test('toMap/fromMap preserva itens, validade e vínculo com o pedido', () {
    final original = _orcamento(validade: DateTime(2026, 9, 30)).copyWith(
      status: Orcamento.statusAprovado,
      pedidoGeradoId: 'ped-9',
      pedidoGeradoNumero: 'PED-0009',
      dataAprovacao: DateTime(2026, 9, 20, 14, 30),
    );

    final restaurado = Orcamento.fromMap(original.toMap());

    expect(restaurado.numero, 'ORC-0001');
    expect(restaurado.itens.length, 2);
    expect(restaurado.itens.first.nome, 'Ração 15kg');
    expect(restaurado.itens.first.quantidade, 2);
    expect(restaurado.validadeOrcamento, DateTime(2026, 9, 30));
    expect(restaurado.status, Orcamento.statusAprovado);
    expect(restaurado.pedidoGeradoNumero, 'PED-0009');
    expect(restaurado.temPedidoGerado, isTrue);
    expect(restaurado.dataAprovacao, DateTime(2026, 9, 20, 14, 30));
    expect(restaurado.totalGeral, 230);
  });

  test('toMap serializa datas com fuso explícito (UTC)', () {
    final mapa = _orcamento().toMap();

    expect(mapa['data_orcamento'].toString(), endsWith('Z'));
    expect(mapa['created_at'].toString(), endsWith('Z'));
  });

  test('copyWith com limparValidade remove o prazo da proposta', () {
    final orcamento = _orcamento(validade: DateTime(2026, 9, 30));
    expect(orcamento.validadeOrcamento, isNotNull);
    expect(orcamento.copyWith(limparValidade: true).validadeOrcamento, isNull);
  });

  test('toPedido() adapta a proposta para impressão/detalhes', () {
    final pedido = _orcamento().toPedido();

    expect(pedido.numero, 'ORC-0001');
    expect(pedido.produtos.length, 2);
    expect(pedido.pagamentos, isEmpty);
    expect(pedido.totalGeral, 230);
    expect(pedido.status, 'Pendente');
  });
}

extension on Orcamento {
  /// Nomes dos itens, na ordem — só para deixar o teste legível.
  List<String> get _itensNomes => itens.map((i) => i.nome).toList();
}
