import 'dart:io';
import 'package:flutter/foundation.dart';

/// Detecta e configura automaticamente o bridge NFC-e local
class LocalBridgeDetector {
  static const List<String> _possiblePorts = ['8000', '8001', '8080', '9000'];
  static const List<String> _possibleHosts = ['localhost', '127.0.0.1'];

  /// Detecta automaticamente o bridge NFC-e rodando localmente
  static Future<String?> detectBridgeUrl() async {
    if (kIsWeb) return null;

    debugPrint('>>> [BridgeDetector] Procurando bridge NFC-e local...');

    for (final host in _possibleHosts) {
      for (final port in _possiblePorts) {
        final url = 'http://$host:$port';
        if (await _testBridgeConnection(url)) {
          debugPrint('>>> [BridgeDetector] ✅ Bridge encontrado em: $url');
          return url;
        }
      }
    }

    debugPrint('>>> [BridgeDetector] ❌ Nenhum bridge encontrado');
    return null;
  }

  /// Testa se o bridge está respondendo em uma URL específica
  static Future<bool> _testBridgeConnection(String url) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 3);
      
      final request = await client.getUrl(Uri.parse('$url/'));
      final response = await request.close();
      
      client.close();
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Verifica se o bridge está rodando na URL padrão
  static Future<bool> isDefaultBridgeRunning() async {
    return await _testBridgeConnection('http://localhost:8000');
  }

  /// Obtém a URL do bridge com fallback automático
  static Future<String> getBridgeUrl({String? customUrl}) async {
    // Se tiver URL customizada, usa ela
    if (customUrl != null && customUrl.isNotEmpty) {
      debugPrint('>>> [BridgeDetector] Usando URL customizada: $customUrl');
      return customUrl;
    }

    // Tenta detectar automaticamente
    final detectedUrl = await detectBridgeUrl();
    if (detectedUrl != null) {
      return detectedUrl;
    }

    // Fallback para localhost:8000
    debugPrint('>>> [BridgeDetector] Usando URL padrão: http://localhost:8000');
    return 'http://localhost:8000';
  }
}
