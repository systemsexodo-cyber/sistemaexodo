import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sistema_exodo_novo/services/supabase_service.dart';

class AppUpdateService {
  static const String currentAppVersion = "1.0.10";

  /// Verifica se há uma nova versão do aplicativo no Supabase
  static Future<Map<String, dynamic>?> verificarAtualizacao() async {
    if (kIsWeb) return null; // Web não se auto-atualiza via arquivo local
    if (!Platform.isWindows) return null; // Apenas Windows por enquanto

    try {
      final response = await SupabaseService.instance.select(
        'bridge_config',
        filters: {'id': 'app_latest'},
      );

      if (response.isEmpty) return null;

      final config = response.first;
      final String nuverVersion = config['version'] ?? '';
      final String downloadUrl = config['download_url'] ?? '';

      if (nuverVersion.isEmpty || downloadUrl.isEmpty) return null;

      // Comparar versões de forma semântica simples
      if (_deveAtualizar(currentAppVersion, nuverVersion)) {
        return {
          'version': nuverVersion,
          'download_url': downloadUrl,
        };
      }
    } catch (e) {
      debugPrint('>>> [AppUpdateService] Erro ao verificar atualização: $e');
    }
    return null;
  }

  /// Compara se a versão remota é maior que a versão local
  static bool _deveAtualizar(String local, String remota) {
    try {
      final localParts = local.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final remotaParts = remota.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      for (int i = 0; i < localParts.length && i < remotaParts.length; i++) {
        if (remotaParts[i] > localParts[i]) return true;
        if (remotaParts[i] < localParts[i]) return false;
      }
      // Se forem iguais nas partes comuns, mas a remota tiver mais segmentos (ex: 1.0.8 vs 1.0.8.1)
      if (remotaParts.length > localParts.length) {
        for (int i = localParts.length; i < remotaParts.length; i++) {
          if (remotaParts[i] > 0) return true;
        }
      }
    } catch (e) {
      debugPrint('>>> [AppUpdateService] Erro na comparação de versão: $e');
    }
    return false;
  }

  /// Faz download e dispara o instalador/executável atualizado
  static Future<bool> baixarEAplicarAtualizacao(String downloadUrl, Function(double) onProgress) async {
    try {
      final currentExePath = Platform.resolvedExecutable;
      final exeDir = p.dirname(currentExePath);
      final newExePath = p.join(exeDir, 'sistema_exodo_novo.exe.new');
      final batPath = p.join(exeDir, 'self_update_app.bat');

      debugPrint('>>> [AppUpdateService] Baixando de: $downloadUrl');
      debugPrint('>>> [AppUpdateService] Destino: $newExePath');

      // Fazer download em chunks para notificar o progresso
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Erro HTTP ao baixar arquivo: ${response.statusCode}');
      }

      final contentLength = response.contentLength ?? 0;
      int downloaded = 0;
      final file = File(newExePath);
      final sink = file.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloaded += chunk.length;
        if (contentLength > 0) {
          final progress = downloaded / contentLength;
          onProgress(progress);
        }
      }

      await sink.close();
      client.close();

      // Escrever o script BAT para fazer a substituição do executável
      final batContent = '''
@echo off
title Atualizando Sistema Exodo
echo Aguardando o aplicativo fechar...
timeout /t 2 /nobreak >nul
taskkill /F /IM sistema_exodo_novo.exe >nul 2>&1
timeout /t 1 /nobreak >nul
move /Y "$newExePath" "$currentExePath"
echo Iniciando nova versao...
start "" "$currentExePath"
del "%~f0"
''';
      await File(batPath).writeAsString(batContent);

      debugPrint('>>> [AppUpdateService] Executando script de swap e fechando...');
      // Disparar o BAT
      await Process.start('cmd.exe', ['/c', batPath], runInShell: true);
      // Fechar a si mesmo imediatamente
      exit(0);
    } catch (e) {
      debugPrint('>>> [AppUpdateService] Erro ao aplicar atualização: $e');
      return false;
    }
  }
}
