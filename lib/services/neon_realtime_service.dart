import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'neon_config.dart';
import 'neon_realtime_seal.dart';

/// Avisa que ALGO mudou em [tabela] na nuvem. Quem escuta decide o que fazer
/// (no desktop, puxar o delta para o banco local — que continua sendo o
/// principal — e recarregar as telas).
typedef OnMudancaNaNuvem = void Function(String tabela);

/// Push de mudanças da nuvem (Neon Realtime / Live SQL API).
///
/// COMO FUNCIONA
/// O serviço abre UM WebSocket no `NEON_REALTIME_URL` e assina, para cada
/// tabela crítica, uma consulta-miniatura: um agregado de UMA linha
/// (`count(*)` e `max(updated_at)`) filtrado pela empresa aberta. Qualquer
/// INSERT/DELETE muda a contagem e qualquer UPDATE muda o `max(updated_at)` —
/// então o serviço devolve um quadro e nós sabemos que aquela tabela mexeu.
///
/// Por que agregado e não as linhas: a assinatura manda o resultado
/// materializado INTEIRO na primeira carga. Assinar `produtos` inteiro
/// significaria baixar ~7 mil linhas só para depois receber um aviso. O
/// agregado é uma linha, e o conteúdo continua vindo pelo caminho de sempre
/// (Data API/`carregarTudoDoSupabase`).
///
/// DETALHES DO PROTOCOLO (conferidos contra o SDK oficial `@neon/realtime`,
/// o único publicado — não existe SDK Dart):
///   * o handshake EXIGE o subprotocolo `neon.realtime.v1`;
///   * o cliente só manda `subscribe` com um selo (ver [NeonRealtimeSelo]),
///     `renew`, `unsubscribe` e `pong`;
///   * o selo vence em 60 s → renovamos a cada [intervaloRenovacao];
///   * o serviço manda `ping` e espera `pong` com o mesmo token;
///   * `keyed_results` é o quadro de mudança (o `targets[].live_id` diz de
///     qual assinatura veio);
///   * `upstream_rejected` em uma tabela que não tem `updated_at`: refazemos
///     a assinatura dela só com `count(*)`.
///
/// É Dart puro (só depende de `web_socket_channel`), então o mesmo código roda
/// no Windows, no Android e na web. Na web o segredo NÃO é publicado (o pacote
/// do site passa por `tool/limpa_segredos_web.ps1`), então lá a lista sai
/// vazia e o serviço simplesmente não liga.
class NeonRealtimeService {
  static final NeonRealtimeService instance = NeonRealtimeService._();
  NeonRealtimeService._();

  /// Subprotocolo exigido pelo serviço (o handshake falha sem ele).
  static const String subprotocolo = 'neon.realtime.v1';

  /// O selo vale 60 s; renovamos antes de vencer.
  static const Duration intervaloRenovacao = Duration(seconds: 45);

  /// Espera antes de tentar reconectar (dobra até [esperaMaxima]).
  static const Duration esperaInicial = Duration(seconds: 2);
  static const Duration esperaMaxima = Duration(seconds: 30);

  /// Consulta-sinal com `updated_at` (pega INSERT, DELETE e UPDATE).
  static const String _sqlComTimestamp =
      'SELECT count(*) AS n, max(updated_at::text) AS d '
      'FROM public.%TABELA% WHERE empresa_id = \$1';

  /// Consulta-sinal só de contagem (tabelas sem `updated_at`: INSERT/DELETE).
  static const String _sqlSoContagem =
      'SELECT count(*) AS n FROM public.%TABELA% WHERE empresa_id = \$1';

  WebSocketChannel? _canal;
  StreamSubscription<dynamic>? _assinaturaCanal;
  Timer? _temporizadorRenovacao;
  Timer? _temporizadorReconexao;

  bool _ativo = false;
  bool _encerrando = false;
  int _tentativas = 0;
  int _proximoRequestId = 1;

  String? _empresaId;
  List<String> _tabelas = const <String>[];
  OnMudancaNaNuvem? _onMudanca;

  /// `live_id` -> nome da tabela (o que troca de `keyed_results`).
  final Map<String, String> _tabelaPorLiveId = <String, String>{};

  /// `request_id` -> tabela que ainda espera o `subscribed`/`subscribe_rejected`.
  final Map<String, String> _tabelaPorRequestId = <String, String>{};

  /// Tabelas que recusaram a consulta com `updated_at` (não têm a coluna).
  final Set<String> _tabelasSemTimestamp = <String>{};

  /// Última publicação já avisada (um lote de mudanças = um aviso por tabela).
  String? _ultimaPublicacaoAvisada;

  bool get ativo => _ativo;

  /// Quantas tabelas estão assinadas agora (diagnóstico/teste).
  int get assinaturasAtivas => _tabelaPorLiveId.length;

  /// Liga a escuta. É idempotente: chamar de novo troca empresa/callback e
  /// reconecta só se a empresa mudou.
  Future<void> iniciar(
    String empresaId, {
    required List<String> tabelas,
    required OnMudancaNaNuvem onMudanca,
  }) async {
    _onMudanca = onMudanca;
    _tabelas = List<String>.unmodifiable(tabelas);
    if (_ativo && _empresaId == empresaId) return;

    await parar();
    _encerrando = false;
    _empresaId = empresaId;

    if (!NeonConfig.realtimeDisponivel) {
      debugPrint(
        '>>> [Neon-Realtime] ⏸️ Sem NEON_REALTIME_URL/SECRET em '
        '${NeonConfig.nomeArquivo}: push da nuvem desligado (segue LAN + delta).',
      );
      return;
    }
    if (_tabelas.isEmpty) return;

    await _conectar();
  }

  /// Desliga a escuta e limpa o estado.
  Future<void> parar() async {
    _encerrando = true;
    _ativo = false;
    _temporizadorRenovacao?.cancel();
    _temporizadorRenovacao = null;
    _temporizadorReconexao?.cancel();
    _temporizadorReconexao = null;
    _tabelaPorLiveId.clear();
    _tabelaPorRequestId.clear();
    _ultimaPublicacaoAvisada = null;
    try {
      await _assinaturaCanal?.cancel();
    } catch (_) {}
    _assinaturaCanal = null;
    try {
      await _canal?.sink.close();
    } catch (_) {}
    _canal = null;
  }

  Future<void> _conectar() async {
    if (_encerrando || _empresaId == null) return;
    try {
      final canal = WebSocketChannel.connect(
        Uri.parse(NeonConfig.realtimeUrl),
        protocols: const <String>[subprotocolo],
      );
      _canal = canal;
      await canal.ready;

      _ativo = true;
      _tentativas = 0;
      debugPrint('>>> [Neon-Realtime] 🔌 Conectado (empresa $_empresaId).');

      _assinaturaCanal = canal.stream.listen(
        (quadro) => _aoReceber(quadro),
        onError: (Object e) {
          debugPrint('>>> [Neon-Realtime] ⚠️ Erro no socket: $e');
          _agendarReconexao();
        },
        onDone: () {
          debugPrint(
            '>>> [Neon-Realtime] 🔌 Socket fechado '
            '(código ${canal.closeCode}).',
          );
          _agendarReconexao();
        },
      );

      for (final tabela in _tabelas) {
        _assinar(tabela);
      }
      _temporizadorRenovacao?.cancel();
      _temporizadorRenovacao = Timer.periodic(
        intervaloRenovacao,
        (_) => _renovar(),
      );
    } catch (e) {
      debugPrint('>>> [Neon-Realtime] ⚠️ Falha ao conectar: $e');
      _agendarReconexao();
    }
  }

  String _sqlDaTabela(String tabela) {
    final modelo = _tabelasSemTimestamp.contains(tabela)
        ? _sqlSoContagem
        : _sqlComTimestamp;
    return modelo.replaceAll('%TABELA%', tabela);
  }

  void _assinar(String tabela) {
    final canal = _canal;
    final empresaId = _empresaId;
    if (canal == null || empresaId == null) return;
    final requestId = '${_proximoRequestId++}';
    _tabelaPorRequestId[requestId] = tabela;
    try {
      final selo = NeonRealtimeSelo.selar(
        sql: _sqlDaTabela(tabela),
        segredo: NeonConfig.realtimeSecret,
        parametros: <Map<String, Object?>>[
          NeonRealtimeSelo.parametroTexto(empresaId),
        ],
      );
      canal.sink.add(jsonEncode(<String, Object?>{
        'type': 'subscribe',
        'request_id': requestId,
        'authorization': selo.capability,
      }));
    } catch (e) {
      _tabelaPorRequestId.remove(requestId);
      debugPrint('>>> [Neon-Realtime] ⚠️ Não consegui assinar $tabela: $e');
    }
  }

  /// Refaz o selo das assinaturas vivas antes de vencerem.
  void _renovar() {
    final canal = _canal;
    final empresaId = _empresaId;
    if (canal == null || empresaId == null || _tabelaPorLiveId.isEmpty) return;
    final porTabela = Map<String, String>.fromEntries(
      _tabelaPorLiveId.entries.map((e) => MapEntry(e.value, e.key)),
    );
    for (final entrada in porTabela.entries) {
      try {
        final selo = NeonRealtimeSelo.selar(
          sql: _sqlDaTabela(entrada.key),
          segredo: NeonConfig.realtimeSecret,
          parametros: <Map<String, Object?>>[
            NeonRealtimeSelo.parametroTexto(empresaId),
          ],
        );
        canal.sink.add(jsonEncode(<String, Object?>{
          'type': 'renew',
          'live_id': entrada.value,
          'authorization': selo.capability,
        }));
      } catch (e) {
        debugPrint('>>> [Neon-Realtime] ⚠️ Falha ao renovar ${entrada.key}: $e');
      }
    }
    debugPrint(
      '>>> [Neon-Realtime] 🔁 ${porTabela.length} assinatura(s) renovada(s).',
    );
  }

  void _aoReceber(dynamic quadro) {
    final texto = quadro is String ? quadro : utf8.decode(quadro as List<int>);
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(texto) as Map<String, dynamic>;
    } catch (_) {
      return; // quadro que não é JSON: nada a fazer
    }

    switch (msg['type']?.toString()) {
      case 'ping':
        _canal?.sink.add(
          jsonEncode(<String, Object?>{'type': 'pong', 'token': msg['token']}),
        );
        break;
      case 'subscribed':
        final requestId = msg['request_id']?.toString();
        final liveId = msg['live_id']?.toString();
        final tabela = _tabelaPorRequestId.remove(requestId ?? '');
        if (tabela != null && liveId != null) {
          _tabelaPorLiveId[liveId] = tabela;
          debugPrint('>>> [Neon-Realtime] ✅ Assinado: $tabela (live $liveId).');
        }
        break;
      case 'subscribe_rejected':
        final requestId = msg['request_id']?.toString();
        final tabela = _tabelaPorRequestId.remove(requestId ?? '');
        final motivo = msg['code']?.toString() ?? '?';
        debugPrint('>>> [Neon-Realtime] ⚠️ Assinatura de $tabela recusada: '
            '$motivo ${msg['message'] ?? ''}');
        // Tabela sem `updated_at`: refaz só com a contagem.
        if (tabela != null &&
            _tabelasSemTimestamp.add(tabela) &&
            _sqlDaTabela(tabela) != _sqlComTimestamp.replaceAll('%TABELA%', tabela)) {
          _assinar(tabela);
        }
        break;
      // Mudança de verdade. O serviço manda `keyed_results` quando a consulta
      // devolve LINHAS e `reset_required` quando é um AGREGADO (aqui, todos
      // são): nos dois o `targets[].live_id` diz de qual tabela veio.
      case 'keyed_results':
      case 'reset_required':
        _avisarMudanca(msg);
        break;
      default:
        break; // ready/progress/baseline_sync_*/open/commit: nada a fazer
    }
  }

  void _avisarMudanca(Map<String, dynamic> msg) {
    final publicacao = msg['publication_id']?.toString();
    // Um lote pode trazer várias mudanças: avisamos uma vez por publicação.
    if (publicacao != null && publicacao == _ultimaPublicacaoAvisada) return;
    _ultimaPublicacaoAvisada = publicacao;

    final alvos = msg['targets'];
    final avisadas = <String>{};
    if (alvos is List) {
      for (final alvo in alvos) {
        if (alvo is! Map) continue;
        final liveId = alvo['live_id']?.toString();
        final tabela = liveId == null ? null : _tabelaPorLiveId[liveId];
        if (tabela == null || !avisadas.add(tabela)) continue;
        _onMudanca?.call(tabela);
      }
    }
  }

  void _agendarReconexao() {
    if (_encerrando) return;
    _ativo = false;
    _tabelaPorLiveId.clear();
    _tabelaPorRequestId.clear();
    _temporizadorRenovacao?.cancel();
    _temporizadorRenovacao = null;
    if (_temporizadorReconexao?.isActive ?? false) return;

    final espera = Duration(
      milliseconds: (esperaInicial.inMilliseconds *
              (1 << _tentativas.clamp(0, 4)))
          .clamp(esperaInicial.inMilliseconds, esperaMaxima.inMilliseconds),
    );
    _tentativas++;
    debugPrint(
      '>>> [Neon-Realtime] ⏳ Reconectando em ${espera.inSeconds}s '
      '(tentativa $_tentativas).',
    );
    _temporizadorReconexao = Timer(espera, () async {
      _temporizadorReconexao = null;
      await _limparCanal();
      unawaited(_conectar());
    });
  }

  Future<void> _limparCanal() async {
    try {
      await _assinaturaCanal?.cancel();
    } catch (_) {}
    _assinaturaCanal = null;
    try {
      await _canal?.sink.close();
    } catch (_) {}
    _canal = null;
  }
}
