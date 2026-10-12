// Vários estoques (Loja, Depósito…) por produto.
//
// O que este teste cobre:
//  1. `planejarReposicaoDeEstoque` — a decisão "de onde tirar" quando a venda
//     precisa de mercadoria que não está no estoque principal (é a peça
//     inteligente do recurso, então tem que estar certa);
//  2. o modelo `Estoque` (padrões, principal, nome para tela);
//  3. o produto guardando o saldo por estoque e o estoque padrão (ida e volta
//     por toMap/fromMap, que é o que o banco e a nuvem usam).
//
// Rodar: flutter test test/estoques_multiplos_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/models/estoque.dart';
import 'package:sistema_exodo_novo/models/produto.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';

void main() {
  group('planejarReposicaoDeEstoque (de onde trazer o que falta)', () {
    test('tira primeiro do estoque PADRÃO do produto, mesmo sendo o menor', () {
      final plano = DataService.planejarReposicaoDeEstoque(
        saldos: {'estoque_loja': 0, 'estoque_deposito': 20, 'estoque_reserva': 5},
        destinoId: 'estoque_loja',
        faltando: 3,
        preferidoId: 'estoque_reserva',
      );
      expect(plano, [(estoqueId: 'estoque_reserva', quantidade: 3)]);
    });

    test('se o estoque padrão não basta, completa com quem tem mais saldo', () {
      final plano = DataService.planejarReposicaoDeEstoque(
        saldos: {'estoque_loja': 0, 'estoque_deposito': 20, 'estoque_reserva': 5},
        destinoId: 'estoque_loja',
        faltando: 8,
        preferidoId: 'estoque_reserva',
      );
      expect(plano, [
        (estoqueId: 'estoque_reserva', quantidade: 5),
        (estoqueId: 'estoque_deposito', quantidade: 3),
      ]);
    });

    test('virado do avesso: o depósito é o padrão e a loja é o destino', () {
      final plano = DataService.planejarReposicaoDeEstoque(
        saldos: {'estoque_loja': 1, 'estoque_deposito': 40},
        destinoId: 'estoque_loja',
        faltando: 5,
        preferidoId: 'estoque_loja', // padrão é o próprio destino — não serve
      );
      expect(plano, [(estoqueId: 'estoque_deposito', quantidade: 5)]);
    });

    test('nunca tira mais do que existe em cada estoque', () {
      final plano = DataService.planejarReposicaoDeEstoque(
        saldos: {'a': 2, 'b': 3},
        destinoId: 'destino',
        faltando: 10,
      );
      expect(plano.map((p) => p.quantidade).reduce((a, b) => a + b), 5,
          reason: 'só havia 5 no total — a diferença fica faltando (estoque negativo)');
    });

    test('estoque de destino não é fonte de si mesmo', () {
      final plano = DataService.planejarReposicaoDeEstoque(
        saldos: {'estoque_loja': 99, 'estoque_deposito': 1},
        destinoId: 'estoque_loja',
        faltando: 5,
      );
      expect(plano, [(estoqueId: 'estoque_deposito', quantidade: 1)]);
    });

    test('nada em lugar nenhum: plano vazio (a venda segue e fica negativa)', () {
      final plano = DataService.planejarReposicaoDeEstoque(
        saldos: {'estoque_loja': 0, 'estoque_deposito': 0},
        destinoId: 'estoque_loja',
        faltando: 2,
      );
      expect(plano, isEmpty);
    });

    test('saldo zerado ou negativo não entra como fonte', () {
      final plano = DataService.planejarReposicaoDeEstoque(
        saldos: {'a': -3, 'b': 0},
        destinoId: 'd',
        faltando: 1,
      );
      expect(plano, isEmpty);
    });
  });

  group('Estoque (o cadastro dos locais)', () {
    test('os dois estoques criados de fábrica: Loja (principal) e Depósito', () {
      final lista = Estoque.padrao();
      expect(lista.map((e) => e.nome), ['Loja', 'Depósito']);
      expect(lista.first.principal, isTrue);
      expect(lista.last.principal, isFalse);
    });

    test('o principal é o marcado; sem nenhum marcado, vale o primeiro', () {
      final semMarca = [
        Estoque(id: 'a', nome: 'Loja'),
        Estoque(id: 'b', nome: 'Depósito'),
      ];
      expect(estoquePrincipal(semMarca)?.id, 'a');

      final marcado = [
        Estoque(id: 'a', nome: 'Loja'),
        Estoque(id: 'b', nome: 'Depósito', principal: true),
      ];
      expect(estoquePrincipal(marcado)?.id, 'b');
      expect(estoquePrincipal(const []), isNull);
    });

    test('nome para a tela nunca fica vazio', () {
      final lista = Estoque.padrao();
      expect(nomeDoEstoque(lista, 'estoque_deposito'), 'Depósito');
      expect(nomeDoEstoque(lista, 'nao_existe'), 'Estoque principal',
          reason: 'estoque excluído (ou id nulo) cai no rótulo genérico');
      expect(nomeDoEstoque(lista, null), 'Estoque principal');
    });

    test('ida e volta pelo mapa do banco (toMap/fromMap)', () {
      final e = Estoque(id: 'estoque_caminhao', nome: 'Caminhão', ordem: 3);
      final voltou = Estoque.fromMap(e.toMap());
      expect(voltou.id, 'estoque_caminhao');
      expect(voltou.nome, 'Caminhão');
      expect(voltou.principal, isFalse);
      expect(voltou.ordem, 3);
      expect(e.copyWith(principal: true).principal, isTrue);
      expect(e.copyWith(principal: true).nome, 'Caminhão');
    });
  });

  group('Produto guarda o saldo por estoque e o estoque padrão', () {
    Produto novo(Map<String, double> porEstoque, String? padrao, double total) => Produto(
          id: 'p1',
          nome: 'Ração Premium',
          unidade: 'kg',
          grupo: 'Ração',
          preco: 10,
          estoque: total,
          estoquePorEstoque: porEstoque,
          estoquePadraoId: padrao,
          createdAt: DateTime(2026, 9, 25),
          updatedAt: DateTime(2026, 9, 25),
        );

    test('vai e volta por toMap/fromMap (é o que o banco e a nuvem usam)', () {
      final p = novo({'estoque_loja': 5, 'estoque_deposito': 15}, 'estoque_deposito', 20);
      final mapa = p.toMap();
      expect(mapa['estoque_por_estoque'], {'estoque_loja': 5, 'estoque_deposito': 15});
      expect(mapa['estoque_padrao_id'], 'estoque_deposito');

      final voltou = Produto.fromMap(mapa);
      expect(voltou.estoquePorEstoque, {'estoque_loja': 5, 'estoque_deposito': 15});
      expect(voltou.estoquePadraoId, 'estoque_deposito');
      expect(voltou.estoque, 20, reason: 'o total do produto continua sendo o total');
    });

    test('produto sem nada disso continua funcionando (catálogo antigo)', () {
      final p = novo(const {}, null, 7);
      expect(p.estoquePorEstoque, isEmpty);
      expect(p.estoquePadraoId, isNull);
      final voltou = Produto.fromMap(p.toMap());
      expect(voltou.estoquePorEstoque, isEmpty);
      expect(voltou.estoquePadraoId, isNull);
    });

    test('copyWith troca o saldo de um estoque sem perder o resto', () {
      final p = novo({'estoque_loja': 5, 'estoque_deposito': 15}, 'estoque_deposito', 20);
      final depois = p.copyWith(estoquePorEstoque: {'estoque_loja': 4, 'estoque_deposito': 15});
      expect(depois.estoquePorEstoque['estoque_loja'], 4);
      expect(depois.estoquePadraoId, 'estoque_deposito');
      expect(p.estoquePorEstoque['estoque_loja'], 5, reason: 'o original não muda');
      expect(p.copyWith().estoquePorEstoque, p.estoquePorEstoque);
    });

    test('o estoque padrão pode ser limpo (volta a usar o principal)', () {
      final p = novo({'estoque_loja': 5, 'estoque_deposito': 15}, 'estoque_deposito', 20);
      expect(p.copyWith(limparEstoquePadrao: true).estoquePadraoId, isNull);
      expect(p.copyWith(limparEstoquePadrao: false).estoquePadraoId, 'estoque_deposito');
    });
  });
}
