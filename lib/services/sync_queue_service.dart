import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Serviço para gerenciar fila de sincronização pendente
/// Armazena operações que falharam e tenta novamente quando a conexão voltar
class SyncQueueService {
  final List<SyncOperation> _queue = [];
  bool _isProcessing = false;
  Timer? _retryTimer;
  Timer? _periodicRetryTimer;
  bool _hasConnection = true;
  
  // Função para resolver operações vindas do banco de dados
  Future<void> Function(String type, String dataId, Map<String, dynamic> data)? _operationResolver;

  SyncQueueService({Future<void> Function(String, String, Map<String, dynamic>)? resolver}) {
    _operationResolver = resolver;
    // Carregar operações pendentes do SharedPreferences (Fila persistida)
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
    
    // Persistir no SharedPreferences
    _persistirFila();
    
    debugPrint('>>> [SyncQueue] Operação adicionada à fila e persistida localmente: ${operation.type} (${_queue.length} pendentes)');
    
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

  /// Salva a fila atual no SharedPreferences
  Future<void> _persistirFila() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final listMap = _queue.map((op) => {
        'id': op.id,
        'empresa_id': op.empresaId,
        'tipo': op.type,
        'data_id': op.dataId,
        'data_json': jsonEncode(op.data),
        'retry_count': op.retryCount,
      }).toList();
      await prefs.setString('exodo_sync_queue', jsonEncode(listMap));
    } catch (e) {
      debugPrint('>>> [SyncQueue] ❌ Erro ao persistir fila de sincronização: $e');
    }
  }

  /// Carrega as operações pendentes do SharedPreferences ao iniciar o app
  Future<void> _carregarFilaDoBanco() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queueJson = prefs.getString('exodo_sync_queue');
      if (queueJson == null || queueJson.isEmpty) return;
      
      final decoded = jsonDecode(queueJson) as List;
      if (decoded.isEmpty) return;
      
      debugPrint('>>> [SyncQueue] 📦 Restaurando ${decoded.length} operações pendentes...');
      
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
      } catch (e) {
        debugPrint('>>> [SyncQueue] ✗ Erro ao sincronizar ${operation.type}: $e');
        
        // Tratar erros irrecuperáveis (ex: erro de esquema/coluna inexistente no Supabase)
        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains('pgrst204') || 
            (errorStr.contains('column') && errorStr.contains('not find')) ||
            errorStr.contains('42703')) {
          debugPrint('>>> [SyncQueue] ⚠️ Erro irrecuperável (Esquema). Descartando operação para evitar travamentos.');
          await _persistirFila();
          continue;
        }

        // Adicionar novamente à fila se não for erro de conexão
        if (!_isConnectionError(e)) {
          operation.retryCount++;
          // Aumentar limite de tentativas para 10 (antes era 3)
          if (operation.retryCount < 10) {
            failed.add(operation);
            debugPrint('>>> [SyncQueue] ⚠ Operação ${operation.type} falhou (tentativa ${operation.retryCount}/10), será tentada novamente');
          } else {
            debugPrint('>>> [SyncQueue] ⚠⚠⚠ ATENÇÃO: Operação ${operation.type} excedeu 10 tentativas!');
            debugPrint('>>> [SyncQueue] ⚠⚠⚠ Os dados estão salvos localmente, mas NÃO foram sincronizados com Supabase!');
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

    // Adicionar falhas de volta à fila e persistir fila atualizada
    _queue.addAll(failed);
    await _persistirFila();

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
