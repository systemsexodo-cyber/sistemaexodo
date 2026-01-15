import 'dart:async';
import 'package:flutter/foundation.dart';

/// Serviço para gerenciar fila de sincronização pendente
/// Armazena operações que falharam e tenta novamente quando a conexão voltar
class SyncQueueService {
  final List<SyncOperation> _queue = [];
  bool _isProcessing = false;
  Timer? _retryTimer;
  Timer? _periodicRetryTimer;
  bool _hasConnection = true;
  
  SyncQueueService() {
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
    
    debugPrint('>>> [SyncQueue] Operação adicionada à fila: ${operation.type} (${_queue.length} pendentes)');
    
    // Tentar processar se tiver conexão
    if (_hasConnection && !_isProcessing) {
      _processQueue();
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
        debugPrint('>>> [SyncQueue] ✓ Operação ${operation.type} sincronizada com sucesso');
      } catch (e) {
        debugPrint('>>> [SyncQueue] ✗ Erro ao sincronizar ${operation.type}: $e');
        // Adicionar novamente à fila se não for erro de conexão
        if (!_isConnectionError(e)) {
          operation.retryCount++;
          // Aumentar limite de tentativas para 10 (antes era 3)
          if (operation.retryCount < 10) {
            failed.add(operation);
            debugPrint('>>> [SyncQueue] ⚠ Operação ${operation.type} falhou (tentativa ${operation.retryCount}/10), será tentada novamente');
          } else {
            debugPrint('>>> [SyncQueue] ⚠⚠⚠ ATENÇÃO: Operação ${operation.type} excedeu 10 tentativas!');
            debugPrint('>>> [SyncQueue] ⚠⚠⚠ Os dados estão salvos localmente, mas NÃO foram sincronizados com Firebase!');
            // NÃO descartar - manter na fila para tentar mais tarde
            failed.add(operation);
          }
        } else {
          // Se for erro de conexão, adicionar de volta no início
          _queue.insert(0, operation);
          onConnectionLost();
          break; // Parar processamento se não tiver conexão
        }
      }
      
      // Pequeno delay entre operações para não sobrecarregar
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Adicionar falhas de volta à fila
    _queue.addAll(failed);

    _isProcessing = false;

    if (_queue.isNotEmpty) {
      debugPrint('>>> [SyncQueue] ${_queue.length} operações ainda pendentes');
    } else {
      debugPrint('>>> [SyncQueue] ✓ Fila processada com sucesso');
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
      'operations': _queue.map((op) => {
        'type': op.type,
        'dataId': op.dataId,
        'retryCount': op.retryCount,
      }).toList(),
    };
  }
}

/// Representa uma operação de sincronização
class SyncOperation {
  final String type; // Tipo de operação (ex: 'agendamento', 'venda', etc)
  final String dataId; // ID do dado
  final Future<void> Function() execute; // Função para executar a sincronização
  int retryCount = 0;

  SyncOperation({
    required this.type,
    required this.dataId,
    required this.execute,
  });
}
