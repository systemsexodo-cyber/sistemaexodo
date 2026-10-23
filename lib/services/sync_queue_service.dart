import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'database_service.dart';
import 'local_storage_service.dart';
import 'sync_monitor_service.dart';
import 'supabase_service.dart';

/// Serviço para gerenciar fila de sincronização pendente
/// Armazena operações que falharam e tenta novamente quando a conexão voltar
/// Desktop: Persiste no PostgreSQL e espelha em arquivo para contingência
/// Web: Persiste em memória (sem SharedPreferences)
class SyncQueueService {
  final List<SyncOperation> _queue = [];
  final LocalStorageService _emergencyStorage = LocalStorageService();
  bool _isProcessing = false;
  bool _paused;
  final bool _persistQueue;
  Timer? _retryTimer;
  Timer? _periodicRetryTimer;
  bool _hasConnection = true;
  bool Function(String? empresaId)? _operationGate;
  
  // Constantes de limite
  static const int _maxRetryCount = 10;
  static const int _maxQueueSize = 500;
  static const Duration _baseBackoffDelay = Duration(seconds: 5);

  /// Falhas PERMANENTES: a operação nunca vai passar, então descartá-la evita
  /// um retry infinito. Só entram aqui códigos de ESQUEMA/PERMISSÃO — antes a
  /// lista era tão ampla que engolia 'column', 'constraint', 'foreign key' e
  /// 'is not a subtype', descartando operações que só precisavam de mais tempo
  /// (ex.: um fechamento que depende da abertura ainda não sincronizada).
  static const List<String> _padroesIrrecuperaveis = [
    'pgrst204', // coluna não existe no schema cache da nuvem
    'pgrst205', // tabela não existe no schema cache da nuvem
    '42703', // undefined_column
    '42804', // datatype_mismatch (valor incompatível com a coluna)
    '42883', // undefined_function
    '42p01', // undefined_table
    '42501', // insufficient_privilege (RLS)
    'permission denied',
    'violates row-level security',
  ];
  
  // Função para resolver operações vindas do banco de dados
  Future<void> Function(String type, String dataId, Map<String, dynamic> data)? _operationResolver;

  SyncQueueService({
    Future<void> Function(String, String, Map<String, dynamic>)? resolver,
    bool initiallyPaused = false,
    @visibleForTesting bool persistQueue = true,
  }) : _paused = initiallyPaused,
       _persistQueue = persistQueue {
    _operationResolver = resolver;
    
    // Iniciar monitoramento de sync
    SyncMonitorService.instance.initialize();
    
    // Carregar operações pendentes do PostgreSQL (Fila persistida)
    _carregarFilaDoBanco();
    
    // Iniciar timer periódico para tentar sincronizar pendências a cada 5 minutos
    _periodicRetryTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_queue.isNotEmpty && _hasConnection && !_isProcessing && !_paused) {
        debugPrint('>>> [SyncQueue] 🔄 Tentativa periódica de sincronização (${_queue.length} pendentes)');
        _processQueue();
      }
    });
  }

  /// Pausa o envio sem remover nem consumir operações pendentes.
  void setPaused(bool paused) {
    if (_paused == paused) return;
    _paused = paused;
    if (paused) {
      _retryTimer?.cancel();
      _retryTimer = null;
      return;
    }
    if (_hasConnection && !_isProcessing && _queue.isNotEmpty) {
      _processQueue();
    }
  }

  /// Limita o processamento à empresa atualmente autorizada pelo app.
  void setOperationGate(bool Function(String? empresaId) gate) {
    _operationGate = gate;
    if (!_paused && _hasConnection && !_isProcessing && _hasReadyOperation) {
      _processQueue();
    }
  }

  bool get _hasReadyOperation {
    final agora = DateTime.now();
    return _queue.any((operation) {
      final empresaPermitida =
          _operationGate?.call(operation.empresaId) ?? true;
      final backoffEncerrado =
          operation.nextAttemptAt?.isAfter(agora) != true;
      return empresaPermitida && backoffEncerrado;
    });
  }

  /// Adiciona uma operação à fila de sincronização
  void enqueue(SyncOperation operation) {
    // Evitar duplicatas
    final existingIndex = _queue.indexWhere((op) => 
      op.type == operation.type && 
      op.dataId == operation.dataId
    );
    
    if (existingIndex >= 0) {
      // Atualizar operação existente
      _queue[existingIndex] = operation;
    } else {
      _queue.add(operation);
    }
    
    // Verificar limite maximo da fila para evitar estouro de memoria
    if (_queue.length > _maxQueueSize) {
      final removidas = _queue.length - _maxQueueSize;
      final descartadas = _queue.sublist(0, removidas);
      _queue.removeRange(0, removidas);
      debugPrint('>>> [SyncQueue] ⚠ Fila cheia: removidas $removidas operacoes antigas (limite: $_maxQueueSize)');
      // Nada é descartado em silêncio: o que saiu da fila vai para a DLQ.
      for (final op in descartadas) {
        unawaited(_enviarParaDlq(op, 'fila excedeu o limite de $_maxQueueSize'));
      }
    }
    
    // Persistir no PostgreSQL
    _persistirFila();
    
    debugPrint('>>> [SyncQueue] Operação adicionada à fila e persistida: ${operation.type} (${_queue.length} pendentes)');
    
    // Tentar processar se tiver conexão
    if (_hasConnection && !_isProcessing && !_paused) {
      _processQueue();
    }
  }

  /// Define o resolver para operações carregadas do banco
  void setResolver(Future<void> Function(String, String, Map<String, dynamic>) resolver) {
    _operationResolver = resolver;
    if (_queue.isNotEmpty && _hasConnection && !_isProcessing && !_paused) {
      _processQueue();
    }
  }

  /// Salva a fila atual no PostgreSQL (via DatabaseService)
  Future<void> _persistirFila() async {
    if (kIsWeb || !_persistQueue) {
      return; // Web e filas de teste não persistem.
    }
    final listMap = _queue
        .map(
          (op) => {
            'id': op.id,
            'empresa_id': op.empresaId,
            'tipo': op.type,
            'data_id': op.dataId,
            'data_json': jsonEncode(op.data),
            'retry_count': op.retryCount,
            'proximo_em': op.nextAttemptAt?.millisecondsSinceEpoch,
          },
        )
        .toList();
    try {
      await DatabaseService().salvarConfig(
        'exodo_sync_queue',
        listMap,
        lancarSeFalhar: true,
      );
      await _emergencyStorage.salvarCacheEmergencia(
        'exodo_sync_queue',
        listMap,
      );
    } catch (e) {
      try {
        await _emergencyStorage.salvarCacheEmergencia(
          'exodo_sync_queue',
          listMap,
          pendente: true,
        );
        debugPrint('>>> [SyncQueue] ⚠️ PostgreSQL indisponível; fila preservada em arquivo local.');
      } catch (erroCache) {
        debugPrint('>>> [SyncQueue] ❌ Erro ao persistir fila no PostgreSQL e no arquivo local: $e; $erroCache');
      }
    }
  }

  /// FILA MORTA (DLQ): operação que a fila parou de tentar fica registrada
  /// aqui em vez de sumir em silêncio.
  ///
  /// Os DADOS continuam salvos localmente (a DLQ só documenta o que a nuvem não
  /// recebeu), então ela serve para o suporte enxergar a divergência
  /// local×nuvem e reenviar manualmente — antes, um erro de esquema, 10
  /// tentativas falhando ou uma fila cheia descartavam a mutação sem nenhum
  /// registro durável.
  static const String _chaveDlq = 'exodo_sync_dlq';
  static const int _maxItensDlq = 200;

  Future<void> _enviarParaDlq(SyncOperation operation, String motivo) async {
    debugPrint(
      '>>> [SyncQueue] 📥 ${operation.type} (${operation.dataId}) → DLQ: $motivo',
    );
    if (kIsWeb || !_persistQueue) return;
    try {
      final bruto = await DatabaseService().carregarConfig(_chaveDlq);
      final lista =
          <Map<String, dynamic>>[
            if (bruto is List)
              for (final e in bruto) Map<String, dynamic>.from(e as Map),
          ];
      lista.add({
        'id': operation.id,
        'empresa_id': operation.empresaId,
        'tipo': operation.type,
        'data_id': operation.dataId,
        'data_json': jsonEncode(operation.data),
        'retry_count': operation.retryCount,
        'descartada_em': DateTime.now().toIso8601String(),
        'motivo': motivo,
      });
      // Teto: a DLQ é diagnóstico, não um segundo backup.
      final excedente = lista.length - _maxItensDlq;
      if (excedente > 0) lista.removeRange(0, excedente);
      await DatabaseService().salvarConfig(_chaveDlq, lista);
    } catch (e) {
      debugPrint('>>> [SyncQueue] ⚠️ Não foi possível registrar a DLQ: $e');
    }
  }

  /// Operações que a fila desistiu de enviar (diagnóstico/reenvio manual).
  Future<List<Map<String, dynamic>>> carregarDlq() async {
    if (kIsWeb || !_persistQueue) return [];
    try {
      final bruto = await DatabaseService().carregarConfig(_chaveDlq);
      if (bruto is! List) return [];
      return [
        for (final e in bruto) Map<String, dynamic>.from(e as Map),
      ];
    } catch (_) {
      return [];
    }
  }

  /// Carrega as operações pendentes do PostgreSQL ao iniciar o app
  Future<void> _carregarFilaDoBanco() async {
    if (kIsWeb || !_persistQueue) return;
    try {
      final emergencyCache = await _emergencyStorage.carregarCacheEmergencia(
        'exodo_sync_queue',
      );
      dynamic valor;
      try {
        valor = await DatabaseService().carregarConfig(
          'exodo_sync_queue',
          lancarSeFalhar: true,
        );
      } catch (_) {
        valor = null;
      }

      if (emergencyCache?['pendente'] == true &&
          emergencyCache?['valor'] is List) {
        // Emergency snapshot is newer than the last PostgreSQL write.
        valor = emergencyCache!['valor'];
        try {
          await DatabaseService().salvarConfig(
            'exodo_sync_queue',
            valor,
            lancarSeFalhar: true,
          );
          await _emergencyStorage.salvarCacheEmergencia(
            'exodo_sync_queue',
            valor,
          );
        } catch (e) {
          debugPrint('>>> [SyncQueue] ℹ️ Fila mantida no cache de emergência: $e');
        }
      } else if (valor == null) {
        valor = emergencyCache?['valor'];
      }
      if (valor == null) return;
      
      final decoded = valor as List;
      if (decoded.isEmpty) return;
      
      debugPrint('>>> [SyncQueue] 📦 Restaurando ${decoded.length} operações pendentes do PostgreSQL...');
      
      for (var item in decoded) {
        final map = item as Map<String, dynamic>;
        final id = map['id'] as String;
        final type = map['tipo'] as String;
        final dataId = map['data_id'] as String? ?? id;
        final data = jsonDecode(map['data_json'] as String) as Map<String, dynamic>;
        
        final op = SyncOperation(
          id: id,
          type: type,
          dataId: dataId,
          data: data,
          empresaId: map['empresa_id'] as String?,
          execute: () async {
            if (_operationResolver != null) {
              await _operationResolver!(type, dataId, data);
            } else {
              throw Exception('Nenhum resolver configurado para restaurar operação');
            }
          },
        );
        op.retryCount = map['retry_count'] as int;
        final proximoEm = map['proximo_em'] as int?;
        if (proximoEm != null) {
          op.nextAttemptAt = DateTime.fromMillisecondsSinceEpoch(proximoEm);
        }
        
        _queue.add(op);
      }
      
      if (_hasConnection && !_isProcessing) {
        _processQueue();
      }
    } catch (e) {
      debugPrint('>>> [SyncQueue] ❌ Erro ao carregar fila persistida: $e');
    }
  }

  /// Processa a fila de sincronização
  Future<void> _processQueue() async {
    if (_isProcessing || _queue.isEmpty || !_hasConnection || _paused) {
      return;
    }

    _isProcessing = true;
    debugPrint('>>> [SyncQueue] Iniciando processamento da fila (${_queue.length} operações)');

    // Operações que voltam para a fila: em backoff (ainda não vencidas) ou que
    // acabaram de falhar e foram reagendadas. O retry agora é AGENDADO por
    // timer (nextAttemptAt), não por `await Future.delayed` — então uma operação
    // esperando backoff não segura mais o processamento das demais.
    final List<SyncOperation> reagendar = [];

    while (_queue.isNotEmpty && _hasConnection && !_paused) {
      // Nuvem marcada indisponível (PGRST002/503/504): pausa a fila SEM consumir
      // tentativas e sem descartar nada. Ela retoma quando a conexão voltar.
      if (SupabaseService.instance.servidorIndisponivel) {
        debugPrint('>>> [SyncQueue] ⏸️ Nuvem indisponível — pausando fila '
            '(${_queue.length} pendentes, nada descartado).');
        break;
      }

      final eligibleIndex = _operationGate == null
          ? 0
          : _queue.indexWhere((op) => _operationGate!(op.empresaId));
      if (eligibleIndex < 0) break;
      final operation = _queue.removeAt(eligibleIndex);

      // Ainda dentro do backoff: guarda sem gastar tentativa.
      final devido = operation.nextAttemptAt;
      if (devido != null && devido.isAfter(DateTime.now())) {
        reagendar.add(operation);
        continue;
      }
      operation.nextAttemptAt = null;
      
      try {
        await operation.execute();
        await _persistirFila(); // Atualizar fila persistente
        debugPrint('>>> [SyncQueue] ✓ Operação ${operation.type} sincronizada e removida da fila');
        
        // Reportar sucesso ao monitor
        if (operation.empresaId != null) {
          SyncMonitorService.instance.registrarEvento(
            empresaId: operation.empresaId!,
            evento: 'sync_item_ok',
            detalhes: '${operation.type} (${operation.dataId}) sincronizado',
          );
        }
      } catch (e) {
        debugPrint('>>> [SyncQueue] ✗ Erro ao sincronizar ${operation.type}: $e');
        
        // Reportar erro ao monitor
        if (operation.empresaId != null) {
          SyncMonitorService.instance.registrarEvento(
            empresaId: operation.empresaId!,
            evento: 'erro_sync',
            detalhes: '${operation.type} (${operation.dataId})',
            erro: e.toString(),
          );
        }
        
        // Falha PERMANENTE (esquema/permissão): nunca vai passar — descarta
        // para não travar a fila. A lista foi restringida aos códigos reais.
        if (erroIrrecuperavel(e)) {
          debugPrint('>>> [SyncQueue] ⚠️ Erro irrecuperável (esquema/permissão). '
              'DESCARTANDO ${operation.type} (${operation.dataId}): $e');
          // Para a fila deixa de tentar, mas o registro NÃO some: vai para a
          // DLQ (registros ainda estão salvos localmente).
          await _enviarParaDlq(operation, 'erro irrecuperável: $e');
          await _persistirFila();
          continue;
        }

        // Erro de conexão: devolve ao início da fila e pausa o processamento.
        if (_isConnectionError(e)) {
          _queue.insert(0, operation);
          onConnectionLost();
          break;
        }

        operation.retryCount++;
        if (operation.retryCount < _maxRetryCount) {
          // Backoff exponencial: 5s, 10s, 20s, 40s, 80s... teto de 5 min.
          // AGENDADO em `nextAttemptAt` (sem `await`): enquanto esta espera, as
          // demais operações continuam sendo processadas normalmente.
          final backoffSeconds =
              (_baseBackoffDelay.inSeconds * (1 << (operation.retryCount - 1)))
                  .clamp(1, 300); // max 5 minutos
          operation.nextAttemptAt =
              DateTime.now().add(Duration(seconds: backoffSeconds));
          debugPrint('>>> [SyncQueue] ⚠ ${operation.type} falhou '
              '(tentativa ${operation.retryCount}/$_maxRetryCount, '
              'nova tentativa em ${backoffSeconds}s)');
          reagendar.add(operation);
        } else {
          debugPrint('>>> [SyncQueue] ⚠⚠⚠ Operacao ${operation.type} '
              '(${operation.dataId}) excedeu $_maxRetryCount tentativas. '
              'DESCARTADA — os dados continuam salvos LOCALMENTE.');
          // Descarte visível: a operação vai para a DLQ, não some em silêncio.
          await _enviarParaDlq(operation, 'excedeu $_maxRetryCount tentativas');
        }
      }
      
      // Pequeno delay entre operações para não sobrecarregar
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Devolve à fila o que está em backoff / falhou e persiste a fila atualizada
    _queue.addAll(reagendar);
    await _persistirFila();

    _isProcessing = false;

    if (_hasConnection &&
        !_paused &&
        !SupabaseService.instance.servidorIndisponivel &&
        _hasReadyOperation) {
      scheduleMicrotask(_processQueue);
    }

    // Dispara um retry exatamente quando a primeira operação vencer o backoff.
    _agendarRetryPeloBackoff(reagendar);

    if (_queue.isNotEmpty) {
      debugPrint('>>> [SyncQueue] ${_queue.length} operações ainda pendentes');
      
      // Atualizar status no monitor com fila pendente
      final empresaId = _queue.where((op) => op.empresaId != null).firstOrNull?.empresaId;
      if (empresaId != null) {
        SyncMonitorService.instance.atualizarStatusSucesso(
          empresaId: empresaId,
          filaPendente: _queue.length,
        );
      }
    } else {
      debugPrint('>>> [SyncQueue] ✓ Fila processada com sucesso');
    }
  }

  /// Erro permanente (esquema/permissão) — a operação nunca vai passar.
  ///
  /// Exposto para teste: a lista precisa continuar RESTRITA aos códigos reais
  /// de esquema/permissão (constraint, chave estrangeira e erros de tipo NÃO
  /// são mais tratados como permanentes).
  @visibleForTesting
  static bool erroIrrecuperavel(Object error) {
    final s = error.toString().toLowerCase();
    for (final padrao in _padroesIrrecuperaveis) {
      if (s.contains(padrao)) return true;
    }
    return false;
  }

  /// Agenda um disparo para quando a operação mais próxima vencer o backoff.
  ///
  /// Substitui o antigo `await Future.delayed(backoff)` dentro do laço, que
  /// segurava a fila inteira por até 5 minutos quando uma única operação falhava.
  void _agendarRetryPeloBackoff(List<SyncOperation> operacoes) {
    if (!_hasConnection) return;

    DateTime? proximo;
    for (final op in operacoes) {
      final t = op.nextAttemptAt;
      if (t != null && (proximo == null || t.isBefore(proximo))) proximo = t;
    }
    if (proximo == null) return;

    final delay = proximo.difference(DateTime.now());
    _retryTimer?.cancel();
    _retryTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      if (_hasConnection && !_isProcessing && !_paused && _queue.isNotEmpty) {
        debugPrint('>>> [SyncQueue] ⏰ Backoff vencido, reprocessando fila '
            '(${_queue.length} pendentes)...');
        _processQueue();
      }
    });
  }

  /// Notifica que a conexão foi restaurada
  void onConnectionRestored() {
    if (!_hasConnection) {
      _hasConnection = true;
      // A falha provavelmente foi de rede: zera os backoffs para retomar na hora.
      for (final op in _queue) {
        op.nextAttemptAt = null;
      }
      _retryTimer?.cancel();
      debugPrint('>>> [SyncQueue] 🔄 Conexão restaurada, processando fila...');
      _processQueue();
    }
  }

  /// Notifica que a conexão foi perdida
  void onConnectionLost() {
    _hasConnection = false;
    debugPrint('>>> [SyncQueue] ⚠ Conexão perdida, pausando sincronização');
  }

  /// Verifica se é erro de conexão
  bool _isConnectionError(dynamic error) {
    // Indisponibilidade da nuvem (PGRST002/schema cache/503/504): trata como
    // "conexão perdida" — pausa a fila e NÃO consome tentativas (antes isso
    // levava a operação a estourar o limite e ser descartada).
    if (SupabaseService.isErroInfraestrutura(error)) return true;
    final errorStr = error.toString().toLowerCase();
    return errorStr.contains('network') ||
           errorStr.contains('connection') ||
           errorStr.contains('timeout') ||
           errorStr.contains('socket') ||
           errorStr.contains('internet');
  }

  /// Retorna quantidade de operações pendentes
  int get pendingCount => _queue.length;

  /// True se existe uma operação pendente (ainda não enviada à nuvem) para este
  /// tipo + registro. É como saber se uma alteração LOCAL ainda não chegou lá:
  /// enquanto estiver na fila, o valor da nuvem para esse registro é mais antigo
  /// e não pode sobrescrever o local (evita perder baixa de estoque / venda).
  bool temPendencia(String type, String dataId) {
    final tipo = type.toLowerCase();
    return _queue.any(
      (op) =>
          op.type.toLowerCase() == tipo &&
          op.dataId == dataId &&
          op.retryCount < _maxRetryCount,
    );
  }

  /// Limpa a fila
  void clear() {
    _queue.clear();
    _persistirFila();
    _retryTimer?.cancel();
    debugPrint('>>> [SyncQueue] Fila limpa');
  }

  void dispose() {
    _retryTimer?.cancel();
    _periodicRetryTimer?.cancel();
    _queue.clear();
  }
  
  /// Força uma tentativa de sincronização imediatamente
  Future<void> forceSync() async {
    if (_queue.isNotEmpty) {
      debugPrint('>>> [SyncQueue] 🔄 Forçando sincronização imediata (${_queue.length} pendentes)');
      await _processQueue();
    }
  }
  
  /// Retorna informações sobre a fila
  Map<String, dynamic> getQueueInfo() {
    return {
      'pendingCount': _queue.length,
      'isProcessing': _isProcessing,
      'hasConnection': _hasConnection,
      'maxRetryCount': _maxRetryCount,
      'maxQueueSize': _maxQueueSize,
      'operations': _queue.map((op) => {
        'type': op.type,
        'dataId': op.dataId,
        'retryCount': op.retryCount,
      }).toList(),
    };
  }
  
  /// Remove operacoes presas que excederam o limite de tentativas
  void clearStuck() {
    final before = _queue.length;
    _queue.removeWhere((op) => op.retryCount >= _maxRetryCount);
    final removidas = before - _queue.length;
    if (removidas > 0) {
      _persistirFila();
      debugPrint('>>> [SyncQueue] 🧹 Limpeza: $removidas operacoes presas removidas da fila');
    }
  }
  
  /// Remove uma operacao especifica da fila por tipo e dataId
  void removeOperation(String type, String dataId) {
    final before = _queue.length;
    _queue.removeWhere((op) => op.type == type && op.dataId == dataId);
    if (_queue.length < before) {
      _persistirFila();
      debugPrint('>>> [SyncQueue] 🗑️ Operacao $type ($dataId) removida manualmente da fila');
    }
  }
  
  /// Remove todas as operacoes de um tipo especifico (ex: produto_historico, vendas_balcao)
  void clearByType(String type) {
    final before = _queue.length;
    _queue.removeWhere((op) => op.type == type);
    final removidas = before - _queue.length;
    if (removidas > 0) {
      _persistirFila();
      debugPrint('>>> [SyncQueue] 🗑️ $removidas operacoes do tipo $type removidas da fila');
    }
  }
}

/// Representa uma operação de sincronização
class SyncOperation {
  final String id;
  final String type; // Tipo de operação (ex: 'agendamento', 'venda', etc)
  final String dataId; // ID do dado
  final String? empresaId;
  final Map<String, dynamic> data;
  final Future<void> Function() execute; // Função para executar a sincronização
  int retryCount = 0;

  /// Quando esta operação pode ser tentada de novo (backoff agendado).
  /// `null` = pronta para tentar agora.
  DateTime? nextAttemptAt;

  SyncOperation({
    String? id,
    required this.type,
    required this.dataId,
    this.empresaId,
    this.data = const {},
    required this.execute,
  }) : id = id ?? 'sync_${DateTime.now().millisecondsSinceEpoch}_${dataId}';
}
