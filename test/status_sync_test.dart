import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/models/status_sync.dart';

/// O monitor de sincronização precisa responder duas perguntas: "há quantos
/// dias esta máquina está sem dar sinal?" e "o erro que aparece ainda vale?".
/// As duas respostas ficam no [StatusSync], longe da UI, e são o que este teste
/// trava — inclusive o caso que enganava o monitor: erro antigo já superado e
/// cliente que desligou (a flag `online` fica `true` para sempre).
void main() {
  final agora = DateTime.utc(2026, 9, 21, 12, 0);
  const empresaId = '22ae2c16-a730-43f3-a4f9-19f105eb0d13';

  StatusSync com(Map<String, dynamic> extra, {String id = empresaId}) =>
      StatusSync.fromMap(id, {
        'empresa_id': id,
        'pc_name': 'PDV-CAIXA-01',
        ...extra,
      });

  test('cliente que acabou de sincronizar: saudável', () {
    final status = com({
      'online': true,
      'ultima_sincronizacao': agora.toIso8601String(),
      'online_data': agora.toIso8601String(),
      'updated_at': agora.toIso8601String(),
      'fila_pendente': 0,
    });

    expect(status.textoStatus(agora), 'Online agora');
    expect(status.tempoLegivel(agora), 'agora');
    expect(status.criticidade(agora), 0);
    expect(status.seloOffline(agora), isNull);
    expect(status.temErroNaoResolvido, isFalse);
  });

  test('parado no mesmo dia mostra horas, sem selo de offline', () {
    final status = com({
      'ultima_sincronizacao':
          agora.subtract(const Duration(hours: 3, minutes: 20)).toIso8601String(),
      'online_data': agora.subtract(const Duration(hours: 3, minutes: 20)).toIso8601String(),
    });

    expect(status.textoStatus(agora), 'Parado há 3h');
    expect(status.tempoLegivel(agora), 'há 3h 20min');
    expect(status.criticidade(agora), 1);
    expect(status.seloOffline(agora), isNull);
  });

  test('offline há dias: é isso que o suporte precisa ver na hora', () {
    final status = com({
      'online': true, // congelado em true: a máquina desligou
      'ultima_sincronizacao':
          agora.subtract(const Duration(days: 3, hours: 4)).toIso8601String(),
      'online_data':
          agora.subtract(const Duration(days: 3, hours: 4)).toIso8601String(),
    });

    expect(status.diasSemContato(agora), 3);
    expect(status.semContatoHaDias(agora), isTrue);
    expect(status.seloOffline(agora), '3 DIAS OFFLINE');
    expect(status.textoStatus(agora), 'OFFLINE há 3 dias');
    expect(status.tempoLegivel(agora), 'há 3 dias e 4h');
    expect(status.criticidade(agora), 3);
  });

  test('um dia offline usa o singular', () {
    final status = com({
      'online_data': agora.subtract(const Duration(hours: 30)).toIso8601String(),
    });

    expect(status.seloOffline(agora), '1 DIA OFFLINE');
    expect(status.textoStatus(agora), 'OFFLINE há 1 dia');
    expect(status.tempoLegivel(agora), 'há 1 dia e 6h');
  });

  test('nunca sincronizou não é tratado como offline saudável', () {
    final status = com({'online': false});

    expect(status.ultimoContato, isNull);
    expect(status.tempoSemContato(agora), isNull);
    expect(status.diasSemContato(agora), isNull);
    expect(status.textoStatus(agora), 'Nunca sincronizou');
    expect(status.seloOffline(agora), 'NUNCA SINCRONIZOU');
    expect(status.criticidade(agora), 2);
  });

  test('erro no MESMO instante da última sincronização está pendente', () {
    // É exatamente o que o sincronizador grava quando o ciclo termina com erro:
    // ultima_sincronizacao e ultimo_erro_data com o mesmo timestamp.
    final status = com({
      'ultima_sincronizacao': agora.toIso8601String(),
      'ultimo_erro': 'upload produtos: HTTP 500',
      'ultimo_erro_data': agora.toIso8601String(),
    });

    expect(status.temErroNaoResolvido, isTrue);
    expect(status.textoStatus(agora), 'Com erro');
    expect(status.criticidade(agora), 4);
  });

  test('erro posterior à última sincronização está pendente', () {
    final status = com({
      'ultima_sincronizacao':
          agora.subtract(const Duration(hours: 2)).toIso8601String(),
      'ultimo_erro': 'upload produtos: HTTP 500',
      'ultimo_erro_data':
          agora.subtract(const Duration(minutes: 40)).toIso8601String(),
    });

    expect(status.temErroNaoResolvido, isTrue);
    expect(status.erroJaResolvido, isFalse);
    expect(status.textoStatus(agora), 'Com erro');
    expect(status.erroHaQuantoTempo(agora), 'há 40min');
    // Erro pendente é o caso mais grave, mesmo com o cliente "recente".
    expect(status.criticidade(agora), 4);
  });

  test('erro antigo já superado por sincronização posterior não acende alerta', () {
    final status = com({
      'ultima_sincronizacao':
          agora.subtract(const Duration(minutes: 3)).toIso8601String(),
      'ultimo_erro': 'download vendas_balcao: falha na nuvem',
      'ultimo_erro_data':
          agora.subtract(const Duration(days: 2)).toIso8601String(),
    });

    expect(status.temErroNaoResolvido, isFalse);
    expect(status.erroJaResolvido, isTrue);
    expect(status.textoStatus(agora), 'Online agora');
    expect(status.criticidade(agora), 0);
  });

  test('erro sem data é considerado pendente (não pode passar em branco)', () {
    final status = com({
      'ultima_sincronizacao':
          agora.subtract(const Duration(minutes: 1)).toIso8601String(),
      'ultimo_erro': 'excecao no ciclo',
    });

    expect(status.temErroNaoResolvido, isTrue);
  });

  test('o contato mais recente manda: heartbeat novo salva a máquina de parecer parada', () {
    final status = com({
      // A sincronização de dados foi ontem...
      'ultima_sincronizacao':
          agora.subtract(const Duration(days: 1)).toIso8601String(),
      // ...mas o heartbeat (a cada 2 min) está em dia.
      'online_data':
          agora.subtract(const Duration(minutes: 2)).toIso8601String(),
    });

    expect(status.ultimoContato, agora.subtract(const Duration(minutes: 2)));
    expect(status.criticidade(agora), 0);
    expect(status.tempoLegivel(agora), 'há 2min');
  });

  test('ordenação: pior primeiro (erro, dias offline, nunca, ok)', () {
    final comErro = com({
      'ultimo_erro': 'falhou',
      'ultimo_erro_data': agora.toIso8601String(),
      'ultima_sincronizacao': agora.toIso8601String(),
    }, id: 'erro');
    final diasOffline = com({
      'online_data': agora.subtract(const Duration(days: 5)).toIso8601String(),
    }, id: 'dias');
    final nunca = StatusSync(empresaId: 'nunca');
    final saudavel = com({
      'online_data': agora.toIso8601String(),
      'ultima_sincronizacao': agora.toIso8601String(),
    }, id: 'ok');

    final lista = [saudavel, nunca, diasOffline, comErro]
      ..sort((a, b) => a.compararCom(b, agora));

    expect(lista.map((e) => e.empresaId).toList(),
        ['erro', 'dias', 'nunca', 'ok']);
  });

  test('fromMap entende data como DateTime e ignora campos ausentes', () {
    final status = StatusSync.fromMap(empresaId, {
      'ultima_sincronizacao': agora,
      'fila_pendente': '7',
    });

    expect(status.ultimaSincronizacao, agora);
    expect(status.filaPendente, 7);
    expect(status.pcName, '');
    expect(status.ultimoErro, '');
    expect(status.temErroNaoResolvido, isFalse);
  });
}
