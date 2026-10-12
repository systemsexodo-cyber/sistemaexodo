import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:postgres/postgres.dart';

import 'env_config.dart';

/// Chamado a cada mudança que o sincronizador da rede local (LAN) grava no
/// PostgreSQL deste computador. Recebe o nome da tabela alterada.
typedef OnMudancaRedeLocal = void Function(String tabela);

/// Escuta, em tempo real, as mudanças que a REDE LOCAL traz para este banco.
///
/// Por que existe: o sincronizador da LAN puxa as mudanças do outro PC e grava
/// no PostgreSQL local. O trigger do banco NÃO avisa o app nesse caso (ele
/// silencia quando `exodo.sync_mode='on'`, justamente para a réplica não virar
/// loop de sincronização). Sem um aviso, a tela continuava mostrando os dados
/// da abertura do app — só atualizava ao sair e entrar de novo.
///
/// O sincronizador então emite `pg_notify('exodo_ui_event', '<tabela>')` e aqui
/// escutamos esse canal. É o equivalente local do Supabase Realtime: quando a
/// nuvem está fora (ex.: bloqueada), este é o caminho que mantém as telas
/// atualizadas entre os PCs da loja.
class LanRealtimeService {
  static final LanRealtimeService instance = LanRealtimeService._();
  LanRealtimeService._();

  static const String _canal = 'exodo_ui_event';

  Connection? _conn;
  StreamSubscription<String>? _sub;
  OnMudancaRedeLocal? _callback;
  bool _ativo = false;
  int _reconexoesConsecutivas = 0;

  bool get ativo => _ativo;

  /// Começa a escutar. É idempotente: chamadas repetidas enquanto já está ativo
  /// apenas trocam o callback, sem abrir outra conexão.
  Future<void> iniciar({required OnMudancaRedeLocal callback}) async {
    _callback = callback;
    if (_ativo) return;
    await _conectar();
  }

  Future<void> _conectar() async {
    if (kIsWeb) return;
    try {
      await _sub?.cancel();
      _sub = null;
      await _fecharConexao();

      final host = EnvConfig.dbHost.toLowerCase() == 'localhost'
          ? '127.0.0.1'
          : EnvConfig.dbHost;

      final conn = await Connection.open(
        Endpoint(
          host: host,
          port: EnvConfig.dbPort,
          database: EnvConfig.dbName,
          username: EnvConfig.dbUser,
          password: EnvConfig.dbPassword,
        ),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );

      _conn = conn;
      // `channels[canal]` só faz o LISTEN de verdade quando o stream é ouvido.
      _sub = conn.channels[_canal].listen(
        (tabela) {
          if (tabela.isEmpty) return;
          _callback?.call(tabela);
        },
        onError: (Object e) {
          debugPrint('>>> [LAN-Realtime] ⚠️ Erro no canal local: $e');
          _ativo = false;
          _agendarReconexao();
        },
        onDone: () {
          if (_ativo) {
            debugPrint('>>> [LAN-Realtime] 🔌 Canal local encerrado. Reconectando...');
            _ativo = false;
            _agendarReconexao();
          }
        },
      );

      _ativo = true;
      _reconexoesConsecutivas = 0;
      debugPrint(
        '>>> [LAN-Realtime] ✅ Escutando "$_canal" (rede local em tempo real).',
      );
    } catch (e) {
      debugPrint('>>> [LAN-Realtime] ❌ Não consegui escutar a rede local: $e');
      _ativo = false;
      _agendarReconexao();
    }
  }

  void _agendarReconexao() {
    if (_callback == null) return;
    _reconexoesConsecutivas = (_reconexoesConsecutivas + 1).clamp(1, 5);
    final segundos = 1 << _reconexoesConsecutivas; // 2, 4, 8, 16, 32s
    debugPrint('>>> [LAN-Realtime] ⏳ Reconectando em ${segundos}s...');
    Future.delayed(Duration(seconds: segundos), () {
      if (_callback != null && !_ativo) _conectar();
    });
  }

  Future<void> _fecharConexao() async {
    final conn = _conn;
    _conn = null;
    if (conn != null) {
      try {
        await conn.close();
      } catch (_) {}
    }
  }

  /// Para a escuta (logout / troca de empresa / dispose).
  Future<void> parar() async {
    _callback = null;
    await _sub?.cancel();
    _sub = null;
    await _fecharConexao();
    _ativo = false;
    _reconexoesConsecutivas = 0;
    debugPrint('>>> [LAN-Realtime] ⏹️ Escuta encerrada.');
  }
}
