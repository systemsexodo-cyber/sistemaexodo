// Helper para hard refresh no Web
import 'dart:html' as html;
import 'package:flutter/foundation.dart';

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

/// Abre uma janela no navegador
void openWindow(String url, String name) {
  html.window.open(url, name);
}

/// Abre uma URL no navegador (compatível com mailto:)
void openUrl(String url) {
  html.window.location.href = url;
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

/// Stream de foco da janela no navegador
Stream<dynamic> get onWindowFocus => html.window.onFocus;

/// Toca áudio no navegador
void playAudio(String assetPath, {double volume = 1.0}) {
  try {
    // No Web, o Flutter gera os assets com um prefixo se necessário
    final audio = html.AudioElement(assetPath);
    audio.volume = volume; // Define o volume
    audio.play();
  } catch (e) {
    print('Erro ao tocar áudio no Web: $e');
  }
}

/// Faz o download de um arquivo no navegador
void downloadFile(String content, String fileName, String mimeType) {
  try {
    final blob = html.Blob([content], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute("download", fileName)
      ..click();
    html.Url.revokeObjectUrl(url);
  } catch (e) {
    print('Erro ao baixar arquivo: $e');
  }
}

/// Faz o download de um arquivo binário no navegador
void downloadBytes(List<int> bytes, String fileName, String mimeType) {
  try {
    debugPrint('>>> [HtmlHelper] Iniciando download de ${bytes.length} bytes: $fileName ($mimeType)');
    final blob = html.Blob([bytes], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    
    final anchor = html.AnchorElement(href: url);
    anchor.setAttribute("download", fileName);
    anchor.style.display = 'none'; // Garantir que não interfira no layout
    html.document.body?.append(anchor); // Adicionar ao body para garantir visibilidade ao clique
    
    anchor.click(); // Clique programático
    
    // Remover do DOM após um pequeno delay para garantir que o Chrome processou
    Future.delayed(const Duration(milliseconds: 500), () {
      anchor.remove();
      html.Url.revokeObjectUrl(url);
      debugPrint('>>> [HtmlHelper] URL de download revogada e limpa.');
    });
    
    debugPrint('>>> [HtmlHelper] Clique de download disparado!');
  } catch (e) {
    debugPrint('>>> [HtmlHelper] ❌ ERRO ao baixar arquivo binário: $e');
  }
}

/// Verifica se está em tela cheia no navegador
bool isFullscreen() {
  return html.document.fullscreenElement != null;
}

/// Solicita tela cheia no navegador
void requestFullscreen() {
  html.document.documentElement?.requestFullscreen();
}

/// Sai da tela cheia no navegador
void exitFullscreen() {
  html.document.exitFullscreen();
}


