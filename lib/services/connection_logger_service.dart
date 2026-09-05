import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Serviço persistente para registrar logs locais quando a internet cai ou quando há erros
class ConnectionLoggerService {
  static File? _logFile;

  static Future<void> _initFile() async {
    if (_logFile != null) return;
    if (kIsWeb) return;

    try {
      final appDir = await getApplicationSupportDirectory();
      final logPath = p.join(appDir.path, 'connection_logs.txt');
      _logFile = File(logPath);
      if (!await _logFile!.exists()) {
        await _logFile!.create(recursive: true);
        await _logFile!.writeAsString('=== INÍCIO DO LOG DE CONEXÃO E NUVEM ===\n');
      }
    } catch (e) {
      debugPrint('>>> [ConnectionLogger] Erro ao inicializar arquivo de log: $e');
    }
  }

  /// Registra uma mensagem de log com timestamp no arquivo físico
  static Future<void> log(String message) async {
    final now = DateTime.now().toLocal().toString();
    final logLine = '[$now] $message\n';
    debugPrint('>>> [ConnectionLogger] $logLine');

    if (kIsWeb) return;

    try {
      await _initFile();
      if (_logFile != null) {
        await _logFile!.writeAsString(logLine, mode: FileMode.append, flush: true);
      }
    } catch (e) {
      debugPrint('>>> [ConnectionLogger] Erro ao gravar log: $e');
    }
  }

  /// Retorna o conteúdo dos logs (últimas linhas)
  static Future<String> readLogs() async {
    if (kIsWeb) return 'Logs não disponíveis no navegador.';
    try {
      await _initFile();
      if (_logFile != null && await _logFile!.exists()) {
        return await _logFile!.readAsString();
      }
    } catch (_) {}
    return 'Nenhum log gravado.';
  }

  /// Limpa os logs
  static Future<void> clearLogs() async {
    if (kIsWeb) return;
    try {
      await _initFile();
      if (_logFile != null && await _logFile!.exists()) {
        await _logFile!.writeAsString('=== LOG REINICIADO ===\n');
      }
    } catch (_) {}
  }
}
