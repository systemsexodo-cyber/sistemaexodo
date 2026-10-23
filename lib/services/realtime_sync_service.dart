import 'dart:async';

import 'package:flutter/foundation.dart';
import 'neon_config.dart';
import 'neon_realtime_service.dart';
import 'supabase_service.dart';

/// Callback chamado quando o DataService precisa ser atualizado com novos dados
typedef OnRealtimeData =
    void Function(String tabela, String evento, Map<String, dynamic> payload);

/// Sincronização em tempo real (multi-PC).
///
/// ANTES (Supabase): um WebSocket (`Supabase Realtime`) avisava esta máquina
/// quando outra gravava um registro, em < 100 ms.
///
/// AGORA (Neon): o push é feito pelo Neon Realtime (Live SQL API), por um
/// cliente Dart próprio — ver [NeonRealtimeService]. Ele assina um agregado de
/// UMA linha por tabela crítica e, quando a nuvem avisa que aquela tabela
/// mudou, o [DataService] puxa o delta na hora (em vez de esperar o timer de
/// 45 s). O banco local continua sendo o principal: o aviso só ANTECIPA a
/// sincronização que já existia.
///
/// As três camadas convivem:
///   * **nuvem em tempo real** ([NeonRealtimeService]) — máquinas em redes
///     diferentes veem a mudança em ~1 s;
///   * **LAN em tempo real** ([LanRealtimeService]) — o sincronizador da rede
///     local grava no Postgres deste PC e avisa por `pg_notify`; é o caminho
///     que sustenta a loja sem internet;
///   * **sincronização periódica** do [DataService] (timer) + [sincronizarDelta]
///     e a fila de envio ([SyncQueueService]) — a rede de segurança.
class RealtimeSyncService {
  static final RealtimeSyncService instance = RealtimeSyncService._();
  RealtimeSyncService._();

  String? _empresaIdAtual;
  bool _ativo = false;
  DateTime? _lastSyncAt;

  /// Callback para notificar o DataService sobre mudanças
  OnRealtimeData? onRealtimeData;

  /// Callback para notificar sobre início/fim de processamento em lote (suspensão da UI)
  void Function(bool active)? onBatchStatus;

  // Tabelas críticas que recebem tempo real.
  //
  // O aviso da nuvem agora puxa SÓ a tabela que mudou
  // (`DataService._recarregarPelaNuvem`), então incluir mais telas aqui custa
  // uma consulta pequena por evento — antes cada inclusão custava o ciclo
  // completo das 30 tabelas. Ficaram de fora `servicos_realizados` e
  // `orcamentos`, por exemplo, e por isso essas telas só atualizavam no pulso.
  // Todas têm `updated_at` no schema (`scripts/init_db.sql`).
  static const List<String> _tabelasCriticas = [
    'mesas_comandas',
    'vendas_balcao',
    'pedidos',
    'produtos',
    'aberturas_caixa',
    'fechamentos_caixa',
    'agendamentos_servico',
    'contas_pagar',
    'clientes',
    'funcionarios',
    'notas_entrada',
    'pedidos_compra',
    'ordens_servico',
    'taxas_entrega',
    'romaneios',
    'servicos_realizados',
    'orcamentos',
    'sangrias_caixa',
    'suprimentos_caixa',
    'entregas',
    'nfces',
  ];

  /// Avisa que uma tabela mudou na nuvem (ver [NeonRealtimeService]).
  OnMudancaNaNuvem? aoMudarNaNuvem;

  bool get ativo => _ativo;
  DateTime? get lastSyncAt => _lastSyncAt;

  /// Liga o push da nuvem (Neon Realtime) e guarda o callback.
  ///
  /// [callback] continua sendo o caminho de payload (compatibilidade com o que
  /// o Supabase entregava); [aoMudarNaNuvem] é o caminho novo, que recebe só o
  /// NOME da tabela que mudou — é o que o [DataService] usa para puxar o delta.
  Future<void> iniciar(
    String empresaId, {
    required OnRealtimeData callback,
    OnMudancaNaNuvem? aoMudarNaNuvem,
  }) async {
    onRealtimeData = callback;
    this.aoMudarNaNuvem = aoMudarNaNuvem;
    // Repetir a chamada para a MESMA empresa não precisa reabrir o socket: o
    // serviço da nuvem já está assinando as tabelas dela.
    final mesmaEmpresaEJaAtivo =
        _empresaIdAtual == empresaId && NeonRealtimeService.instance.ativo;
    _empresaIdAtual = empresaId;
    _lastSyncAt = DateTime.now();
    if (mesmaEmpresaEJaAtivo) {
      _ativo = true;
      return;
    }

    if (!NeonConfig.realtimeDisponivel) {
      _ativo = false;
      debugPrint(
        '>>> [Realtime] ⏸️ Push da nuvem desligado: falta '
        'NEON_REALTIME_URL/SECRET em ${NeonConfig.nomeArquivo}. Multi-PC segue '
        'por LAN + sincronização periódica.',
      );
      return;
    }

    final avisar = this.aoMudarNaNuvem;
    if (avisar == null) {
      _ativo = false;
      return;
    }

    _ativo = true;
    debugPrint(
      '>>> [Realtime] 🔔 Push da nuvem ligado (Neon Realtime) para '
      '${_tabelasCriticas.length} tabela(s) críticas.',
    );
    await NeonRealtimeService.instance.iniciar(
      empresaId,
      tabelas: _tabelasCriticas,
      onMudanca: avisar,
    );
  }

  /// Aguarda confirmação de que um evento foi divulgado pela nuvem.
  ///
  /// Sem push, não há o que aguardar: retorna `false` imediatamente (antes,
  /// esperava até 2 s pelo eco do WebSocket). Os chamadores já tratam este
  /// `false` como "não confirmado" e seguem.
  Future<bool> aguardarConfirmacao(
    String tabela,
    String id, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    return false;
  }

  /// Para a escuta em tempo real.
  Future<void> parar() async {
    _ativo = false;
    _empresaIdAtual = null;
    await NeonRealtimeService.instance.parar();
    debugPrint('>>> [Realtime] ⏹️ Escuta encerrada.');
  }

  /// Sincronização delta: busca na nuvem o que mudou desde o último sync.
  ///
  /// Esta parte NÃO dependia do Realtime (são consultas PostgREST) e continua
  /// funcionando — é justamente o substituto do push para o PC que volta a
  /// ficar online.
  Future<Map<String, List<Map<String, dynamic>>>> sincronizarDelta(
    String empresaId,
  ) async {
    if (!SupabaseService.isAvailable) return {};

    final desde =
        _lastSyncAt ?? DateTime.now().subtract(const Duration(hours: 1));
    final desdeIso = desde.toIso8601String();

    debugPrint('>>> [Realtime] 🔄 Sincronizando delta desde $desdeIso...');

    final Map<String, List<Map<String, dynamic>>> resultado = {};

    for (final tabela in _tabelasCriticas) {
      try {
        final dados = await SupabaseService.instance.client
            .from(tabela)
            .select()
            .eq('empresa_id', empresaId)
            .gte('updated_at', desdeIso)
            .limit(200);

        if (dados.isNotEmpty) {
          resultado[tabela] = List<Map<String, dynamic>>.from(dados);
          debugPrint(
            '>>> [Realtime] ✅ Delta $tabela: ${dados.length} registros',
          );
        }
      } catch (e) {
        debugPrint('>>> [Realtime] ⚠️ Erro ao buscar delta de $tabela: $e');
      }
    }

    _lastSyncAt = DateTime.now();
    return resultado;
  }

  /// Atualiza o campo `updated_at` de uma tabela ao salvar.
  ///
  /// Continua necessário: é o que permite a [sincronizarDelta] (e os deltas do
  /// catálogo) enxergarem o registro alterado.
  static Map<String, dynamic> marcarAtualizado(Map<String, dynamic> dados) {
    return {...dados, 'updated_at': DateTime.now().toIso8601String()};
  }
}
