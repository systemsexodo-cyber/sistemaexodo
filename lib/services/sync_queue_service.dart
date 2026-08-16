import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'database_service.dart';
import 'sync_monitor_service.dart';

/// Serviço para gerenciar fila de sincronização pendente
/// Armazena operações que falharam e tenta novamente quando a conexão voltar
/// Desktop: Persiste no PostgreSQL via DatabaseService
/// Web: Persiste em memória (sem SharedPreferences)
class SyncQueueService {
  final List<SyncOperation> _queue = [];
  bool _isProcessing = false;
  Timer? _retryTimer;
  Timer? _periodicRetryTimer;
  bool _hasConnection = true;
  
  // Constantes de limite
  static const int _maxRetryCount = 10;
  static const int _maxQueueSize = 500;
  static const Duration _baseBackoffDelay = Duration(seconds: 5);
  
  // Função para resolver operações vindas do banco de dados
  Future<void> Function(String type, String dataId, Map<String, dynamic> data)? _operationResolver;

  SyncQueueService({Future<void> Function(String, String, Map<String, dynamic>)? resolver}) {
    _operationResolver = resolver;
    
    // Iniciar monitoramento de sync
    SyncMonitorService.instance.initialize();
    
    // Carregar operações pendentes do PostgreSQL (Fila persistida)
    _carregarFilaDoBanco();
    
    // Iniciar timer periódico para tentar sincronizar pendências a cada 5 minutos
    _periodicRetryTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_queue.isNotEmpty && _hasConnection && !_isProcessing) {
        debugPrint('>>> [SyncQueue] 🔄 Tentativa periódica de sincronização (${_queue.length} pendentes)');
        _processQueue();
      }
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
      _queue.removeRange(0, removidas);
      debugPrint('>>> [SyncQueue] ⚠ Fila cheia: removidas $removidas operacoes antigas (limite: $_maxQueueSize)');
    }
    
    // Persistir no PostgreSQL
    _persistirFila();
    
    debugPrint('>>> [SyncQueue] Operação adicionada à fila e persistida: ${operation.type} (${_queue.length} pendentes)');
    
    // Tentar processar se tiver conexão
    if (_hasConnection && !_isProcessing) {
      _processQueue();
    }
  }

  /// Define o resolver para operações carregadas do banco
  void setResolver(Future<void> Function(String, String, Map<String, dynamic>) resolver) {
    _operationResolver = resolver;
    if (_queue.isNotEmpty && _hasConnection && !_isProcessing) {
      _processQueue();
    }
  }

  /// Salva a fila atual no PostgreSQL (via DatabaseService)
  Future<void> _persistirFila() async {
    if (kIsWeb) return; // Web: não persiste (volátil, reconecta automático)
    try {
      final listMap = _queue.map((op) => {
        'id': op.id,
        'empresa_id': op.empresaId,
        'tipo': op.type,
        'data_id': op.dataId,
        'data_json': jsonEncode(op.data),
        'retry_count': op.retryCount,
      }).toList();
      await DatabaseService().salvarConfig('exodo_sync_queue', listMap);
    } catch (e) {
      debugPrint('>>> [SyncQueue] ❌ Erro ao persistir fila: $e');
    }
  }

  /// Carrega as operações pendentes do PostgreSQL ao iniciar o app
  Future<void> _carregarFilaDoBanco() async {
    if (kIsWeb) return;
    try {
      final valor = await DatabaseService().carregarConfig('exodo_sync_queue');
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
    if (_isProcessing || _queue.isEmpty || !_hasConnection) {
      return;
    }

    _isProcessing = true;
    debugPrint('>>> [SyncQueue] Iniciando processamento da fila (${_queue.length} operações)');

    final List<SyncOperation> failed = [];

    while (_queue.isNotEmpty && _hasConnection) {
      final operation = _queue.removeAt(0);
      
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
        
        // Tratar erros irrecuperaveis com lista ampliada de padroes
        final errorStr = e.toString().toLowerCase();
        final List<String> irrecoverablePatterns = [
          'pgrst204', 'pgrst205', '42703', '42804', '42p01',
          'column', 'not find', 'does not exist', 'relation',
          'permission denied', 'policy', 'rlspolicy',
          'foreign key', 'constraint',
          'type\'null\'', 'is not a subtype',
        ];
        bool isIrrecoverable = false;
        for (final pattern in irrecoverablePatterns) {
          if (errorStr.contains(pattern)) {
            isIrrecoverable = true;
            break;
          }
        }
        
        if (isIrrecoverable) {
          debugPrint('>>> [SyncQueue] ⚠️ Erro irrecuperavel detectado. DESCARTANDO operacao ${operation.type} (${operation.dataId}) para evitar travamentos.');
          await _persistirFila();
          continue;
        }

        // Adicionar novamente a fila se nao for erro de conexao
        if (!_isConnectionError(e)) {
          operation.retryCount++;
          
          if (operation.retryCount < _maxRetryCount) {
            // Exponential backoff: 5s, 10s, 20s, 40s, 80s... capped at 5 min
            final backoffSeconds = (_baseBackoffDelay.inSeconds * (1 << (operation.retryCount - 1)))
                .clamp(1, 300); // max 5 minutos
            
            debugPrint('>>> [SyncQueue] ⚠ Operacao ${operation.type} falhou (tentativa ${operation.retryCount}/$_maxRetryCount, aguardando ${backoffSeconds}s)');
            
            failed.add(operation);
            
            // Delay com backoff exponencial antes de tentar novamente
            await Future.delayed(Duration(seconds: backoffSeconds));
          } else {
            debugPrint('>>> [SyncQueue] ⚠⚠⚠ Operacao ${operation.type} (${operation.dataId}) excedeu $_maxRetryCount tentativas. DESCARTADA.');
            debugPrint('>>> [SyncQueue] ⚠⚠⚠ Os dados estao salvos LOCALMENTE e nao foram perdidos.');
            // NAO adicionar a failed - operacao sera descartada
          }
        } else {
          // Se for erro de conexao, adicionar de volta no inicio
          _queue.insert(0, operation);
          onConnectionLost();
          break;
        }
      }
      
      // Pequeno delay entre operações para não sobrecarregar
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Adicionar falhas de volta à fila e persistir fila atualizada
    _queue.addAll(failed);
    await _persistirFila();

    _isProcessing = false;

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
      
      // Atualizar status no monitor indicando sync completo (fila vazia)
      if (failed.isNotEmpty) {
        final empresaId = failed.where((op) => op.empresaId != null).firstOrNull?.empresaId;
        if (empresaId != null) {
          SyncMonitorService.instance.atualizarStatusSucesso(
            empresaId: empresaId,
            filaPendente: failed.length,
          );
        }
      }
    }
  }

  /// Notifica que a conexão foi restaurada
  void onConnectionRestored() {
    if (!_hasConnection) {
      _hasConnection = true;
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
    final errorStr = error.toString().toLowerCase();
    return errorStr.contains('network') ||
           errorStr.contains('connection') ||
           errorStr.contains('timeout') ||
           errorStr.contains('socket') ||
           errorStr.contains('internet');
  }

  /// Retorna quantidade de operações pendentes
  int get pendingCount => _queue.length;

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

  SyncOperation({
    String? id,
    required this.type,
    required this.dataId,
    this.empresaId,
    this.data = const {},
    required this.execute,
  }) : id = id ?? 'sync_${DateTime.now().millisecondsSinceEpoch}_${dataId}';
}
