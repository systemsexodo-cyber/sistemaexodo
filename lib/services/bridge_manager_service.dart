import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'local_bridge_detector.dart';

/// Gerencia o bridge NFC-e local (instalação, verificação, inicialização)
class BridgeManagerService {
  static const String _bridgeExecutable = 'ExodoNfceBridge.exe';
  static const String _defaultBridgePath = 'C:\\ExodoNFCe\\';
  
  /// Verifica se o bridge NFC-e está instalado
  static Future<bool> isBridgeInstalled() async {
    if (kIsWeb) return false;
    
    final paths = [
      _defaultBridgePath + _bridgeExecutable,
      await _getAppDataBridgePath(),
      _bridgeExecutable, // Se estiver no PATH
    ];

    for (final path in paths) {
      if (path == null) continue;
      if (await File(path).exists()) {
        debugPrint('>>> [BridgeManager] ✅ Bridge encontrado em: $path');
        return true;
      }
    }

    debugPrint('>>> [BridgeManager] ❌ Bridge não encontrado');
    return false;
  }

  /// Obtém o caminho do bridge na pasta AppData
  static Future<String?> _getAppDataBridgePath() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      return '${appDir.path}\\$_bridgeExecutable';
    } catch (e) {
      return null;
    }
  }

  /// Verifica se o bridge está rodando
  static Future<bool> isBridgeRunning() async {
    return await LocalBridgeDetector.isDefaultBridgeRunning();
  }

  /// Inicia o bridge NFC-e (se estiver instalado)
  static Future<bool> startBridge() async {
    if (kIsWeb) return false;
    
    if (!await isBridgeInstalled()) {
      debugPrint('>>> [BridgeManager] ❌ Bridge não está instalado');
      return false;
    }

    if (await isBridgeRunning()) {
      debugPrint('>>> [BridgeManager] ✅ Bridge já está rodando');
      return true;
    }

    try {
      final bridgePath = await _findBridgeExecutable();
      if (bridgePath == null) return false;
      
      final execFile = File(bridgePath);
      final execDir = execFile.parent.path;
      debugPrint('>>> [BridgeManager] 🚀 Iniciando bridge em: $bridgePath (Diretório: $execDir)');
      
      await Process.start(
        bridgePath,
        [],
        mode: ProcessStartMode.detached,
        workingDirectory: execDir,
      );
      
      // Aguardar alguns segundos para o bridge iniciar
      await Future.delayed(const Duration(seconds: 3));
      
      final isRunning = await isBridgeRunning();
      if (isRunning) {
        debugPrint('>>> [BridgeManager] ✅ Bridge iniciado com sucesso');
      } else {
        debugPrint('>>> [BridgeManager] ❌ Falha ao iniciar bridge');
      }
      
      return isRunning;
    } catch (e) {
      debugPrint('>>> [BridgeManager] ❌ Erro ao iniciar bridge: $e');
      return false;
    }
  }

  /// Encontra o executável do bridge
  static Future<String?> _findBridgeExecutable() async {
    final paths = [
      _defaultBridgePath + _bridgeExecutable,
      await _getAppDataBridgePath(),
    ];

    for (final path in paths) {
      if (path != null && await File(path).exists()) {
        return path;
      }
    }

    return null;
  }

  /// Obtém o status completo do bridge
  static Future<BridgeStatus> getBridgeStatus() async {
    final isInstalled = await isBridgeInstalled();
    final isRunning = isInstalled ? await isBridgeRunning() : false;
    final bridgeUrl = isRunning ? await LocalBridgeDetector.detectBridgeUrl() : null;

    return BridgeStatus(
      isInstalled: isInstalled,
      isRunning: isRunning,
      url: bridgeUrl,
      executablePath: isInstalled ? await _findBridgeExecutable() : null,
    );
  }

  /// Mostra instruções para o cliente instalar o bridge
  static String getInstallationInstructions() {
    return '''
📋 INSTRUÇÕES - INSTALAÇÃO DO EMISSOR NFC-e LOCAL

1️⃣ BAIXAR O BRIDGE:
• Faça download do arquivo: ExodoNfceBridge.exe
• Link de download: [FORNECIDO PELO SUPORTE]

2️⃣ INSTALAR:
• Crie a pasta: C:\\ExodoNFCe\\
• Copie o ExodoNfceBridge.exe para esta pasta

3️⃣ EXECUTAR:
• Dê duplo clique no ExodoNfceBridge.exe
• Mantenha o programa aberto enquanto usa o sistema

4️⃣ CONFIGURAR FIREWALL (se necessário):
• Permita acesso na rede privada para o ExodoNfceBridge.exe
• Porta padrão: 8000

✅ PRONTO! O sistema detectará automaticamente o bridge.
''';
  }
}

/// Status do bridge NFC-e
class BridgeStatus {
  final bool isInstalled;
  final bool isRunning;
  final String? url;
  final String? executablePath;

  BridgeStatus({
    required this.isInstalled,
    required this.isRunning,
    this.url,
    this.executablePath,
  });

  @override
  String toString() {
    return 'BridgeStatus(installed: $isInstalled, running: $isRunning, url: $url)';
  }
}
