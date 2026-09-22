// Teste da conferência Local × Nuvem contra os bancos REAIS.
//
// Só leitura: abre uma conexão no PostgreSQL local e outra no Postgres da nuvem
// (Session pooler) e compara as contagens por empresa. Não grava nada.
//
// Rodar: flutter test test/conferencia_nuvem_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/services/conferencia_nuvem_service.dart';

void main() {
  const bmj = '22ae2c16-a730-43f3-a4f9-19f105eb0d13';

  test('conferir conta local e nuvem e aponta as diferencas por empresa',
      () async {
    final r = await ConferenciaNuvemService.instance.conferir();

    print('erro local : ${r.erroLocal ?? '(nenhum)'}');
    print('erro nuvem : ${r.erroNuvem ?? '(nenhum)'}');
    print('linhas comparadas (tabela+empresa): ${r.linhas.length}');
    print('total local: ${r.totalLocal} | total nuvem: ${r.totalNuvem}');
    print('diferencas : ${r.comDiferenca.length}');
    print('so no local: ${r.somenteNoLocal}');
    print('so na nuvem: ${r.somenteNaNuvem}');

    for (final d in r.comDiferenca.take(15)) {
      print('  ${d.tabela} | ${d.empresaId} | '
          'local=${d.local} nuvem=${d.nuvem} delta=${d.diferenca}');
    }

    expect(r.erroLocal, isNull, reason: 'o banco local precisa responder');
    expect(r.erroNuvem, isNull, reason: 'a nuvem precisa responder');
    expect(r.linhas, isNotEmpty, reason: 'nenhuma contagem foi comparada');
    expect(r.linhas.length, greaterThan(20),
        reason: 'deveriam entrar dezenas de pares tabela+empresa');

    // A BMJ tem clientes e produtos nos dois lados: as contagens devem existir.
    final produtosBmj = r.linhas.where(
      (l) => l.tabela == 'produtos' && l.empresaId == bmj,
    );
    expect(produtosBmj, isNotEmpty, reason: 'produtos da BMJ nao apareceu');
    final p = produtosBmj.first;
    print('produtos BMJ -> local=${p.local} nuvem=${p.nuvem}');
    expect(p.local, isNotNull);
    expect(p.nuvem, isNotNull);

    // O nome da empresa precisa ser resolvido (relatorio legivel).
    print('nome da BMJ: ${r.nomeDaEmpresa(bmj)}');
    expect(r.nomeDaEmpresa(bmj), isNot(bmj));

    // Toda diferenca reportada tem que ser realmente diferente.
    for (final d in r.comDiferenca) {
      expect(d.diferenca == 0, isFalse);
    }

    // Contagem que deu certo nao pode vir como "desconhecido": tabela vazia
    // para aquela empresa e' 0, nao null.
    for (final l in r.linhas) {
      expect(l.local, isNotNull,
          reason: '${l.tabela}/${l.empresaId} ficou sem contagem local');
      expect(l.nuvem, isNotNull,
          reason: '${l.tabela}/${l.empresaId} ficou sem contagem na nuvem');
    }

    // Telemetria (logs/views) fica marcada e pode ser escondida.
    final telemetria = r.linhas.where((l) => l.telemetria).toList();
    print('linhas de telemetria: ${telemetria.length}');
    expect(telemetria, isNotEmpty);
    final semTelemetria = r.filtrar(
      somenteDiferencas: true,
      ocultarTelemetria: true,
    );
    expect(semTelemetria.any((l) => l.telemetria), isFalse,
        reason: 'o filtro de telemetria vazou logs para o relatorio');
    expect(r.contarDiferencas(ocultarTelemetria: true),
        lessThanOrEqualTo(r.comDiferenca.length));
    print('diferencas sem telemetria: '
        '${r.contarDiferencas(ocultarTelemetria: true)}');

    // Um caso concreto conhecido: o historico de produto da empresa ATIVA agora
    // desce para o local (o sincronizador da bandeja passou a importar só a
    // empresa aberta), então o local pode ser igual ou MENOR que a nuvem — mas
    // nunca maior (isso indicaria dado que a nuvem não tem).
    final historico = r.linhas.where(
      (l) => l.tabela == 'produto_historico' && l.empresaId == bmj,
    );
    if (historico.isNotEmpty) {
      print('produto_historico BMJ -> local=${historico.first.local} '
          'nuvem=${historico.first.nuvem}');
      expect(historico.first.nuvem, greaterThan(0));
      expect(historico.first.local,
          lessThanOrEqualTo(historico.first.nuvem ?? 0),
          reason: 'o local não pode ter mais historico do que a nuvem');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
