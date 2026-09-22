import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import '../models/status_sync.dart';
import 'supabase_service.dart';

/// Servico de monitoramento de sincronizacao
/// Envia eventos de sync para as tabelas sync_logs e sync_status no Supabase
/// Permite que o admin veja o status de cada cliente em tempo real
class SyncMonitorService {
  static final SyncMonitorService instance = SyncMonitorService._();
  SyncMonitorService._();

  bool _initialized = false;
  String _pcName = '';
  String _empresaId = '';
  Timer? _heartbeatTimer;

  /// Inicializa o monitoramento.
  ///
  /// Pode ser chamado de novo a cada troca de empresa: o timer de heartbeat é
  /// criado uma única vez, mas a empresa monitorada passa a ser a empresa atual
  /// (senão o monitor mostraria para sempre a primeira empresa aberta).
  void initialize({String empresaId = '', String pcName = ''}) {
    if (empresaId.isNotEmpty) _empresaId = empresaId;
    if (pcName.isNotEmpty) _pcName = pcName;
    if (_pcName.isEmpty) _pcName = _getPcName();

    if (_initialized) return;
    _initialized = true;

    // Iniciar heartbeat periodico (a cada 2 minutos)
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (_empresaId.isNotEmpty) {
        _atualizarHeartbeat(_empresaId);
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
      final agora = DateTime.now().toUtc().toIso8601String();
      await SupabaseService.instance.upsert('sync_status', {
        'empresa_id': empresaId,
        'pc_name': _pcName,
        'ultima_sincronizacao': agora,
        'fila_pendente': filaPendente,
        'versao_app': versaoApp,
        'online': true,
        'online_data': agora,
        // Zerar o erro anterior: sem isso o monitor continuaria mostrando
        // "Com Erros" para sempre, mesmo depois de o cliente se recuperar.
        'ultimo_erro': '',
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

  /// Status de sync de todas as empresas, já interpretado pelo [StatusSync].
  ///
  /// Ordenado do pior para o melhor (erro pendente, dias offline, ...), que é a
  /// ordem em que o suporte precisa olhar.
  static Future<List<StatusSync>> buscarStatusInterpretado({DateTime? agora}) async {
    final agora2 = agora ?? DateTime.now();
    final status = await buscarStatusTodasEmpresas();
    final interpretados = status
        .map((linha) =>
            StatusSync.fromMap(linha['empresa_id']?.toString() ?? '', linha))
        .toList();
    interpretados.sort((a, b) => a.compararCom(b, agora2));
    return interpretados;
  }

  /// Ultimos eventos de erro de TODAS as empresas (para o painel "Erros
  /// recentes" do monitor). A tabela `sync_logs` guarda a mensagem completa do
  /// erro, o PC de origem e o horario.
  static Future<List<Map<String, dynamic>>> buscarErrosRecentes({
    int limite = 40,
  }) async {
    if (!SupabaseService.isAvailable) return [];

    try {
      // Filtra no servidor (`erro <> ''`): sem isso, um erro de dois dias atrás
      // ficaria fora dos "N" eventos mais recentes — que são quase todos
      // `sync_ok` de rotina — e o painel diria "nenhum erro registrado".
      return await SupabaseService.instance.select(
        'sync_logs',
        filtrosDiferentes: {'erro': ''},
        orderBy: 'created_at',
        descending: true,
        limit: limite,
      );
    } catch (e) {
      debugPrint('>>> [SyncMonitor] Erro ao buscar erros recentes: $e');
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
