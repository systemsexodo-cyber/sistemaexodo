// Persistência do histórico de estoque e aparar os itens antigos da memória.
//
// Duas coisas que quebravam em silêncio:
//
// 1. `EstoqueHistorico.toMap()` não mandava `produto_id` nem `created_at` —
//    a tela de histórico do produto filtra por `h.produtoId == produto.id`
//    (histórico sempre VAZIO) e a tabela local não tem DEFAULT em `created_at`
//    (300 linhas nulas no banco do usuário).
// 2. O aparador de memória cortava o FIM da lista — que é o mais NOVO, já que
//    a lista só cresce por `add` — porque EstoqueHistorico/AjusteEstoqueLote
//    não têm `updatedAt` e o sort devolvia 0 para todo par.
//
// Rodar: flutter test test/historico_estoque_persistencia_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/models/estoque_historico.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';

EstoqueHistorico _movimento(String id, DateTime data, {double qtd = 1}) =>
    EstoqueHistorico(
      id: id,
      produtoId: 'PROD-1',
      data: data,
      quantidade: qtd,
      tipo: 'entrada',
    );

/// Item com `updatedAt` (como Produto) — garante que o caminho antigo do
/// aparador continua mandando.
class _ComAtualizacao {
  final String nome;
  final DateTime updatedAt;
  const _ComAtualizacao(this.nome, this.updatedAt);
}

void main() {
  group('EstoqueHistorico.toMap()', () {
    test('manda produto_id — sem ele a linha nasce órfã e a tela fica vazia', () {
      final h = _movimento('1790520739017_PROD-1', DateTime(2026, 9, 27, 11, 52));

      expect(h.toMap()['produto_id'], 'PROD-1',
          reason: 'sem produto_id o histórico do produto nunca aparece');
      expect(h.toMap()['id'], '1790520739017_PROD-1');
    });

    test('manda created_at — a tabela local não tem DEFAULT e nascia NULL', () {
      final data = DateTime(2026, 9, 27, 11, 52, 19);
      final h = _movimento('X', data);

      expect(h.toMap()['created_at'], isNotNull,
          reason: 'created_at nascia NULL no banco local');
      expect(DateTime.parse(h.toMap()['created_at'] as String).toUtc(),
          data.toUtc());
    });

    test('id, data, quantidade e tipo sobrevivem ao round-trip', () {
      final h = _movimento('ROUND-1', DateTime(2026, 5, 20, 8, 30), qtd: -4.5);
      final voltou = EstoqueHistorico.fromMap(h.toMap());

      expect(voltou.id, 'ROUND-1');
      expect(voltou.produtoId, 'PROD-1');
      expect(voltou.quantidade, -4.5);
      expect(voltou.tipo, 'entrada');
      expect(voltou.data.toUtc(), h.data.toUtc());
    });
  });

  group('apararItensAntigos (memória)', () {
    test('mantém os 3 mais RECENTES quando a lista está em ordem', () {
      // É assim que a lista chega: o mais velho primeiro, cresce por `add`.
      final lista = [
        for (var i = 0; i < 10; i++)
          _movimento('m$i', DateTime(2026, 9, 1).add(Duration(hours: i))),
      ];

      DataService.apararItensAntigos(lista, 3);

      // Ordenado do mais novo ao mais velho, e o corte tira o rabo: sobram os
      // três lançamentos mais recentes.
      expect(lista.map((e) => e.id).toList(), ['m9', 'm8', 'm7'],
          reason: 'sem ordenar o corte pegava o FIM da lista sem sentido — e '
              'em uso real perdia os lançamentos que acabaram de ser feitos');
      expect(
          lista.every((e) => !e.data.isBefore(DateTime(2026, 9, 1, 7))), isTrue);
    });

    test('mantém os mais recentes mesmo com a lista fora de ordem', () {
      final lista = [
        _movimento('velho1', DateTime(2026, 1, 1)),
        _movimento('novo', DateTime(2026, 9, 27)),
        _movimento('velho2', DateTime(2026, 2, 1)),
        _movimento('meio', DateTime(2026, 6, 1)),
      ];

      DataService.apararItensAntigos(lista, 2);

      expect(lista.map((e) => e.id).toSet(), {'novo', 'meio'},
          reason: 'o mais antigo não pode sobreviver só por estar no meio');
    });

    test('não mexe em nada quando está abaixo do limite', () {
      final lista = [
        _movimento('a', DateTime(2026, 1, 1)),
        _movimento('b', DateTime(2026, 1, 2)),
      ];

      DataService.apararItensAntigos(lista, 5);

      expect(lista.map((e) => e.id).toList(), ['a', 'b']);
    });

    test('item com updatedAt continua sendo cortado pelo updatedAt', () {
      final lista = [
        _ComAtualizacao('antigo', DateTime(2026, 1, 1)),
        _ComAtualizacao('novo', DateTime(2026, 9, 27)),
        _ComAtualizacao('meio', DateTime(2026, 5, 1)),
      ];

      DataService.apararItensAntigos(lista, 2);

      expect(lista.map((e) => e.nome).toSet(), {'novo', 'meio'});
    });
  });
}
