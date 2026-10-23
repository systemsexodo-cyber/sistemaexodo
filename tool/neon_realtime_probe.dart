// Sonda do Neon Realtime: assina uma consulta ao vivo usando o MESMO código do
// app (`lib/services/neon_realtime_seal.dart`) e imprime cada quadro recebido.
//
// Serve para duas coisas:
//   1. provar que o selo Dart é aceito pelo serviço (nenhuma implementação de
//      protocolo é confiável sem isso);
//   2. ver a forma dos quadros (subscribe/subscribed/baseline/keyed_results)
//      para a integração com o app.
//
// Rode na raiz do projeto:
//
//   dart run tool/neon_realtime_probe.dart [segundos] ["SQL"] [--param valor]...
//
// Cada `--param` vira um `$n` declarado no selo (texto). Sai com 0 quando o
// serviço aceitou a assinatura.
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';

import 'package:sistema_exodo_novo/services/neon_config.dart';
import 'package:sistema_exodo_novo/services/neon_realtime_seal.dart';
import 'package:web_socket_channel/io.dart';

const String _sqlPadrao =
    "SELECT id, evento FROM public.sync_logs WHERE pc_name = 'teste-realtime'";

Future<void> main(List<String> args) async {
  final segundos = args.isNotEmpty ? int.tryParse(args[0]) ?? 40 : 40;

  // `--param` repetível: vira $1, $2… declarados dentro do selo.
  final parametros = <Map<String, Object?>>[];
  final restante = <String>[];
  for (var i = 1; i < args.length; i++) {
    if (args[i] == '--param' && i + 1 < args.length) {
      parametros.add(NeonRealtimeSelo.parametroTexto(args[++i]));
    } else {
      restante.add(args[i]);
    }
  }
  final sql = restante.isNotEmpty ? restante.join(' ') : _sqlPadrao;

  print('=' * 76);
  print('Neon Realtime — sonda da assinatura');
  print('credenciais : ${NeonConfig.nomeArquivo}');
  print('socket      : ${NeonConfig.realtimeUrl}');
  print('consulta    : $sql');
  print('parâmetros  : ${parametros.length}');
  print('=' * 76);

  if (!NeonConfig.realtimeDisponivel) {
    print('Faltam NEON_REALTIME_URL / NEON_REALTIME_SECRET no '
        '${NeonConfig.nomeArquivo}.');
    print('Rode: neon env pull --service realtime --file ${NeonConfig.nomeArquivo}');
    return;
  }

  final selo = NeonRealtimeSelo.selar(
    sql: sql,
    segredo: NeonConfig.realtimeSecret,
    parametros: parametros,
  );
  print('selo emitido: $selo');

  final recebidos = StreamController<String>();
  final canal = IOWebSocketChannel.connect(
    Uri.parse(NeonConfig.realtimeUrl),
    // O serviço RECUSA o handshake sem este subprotocolo: é o nome do
    // protocolo que o SDK oficial pede (`neon.realtime.v1`).
    protocols: const ['neon.realtime.v1'],
    pingInterval: const Duration(seconds: 20),
  );
  await canal.ready;

  var assinou = false;
  var encerrado = false;

  final assinatura = canal.stream.listen(
    (quadro) {
      final texto = quadro is String ? quadro : utf8.decode(quadro as List<int>);
      print('[<] ${texto.length > 300 ? '${texto.substring(0, 300)}…' : texto}');
      try {
        final msg = jsonDecode(texto) as Map<String, dynamic>;
        final tipo = msg['type']?.toString() ?? '?';
        if (tipo == 'subscribed') {
          assinou = true;
          recebidos.add('subscribed:live_id=${msg['live_id']}');
        } else if (tipo == 'subscribe_rejected') {
          recebidos.add(
            'rejeitado:${msg['code']}${msg['message'] == null ? '' : ' — ${msg['message']}'}',
          );
        }
        // Batimento: o serviço manda `ping` e espera o `pong` de volta.
        if (tipo == 'ping') {
          canal.sink.add(jsonEncode({'type': 'pong', 'token': msg['token']}));
          print('[>] {"type":"pong"}');
        }
      } catch (e) {
        print('    (quadro não é JSON: $e)');
      }
    },
    onError: (Object e) {
      print('[!] erro no socket: $e');
      if (!encerrado) recebidos.add('erro:$e');
    },
    onDone: () {
      print('[!] socket fechado (código ${canal.closeCode})');
      if (!encerrado) recebidos.add('fechado:${canal.closeCode}');
    },
  );

  print('[>] {"type":"subscribe", ...}');
  canal.sink.add(jsonEncode({
    'type': 'subscribe',
    'request_id': '1',
    'authorization': selo.capability,
  }));

  // Espera o veredito (aceito/rejeitado) antes do período de observação.
  final veredito = await recebidos.stream.first.timeout(
    const Duration(seconds: 20),
    onTimeout: () => 'sem resposta em 20s',
  );
  print('-' * 76);
  print('veredito: $veredito');

  if (assinou) {
    print('Observando mudanças por $segundos s — faça um INSERT/UPDATE/DELETE '
        'na tabela para ver os quadros:');
  }

  await Future<void>.delayed(Duration(seconds: segundos));
  encerrado = true;
  await assinatura.cancel();
  await canal.sink.close();
  await recebidos.close();
  print('=' * 76);
  print(assinou ? 'OK: assinatura aceita.' : 'FALHOU: assinatura não aceita.');
}
