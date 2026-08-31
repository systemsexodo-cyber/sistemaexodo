import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'local_bridge_detector.dart';
import 'process_utils.dart';
import 'win32_process_helper.dart';

/// Gerencia o bridge NFC-e local (instalação, verificação, inicialização)
class BridgeManagerService {
  static const String _bridgeExecutable = 'ExodoNfceBridge.exe';
  static const String _defaultBridgePath = 'C:\\ExodoNFCe\\';
  
  /// Encerra processos do bridge que possam estar travando o arquivo
  static Future<void> _encerrarBridgeSeRodando() async {
    try {
      await runProcessDetached('taskkill', ['/F', '/IM', _bridgeExecutable]);
      await runProcessDetached('taskkill', ['/F', '/IM', 'ExodoNfceBridgeWatchdog.exe']);
      // Aguardar um segundo para liberar o lock do arquivo
      await Future.delayed(const Duration(seconds: 1));
    } catch (_) {}
  }

  /// Garante que o bridge está instalado em algum caminho válido copiando se necessário
  static Future<void> _garantirBridgeInstalado() async {
    if (kIsWeb) return;
    try {
      // Encontrar arquivo de origem nos caminhos locais do app
      String? origemValida;
      final caminhosOrigem = [
        '${Directory.current.path}\\backend_nfce\\dist\\ExodoNfceBridge.exe',
        '${File(Platform.resolvedExecutable).parent.path}\\backend_nfce\\dist\\ExodoNfceBridge.exe',
        '${Directory.current.path}\\backend_nfce\\dist\\ExodoNfceBridge_v355.exe',
        '${File(Platform.resolvedExecutable).parent.path}\\backend_nfce\\dist\\ExodoNfceBridge_v355.exe',
        '${Directory.current.path}\\bridge\\ExodoNfceBridge.exe',
        '${File(Platform.resolvedExecutable).parent.path}\\bridge\\ExodoNfceBridge.exe',
        '${Directory.current.path}\\ExodoNfceBridge_v355.exe',
        '${File(Platform.resolvedExecutable).parent.path}\\ExodoNfceBridge_v355.exe',
        _bridgeExecutable,
        '${Directory.current.path}\\$_bridgeExecutable',
        '${Directory.current.path}\\dist\\$_bridgeExecutable',
        '${File(Platform.resolvedExecutable).parent.path}\\$_bridgeExecutable',
        '${File(Platform.resolvedExecutable).parent.path}\\dist\\$_bridgeExecutable',
      ];

      for (final origem in caminhosOrigem) {
        if (await File(origem).exists()) {
          origemValida = origem;
          break;
        }
      }

      if (origemValida == null) return; // Nenhuma origem encontrada

      final fileOrigem = File(origemValida);
      final numBytesOrigem = await fileOrigem.length();

      // 1. Tentar pasta padrão C:\ExodoNFCe\
      final defaultDest = _defaultBridgePath + _bridgeExecutable;
      final fileDefaultDest = File(defaultDest);
      
      bool precisaCopiarDefault = true;
      if (await fileDefaultDest.exists()) {
        final numBytesDest = await fileDefaultDest.length();
        if (numBytesDest == numBytesOrigem) {
          precisaCopiarDefault = false;
        }
      }

      if (precisaCopiarDefault) {
        try {
          await _encerrarBridgeSeRodando();
          await Directory(_defaultBridgePath).create(recursive: true);
          await fileOrigem.copy(defaultDest);
          debugPrint('>>> [BridgeManager] ✅ Bridge copiado/atualizado para C:\\ExodoNFCe (tamanho: $numBytesOrigem)');
          return;
        } catch (e) {
          debugPrint('>>> [BridgeManager] ⚠️ Sem permissão para criar C:\\ExodoNFCe, tentando AppData: $e');
        }
      } else {
        return; // Já está instalado e atualizado
      }

      // Se falhar, tenta copiar para AppData
      final appDataPath = await _getAppDataBridgePath();
      if (appDataPath != null) {
        final appDataFile = File(appDataPath);
        bool precisaCopiarAppData = true;
        if (await appDataFile.exists()) {
          final numBytesAppData = await appDataFile.length();
          if (numBytesAppData == numBytesOrigem) {
            precisaCopiarAppData = false;
          }
        }

        if (precisaCopiarAppData) {
          try {
            await _encerrarBridgeSeRodando();
            await Directory(appDataFile.parent.path).create(recursive: true);
            await fileOrigem.copy(appDataPath);
            debugPrint('>>> [BridgeManager] ✅ Bridge copiado/atualizado para AppData: $appDataPath (tamanho: $numBytesOrigem)');
          } catch (e) {
            debugPrint('>>> [BridgeManager] ❌ Erro ao copiar para AppData: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('>>> [BridgeManager] ❌ Erro ao garantir instalação do bridge: $e');
    }
  }

  /// Verifica se o bridge NFC-e está instalado
  static Future<bool> isBridgeInstalled() async {
    if (kIsWeb) return false;
    
    await _garantirBridgeInstalado();
    
    final paths = [
      _defaultBridgePath + _bridgeExecutable,
      await _getAppDataBridgePath(),
      '${Directory.current.path}\\backend_nfce\\dist\\ExodoNfceBridge.exe',
      '${File(Platform.resolvedExecutable).parent.path}\\backend_nfce\\dist\\ExodoNfceBridge.exe',
      '${Directory.current.path}\\backend_nfce\\dist\\ExodoNfceBridge_v355.exe',
      '${File(Platform.resolvedExecutable).parent.path}\\backend_nfce\\dist\\ExodoNfceBridge_v355.exe',
      '${Directory.current.path}\\bridge\\ExodoNfceBridge.exe',
      '${File(Platform.resolvedExecutable).parent.path}\\bridge\\ExodoNfceBridge.exe',
      '${Directory.current.path}\\ExodoNfceBridge_v355.exe',
      '${File(Platform.resolvedExecutable).parent.path}\\ExodoNfceBridge_v355.exe',
      _bridgeExecutable,
      '${Directory.current.path}\\$_bridgeExecutable',
      '${File(Platform.resolvedExecutable).parent.path}\\$_bridgeExecutable',
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
    
    await _garantirBridgeInstalado();
    
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
      final execDir = execFile.parent.path.isEmpty ? Directory.current.path : execFile.parent.path;
      debugPrint('>>> [BridgeManager] 🚀 Iniciando bridge em: $bridgePath (Diretório: $execDir)');
      
      // Usar Win32 API para iniciar sem janela CMD
      final pid = Win32ProcessHelper.startProcessHidden(
        bridgePath,
        workingDirectory: execDir,
      );
      if (pid == null) {
        debugPrint('>>> [BridgeManager] ❌ Win32 CreateProcess falhou, tentando fallback...');
        // Fallback: Process.start com detached
        await Process.start(
          bridgePath,
          [],
          mode: ProcessStartMode.detached,
          workingDirectory: execDir,
        );
      }
      
      // Aguardar o bridge iniciar o servidor HTTP (pode demorar)
      // Verificar com retries a cada 2 segundos, até 15 segundos no total
      for (int i = 0; i < 8; i++) {
        await Future.delayed(const Duration(seconds: 2));
        final isRunning = await isBridgeRunning();
        if (isRunning) {
          debugPrint('>>> [BridgeManager] ✅ Bridge iniciado com sucesso (tentativa ${i + 1})');
          return true;
        }
      }
      debugPrint('>>> [BridgeManager] ❌ Bridge não respondeu após 16s de tentativas');
      return false;
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
      '${Directory.current.path}\\backend_nfce\\dist\\ExodoNfceBridge.exe',
      '${File(Platform.resolvedExecutable).parent.path}\\backend_nfce\\dist\\ExodoNfceBridge.exe',
      '${Directory.current.path}\\backend_nfce\\dist\\ExodoNfceBridge_v355.exe',
      '${File(Platform.resolvedExecutable).parent.path}\\backend_nfce\\dist\\ExodoNfceBridge_v355.exe',
      '${Directory.current.path}\\bridge\\ExodoNfceBridge.exe',
      '${File(Platform.resolvedExecutable).parent.path}\\bridge\\ExodoNfceBridge.exe',
      '${Directory.current.path}\\ExodoNfceBridge_v355.exe',
      '${File(Platform.resolvedExecutable).parent.path}\\ExodoNfceBridge_v355.exe',
      _bridgeExecutable,
      '${Directory.current.path}\\$_bridgeExecutable',
      '${File(Platform.resolvedExecutable).parent.path}\\$_bridgeExecutable',
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
