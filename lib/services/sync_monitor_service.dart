import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'supabase_service.dart';

/// Servico de monitoramento de sincronizacao
/// Envia eventos de sync para as tabelas sync_logs e sync_status no Supabase
/// Permite que o admin veja o status de cada cliente em tempo real
class SyncMonitorService {
  static final SyncMonitorService instance = SyncMonitorService._();
  SyncMonitorService._();

  bool _initialized = false;
  String _pcName = '';
  Timer? _heartbeatTimer;

  /// Inicializa o monitoramento
  void initialize({String empresaId = '', String pcName = ''}) {
    if (_initialized) return;
    _initialized = true;
    _pcName = pcName.isNotEmpty ? pcName : _getPcName();

    // Iniciar heartbeat periodico (a cada 2 minutos)
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (empresaId.isNotEmpty) {
        _atualizarHeartbeat(empresaId);
      }
    });

    debugPrint('>>> [SyncMonitor] Monitoramento iniciado (PC: $_pcName)');
  }

  String _getPcName() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'desconhecido';
    }
  }

  /// Registra um evento de sync no Supabase
  Future<void> registrarEvento({
    required String empresaId,
    required String evento,
    String detalhes = '',
    String erro = '',
  }) async {
    if (!SupabaseService.isAvailable) return;
    if (empresaId.isEmpty) return;

    try {
      await SupabaseService.instance.upsert('sync_logs', {
        'empresa_id': empresaId,
        'pc_name': _pcName,
        'evento': evento,
        'detalhes': detalhes,
        'erro': erro,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      // Se for evento de erro, atualizar status
      if (evento == 'erro_sync') {
        await _atualizarStatusErro(empresaId, erro);
      }
    } catch (e) {
      debugPrint('>>> [SyncMonitor] Erro ao registrar evento: $e');
    }
  }

  /// Atualiza o status de sync apos uma operacao bem-sucedida
  Future<void> atualizarStatusSucesso({
    required String empresaId,
    int filaPendente = 0,
    String versaoApp = '',
  }) async {
    if (!SupabaseService.isAvailable || empresaId.isEmpty) return;

    try {
      await SupabaseService.instance.upsert('sync_status', {
        'empresa_id': empresaId,
        'pc_name': _pcName,
        'ultima_sincronizacao': DateTime.now().toUtc().toIso8601String(),
        'fila_pendente': filaPendente,
        'versao_app': versaoApp,
        'online': true,
        'online_data': DateTime.now().toUtc().toIso8601String(),
      });

      await SupabaseService.instance.upsert('sync_logs', {
        'empresa_id': empresaId,
        'pc_name': _pcName,
        'evento': 'sync_ok',
        'detalhes': 'Sincronizacao concluida. Fila: $filaPendente pendentes',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('>>> [SyncMonitor] Erro ao atualizar status sucesso: $e');
    }
  }

  /// Atualiza o status quando ocorre um erro
  Future<void> _atualizarStatusErro(String empresaId, String erro) async {
    if (!SupabaseService.isAvailable || empresaId.isEmpty) return;

    try {
      await SupabaseService.instance.upsert('sync_status', {
        'empresa_id': empresaId,
        'pc_name': _pcName,
        'ultimo_erro': erro.length > 500 ? erro.substring(0, 500) : erro,
        'ultimo_erro_data': DateTime.now().toUtc().toIso8601String(),
        'online': true,
        'online_data': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('>>> [SyncMonitor] Erro ao atualizar status erro: $e');
    }
  }

  /// Atualiza heartbeat (sinal de que o cliente esta online)
  Future<void> _atualizarHeartbeat(String empresaId) async {
    if (!SupabaseService.isAvailable || empresaId.isEmpty) return;

    try {
      await SupabaseService.instance.upsert('sync_status', {
        'empresa_id': empresaId,
        'pc_name': _pcName,
        'online': true,
        'online_data': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {}
  }

  /// Marca o cliente como offline
  Future<void> marcarOffline(String empresaId) async {
    if (!SupabaseService.isAvailable || empresaId.isEmpty) return;

    try {
      await SupabaseService.instance.upsert('sync_status', {
        'empresa_id': empresaId,
        'pc_name': _pcName,
        'online': false,
      });
    } catch (_) {}
  }

  /// Busca status de sync de todas as empresas (para admin)
  static Future<List<Map<String, dynamic>>> buscarStatusTodasEmpresas() async {
    if (!SupabaseService.isAvailable) return [];

    try {
      final result = await SupabaseService.instance.select(
        'sync_status',
        orderBy: 'ultima_sincronizacao',
        descending: true,
      );
      return result;
    } catch (e) {
      debugPrint('>>> [SyncMonitor] Erro ao buscar status geral: $e');
      return [];
    }
  }

  /// Busca logs de sync de uma empresa especifica
  static Future<List<Map<String, dynamic>>> buscarLogsEmpresa(
    String empresaId, {
    int limite = 50,
  }) async {
    if (!SupabaseService.isAvailable) return [];

    try {
      final result = await SupabaseService.instance.select(
        'sync_logs',
        filters: {'empresa_id': empresaId},
        orderBy: 'created_at',
        descending: true,
        limit: limite,
      );
      return result;
    } catch (e) {
      debugPrint('>>> [SyncMonitor] Erro ao buscar logs: $e');
      return [];
    }
  }

  /// Para o monitoramento
  void dispose() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _initialized = false;
  }
}
