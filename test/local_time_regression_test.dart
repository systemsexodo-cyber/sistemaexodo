import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/models/caixa.dart';
import 'package:sistema_exodo_novo/models/forma_pagamento.dart';
import 'package:sistema_exodo_novo/models/venda_balcao.dart';
import 'package:sistema_exodo_novo/utils/date_parser.dart';

void main() {
  test('VendaBalcao.toMap() deve serializar em UTC (evita deslocamento de fuso no Supabase)', () {
    final dataVenda = DateTime(2026, 7, 12, 13, 1, 0); // hora local (BRT)
    final venda = VendaBalcao(
      id: 'v1',
      numero: 'VND-0001',
      dataVenda: dataVenda,
      itens: const [],
      tipoPagamento: TipoPagamento.dinheiro,
      valorTotal: 100,
      createdAt: dataVenda,
    );

    final map = venda.toMap();

    // O valor serializado deve carregar fuso explícito (Z = UTC).
    expect(map['data_venda'], equals(dataVenda.toUtc().toIso8601String()));
    expect(map['created_at'], equals(dataVenda.toUtc().toIso8601String()));

    // Round-trip: o DateParser deve recuperar a MESMA hora local de origem.
    final parseado = DateParser.parse(map['data_venda']);
    expect(parseado.hour, equals(dataVenda.hour));
    expect(parseado.minute, equals(dataVenda.minute));
  });

  test('AberturaCaixa.toMap() deve serializar em UTC (evita deslocamento de fuso no Supabase)', () {
    final dataAbertura = DateTime(2026, 7, 12, 13, 1, 0); // hora local (BRT)
    final abertura = AberturaCaixa(
      id: 'a1',
      numero: 'CAIXA-001',
      dataAbertura: dataAbertura,
      valorInicial: 0,
      createdAt: dataAbertura,
      updatedAt: dataAbertura,
    );

    final map = abertura.toMap();

    expect(map['data_abertura'], equals(dataAbertura.toUtc().toIso8601String()));
    expect(map['created_at'], equals(dataAbertura.toUtc().toIso8601String()));
    expect(map['updated_at'], equals(dataAbertura.toUtc().toIso8601String()));

    final parseado = DateParser.parse(map['data_abertura']);
    expect(parseado.hour, equals(dataAbertura.hour));
    expect(parseado.minute, equals(dataAbertura.minute));
  });

  test('SangriaCaixa.toMap() deve serializar em UTC', () {
    final data = DateTime(2026, 7, 12, 13, 1, 0);
    final sangria = SangriaCaixa(
      id: 's1',
      aberturaCaixaId: 'a1',
      data: data,
      valor: 50,
      motivo: 'teste',
      createdAt: data,
      updatedAt: data,
    );

    final map = sangria.toMap();

    expect(map['data_operacao'], equals(data.toUtc().toIso8601String()));
    final parseado = DateParser.parse(map['data_operacao']);
    expect(parseado.hour, equals(data.hour));
    expect(parseado.minute, equals(data.minute));
  });
}
