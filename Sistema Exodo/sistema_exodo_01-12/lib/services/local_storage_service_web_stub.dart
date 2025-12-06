// Implementação Web do LocalStorageService usando dart:html
// Este arquivo será usado apenas no Web

import 'dart:html' as html;

/// Implementação Web do localStorage
class LocalStorageWeb {
  static Future<void> salvar(String key, String value) async {
    try {
      html.window.localStorage[key] = value;
    } catch (e) {
      throw Exception('Erro ao salvar no localStorage: $e');
    }
  }

  static Future<String?> carregar(String key) async {
    try {
      return html.window.localStorage[key];
    } catch (e) {
      return null;
    }
  }

  static Future<void> remover(String key) async {
    try {
      html.window.localStorage.remove(key);
    } catch (e) {
      // Ignorar erros ao remover
    }
  }
}


