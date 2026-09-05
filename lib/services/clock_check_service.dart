import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Serviço que verifica se o relógio do computador está correto comparando
/// com servidores de tempo na internet. Um relógio errado pode causar:
///
/// - 🔄 **Conflitos de sincronização:** `updatedAt` incorreto faz dados antigos
///   sobrescreverem dados novos no Supabase (delta sync usa `gte updated_at`)
/// - 🔑 **Token JWT expirado prematuramente:** sessão do Supabase inválida
/// - 📄 **NF-e/NFC-e rejeitada pela SEFAZ:** diferença > 5 min = rejeição fiscal
/// - 📋 **Histórico em ordem errada:** registros aparecem fora de sequência
/// - 🔒 **Falha de autenticação:** HTTPS requer relógio correto para verificar TLS
class ClockCheckService extends ChangeNotifier {
  static final ClockCheckService _instance = ClockCheckService._internal();
  factory ClockCheckService() => _instance;
  ClockCheckService._internal();

  static const _prefKeySkipUntil = 'clock_warning_skip_until';
  static const int _limiteAvisoSegundos = 180; // 3 minutos — avisa
  static const int _limiteCriticoSegundos = 300; // 5 minutos — crítico (SEFAZ)

  int? _diferencaSegundos; // null = não verificado ainda / sem internet
  bool _verificando = false;
  DateTime? _ultimaVerificacao;
  String? _ultimoErro;

  /// Diferença em segundos entre horário local e servidor NTP
  /// Positivo = relógio local adiantado; Negativo = atrasado
  int? get diferencaSegundos => _diferencaSegundos;

  /// True se o relógio estiver significativamente errado (> 3 min)
  bool get relogioErrado =>
      _diferencaSegundos != null &&
      _diferencaSegundos!.abs() >= _limiteAvisoSegundos;

  /// True se for crítico (> 5 min — risco de rejeição de NF-e)
  bool get relogioCritico =>
      _diferencaSegundos != null &&
      _diferencaSegundos!.abs() >= _limiteCriticoSegundos;

  /// Texto descritivo da diferença
  String get descricaoDiferenca {
    if (_diferencaSegundos == null) return 'Não verificado';
    final abs = _diferencaSegundos!.abs();
    final min = abs ~/ 60;
    final seg = abs % 60;
    final direcao = _diferencaSegundos! > 0 ? 'adiantado' : 'atrasado';
    if (min > 0) {
      return 'Relógio $direcao em ${min}min ${seg}s';
    }
    return 'Relógio $direcao em ${seg}s';
  }

  bool get verificando => _verificando;
  DateTime? get ultimaVerificacao => _ultimaVerificacao;
  String? get ultimoErro => _ultimoErro;

  /// Verifica o relógio comparando com worldtimeapi.org (ou fallback no Google)
  Future<void> verificar({bool forcar = false}) async {
    if (_verificando) return;

    // Não verificar novamente se foi feito há menos de 15 minutos (exceto força)
    if (!forcar &&
        _ultimaVerificacao != null &&
        DateTime.now().difference(_ultimaVerificacao!).inMinutes < 15) {
      return;
    }

    _verificando = true;
    _ultimoErro = null;
    notifyListeners();

    bool sucesso = false;

    // ── Tentativa 1: WorldTimeAPI ─────────────────────────────────────────
    try {
      final httpClient = HttpClient();
      httpClient.connectionTimeout = const Duration(seconds: 5);
      final request = await httpClient.getUrl(
        Uri.parse('https://worldtimeapi.org/api/timezone/America/Sao_Paulo'),
      );
      request.headers.set('User-Agent', 'ExodoSystem/1.0');
      final response = await request.close().timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final body =
            await response.transform(const SystemEncoding().decoder).join();
        final match = RegExp(r'"unixtime":(\d+)').firstMatch(body);
        if (match != null) {
          final ntpUnix = int.parse(match.group(1)!);
          final localUnix = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
          _diferencaSegundos = localUnix - ntpUnix;
          _ultimaVerificacao = DateTime.now();
          sucesso = true;
          debugPrint(
            '>>> [ClockCheck] ✅ WorldTimeAPI. Diferença: ${_diferencaSegundos}s ($descricaoDiferenca)',
          );
        }
      }
      httpClient.close();
    } catch (e) {
      debugPrint('>>> [ClockCheck] ⚠️ WorldTimeAPI falhou: $e');
    }

    // ── Tentativa 2: Cabeçalho Date do Google ─────────────────────────────
    if (!sucesso) {
      try {
        final httpClient = HttpClient();
        httpClient.connectionTimeout = const Duration(seconds: 5);
        final request =
            await httpClient.headUrl(Uri.parse('https://www.google.com'));
        final response = await request.close().timeout(const Duration(seconds: 5));

        final dateHeader = response.headers.value('date');
        if (dateHeader != null) {
          final serverTime = HttpDate.parse(dateHeader);
          final localTime = DateTime.now().toUtc();
          _diferencaSegundos = localTime.difference(serverTime).inSeconds;
          _ultimaVerificacao = DateTime.now();
          sucesso = true;
          debugPrint(
            '>>> [ClockCheck] ✅ Fallback Google. Diferença: ${_diferencaSegundos}s ($descricaoDiferenca)',
          );
        }
        httpClient.close();
      } catch (e) {
        debugPrint('>>> [ClockCheck] ⚠️ Fallback Google falhou: $e');
        _ultimoErro = 'Sem internet para verificar o relógio';
      }
    }

    _verificando = false;
    notifyListeners();
  }

  /// Marca para ignorar o aviso por 24h
  Future<void> ignorarPor24h() async {
    final prefs = await SharedPreferences.getInstance();
    final ate = DateTime.now().add(const Duration(hours: 24));
    await prefs.setString(_prefKeySkipUntil, ate.toIso8601String());
    notifyListeners();
  }

  /// Verifica se deve exibir o aviso de relógio errado
  Future<bool> deveExibirAviso() async {
    if (!relogioErrado) return false;
    final prefs = await SharedPreferences.getInstance();
    final skipStr = prefs.getString(_prefKeySkipUntil);
    if (skipStr == null) return true;
    final skipAte = DateTime.tryParse(skipStr);
    if (skipAte == null) return true;
    return DateTime.now().isAfter(skipAte);
  }

  /// Retorna o ícone adequado ao estado do relógio
  String get iconeStatus {
    if (_diferencaSegundos == null) return '⏱️';
    if (relogioCritico) return '🚨';
    if (relogioErrado) return '⚠️';
    return '✅';
  }

  /// Cor de alerta
  int get corAlerta {
    if (relogioCritico) return 0xFFE53935; // Vermelho
    if (relogioErrado) return 0xFFFFA000; // Âmbar
    return 0xFF43A047; // Verde
  }
}
