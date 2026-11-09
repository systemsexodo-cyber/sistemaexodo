import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/services/historico_mensalidade.dart';

void main() {
  test('registra o pagamento do Pix nas configurações da empresa', () {
    final configs = HistoricoMensalidade.registrar(
      const {},
      competencia: '2026-11',
      valor: 120,
      pagamentoId: '987654',
      pagoEm: DateTime.utc(2026, 11, 4, 15, 30),
    );

    final historico = HistoricoMensalidade.ler(configs);
    expect(historico, hasLength(1));
    expect(historico.single['competencia'], '2026-11');
    expect(historico.single['valor'], 120);
    expect(historico.single['pagamento_id'], '987654');
    expect(historico.single['origem'], 'mercado_pago');
    expect(
      HistoricoMensalidade.rotuloData(historico.single['pago_em']),
      '04/11/2026',
    );
  });

  test('não duplica o mesmo pagamento nem o mesmo OK manual do mês', () {
    var configs = HistoricoMensalidade.registrar(
      const {},
      competencia: '2026-11',
      valor: 120,
      pagamentoId: '987654',
    );
    configs = HistoricoMensalidade.registrar(
      configs,
      competencia: '2026-11',
      valor: 120,
      pagamentoId: '987654',
    );
    configs = HistoricoMensalidade.registrar(
      configs,
      competencia: '2026-11',
      valor: 120,
      origem: 'manual',
    );
    configs = HistoricoMensalidade.registrar(
      configs,
      competencia: '2026-11',
      valor: 130,
      origem: 'manual',
    );

    final historico = HistoricoMensalidade.ler(configs);
    expect(historico, hasLength(2));
    final manual = historico.firstWhere((r) => r['origem'] == 'manual');
    expect(manual['valor'], 130);
  });

  test('mescla histórico local e da nuvem sem perder meses', () {
    final local = HistoricoMensalidade.ler(
      HistoricoMensalidade.registrar(
        const {},
        competencia: '2026-11',
        valor: 120,
        pagamentoId: '111',
        pagoEm: DateTime.utc(2026, 11, 4),
      ),
    );
    final nuvem = HistoricoMensalidade.ler(
      HistoricoMensalidade.registrar(
        HistoricoMensalidade.registrar(
          const {},
          competencia: '2026-10',
          valor: 120,
          pagamentoId: '222',
          pagoEm: DateTime.utc(2026, 10, 5),
        ),
        competencia: '2026-11',
        valor: 120,
        pagamentoId: '111',
        pagoEm: DateTime.utc(2026, 11, 4),
      ),
    );

    final mesclado = HistoricoMensalidade.mesclar(local, nuvem);
    expect(mesclado.map((r) => r['competencia']), ['2026-10', '2026-11']);

    final ordenado = HistoricoMensalidade.recentesPrimeiro(mesclado);
    expect(ordenado.first['competencia'], '2026-11');
  });

  test('mantém só os registros mais recentes e formata a competência', () {
    var configs = const <String, dynamic>{};
    for (var mes = 1; mes <= HistoricoMensalidade.maximoRegistros + 2; mes++) {
      final competencia =
          '20${(20 + mes ~/ 12).toString().padLeft(2, '0')}-'
          '${(mes % 12 + 1).toString().padLeft(2, '0')}';
      configs = HistoricoMensalidade.registrar(
        configs,
        competencia: competencia,
        valor: 120,
        origem: 'manual',
      );
    }

    expect(
      HistoricoMensalidade.ler(configs),
      hasLength(HistoricoMensalidade.maximoRegistros),
    );
    expect(HistoricoMensalidade.rotuloCompetencia('2026-11'), '11/2026');
    expect(
      HistoricoMensalidade.rotuloCompetencia('sem-formato'),
      'sem-formato',
    );
  });
}
