// Teste de integração do push da nuvem (Neon Realtime).
//
// Prova o caminho completo usado pelo app: [NeonRealtimeService] assina uma
// tabela e o sinal tem de chegar quando os dados MUDAM de verdade — a mudança
// é feita pelo MESMO cliente da nuvem que o app usa ([NeonClient], Data API),
// não por um atalho de teste.
//
// Precisa das credenciais (`.env.neon` com NEON_REALTIME_URL/SECRET) e de
// internet. Rode:
//
//   flutter test test/neon_realtime_service_test.dart
//
// Marca as linhas que cria com um marcador único e as apaga no fim.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/services/neon_client.dart';
import 'package:sistema_exodo_novo/services/neon_config.dart';
import 'package:sistema_exodo_novo/services/neon_realtime_service.dart';

void main() {
  final marcador = 'teste-realtime-${DateTime.now().millisecondsSinceEpoch}';

  test('assinatura avisa quando a tabela muda na nuvem', () async {
    if (!NeonConfig.realtimeDisponivel) {
      markTestSkipped(
        'Sem NEON_REALTIME_URL/SECRET em ${NeonConfig.nomeArquivo}.',
      );
      return;
    }

    final nuvem = NeonClient.instance;
    await nuvem.inicializar();

    // A empresa '1' existe na nuvem (é a empresa padrão do banco).
    const empresaId = '1';
    final avisos = <String>[];
    final chegou = Completer<void>();

    await NeonRealtimeService.instance.iniciar(
      empresaId,
      tabelas: const ['sync_logs'],
      onMudanca: (tabela) {
        avisos.add(tabela);
        if (!chegou.isCompleted) chegou.complete();
      },
    );

    // Espera a assinatura subir (o serviço assina logo após o `ready`).
    final inicio = DateTime.now();
    while (NeonRealtimeService.instance.assinaturasAtivas == 0 &&
        DateTime.now().difference(inicio) < const Duration(seconds: 20)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    expect(
      NeonRealtimeService.instance.assinaturasAtivas,
      greaterThan(0),
      reason: 'a assinatura de sync_logs não ficou ativa em 20 s',
    );

    // Escrita REAL na nuvem, pelo mesmo cliente do app.
    await nuvem.from('sync_logs').insert({
      'empresa_id': empresaId,
      'pc_name': marcador,
      'evento': 'prova-realtime',
      'detalhes': 'teste de integração do push da nuvem',
    });

    await chegou.future.timeout(
      const Duration(seconds: 25),
      onTimeout: () => throw StateError(
        'o sinal de mudança não chegou em 25 s (avisos: $avisos)',
      ),
    );

    expect(avisos, contains('sync_logs'));

    // Limpeza: apaga só o que este teste criou.
    await nuvem.from('sync_logs').delete().eq('pc_name', marcador);
    await NeonRealtimeService.instance.parar();
  }, timeout: const Timeout(Duration(minutes: 2)));

  // O selo vence em 60 s. Se a renovação não funcionar, o realtime morre em
  // silêncio depois de um minuto — é o defeito mais fácil de passar despercebido.
  test('continua avisando depois de renovar o selo (>60 s)', () async {
    if (!NeonConfig.realtimeDisponivel) {
      markTestSkipped(
        'Sem NEON_REALTIME_URL/SECRET em ${NeonConfig.nomeArquivo}.',
      );
      return;
    }

    final nuvem = NeonClient.instance;
    await nuvem.inicializar();
    const empresaId = '1';
    final marcadorRenovacao = '$marcador-renovacao';

    var avisos = 0;
    await NeonRealtimeService.instance.iniciar(
      empresaId,
      tabelas: const ['sync_logs'],
      onMudanca: (_) => avisos++,
    );

    final inicio = DateTime.now();
    while (NeonRealtimeService.instance.assinaturasAtivas == 0 &&
        DateTime.now().difference(inicio) < const Duration(seconds: 20)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    expect(NeonRealtimeService.instance.assinaturasAtivas, greaterThan(0));

    // Passa da validade do selo (60 s) com o serviço no ar.
    await Future<void>.delayed(const Duration(seconds: 70));

    avisos = 0;
    await nuvem.from('sync_logs').insert({
      'empresa_id': empresaId,
      'pc_name': marcadorRenovacao,
      'evento': 'prova-realtime-renovacao',
      'detalhes': 'teste da renovação do selo',
    });

    final prazo = DateTime.now().add(const Duration(seconds: 25));
    while (avisos == 0 && DateTime.now().isBefore(prazo)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    expect(
      avisos,
      greaterThan(0),
      reason: 'o aviso parou depois da renovação (selo vencido não foi trocado)',
    );

    await nuvem.from('sync_logs').delete().eq('pc_name', marcadorRenovacao);
    await NeonRealtimeService.instance.parar();
  }, timeout: const Timeout(Duration(minutes: 4)));
}
