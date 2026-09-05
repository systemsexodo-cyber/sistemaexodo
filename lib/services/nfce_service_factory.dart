/// Factory para criar o serviço de NFC-e apropriado
/// Por padrão, usa backend Python local (localhost:8000).

import 'nfce_backend_service.dart' show NFCeServiceBase, NFCeBackendService;

/// Factory para criar serviços de NFC-e
class NFCeServiceFactory {
  /// URL do backend Python — null = usa localhost:8000 (padrão)
  static String? _backendUrl;

  /// Se deve usar backend Python (padrão: true)
  static bool _usarBackend = true;

  /// Configurar URL do backend (para túneis Zrok/Ngrok ou IP de rede)
  static void configurarBackend({String? url, bool usarBackend = true}) {
    _backendUrl = url;
    _usarBackend = usarBackend;
  }

  /// Criar instância do serviço
  static NFCeServiceBase criar() {
    return NFCeBackendService(baseUrl: _backendUrl);
  }

  /// Verificar se o Bridge local está disponível via HTTP (GET /health)
  static Future<bool> verificarBackend() async {
    if (!_usarBackend) return false;
    try {
      final backendService = NFCeBackendService(baseUrl: _backendUrl);
      return await backendService.verificarConexao();
    } catch (e) {
      return false;
    }
  }
}
