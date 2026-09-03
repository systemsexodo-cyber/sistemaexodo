import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions, BucketOptions;
import 'package:sistema_exodo_novo/services/supabase_service.dart';
import 'process_utils.dart';

class AppUpdateService {
  static const String currentAppVersion = "1.0.36";

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

  /// Publica uma atualização no Supabase (global ou por empresa).
  /// Faz upload do executável para o Storage e atualiza bridge_config.
  /// Retorna (sucesso, mensagem).
  static Future<(bool, String)> publicarAtualizacao({
    required String versao,
    String? empresaId, // null = global
    bool force = false,
  }) async {
    try {
      final dbVersion = force ? '!$versao' : versao;
      final isGlobal = empresaId == null || empresaId.isEmpty;
      final configId = isGlobal ? 'app_latest' : 'app_update_$empresaId';

      debugPrint('>>> [AppUpdateService] 📦 Publicando versão $dbVersion (${isGlobal ? "GLOBAL" : "EMPRESA: $empresaId"})');

      // 1. Localizar executável compilado
      final currentExePath = Platform.resolvedExecutable;
      final exeDir = p.dirname(currentExePath);
      
      // Procurar o .exe na pasta de release do build
      String localExe = p.join(exeDir, 'sistema_exodo_novo.exe');
      if (!await File(localExe).exists()) {
        // Fallback: procurar no build directory relativo ao projeto
        final projectDir = p.dirname(p.dirname(p.dirname(p.dirname(exeDir))));
        localExe = p.join(projectDir, 'build', 'windows', 'x64', 'runner', 'Release', 'sistema_exodo_novo.exe');
      }
      if (!await File(localExe).exists()) {
        return (false, 'Executável não encontrado. Compile com: flutter build windows --release');
      }

      final fileSize = await File(localExe).length();
      debugPrint('>>> [AppUpdateService] 📏 Tamanho: ${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB');

      // 2. Upload do executável para Supabase Storage
      debugPrint('>>> [AppUpdateService] 📤 Enviando para Supabase Storage...');
      
      final fileBytes = await File(localExe).readAsBytes();
      final bucketName = 'atualizacoes';
      final fileName = 'sistema_exodo_novo.exe';
      
      try {
        await SupabaseService.instance.client.storage
            .from(bucketName)
            .uploadBinary(fileName, fileBytes,
                fileOptions: const FileOptions(upsert: true));
      } catch (e) {
        // Se o bucket não existe, tentar criá-lo
        debugPrint('>>> [AppUpdateService] ⚠️ Erro no upload, tentando criar bucket...');
        try {
          await SupabaseService.instance.client.storage.createBucket(
            bucketName,
            const BucketOptions(public: true),
          );
          // Tentar novamente
          await SupabaseService.instance.client.storage
              .from(bucketName)
              .uploadBinary(fileName, fileBytes,
                  fileOptions: const FileOptions(upsert: true));
        } catch (e2) {
          return (false, 'Erro ao criar bucket ou fazer upload: $e2');
        }
      }

      final downloadUrl = SupabaseService.instance.client.storage
          .from(bucketName)
          .getPublicUrl(fileName);
      debugPrint('>>> [AppUpdateService] ✅ Upload concluído! URL: $downloadUrl');

      // 3. Atualizar bridge_config
      debugPrint('>>> [AppUpdateService] 💦 Atualizando bridge_config ($configId)...');
      
      final payload = {
        'id': configId,
        'version': dbVersion,
        'download_url': downloadUrl,
        'ativo': true,
      };

      // Tentar upsert (insert or update)
      try {
        await SupabaseService.instance.client
            .from('bridge_config')
            .upsert(payload, onConflict: 'id');
      } catch (e) {
        return (false, 'Erro ao salvar na bridge_config: $e');
      }

      // 4. Verificar
      final check = await SupabaseService.instance.client
          .from('bridge_config')
          .select()
          .eq('id', configId)
          .maybeSingle();

      if (check != null) {
        final msg = isGlobal
            ? '✅ Versão $versao publicada para TODOS os clientes!'
            : '✅ Versão $versao publicada para a empresa $empresaId!';
        debugPrint('>>> [AppUpdateService] $msg');
        return (true, msg);
      } else {
        return (false, 'Não foi possível confirmar o registro na bridge_config');
      }
    } catch (e) {
      debugPrint('>>> [AppUpdateService] ❌ Erro ao publicar: $e');
      return (false, 'Erro inesperado: $e');
    }
  }
}
