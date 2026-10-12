import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/models/ajuste_estoque_lote.dart';

void main() {
  test('lote sobrevive ao round-trip de toMap/fromMap com itens', () {
    final lote = AjusteEstoqueLote(
      id: 'AJL-123',
      data: DateTime(2026, 9, 22, 14, 30),
      usuario: 'Charles',
      observacao: 'contagem da loja',
      itens: [
        AjusteEstoqueLoteItem(
          produtoId: 'P1',
          produtoNome: 'Ração Premium',
          produtoCodigo: 'COD-1',
          estoqueAnterior: 5,
          estoqueNovo: 20,
        ),
        AjusteEstoqueLoteItem(
          produtoId: 'P2',
          produtoNome: 'Brinquedo',
          estoqueAnterior: 3,
          estoqueNovo: -2, // estoque negativo é permitido
          precoAnterior: 29.9,
          precoNovo: 39.9,
        ),
      ],
    );

    final voltou = AjusteEstoqueLote.fromMap(lote.toMap());

    expect(voltou.id, 'AJL-123');
    expect(voltou.usuario, 'Charles');
    expect(voltou.observacao, 'contagem da loja');
    expect(voltou.desfeito, isFalse);
    expect(voltou.itens.length, 2);
    expect(voltou.itens.first.estoqueAnterior, 5);
    expect(voltou.itens.first.estoqueNovo, 20);
    expect(voltou.itens.last.estoqueNovo, -2);
    expect(voltou.itens.last.precoNovo, 39.9);
    expect(voltou.data.difference(lote.data).inSeconds.abs() < 2, isTrue);
  });

  test('alterouEstoque/alterouPreco ignoram valores iguais e nulos', () {
    const soPreco = AjusteEstoqueLoteItem(
      produtoId: 'P1',
      produtoNome: 'X',
      precoAnterior: 10,
      precoNovo: 12,
    );
    expect(soPreco.alterouEstoque, isFalse);
    expect(soPreco.alterouPreco, isTrue);

    const semMudanca = AjusteEstoqueLoteItem(
      produtoId: 'P2',
      produtoNome: 'Y',
      estoqueAnterior: 4,
      estoqueNovo: 4,
      precoAnterior: 9.99,
      precoNovo: 9.991,
    );
    expect(semMudanca.alterouEstoque, isFalse);
    expect(semMudanca.alterouPreco, isFalse);
  });

  test('copyWith marca o lote como desfeito mantendo os itens', () {
    final lote = AjusteEstoqueLote(
      id: 'AJL-9',
      data: DateTime(2026, 9, 22),
      itens: const [
        AjusteEstoqueLoteItem(
          produtoId: 'P1',
          produtoNome: 'X',
          estoqueAnterior: 0,
          estoqueNovo: 8,
        ),
      ],
    );
    expect(lote.podeSerDesfeito, isTrue);

    final desfeito = lote.copyWith(
      desfeito: true,
      dataDesfeito: DateTime(2026, 9, 23),
      usuarioDesfeito: 'Maria',
    );

    expect(desfeito.desfeito, isTrue);
    expect(desfeito.podeSerDesfeito, isFalse);
    expect(desfeito.usuarioDesfeito, 'Maria');
    expect(desfeito.itens.length, 1);
    expect(lote.desfeito, isFalse, reason: 'o original não pode ser alterado');
  });

  test('item guarda QUAL estoque foi ajustado (para o DESFAZER voltar ao mesmo lugar)', () {
    final lote = AjusteEstoqueLote(
      id: 'AJL-900',
      data: DateTime(2026, 9, 27),
      itens: const [
        AjusteEstoqueLoteItem(
          produtoId: 'P1',
          produtoNome: 'coca cola',
          estoqueAnterior: 32,
          estoqueNovo: 30,
          estoqueId: 'estoque_deposito',
        ),
        AjusteEstoqueLoteItem(
          produtoId: 'P2',
          produtoNome: 'sem saldo por estoque',
          estoqueAnterior: 5,
          estoqueNovo: 5,
        ),
      ],
    );

    expect(lote.itens.first.toMap()['estoque_id'], 'estoque_deposito');

    final voltou = AjusteEstoqueLote.fromMap(lote.toMap());
    expect(voltou.itens.first.estoqueId, 'estoque_deposito',
        reason: 'sem o estoque no item, o DESFAZER devolveria o valor ao TOTAL');

    // Lote gravado antes do seletor de estoque (sem o campo) continua válido:
    // null = ajuste sobre o total do produto, como era.
    final antigo = AjusteEstoqueLote.fromMap({
      ...lote.toMap(),
      'itens': [
        {'produto_id': 'P9', 'produto_nome': 'X', 'estoque_anterior': 1, 'estoque_novo': 2},
      ],
    });
    expect(antigo.itens.single.estoqueId, isNull);
  });
}
