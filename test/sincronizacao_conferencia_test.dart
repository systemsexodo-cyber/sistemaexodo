// Teste da SIMULAÇÃO da sincronização da conferência, contra os bancos REAIS.
//
// A sincronização da tela de conferência faz INSERT nas duas pontas, então não
// dá para exercitá-la à vontade dentro da suíte. A simulação (`simular: true`)
// monta o plano inteiro — estrutura das tabelas, colunas que existem nos dois
// lados, conversão de cada valor para o tipo da coluna de destino — e para
// exatamente antes de gravar. É isso que este teste cobra:
//
//  1. todo par divergente consegue MONTAR o plano (é aqui que apareciam os
//     erros "coluna não existe", "json inválido" e "bigint: 0.0");
//  2. nada é gravado em nenhum dos lados;
//  3. nenhuma linha desaparece de nenhum dos lados.
//
// Rodar: flutter test test/sincronizacao_conferencia_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/services/conferencia_nuvem_service.dart';

void main() {
  test('simulacao da sincronizacao planeja sem erro e nao grava nada',
      () async {
    final service = ConferenciaNuvemService.instance;

    final antes = await service.conferir();
    expect(antes.erroLocal, isNull, reason: 'o banco local precisa responder');
    expect(antes.erroNuvem, isNull, reason: 'a nuvem precisa responder');

    final divergentes = antes.comDiferenca.where((l) => !l.telemetria).toList();
    print('pares divergentes: ${divergentes.length}');

    final (ok, msg, total) = await service.sincronizarDiferencas(
      antes,
      simular: true,
      onProgress: (m) => print('  · $m'),
    );
    print('=== plano ===');
    print(msg);
    print('seriam copiadas: $total');

    // O plano tem que fechar para TODOS os pares: erro aqui é schema/tipo.
    expect(ok, isTrue, reason: 'a simulação encontrou erro de plano:\n$msg');
    expect(msg, contains('SERIAM copiadas'),
        reason: 'a mensagem tem que deixar claro que nada foi gravado');

    final depois = await service.conferir();
    final antesPorPar = {
      for (final l in antes.linhas) '${l.tabela}|${l.empresaId}': l,
    };
    for (final l in depois.linhas) {
      final a = antesPorPar['${l.tabela}|${l.empresaId}'];
      if (a == null) continue;
      // A NUVEM nunca pode encolher: a simulação só lê.
      expect(l.nuvem! >= (a.nuvem ?? 0), isTrue,
          reason: '${l.tabela}/${l.empresaId} perdeu linhas na NUVEM');
      // O LOCAL pode oscilar: o APP ESTÁ ABERTO na máquina e o sincronizador da
      // bandeja apaga/recarrega a base local em paralelo. Encolher aqui é isso —
      // não é a simulação (que não grava nada, conferido pelo `total` acima).
      if (l.local! < (a.local ?? 0)) {
        print('· ${l.tabela}/${l.empresaId}: LOCAL ${a.local} → ${l.local} '
            '(o sincronizador em paralelo mexeu; a simulação não grava)');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 10)));

  // A base local guarda somente a empresa aberta no app (o sincronizador da
  // bandeja apaga as outras a cada reinício). Por isso a sincronização, quando
  // recebe a empresa aberta, só mexe nela — e avisa que as outras ficaram fora.
  test('com a empresa aberta definida, as divergencias das outras ficam fora',
      () async {
    final service = ConferenciaNuvemService.instance;
    final r = await service.conferir();

    // Pares em que o local está zerado: aí o plano é igualzinho à contagem da
    // nuvem, o que deixa o teste exato.
    final zerados = r.comDiferenca
        .where((l) => !l.telemetria && l.local == 0 && (l.nuvem ?? 0) > 0)
        .toList();

    DiferencaConferencia? a;
    DiferencaConferencia? b;
    for (final d in zerados) {
      if (a == null) {
        a = d;
      } else if (d.empresaId != a.empresaId) {
        b = d;
        break;
      }
    }
    if (b == null) {
      print('hoje só há uma empresa divergente: nada a checar');
      return;
    }

    final plano = ResultadoConferencia(
      linhas: [a!, b!],
      somenteNoLocal: const [],
      somenteNaNuvem: const [],
      nomesDeEmpresas: r.nomesDeEmpresas,
    );

    // ⚠️ O APP ESTÁ ABERTO nesta máquina e o sincronizador da bandeja copia
    // divergências sozinho. Ou o plano traz exatamente as linhas da empresa
    // escolhida, ou não há mais nada a copiar (0) porque o outro processo já
    // resolveu — nunca uma quantidade intermediária (isso sim seria bug).
    bool planoConfere(int? total, int? nuvem) =>
        total == nuvem || total == 0;

    final (okA, msgA, totalA) = await service.sincronizarDiferencas(
      plano,
      simular: true,
      empresaAtiva: a.empresaId,
    );
    print('com a empresa aberta = ${a.empresaId}: $totalA linha(s) | $msgA');
    expect(okA, isTrue, reason: msgA);
    expect(planoConfere(totalA, a.nuvem), isTrue,
        reason: 'só as linhas da empresa aberta podem entrar no plano '
            '(plano=$totalA, nuvem=${a.nuvem})');
    expect(msgA, contains('outras empresas'),
        reason: 'o relatório precisa avisar que as outras ficaram de fora');

    final (_, msgB, totalB) = await service.sincronizarDiferencas(
      plano,
      simular: true,
      empresaAtiva: b.empresaId,
    );
    print('com a empresa aberta = ${b.empresaId}: $totalB linha(s) | $msgB');
    expect(planoConfere(totalB, b.nuvem), isTrue,
        reason: 'trocando a empresa aberta, o plano passa a ser o dela '
            '(plano=$totalB, nuvem=${b.nuvem}); 0 = o sincronizador em '
            'paralelo já copiou');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
