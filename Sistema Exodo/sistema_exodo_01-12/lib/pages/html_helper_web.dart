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

