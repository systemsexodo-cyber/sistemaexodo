// Stub para quando não é Web (não faz nada)

/// Faz hard refresh da página no navegador (stub - não faz nada quando não é Web)
void fazerHardRefresh() {
  // Não faz nada quando não é Web
}

/// Retorna o host da janela (stub)
String getWindowHost() {
  return "sistema-exodo.web.app";
}

/// Retorna a origem da janela (stub)
String getWindowOrigin() {
  return "https://sistema-exodo.web.app";
}

/// Retorna o pathname da janela (stub)
String getWindowPathname() {
  return "";
}

/// Abre uma nova janela (stub)
void openWindow(String url, String name) {
  // Não faz nada fora da Web
}

/// Atualiza o caminho da URL (stub)
void updateUrl(String path, {bool replace = false}) {
  // Não faz nada fora da Web
}

/// Stream de foco da janela (stub)
Stream<dynamic> get onWindowFocus => const Stream.empty();

/// Toca áudio no navegador (stub)
void playAudio(String assetPath, {double volume = 1.0}) {
  // Não faz nada fora da Web
}

