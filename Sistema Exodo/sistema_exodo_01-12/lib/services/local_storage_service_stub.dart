// Stub para plataformas não-Web
// Este arquivo não será usado no Web

/// Stub para localStorage em plataformas não-Web
class LocalStorageWeb {
  static Future<void> salvar(String key, String value) async {
    // Não implementado para plataformas não-Web
  }

  static Future<String?> carregar(String key) async {
    return null;
  }

  static Future<void> remover(String key) async {
    // Não implementado para plataformas não-Web
  }
}


