import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sistema_exodo_novo/services/supabase_service.dart';
import 'process_utils.dart';

class AppUpdateService {
  static const String currentAppVersion = "1.0.35";

  /// Verifica se há uma nova versão do aplicativo no Supabase (Direcionada por Empresa ou Global)
  static Future<Map<String, dynamic>?> verificarAtualizacao({
    String? empresaId,
    Map<String, dynamic>? configsEmpresa,
  }) async {
    if (kIsWeb) return null; // Web não se auto-atualiza via arquivo local
    if (!Platform.isWindows) return null; // Apenas Windows por enquanto

    try {
      // 1. PRIMEIRO: Checar no Supabase se há atualização direcionada para esta empresa
      if (empresaId != null && empresaId.isNotEmpty) {
        final respEmpresa = await SupabaseService.instance.select(
          'bridge_config',
          filters: {'id': 'app_update_$empresaId'},
        ).timeout(const Duration(seconds: 3));

        if (respEmpresa.isNotEmpty) {
          final config = respEmpresa.first;
          final String vRemota = config['version'] ?? '';
          final String downloadUrl = config['download_url'] ?? '';
          final bool ativa = config['ativo'] ?? true;

          if (ativa && vRemota.isNotEmpty && downloadUrl.isNotEmpty) {
            if (_deveAtualizar(currentAppVersion, vRemota)) {
              return {
                'version': _limparVersao(vRemota),
                'download_url': downloadUrl,
                'is_direcionada': true,
              };
            }
          }
        }
      }

      // 2. SEGUNDO: Checar nas configurações da empresa local
      if (configsEmpresa != null && configsEmpresa['atualizacao_ativa'] == true) {
        final String vRemota = configsEmpresa['versao_alvo'] ?? '';
        final String downloadUrl = configsEmpresa['update_download_url'] ?? '';

        if (vRemota.isNotEmpty && downloadUrl.isNotEmpty) {
          if (_deveAtualizar(currentAppVersion, vRemota)) {
            return {
              'version': _limparVersao(vRemota),
              'download_url': downloadUrl,
              'is_direcionada': true,
            };
          }
        }
      }

      // 3. TERCEIRO: Fallback para versão global no Supabase se a empresa permitir atualização global
      final bool bloqueiaAtualizacaoGlobal = configsEmpresa?['bloquear_atualizacao_global'] == true;
      if (!bloqueiaAtualizacaoGlobal) {
        final response = await SupabaseService.instance.select(
          'bridge_config',
          filters: {'id': 'app_latest'},
        ).timeout(const Duration(seconds: 3));

        if (response.isNotEmpty) {
          final config = response.first;
          final String nuverVersion = config['version'] ?? '';
          final String downloadUrl = config['download_url'] ?? '';

          if (nuverVersion.isNotEmpty && downloadUrl.isNotEmpty) {
            if (_deveAtualizar(currentAppVersion, nuverVersion)) {
              return {
                'version': _limparVersao(nuverVersion),
                'download_url': downloadUrl,
                'is_direcionada': false,
              };
            }
          }
        }
      }
    } catch (e) {
      debugPrint('>>> [AppUpdateService] Erro ao verificar atualização: $e');
    }
    return null;
  }

  /// Remove o prefixo de força '!' da versão, se presente
  static String _limparVersao(String v) => v.startsWith('!') ? v.substring(1) : v;

  /// Compara se a versão remota é maior que a versão local
  /// Se a versão remota começar com '!', força a atualização (suporta downgrade)
  static bool _deveAtualizar(String local, String remota) {
    try {
      // Verificar se é atualização forçada (downgrade prefixado com '!')
      final bool isForced = remota.startsWith('!');
      if (isForced) {
        remota = remota.substring(1); // Remove o prefixo '!'
        return true; // Força a atualização independente da versão
      }

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
      // Disparar o BAT sem janela CMD
      await Process.start('cmd.exe', ['/c', batPath], mode: ProcessStartMode.detached);
      // Fechar a si mesmo imediatamente
      exit(0);
    } catch (e) {
      debugPrint('>>> [AppUpdateService] Erro ao aplicar atualização: $e');
      return false;
    }
  }
}
