// Helper para hard refresh no Web
import 'dart:html' as html;

/// Faz hard refresh da página no navegador
void fazerHardRefresh() {
  try {
    // Método 1: location.reload() - recarrega a página
    html.window.location.reload();
  } catch (e) {
    // Método 2: location.href = location.href - força reload
    try {
      html.window.location.href = html.window.location.href;
    } catch (e2) {
      // Método 3: Usar window.location.replace para forçar reload
      html.window.location.replace(html.window.location.href);
    }
  }
}

/// Retorna o host da janela no navegador
String getWindowHost() {
  return html.window.location.host;
}

/// Retorna a origem da janela no navegador
String getWindowOrigin() {
  return html.window.location.origin;
}

/// Retorna o pathname da janela no navegador
String getWindowPathname() {
  return html.window.location.pathname ?? '';
}

/// Abre uma nova janela no navegador
void openWindow(String url, String name) {
  html.window.open(url, name);
}

/// Atualiza o caminho da URL
void updateUrl(String path, {bool replace = false}) {
  try {
    if (replace) {
      html.window.history.replaceState(null, '', path);
    } else {
      html.window.history.pushState(null, '', path);
    }
  } catch (e) {
    print('Erro ao atualizar URL: $e');
  }
}

