import 'dart:io';
import 'package:flutter/foundation.dart';
import 'process_utils.dart';
import 'win32_process_helper.dart';

/// Gerencia o executável SincronizadorNuvem.exe
class SincronizadorManagerService {
  static const String _syncExecutable = 'SincronizadorNuvem.exe';

  /// Locais onde o executável pode estar (mesma lógica do BridgeManager)
  static Future<List<String>> _getPossiblePaths() async {
    final resolved = File(Platform.resolvedExecutable).parent.path;
    final paths = <String>[
      // Na pasta do executável (padrão)
      '${Directory.current.path}\\$_syncExecutable',
      '${resolved}\\$_syncExecutable',
      // Em subpasta dist/
      '${Directory.current.path}\\dist\\$_syncExecutable',
      '${resolved}\\dist\\$_syncExecutable',
      // Console variant
      '${Directory.current.path}\\SincronizadorNuvemConsole.exe',
      '${resolved}\\SincronizadorNuvemConsole.exe',
      '${Directory.current.path}\\dist\\SincronizadorNuvemConsole.exe',
      '${resolved}\\dist\\SincronizadorNuvemConsole.exe',
      // Fallback para PATH
      _syncExecutable,
    ];

    // Buscar tambem em diretórios pais (caso o app rode de build/.../Release/)
    final dir = Directory(resolved);
    var parent = dir.parent;
    for (int i = 0; i < 6; i++) {
      paths.add('${parent.path}\\$_syncExecutable');
      paths.add('${parent.path}\\dist\\$_syncExecutable');
      paths.add('${parent.path}\\SincronizadorNuvemConsole.exe');
      if (parent.path == parent.parent.path) break; // raiz do disco
      parent = parent.parent;
    }

    return paths;
  }

  /// Procura o executável em todos os locais possíveis
  static Future<String?> _findExecutable() async {
    final paths = await _getPossiblePaths();
    for (final path in paths) {
      if (await File(path).exists()) {
        debugPrint('>>> [SincronizadorManager] ✅ Executável encontrado em: $path');
        return path;
      }
    }
    debugPrint('>>> [SincronizadorManager] ❌ SincronizadorNuvem.exe não encontrado em nenhum local');
    debugPrint('>>> [SincronizadorManager] 📁 Locais verificados: $paths');
    return null;
  }

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

  /// Mutex para evitar múltiplas inicializações simultâneas
  static bool _iniciando = false;
  
  /// Inicia o SincronizadorNuvem.exe se ele não estiver rodando
  static Future<bool> startSincronizador() async {
    if (kIsWeb || !Platform.isWindows) return false;
    
    // Evitar múltiplas inicializações simultâneas (race condition)
    if (_iniciando) {
      debugPrint('>>> [SincronizadorManager] ⏳ Inicialização já em andamento, ignorando...');
      return true;
    }
    _iniciando = true;
    
    try {
      if (await isSincronizadorRunning()) {
        debugPrint('>>> [SincronizadorManager] ✅ Sincronizador já está rodando');
        return true;
      }

      // 1. Procurar executável em múltiplos locais
      final execPath = await _findExecutable();
      if (execPath == null) return false;

      final dir = File(execPath).parent.path;
      debugPrint('>>> [SincronizadorManager] 🚀 Iniciando Sincronizador em: $execPath');

      // 2. Usar Win32 API para iniciar sem janela CMD
      final pid = Win32ProcessHelper.startProcessHidden(execPath, workingDirectory: dir);
      if (pid == null) {
        debugPrint('>>> [SincronizadorManager] ⚠️ Win32 falhou, tentando fallback...');
        await Process.start(execPath, [], mode: ProcessStartMode.normal, workingDirectory: dir);
      }

      // 3. Aguardar inicialização com retries (máximo 10s)
      for (int i = 0; i < 5; i++) {
        await Future.delayed(const Duration(seconds: 2));
        if (await isSincronizadorRunning()) {
          debugPrint('>>> [SincronizadorManager] ✅ Sincronizador iniciado com sucesso (tentativa ${i + 1})');
          return true;
        }
      }

      debugPrint('>>> [SincronizadorManager] ⚠️ Sincronizador pode estar iniciando...');
      return true;
    } catch (e) {
      debugPrint('>>> [SincronizadorManager] ❌ Erro ao iniciar sincronizador: $e');
      return false;
    } finally {
      _iniciando = false;
    }
  }
}
