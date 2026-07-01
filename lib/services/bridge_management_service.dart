import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'supabase_service.dart';

class BridgeCommand {
  final String id;
  final String comando;
  final String status;
  final String? resultado;
  final bool? sucesso;
  final DateTime? createdAt;
  final String? pcName;

  BridgeCommand({
    required this.id,
    required this.comando,
    required this.status,
    this.resultado,
    this.sucesso,
    this.createdAt,
    this.pcName,
  });

  factory BridgeCommand.fromMap(Map<String, dynamic> data) {
    return BridgeCommand(
      id: data['id']?.toString() ?? '',
      comando: data['comando'] ?? '',
      status: data['status'] ?? '',
      resultado: data['resultado'],
      sucesso: data['sucesso'] == true,
      createdAt: data['created_at'] != null 
          ? DateTime.tryParse(data['created_at']) 
          : null,
      pcName: data['pc_name'],
    );
  }
}

class BridgeManagementService {
  static final BridgeManagementService instance = BridgeManagementService._();
  BridgeManagementService._();

  /// Envia um comando para todos os bridges ou um específico
  Future<String> enviarComando(String comando, {String? targetPc, Map<String, dynamic>? extraData}) async {
    try {
      final Map<String, dynamic> data = {
        'comando': comando,
        'status': 'pendente',
        'target_pc': targetPc,
      };

      if (extraData != null) {
        data['extra_data'] = extraData;
      }

      final response = await SupabaseService.instance.insert('bridge_commands', data);
      debugPrint('>>> [BridgeManager] Comando "$comando" enviado via Supabase');
      return response['id']?.toString() ?? '';
    } catch (e) {
      debugPrint('❌ Erro ao enviar comando bridge: $e');
      rethrow;
    }
  }

  /// Atalho para enviar update para todos
  Future<void> atualizarTodos() async {
    await enviarComando('update');
  }

  /// Atalho para reiniciar todos
  Future<void> reiniciarTodos() async {
    await enviarComando('restart');
  }
  
  /// Atalho para identificar bridges
  Future<void> identificarBridges() async {
    await enviarComando('identify');
  }

  Future<void> subirNovaVersaoBridge(PlatformFile file, String version, String configId, Function(double) onProgress) async {
    if (file.bytes == null) {
      throw Exception('O arquivo selecionado está vazio ou não pôde ser lido.');
    }

    try {
      String pathPrefix = 'bridge_updates';
      String filenamePrefix = 'ExodoNfceBridge';
      
      if (configId == 'app_latest') {
        pathPrefix = 'app_updates';
        filenamePrefix = 'sistema_exodo_novo';
      } else if (configId == 'sync_latest') {
        pathPrefix = 'sync_updates';
        filenamePrefix = 'SincronizadorNuvem';
      }

      final fileName = '$pathPrefix/${filenamePrefix}_v$version.exe';
      
      onProgress(0.1);
      
      // Upload para Supabase Storage
      final downloadUrl = await SupabaseService.instance.uploadFile(
        'configuracoes', // Usando um bucket de configurações/arquivos de sistema
        fileName,
        file.bytes,
        contentType: 'application/x-msdownload',
      );

      if (downloadUrl == null) {
        throw Exception('Falha ao subir arquivo para o Supabase Storage');
      }

      onProgress(0.9);

      // Atualizar bridge_config no Supabase (upsert)
      await SupabaseService.instance.upsert('bridge_config', {
        'id': configId,
        'version': version,
        'download_url': downloadUrl,
        'updated_at': DateTime.now().toIso8601String(),
      });

      onProgress(1.0);
      debugPrint('>>> [BridgeManager] Versão $version ($configId) enviada com sucesso! URL: $downloadUrl');
    } catch (e) {
      debugPrint('>>> [BridgeManager] Erro no upload da nova versão: $e');
      rethrow;
    }
  }
}
