/// Factory para criar o serviço de NFC-e apropriado
/// Por padrão, usa backend Python. Pode ser configurado para usar implementação manual

import 'nfce_backend_service.dart' show NFCeServiceBase, NFCeBackendService;
// Comentado para evitar conflito de nomes com nfce_service.dart simples
// import 'nfce_service.dart';
// import 'sefaz_service.dart';
// import 'certificado_service.dart';
// import 'assinatura_service.dart';
// import 'xml_builder_service.dart';

/// Factory para criar serviços de NFC-e
class NFCeServiceFactory {
  /// URL do backend Python (pode ser configurada)
  static String? _backendUrl;
  
  /// Se deve usar backend Python (padrão: true)
  static bool _usarBackend = true;
  
  /// Configurar URL do backend
  static void configurarBackend({String? url, bool usarBackend = true}) {
    _backendUrl = url;
    _usarBackend = usarBackend;
  }
  
  /// Criar instância do serviço apropriado
  static NFCeServiceBase criar() {
    // Sempre usar backend Python (a implementação manual foi desativada)
    return NFCeBackendService(baseUrl: _backendUrl);
  }
  
  /// Verificar se backend está disponível
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
