// O limite de "dias sem internet antes de pedir a chave de liberação offline"
// é configurável POR EMPRESA (configuracoes['limite_dias_offline']).
//
// Antes o valor estava fixo no código (5 em quase todas as telas, 7 no boot),
// então não dava para ajustar por empresa nem testar um cenário de 7 dias de
// forma consistente. Agora Empresa.verificarMotivoBloqueio usa o limite da
// própria empresa quando nenhum valor é passado.

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';

Empresa _bmj({Map<String, dynamic>? configuracoes}) => Empresa(
  id: 'BMJ',
  razaoSocial: 'BMJ',
  slug: 'bmj',
  configuracoes: configuracoes,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

MotivoBloqueioEmpresa _comDiasOffline(int dias) => _bmj().verificarMotivoBloqueio(
  ultimaValidacaoOnline: DateTime.now().subtract(Duration(days: dias)),
);

void main() {
  test('sem configuração, usa o padrão de 7 dias', () {
    expect(_bmj().limiteDiasOffline, Empresa.limiteDiasOfflinePadrao);
    expect(_bmj().limiteDiasOffline, 7);
  });

  test('lê o limite configurado da empresa (aceita int e String)', () {
    expect(
      _bmj(configuracoes: {'limite_dias_offline': 10}).limiteDiasOffline,
      10,
    );
    expect(
      _bmj(configuracoes: {'limite_dias_offline': '3'}).limiteDiasOffline,
      3,
    );
    // JSON/Supabase pode devolver numérico como double.
    expect(
      _bmj(configuracoes: {'limite_dias_offline': 10.0}).limiteDiasOffline,
      10,
    );
  });

  test('configuração ausente/inválida cai no padrão', () {
    expect(
      _bmj(configuracoes: {'limite_dias_offline': 'abc'}).limiteDiasOffline,
      7,
    );
    expect(
      _bmj(configuracoes: {'limite_dias_offline': 0}).limiteDiasOffline,
      7,
    );
    expect(
      _bmj(configuracoes: {'limite_dias_offline': -2}).limiteDiasOffline,
      7,
    );
  });

  test('a partir de 7 dias offline a empresa padrão NÃO bloqueia', () {
    expect(_comDiasOffline(7), MotivoBloqueioEmpresa.nenhum);
  });

  test('com 8 dias offline a empresa padrão bloqueia (mais de 7 dias)', () {
    expect(_comDiasOffline(8), MotivoBloqueioEmpresa.excessoDiasOffline);
  });

  test('o limite configurado é respeitado (empresa de 3 dias)', () {
    final bmj = _bmj(configuracoes: {'limite_dias_offline': 3});
    expect(
      bmj.verificarMotivoBloqueio(
        ultimaValidacaoOnline: DateTime.now().subtract(
          const Duration(days: 4),
        ),
      ),
      MotivoBloqueioEmpresa.excessoDiasOffline,
    );
    expect(
      bmj.verificarMotivoBloqueio(
        ultimaValidacaoOnline: DateTime.now().subtract(
          const Duration(days: 3),
        ),
      ),
      MotivoBloqueioEmpresa.nenhum,
    );
  });

  test('limite explícito ainda tem prioridade sobre a configuração', () {
    final bmj = _bmj(configuracoes: {'limite_dias_offline': 30});
    expect(
      bmj.verificarMotivoBloqueio(
        ultimaValidacaoOnline: DateTime.now().subtract(const Duration(days: 6)),
        limiteDiasOffline: 5,
      ),
      MotivoBloqueioEmpresa.excessoDiasOffline,
    );
  });
}
