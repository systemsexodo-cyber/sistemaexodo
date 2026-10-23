// REGRESSÃO: no painel de motoboys o operador precisa VER a comissão de cada
// entrega e o TOTAL, filtrando por motoboy e por entrega — e poder DESFAZER um
// "Entregue" (para a entrega sair da conta da comissão).
//
// Pedido do balcão: "no filtro de entregas já entregues do motoboy, a opção de
// ver o valor de cada comissão e o total, com filtro por motoboy e entrega" e
// "opção de tirar entregue e colocar como não entregue para não contabilizar na
// comissão".
//
// O cálculo vive em `comissaoPorEntregaDoMotoboy` (puro, sem widget) e a
// limpeza da data de entrega em `copyWith(limparDataEntrega: true)`, justamente
// para poderem ser verificados aqui.
//
// Rodar: flutter test test/painel_motoboys_comissao_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/models/delivery_info.dart';
import 'package:sistema_exodo_novo/models/entrega.dart';
import 'package:sistema_exodo_novo/pages/painel_motoboys_page.dart';

void main() {
  group('comissão por entrega mostrada no painel', () {
    test('Fixo por Entrega: paga o valor fixo, independente da taxa', () {
      final motoboy = Motorista(
        id: 'm1',
        nome: 'Volneizão',
        tipoComissao: 'Fixo por Entrega',
        valorComissao: 10.0,
      );

      expect(
        comissaoPorEntregaDoMotoboy(motorista: motoboy, taxaEntrega: 7.0),
        10.0,
      );
      expect(
        comissaoPorEntregaDoMotoboy(motorista: motoboy, taxaEntrega: 0.0),
        10.0,
      );
    });

    test('Porcentagem: paga o percentual sobre a taxa da entrega', () {
      final motoboy = Motorista(
        id: 'm1',
        nome: 'Volneizão',
        tipoComissao: 'Porcentagem',
        valorComissao: 50.0,
      );

      expect(
        comissaoPorEntregaDoMotoboy(motorista: motoboy, taxaEntrega: 30.0),
        15.0,
      );
    });

    test('Diária: não paga nada por entrega (o valor está na diária)', () {
      final motoboy = Motorista(
        id: 'm1',
        nome: 'Volneizão',
        tipoComissao: 'Diária',
        valorComissao: 60.0,
        valorDiaria: 60.0,
      );

      expect(
        comissaoPorEntregaDoMotoboy(motorista: motoboy, taxaEntrega: 30.0),
        0.0,
      );
    });

    test('sem motoboy definido: não há comissão a mostrar', () {
      expect(
        comissaoPorEntregaDoMotoboy(motorista: null, taxaEntrega: 30.0),
        0.0,
      );
    });
  });

  group('desfazer "Entregue" tira a entrega da comissão', () {
    test('a ENTREGA volta para "Em Entrega" e some da conta de comissões', () {
      final entregue = Entrega(
        id: 'e1',
        pedidoId: 'p1',
        clienteNome: 'Cliente',
        enderecoEntrega: 'Rua A, 1',
        status: StatusEntrega.entregue,
        dataCriacao: DateTime(2026, 10, 15, 10),
        dataEntrega: DateTime(2026, 10, 15, 11),
        motoristaId: 'm1',
        taxaEntrega: 10.0,
      );

      final desfeita = entregue.copyWith(
        status: StatusEntrega.emEntrega,
        limparDataEntrega: true,
      );

      expect(desfeita.status, StatusEntrega.emEntrega);
      expect(desfeita.dataEntrega, isNull);

      // A tela de Comissões só soma entrega com status 'Entregue'.
      final aPagar = [entregue, desfeita]
          .where((e) => e.status == StatusEntrega.entregue)
          .toList();
      expect(aPagar.length, 1);
    });

    test('o endereço do pedido também limpa a data de entrega', () {
      final info = DeliveryInfo(
        id: 'd1',
        enderecoId: '',
        logradouro: 'Rua A',
        numero: '1',
        bairro: 'Centro',
        cidade: 'Cidade',
        uf: 'SP',
        status: 'Entregue',
        motoristaId: 'm1',
        dataSaida: DateTime(2026, 10, 15, 10),
        dataEntrega: DateTime(2026, 10, 15, 11),
      );

      final desfeita = info.copyWith(
        status: 'Saiu para entrega',
        limparDataEntrega: true,
      );

      expect(desfeita.status, 'Saiu para entrega');
      expect(desfeita.dataEntrega, isNull);
      // O restante do endereço continua intacto.
      expect(desfeita.logradouro, 'Rua A');
      expect(desfeita.dataSaida, DateTime(2026, 10, 15, 10));
    });
  });
}
