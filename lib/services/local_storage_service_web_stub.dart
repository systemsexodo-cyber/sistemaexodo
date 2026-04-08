import 'dart:html' as html;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart';

/// Implementação Web do localStorage migrada para HIVE
class LocalStorageWeb {
  static const String _boxName = 'exodo_storage';

  static Future<Box> _getBox() async {
    if (!Hive.isBoxOpen(_boxName)) {
      return await Hive.openBox(_boxName);
    }
    return Hive.box(_boxName);
  }

  static Future<void> salvar(String key, String value) async {
    try {
      final box = await _getBox();
      await box.put(key, value);
      
      // Manter uma cópia no localStorage apenas para redundância/segurança extra se for pequeno
      if (value.length < 500000) {
        html.window.localStorage[key] = value;
      }
    } catch (e) {
      debugPrint('>>> [Hive] Erro ao salvar $key: $e');
      // Fallback para localStorage se Hive falhar
      html.window.localStorage[key] = value;
    }
  }

  static Future<String?> carregar(String key) async {
    try {
      final box = await _getBox();
      final value = box.get(key) as String?;
      
      if (value != null) return value;
      
      // MIGRACAO: Se não achou no Hive, tenta carregar do localStorage
      final legacyValue = html.window.localStorage[key];
      if (legacyValue != null) {
         debugPrint('>>> [Migration] 🚚 Movendo chave $key do localStorage p/ Hive');
         await box.put(key, legacyValue);
         return legacyValue;
      }
      
      return null;
    } catch (e) {
      return html.window.localStorage[key];
    }
  }

  static Future<void> remover(String key) async {
    try {
      final box = await _getBox();
      await box.delete(key);
      html.window.localStorage.remove(key);
    } catch (e) {
      html.window.localStorage.remove(key);
    }
  }

  static bool isSessaoAtiva() {
    try {
      final active = html.window.sessionStorage['exodo_session_active'];
      if (active == 'true') return true;
      
      // Se não está ativa, marca como ativa para as próximas chamadas (F5)
      html.window.sessionStorage['exodo_session_active'] = 'true';
      return false;
    } catch (e) {
      return true; // Fallback seguro
    }
  }
}


