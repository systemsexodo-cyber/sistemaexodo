// REGRESSÃO: a comissão do motoboy é a SOMA de duas partes.
//
// Pedido do balcão: "ele pode ter valor fixo de diário mais valor fixo na
// entrega para somar e calcular a comissão".
//
// Antes o cadastro só tinha UMA escolha ('Fixo por Entrega' | 'Diária' |
// 'Porcentagem'), então quem pagava diária MAIS valor por entrega não tinha
// como cadastrar as duas coisas — e a tela de Comissões contava só uma delas.
//
// O cálculo vive em `agregarComissaoMotoboys` (puro, sem widget), justamente
// para poder ser verificado aqui.
//
// Rodar: flutter test test/comissao_motoboy_diaria_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/models/entrega.dart';
import 'package:sistema_exodo_novo/pages/comissoes_page.dart';

Entrega _entrega({
  required String id,
  required String motoristaId,
  required DateTime criadaEm,
  DateTime? entregueEm,
  double? taxa,
}) {
  return Entrega(
    id: id,
    pedidoId: 'pedido-$id',
    clienteNome: 'Cliente $id',
    enderecoEntrega: 'Rua Teste, 1',
    status: StatusEntrega.entregue,
    dataCriacao: criadaEm,
    dataEntrega: entregueEm ?? criadaEm,
    motoristaId: motoristaId,
    taxaEntrega: taxa,
  );
}

void main() {
  test('diária + valor por entrega SOMAM, e a diária conta 1x por dia', () {
    final motoboy = Motorista(
      id: 'm1',
      nome: 'Entregador',
      tipoComissao: 'Fixo por Entrega',
      valorComissao: 7.50,
      valorDiaria: 50.0,
    );

    // 3 entregas: duas no dia 02/10 e uma no dia 03/10 → 2 dias trabalhados.
    final resultado = agregarComissaoMotoboys(
      entregas: [
        _entrega(
          id: '1',
          motoristaId: 'm1',
          criadaEm: DateTime(2026, 10, 2, 10),
          taxa: 10,
        ),
        _entrega(
          id: '2',
          motoristaId: 'm1',
          criadaEm: DateTime(2026, 10, 2, 15),
          taxa: 10,
        ),
        _entrega(
          id: '3',
          motoristaId: 'm1',
          criadaEm: DateTime(2026, 10, 3, 11),
          taxa: 10,
        ),
      ],
      motoristaPorId: (id) => id == 'm1' ? motoboy : null,
    );

    expect(resultado, hasLength(1));
    final c = resultado.single;
    expect(c.entregas, 3);
    expect(c.diasTrabalhados, 2,
        reason: 'Duas entregas no MESMO dia contam um único dia de diária.');
    expect(c.totalPorEntrega, 22.50);
    expect(c.totalDiaria, 100.0);
    expect(c.total, 122.50,
        reason: 'A comissão tem de somar diária com valor por entrega.');
  });

  test('só diária: não paga por entrega', () {
    final motoboy = Motorista(
      id: 'm1',
      nome: 'Diarista',
      tipoComissao: 'Diária',
      valorComissao: 0.0,
      valorDiaria: 60.0,
    );

    final c = agregarComissaoMotoboys(
      entregas: [
        _entrega(
          id: '1',
          motoristaId: 'm1',
          criadaEm: DateTime(2026, 10, 2, 9),
          taxa: 12,
        ),
        _entrega(
          id: '2',
          motoristaId: 'm1',
          criadaEm: DateTime(2026, 10, 3, 9),
          taxa: 12,
        ),
      ],
      motoristaPorId: (_) => motoboy,
    ).single;

    expect(c.totalPorEntrega, 0.0);
    expect(c.totalDiaria, 120.0);
    expect(c.total, 120.0);
  });

  test('porcentagem + diária somam', () {
    final motoboy = Motorista(
      id: 'm1',
      nome: 'Porcentagem',
      tipoComissao: 'Porcentagem',
      valorComissao: 10.0, // 10% da taxa
      valorDiaria: 30.0,
    );

    final c = agregarComissaoMotoboys(
      entregas: [
        _entrega(
          id: '1',
          motoristaId: 'm1',
          criadaEm: DateTime(2026, 10, 2, 9),
          taxa: 20,
        ),
        _entrega(
          id: '2',
          motoristaId: 'm1',
          criadaEm: DateTime(2026, 10, 2, 13),
          taxa: 30,
        ),
      ],
      motoristaPorId: (_) => motoboy,
    ).single;

    expect(c.totalPorEntrega, 5.0, reason: '10% de 20 + 10% de 30 = 5,00.');
    expect(c.totalDiaria, 30.0);
    expect(c.total, 35.0);
  });

  test('o dia da diária é o dia da CONCLUSÃO, não o da criação', () {
    final motoboy = Motorista(
      id: 'm1',
      nome: 'Entregador',
      tipoComissao: 'Fixo por Entrega',
      valorComissao: 5.0,
      valorDiaria: 40.0,
    );

    // Criada em 01/10, concluída em 03/10: conta como dia 03/10.
    final c = agregarComissaoMotoboys(
      entregas: [
        _entrega(
          id: '1',
          motoristaId: 'm1',
          criadaEm: DateTime(2026, 10, 1, 8),
          entregueEm: DateTime(2026, 10, 3, 18),
        ),
        _entrega(
          id: '2',
          motoristaId: 'm1',
          criadaEm: DateTime(2026, 10, 1, 9),
          entregueEm: DateTime(2026, 10, 3, 19),
        ),
      ],
      motoristaPorId: (_) => motoboy,
    ).single;

    expect(c.diasTrabalhados, 1,
        reason: 'As duas foram concluídas no mesmo dia (03/10).');
    expect(c.totalDiaria, 40.0);
  });

  test('motoboy não cadastrado: ganha a taxa integral e nenhuma diária', () {
    final c = agregarComissaoMotoboys(
      entregas: [
        _entrega(
          id: '1',
          motoristaId: 'fantasma',
          criadaEm: DateTime(2026, 10, 2, 9),
          taxa: 8.0,
        ),
      ],
      motoristaPorId: (_) => null,
    ).single;

    expect(c.totalPorEntrega, 8.0);
    expect(c.totalDiaria, 0.0);
    expect(c.total, 8.0);
  });

  test('separa por motoboy e ordena do maior total para o menor', () {
    final comDiaria = Motorista(
      id: 'm1',
      nome: 'Com diária',
      tipoComissao: 'Fixo por Entrega',
      valorComissao: 5.0,
      valorDiaria: 50.0,
    );
    final semDiaria = Motorista(
      id: 'm2',
      nome: 'Sem diária',
      tipoComissao: 'Fixo por Entrega',
      valorComissao: 5.0,
    );

    final resultado = agregarComissaoMotoboys(
      entregas: [
        _entrega(
          id: '1',
          motoristaId: 'm2',
          criadaEm: DateTime(2026, 10, 2, 9),
          taxa: 10,
        ),
        _entrega(
          id: '2',
          motoristaId: 'm1',
          criadaEm: DateTime(2026, 10, 2, 10),
          taxa: 10,
        ),
      ],
      motoristaPorId: (id) => id == 'm1' ? comDiaria : semDiaria,
    );

    expect(resultado, hasLength(2));
    expect(resultado.first.motoristaId, 'm1');
    expect(resultado.first.total, 55.0);
    expect(resultado.last.total, 5.0);
  });

  test('entrega sem motorista não entra na conta de ninguém', () {
    final resultado = agregarComissaoMotoboys(
      entregas: [
        Entrega(
          id: '1',
          pedidoId: 'p1',
          clienteNome: 'Cliente',
          enderecoEntrega: 'Rua Teste, 1',
          status: StatusEntrega.entregue,
          dataCriacao: DateTime(2026, 10, 2),
          taxaEntrega: 10,
        ),
      ],
      motoristaPorId: (_) => throw StateError('não deveria consultar'),
    );

    expect(resultado, isEmpty);
  });
}
