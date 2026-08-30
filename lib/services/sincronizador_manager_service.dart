import 'dart:io';
import 'package:flutter/foundation.dart';
import 'process_utils.dart';
import 'win32_process_helper.dart';

/// Gerencia o executável SincronizadorNuvem.exe
class SincronizadorManagerService {
  static const String _syncExecutable = 'SincronizadorNuvem.exe';
  
  /// Verifica se o Sincronizador está rodando pesquisando os processos do Windows
  static Future<bool> isSincronizadorRunning() async {
    if (kIsWeb || !Platform.isWindows) return false;
    try {
      final result = await runProcessHidden('tasklist', ['/FI', 'IMAGENAME eq $_syncExecutable']);
      return result.stdout.toString().contains(_syncExecutable);
    } catch (e) {
      debugPrint('>>> [SincronizadorManager] Erro ao checar processos: $e');
      return false;
    }
  }

  /// Inicia o SincronizadorNuvem.exe se ele não estiver rodando
  static Future<bool> startSincronizador() async {
    if (kIsWeb || !Platform.isWindows) return false;

    if (await isSincronizadorRunning()) {
      debugPrint('>>> [SincronizadorManager] ✅ Sincronizador já está rodando');
      return true;
    }

    try {
      // 1. Procurar na pasta raiz da aplicação
      final localFile = File(_syncExecutable);
      if (await localFile.exists()) {
        final path = localFile.absolute.path;
        final dir = localFile.absolute.parent.path;
        debugPrint('>>> [SincronizadorManager] 🚀 Iniciando Sincronizador em: $path');
        // Usar Win32 API para iniciar sem janela CMD
        final pid = Win32ProcessHelper.startProcessHidden(path, workingDirectory: dir);
        if (pid == null) {
          debugPrint('>>> [SincronizadorManager] ⚠️ Win32 falhou, tentando fallback...');
          await Process.start(path, [], mode: ProcessStartMode.detached, workingDirectory: dir);
        }
        return true;
      }
      
      debugPrint('>>> [SincronizadorManager] ❌ SincronizadorNuvem.exe não encontrado na pasta raiz');
      return false;
    } catch (e) {
      debugPrint('>>> [SincronizadorManager] ❌ Erro ao iniciar sincronizador: $e');
      return false;
    }
  }
}
