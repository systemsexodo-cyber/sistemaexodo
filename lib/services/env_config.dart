import 'dart:io';
import 'package:flutter/foundation.dart';

class EnvConfig {
  static Map<String, String>? _cachedEnv;

  static Map<String, String> get env {
    if (_cachedEnv != null) return _cachedEnv!;
    _cachedEnv = _loadEnv();
    return _cachedEnv!;
  }

  static Map<String, String> _loadEnv() {
    final values = <String, String>{};
    try {
      var file = File('.env');
      
      if (!file.existsSync() && !kIsWeb) {
        try {
          final exeDir = File(Platform.resolvedExecutable).parent;
          final fallbackFile = File('${exeDir.path}${Platform.pathSeparator}.env');
          if (fallbackFile.existsSync()) {
            file = fallbackFile;
          }
        } catch (_) {}
      }

      if (file.existsSync()) {
        final lines = file.readAsLinesSync();
        for (var line in lines) {
          line = line.trim();
          if (line.isEmpty || line.startsWith('#')) continue;
          final idx = line.indexOf('=');
          if (idx == -1) continue;
          final key = line.substring(0, idx).trim();
          var val = line.substring(idx + 1).trim();
          // Remover aspas se existirem
          if (val.startsWith('"') && val.endsWith('"')) {
            val = val.substring(1, val.length - 1);
          } else if (val.startsWith("'") && val.endsWith("'")) {
            val = val.substring(1, val.length - 1);
          }
          values[key] = val;
        }
        debugPrint('>>> [EnvConfig] ✅ Arquivo .env carregado com sucesso (${values.length} variáveis)');
      } else {
        debugPrint('>>> [EnvConfig] ⚠️ Arquivo .env não encontrado no diretório atual (${Directory.current.path})');
      }
    } catch (e) {
      debugPrint('>>> [EnvConfig] ❌ Erro ao ler arquivo .env: $e');
    }
    return values;
  }

  // Getters para PostgreSQL
  static String get dbHost => env['DB_HOST'] ?? 'localhost';
  static int get dbPort => int.tryParse(env['DB_PORT'] ?? '') ?? 5432;
  static String get dbName => env['DB_NAME'] ?? 'exodo_db';
  static String get dbUser => env['DB_USER'] ?? 'exodo_user';
  static String get dbPassword => env['DB_PASSWORD'] ?? 'senha123';
}
