import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/models/mesa_comanda.dart';
import 'package:sistema_exodo_novo/services/recebimento_helper.dart';

void main() {
  ItemMesaComanda item({
    String id = 'item-1',
    double quantidade = 3,
    double quantidadePaga = 0,
    double preco = 17,
  }) {
    return ItemMesaComanda(
      id: id,
      itemId: id,
      nome: 'Item $id',
      quantidade: quantidade,
      quantidadePaga: quantidadePaga,
      preco: preco,
    );
  }

  group('planejarRecebimento com quantidade parcial', () {
    test('quita apenas a quantidade informada do item', () {
      final origens = [
        OrigemRecebimento(
          id: 'mesa-1',
          rotulo: 'Mesa 1',
          itens: [item(quantidade: 3, preco: 17)],
        ),
      ];

      final plano = planejarRecebimento(
        origens: origens,
        quantidadesPorItem: {'item-1': 2},
        garcomRetirado: true,
      );

      expect(plano.quantidadePorItem['item-1'], 2);
      expect(plano.valorItens, 34);
      expect(plano.valorTotal, 34);
    });

    test('aplica o garçom proporcional sobre a quantidade paga', () {
      final origens = [
        OrigemRecebimento(
          id: 'mesa-1',
          rotulo: 'Mesa 1',
          itens: [item(quantidade: 3, preco: 17)],
        ),
      ];

      final plano = planejarRecebimento(
        origens: origens,
        quantidadesPorItem: {'item-1': 1},
      );

      expect(plano.quantidadePorItem['item-1'], 1);
      expect(plano.valorItens, 17);
      expect(plano.valorTotal, 18.7);
    });

    test('limita a quantidade ao que ainda falta pagar', () {
      final origens = [
        OrigemRecebimento(
          id: 'mesa-1',
          rotulo: 'Mesa 1',
          itens: [item(quantidade: 3, quantidadePaga: 1)],
        ),
      ];

      final plano = planejarRecebimento(
        origens: origens,
        quantidadesPorItem: {'item-1': 10},
        garcomRetirado: true,
      );

      expect(plano.quantidadePorItem['item-1'], 2);
      expect(plano.valorItens, 34);
    });

    test('quantidadesPorItem tem prioridade sobre itensSelecionados', () {
      final origens = [
        OrigemRecebimento(
          id: 'mesa-1',
          rotulo: 'Mesa 1',
          itens: [item(quantidade: 3)],
        ),
      ];

      final plano = planejarRecebimento(
        origens: origens,
        itensSelecionados: {'item-1'},
        quantidadesPorItem: {'item-1': 1},
        garcomRetirado: true,
      );

      expect(plano.quantidadePorItem['item-1'], 1);
      expect(plano.valorItens, 17);
    });
  });
}
