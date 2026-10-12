import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/models/lote_produto.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';

void main() {
  test('validade de hoje continua válida durante todo o dia', () {
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final loteHoje = LoteProduto(
      id: 'vence-hoje',
      produtoId: 'p1',
      numeroLote: 'A',
      dataValidade: hoje,
      quantidade: 1,
    );

    expect(loteHoje.diasParaVencer, 0);
    expect(loteHoje.estaVencido, isFalse);
    expect(loteHoje.venceHoje, isTrue);

    final loteVencido = LoteProduto(
      id: 'venceu-ontem',
      produtoId: 'p1',
      numeroLote: 'B',
      dataValidade: hoje.subtract(const Duration(days: 1)),
      quantidade: 1,
    );
    expect(loteVencido.diasParaVencer, -1);
    expect(loteVencido.estaVencido, isTrue);
  });

  test('lista lotes vencidos e próximos, mas ignora sem saldo ou fora do prazo', () {
    final hoje = DateTime.now();
    final hojeDia = DateTime(hoje.year, hoje.month, hoje.day);
    final lotes = [
      LoteProduto(
        id: 'vencido',
        produtoId: 'p1',
        numeroLote: 'A',
        dataValidade: hojeDia.subtract(const Duration(days: 1)),
        quantidade: 2,
      ),
      LoteProduto(
        id: 'proximo',
        produtoId: 'p2',
        numeroLote: 'B',
        dataValidade: hojeDia.add(const Duration(days: 19)),
        quantidade: 4,
      ),
      LoteProduto(
        id: 'limite-30-dias',
        produtoId: 'p6',
        numeroLote: 'F',
        dataValidade: hojeDia.add(const Duration(days: 30)),
        quantidade: 1,
      ),
      LoteProduto(
        id: 'fora-limite',
        produtoId: 'p7',
        numeroLote: 'G',
        dataValidade: hojeDia.add(const Duration(days: 31)),
        quantidade: 1,
      ),
      LoteProduto(
        id: 'sem-saldo',
        produtoId: 'p3',
        numeroLote: 'C',
        dataValidade: hojeDia.add(const Duration(days: 1)),
        quantidade: 0,
      ),
      LoteProduto(
        id: 'longe',
        produtoId: 'p4',
        numeroLote: 'D',
        dataValidade: hojeDia.add(const Duration(days: 61)),
        quantidade: 1,
      ),
      LoteProduto(
        id: 'sem-validade',
        produtoId: 'p5',
        numeroLote: 'E',
        quantidade: 1,
      ),
    ];

    final resultado = DataService.filtrarLotesComValidadeCritica(
      lotes,
      hoje: hojeDia,
    );

    expect(resultado.map((lote) => lote.id), [
      'vencido',
      'proximo',
      'limite-30-dias',
    ]);
  });
}