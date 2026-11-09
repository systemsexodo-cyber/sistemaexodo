// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'neon_config.dart';
import 'neon_realtime_service.dart';

class SupabaseLocalRealtimeService {
  static final SupabaseLocalRealtimeService instance =
      SupabaseLocalRealtimeService._();
  SupabaseLocalRealtimeService._();

  static const Duration _reconnectInitial = Duration(seconds: 2);
  static const Duration _reconnectMax = Duration(seconds: 30);
  static const Duration _heartbeat = Duration(seconds: 25);

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;

  bool _stopping = false;
  bool _active = false;
  int _attempt = 0;
  int _ref = 0;
  String? _empresaId;
  List<String> _tables = const [];
  OnMudancaNaNuvem? _onChange;

  bool get ativo => _active;

  Future<void> iniciar(
    String empresaId, {
    required List<String> tabelas,
    required OnMudancaNaNuvem onMudanca,
  }) async {
    if (_active && _empresaId == empresaId) {
      _onChange = onMudanca;
      _tables = List.unmodifiable(tabelas);
      return;
    }

    await parar();
    _stopping = false;
    _empresaId = empresaId;
    _tables = List.unmodifiable(tabelas);
    _onChange = onMudanca;

    if (!NeonConfig.supabaseLocalRealtimeDisponivel) {
      debugPrint(
        '>>> [Supabase-Realtime] desligado: SUPABASE_REALTIME_URL não configurada.',
      );
      return;
    }

    await _connect();
  }

  Future<void> parar() async {
    _stopping = true;
    _active = false;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer = null;

    try {
      await _subscription?.cancel();
    } catch (_) {}
    _subscription = null;

    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  Future<void> _connect() async {
    if (_stopping || _empresaId == null) return;

    try {
      final base = Uri.parse(NeonConfig.supabaseLocalRealtimeUrl);
      final params = Map<String, String>.from(base.queryParameters);
      params['apikey'] = NeonConfig.supabaseLocalRealtimeKey;
      params['vsn'] = '1.0.0';

      final uri = base.replace(queryParameters: params);
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      await channel.ready;

      _active = true;
      _attempt = 0;

      debugPrint(
        '>>> [Supabase-Realtime] conectado (empresa ' +
            _empresaId! +
            ').',
      );

      _subscription = channel.stream.listen(
        _onMessage,
        onError: (Object e) {
          debugPrint('>>> [Supabase-Realtime] erro no socket: ' + e.toString());
          _scheduleReconnect();
        },
        onDone: _scheduleReconnect,
      );

      for (final table in _tables) {
        _joinTable(table);
      }

      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(_heartbeat, (_) {
        _send(<String, dynamic>{
          'topic': 'phoenix',
          'event': 'heartbeat',
          'payload': <String, dynamic>{},
          'ref': (_ref++).toString(),
        });
      });
    } catch (e) {
      debugPrint('>>> [Supabase-Realtime] falha ao conectar: ' + e.toString());
      _scheduleReconnect();
    }
  }

  void _joinTable(String table) {
    final empresaId = _empresaId;
    if (empresaId == null) return;

    final topic = 'realtime:public:' + table;
    _send(<String, dynamic>{
      'topic': topic,
      'event': 'phx_join',
      'payload': <String, dynamic>{
        'config': <String, dynamic>{
          'broadcast': <String, dynamic>{'ack': false, 'self': false},
          'presence': <String, dynamic>{'key': ''},
          'postgres_changes': <Map<String, dynamic>>[
            <String, dynamic>{
              'event': '*',
              'schema': 'public',
              'table': table,
              'filter': 'empresa_id=eq.' + empresaId,
            },
          ],
        },
        'access_token': NeonConfig.supabaseLocalRealtimeKey,
      },
      'ref': (_ref++).toString(),
    });
  }

  void _send(Map<String, dynamic> message) {
    try {
      _channel?.sink.add(jsonEncode(message));
    } catch (_) {}
  }

  void _onMessage(dynamic raw) {
    final text = raw is String ? raw : utf8.decode(raw as List<int>);
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final event = msg['event']?.toString();
    final payload = msg['payload'];
    final topic = msg['topic']?.toString() ?? '';

    if (event == 'phx_close' || event == 'phx_error') {
      debugPrint(
        '>>> [Supabase-Realtime] servidor encerrou ' +
            topic +
            ': ' +
            payload.toString(),
      );
      _scheduleReconnect();
      return;
    }

    if (event != 'postgres_changes') return;

    final data = payload is Map ? Map<String, dynamic>.from(payload) : null;
    if (data == null) return;

    final record = data['data'];
    if (record is! Map) return;

    final table = record['table']?.toString();
    if (table == null || table.isEmpty) return;

    debugPrint('>>> [Supabase-Realtime] mudança recebida: ' + table);
    _onChange?.call(table);
  }

  void _scheduleReconnect() {
    if (_stopping || _reconnectTimer?.isActive == true) return;

    _active = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    final seconds = (_reconnectInitial.inSeconds * (1 << _attempt))
        .clamp(_reconnectInitial.inSeconds, _reconnectMax.inSeconds);
    _attempt++;

    _reconnectTimer = Timer(Duration(seconds: seconds), () async {
      _reconnectTimer = null;
      await _connect();
    });
  }
}
