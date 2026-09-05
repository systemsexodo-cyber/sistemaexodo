import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import '../services/database_service.dart';

/// Callback chamado quando o DataService precisa ser atualizado com novos dados
typedef OnRealtimeData = void Function(String tabela, String evento, Map<String, dynamic> payload);

/// Serviço de Sincronização em Tempo Real (Multi-PC)
///
/// Arquitetura:
///   Supabase Realtime (WebSocket) → PostgreSQL local → DataService (memória) → UI
///
/// Quando PC-A salva uma venda, PC-B recebe via WebSocket em < 100ms e
/// atualiza o PostgreSQL e a UI automaticamente.
class RealtimeSyncService {
  static final RealtimeSyncService instance = RealtimeSyncService._();
  RealtimeSyncService._();

  static SupabaseClient get _client => Supabase.instance.client;

  RealtimeChannel? _channel;
  String? _empresaIdAtual;
  bool _ativo = false;
  DateTime? _lastSyncAt;

  /// Callback para notificar o DataService sobre mudanças
  OnRealtimeData? onRealtimeData;

  /// Callback para notificar sobre início/fim de processamento em lote (suspenção da UI)
  void Function(bool active)? onBatchStatus;

  /// Referência ao DatabaseService para atualizar o PostgreSQL local
  final DatabaseService _dbService = DatabaseService();

  // Tabelas críticas que recebem tempo real
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
    'ordens_servico',
    'taxas_entrega',
    'romaneios',
  ];

  // Buffer de atualizações agrupadas por tabela para evitar I/O lock
  final Map<String, Map<String, _BufferedUpdate>> _bufferTabelas = {};
  // Timers para debounce/flush de cada tabela
  final Map<String, Timer> _timersTabelas = {};

  bool get ativo => _ativo;
  DateTime? get lastSyncAt => _lastSyncAt;

  /// Inicia a escuta de mudanças em tempo real para uma empresa
  Future<void> iniciar(String empresaId, {required OnRealtimeData callback}) async {
    if (!SupabaseService.isAvailable) {
      debugPrint('>>> [Realtime] ⚠️ Supabase não disponível. Pulando Realtime.');
      return;
    }

    if (_ativo && _empresaIdAtual == empresaId) {
      debugPrint('>>> [Realtime] ℹ️ Já ativo para empresa $empresaId. Ignorando.');
      return;
    }

    // Para qualquer escuta anterior antes de iniciar nova
    await parar();

    _empresaIdAtual = empresaId;
    onRealtimeData = callback;
    _lastSyncAt = DateTime.now();

    debugPrint('>>> [Realtime] 🚀 Iniciando escuta em tempo real para empresa $empresaId...');

    try {
      _channel = _client.channel(
        'empresa-$empresaId',
        opts: const RealtimeChannelConfig(ack: false),
      );

      // Registrar escuta para cada tabela crítica
      for (final tabela in _tabelasCriticas) {
        _channel!
            .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: tabela,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'empresa_id',
            value: empresaId,
          ),
          callback: (payload) => _processarMudanca(tabela, 'INSERT', payload),
        )
            .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: tabela,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'empresa_id',
            value: empresaId,
          ),
          callback: (payload) => _processarMudanca(tabela, 'UPDATE', payload),
        )
            .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: tabela,
          callback: (payload) => _processarMudanca(tabela, 'DELETE', payload),
        );
      }

      // Escuchar mudanças no status do bridge (para gerenciamento NFC-e)
      _channel!.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'bridge_status',
        callback: (payload) => _processarMudanca('bridge_status', payload.eventType.name, payload),
      );

      // Assinar o canal
      _channel!.subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          _ativo = true;
          debugPrint('>>> [Realtime] ✅ Canal ativo! Escutando ${_tabelasCriticas.length} tabelas.');
        } else if (status == RealtimeSubscribeStatus.closed) {
          _ativo = false;
          debugPrint('>>> [Realtime] 🔴 Canal fechado. Tentando reconectar...');
          _agendarReconexao(empresaId);
        } else if (status == RealtimeSubscribeStatus.channelError) {
          _ativo = false;
          debugPrint('>>> [Realtime] ❌ Erro no canal: $error');
        }
      });
    } catch (e) {
      debugPrint('>>> [Realtime] ❌ Erro ao iniciar: $e');
    }
  }

  /// Processa uma mudança recebida do Supabase Realtime
  void _processarMudanca(String tabela, String evento, dynamic payload) {
    try {
      final Map<String, dynamic> dados = {};

      if (payload is PostgresChangePayload) {
        if (evento == 'DELETE') {
          dados.addAll(payload.oldRecord);
        } else {
          dados.addAll(payload.newRecord);
        }
      } else if (payload is Map) {
        dados.addAll(Map<String, dynamic>.from(payload));
      }

      final id = dados['id'] as String?;
      if (id == null) return;

      // Adicionar alteração ao buffer agrupado para evitar I/O excessivo
      _bufferTabelas.putIfAbsent(tabela, () => {})[id] = _BufferedUpdate(evento, dados);

      // Agendar descarregamento rápido do lote (debounce/throttle)
      _agendarFlush(tabela);

      _lastSyncAt = DateTime.now();
    } catch (e) {
      debugPrint('>>> [Realtime] ❌ Erro ao processar mudança em $tabela: $e');
    }
  }

  void _agendarFlush(String tabela) {
    final tamanhoBuffer = _bufferTabelas[tabela]?.length ?? 0;
    
    // Se acumular mais de 100 itens para a tabela, descarrega imediatamente para não estourar memória
    if (tamanhoBuffer >= 100) {
      _timersTabelas[tabela]?.cancel();
      _timersTabelas.remove(tabela);
      _flushTabela(tabela);
      return;
    }

    // Aguarda 300ms de silêncio para descarregar de uma vez só
    _timersTabelas[tabela]?.cancel();
    _timersTabelas[tabela] = Timer(const Duration(milliseconds: 300), () {
      _timersTabelas.remove(tabela);
      _flushTabela(tabela);
    });
  }

  Future<void> _flushTabela(String tabela) async {
    final buffer = _bufferTabelas.remove(tabela);
    if (buffer == null || buffer.isEmpty) return;

    final updates = <Map<String, dynamic>>[];
    final deletes = <String>[];

    for (final update in buffer.values) {
      if (update.evento == 'DELETE') {
        final id = update.dados['id'] as String?;
        if (id != null) deletes.add(id);
      } else {
        updates.add(update.dados);
      }
    }

    final chave = _mapearTabelaParaChave(tabela);
    if (chave == null) return;

    debugPrint('>>> [Realtime] ⚡ Lote processado em $tabela: ${updates.length} salvamentos, ${deletes.length} deleções');

    // 1. Processar deleções acumuladas
    for (final id in deletes) {
      try {
        await _dbService.removerItemPostgres(chave, id, _empresaIdAtual, isSync: true);
      } catch (e) {
        debugPrint('>>> [Realtime] ⚠️ Erro ao remover $id de $tabela no lote: $e');
      }
    }

    // 2. Processar salvamentos acumulados de uma única vez (Economiza 99% das conexões/transações!)
    if (updates.isNotEmpty) {
      try {
        await _dbService.salvarLista(chave, updates, isSync: true);
      } catch (e) {
        if (e.toString().contains('locked')) {
          debugPrint('>>> [Realtime] ⏭️ Banco de Dados ocupado ao descarregar lote de $tabela, sync de segurança resolverá.');
        } else {
          debugPrint('>>> [Realtime] ⚠️ Erro ao salvar lote de $tabela no Banco de Dados: $e');
        }
      }
    }

    // 3. Notificar a UI em lote (na thread principal, extremamente rápido em memória)
    onBatchStatus?.call(true);
    try {
      for (final update in buffer.values) {
        try {
          onRealtimeData?.call(tabela, update.evento, update.dados);
        } catch (e) {
          debugPrint('>>> [Realtime] ⚠️ Erro ao notificar UI em lote para $tabela: $e');
        }
      }
    } finally {
      onBatchStatus?.call(false);
    }
  }

  /// Mapeia nome da tabela Supabase para a chave usada no DatabaseService
  String? _mapearTabelaParaChave(String tabela) {
    const mapa = {
      'produtos': 'produtos',
      'clientes': 'clientes',
      'pedidos': 'pedidos',
      'vendas_balcao': 'vendas_balcao',
      'mesas_comandas': 'mesas_comandas',
      'agendamentos_servico': 'agendamentos',
      'funcionarios': 'funcionarios',
      'notas_entrada': 'notas_entrada',
      'ordens_servico': 'ordens_servico',
      'taxas_entrega': 'taxas_entrega',
      'romaneios': 'romaneios',
      'contas_pagar': 'contas_pagar',
    };
    return mapa[tabela];
  }

  String? _mapearChaveParaTabela(String? chave) {
    if (chave == null) return null;
    const mapa = {
      'produtos': 'produtos_local',
      'clientes': 'clientes_local',
      'pedidos': 'pedidos_local',
      'vendas_balcao': 'vendas_local',
      'mesas_comandas': 'mesas_local',
      'agendamentos': 'agendamentos_local',
      'funcionarios': 'funcionarios_local',
      'notas_entrada': 'notas_entrada_local',
      'ordens_servico': 'ordens_servico_local',
      'taxas_entrega': 'taxas_entrega_local',
      'romaneios': 'romaneios_local',
      'contas_pagar': 'contas_pagar_local',
      'servicos': 'servicos_local',
    };
    return mapa[chave];
  }

  /// Agenda reconexão automática com backoff exponencial
  int _reconexoesConsecutivas = 0;
  void _agendarReconexao(String empresaId) {
    _reconexoesConsecutivas++;
    final delayMs = (1000 * (1 << _reconexoesConsecutivas.clamp(0, 5))); // 2s, 4s, 8s, 16s, max 32s

    debugPrint('>>> [Realtime] ⏳ Reconectando em ${delayMs ~/ 1000}s...');

    Future.delayed(Duration(milliseconds: delayMs), () {
      if (onRealtimeData != null && _empresaIdAtual == empresaId) {
        iniciar(empresaId, callback: onRealtimeData!);
      }
    });
  }

  /// Para a escuta em tempo real
  Future<void> parar() async {
    for (final timer in _timersTabelas.values) {
      timer.cancel();
    }
    _timersTabelas.clear();
    _bufferTabelas.clear();

    if (_channel != null) {
      await _client.removeChannel(_channel!);
      _channel = null;
    }
    _ativo = false;
    _empresaIdAtual = null;
    _reconexoesConsecutivas = 0;
    debugPrint('>>> [Realtime] ⏹️ Escuta encerrada.');
  }

  /// Sincronização delta: busca o que mudou desde o último sync
  /// Ideal para quando o PC volta a ficar online após período offline
  Future<Map<String, List<Map<String, dynamic>>>> sincronizarDelta(String empresaId) async {
    if (!SupabaseService.isAvailable) return {};

    final desde = _lastSyncAt ?? DateTime.now().subtract(const Duration(hours: 1));
    final desdeIso = desde.toIso8601String();

    debugPrint('>>> [Realtime] 🔄 Sincronizando delta desde $desdeIso...');

    final Map<String, List<Map<String, dynamic>>> resultado = {};

    for (final tabela in _tabelasCriticas) {
      try {
        final dados = await _client
            .from(tabela)
            .select()
            .eq('empresa_id', empresaId)
            .gte('updated_at', desdeIso)
            .limit(200);

        if (dados.isNotEmpty) {
          resultado[tabela] = List<Map<String, dynamic>>.from(dados);
          debugPrint('>>> [Realtime] ✅ Delta $tabela: ${dados.length} registros');
        }
      } catch (e) {
        debugPrint('>>> [Realtime] ⚠️ Erro ao buscar delta de $tabela: $e');
      }
    }

    _lastSyncAt = DateTime.now();
    return resultado;
  }

  /// Atualiza o campo `updated_at` de uma tabela ao salvar para garantir que
  /// outros PCs recebam o evento via Realtime
  static Map<String, dynamic> marcarAtualizado(Map<String, dynamic> dados) {
    return {
      ...dados,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }
}

class _BufferedUpdate {
  final String evento;
  final Map<String, dynamic> dados;
  _BufferedUpdate(this.evento, this.dados);
}
