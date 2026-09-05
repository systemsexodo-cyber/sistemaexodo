import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'supabase_service.dart';

/// Serviço para armazenar imagens migrado para Supabase
class ImageStorageService {
  static const String _bucket = 'imagens';

  /// Salva uma imagem no Supabase Storage e o metadado no DB
  static Future<String> salvarImagem({
    required Uint8List imageBytes,
    required String empresaId,
    required String categoria,
    String? nome,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String finalName = nome != null 
          ? nome.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_') 
          : 'img_$timestamp';
      
      final String storagePath = '$categoria/$empresaId/${finalName}_$timestamp.jpg';
 
      debugPrint('>>> [ImageStorage] Salvando imagem no Supabase: $storagePath');
 
      final url = await SupabaseService.instance.uploadFile(
        _bucket,
        storagePath,
        imageBytes,
        contentType: 'image/jpeg',
      );
 
      if (url == null) {
        throw Exception('Falha ao subir imagem para o Supabase Storage');
      }
 
      // Salvar metadados no Banco de Dados
      await SupabaseService.instance.insert('imagens', {
        'empresa_id': empresaId,
        'categoria': categoria,
        'nome': nome ?? finalName,
        'url': url,
        'tamanho_bytes': imageBytes.length,
      });
 
      return url; // Retorna a URL pública
    } catch (e) {
      debugPrint('>>> [ImageStorage] ❌ ERRO ao salvar imagem: $e');
      rethrow;
    }
  }
 
  /// Salva e retorna a URL
  static Future<String> salvarImagemERetornarUrl({
    required Uint8List imageBytes,
    required String empresaId,
    required String categoria,
    String? nome,
    Map<String, dynamic>? metadata,
  }) async {
    return await salvarImagem(
      imageBytes: imageBytes,
      empresaId: empresaId,
      categoria: categoria,
      nome: nome,
      metadata: metadata,
    );
  }

  /// Lista imagens de uma empresa/categoria via Supabase
  static Future<List<Map<String, dynamic>>> listarImagens({
    required String empresaId,
    String? categoria,
  }) async {
    try {
      final Map<String, dynamic> filters = {'empresa_id': empresaId};
      if (categoria != null) filters['categoria'] = categoria;

      final results = await SupabaseService.instance.select(
        'imagens',
        filters: filters,
        orderBy: 'created_at',
        descending: true,
      );

      return results.map((item) => {
        'id': item['url'], // Usando URL como ID para deleção fácil
        'nome': item['nome'],
        'url': item['url'],
        'categoria': item['categoria'],
        'tamanhoBytes': item['tamanho_bytes'],
        'dataUpload': item['created_at'] != null ? DateTime.parse(item['created_at']) : null,
      }).toList();
    } catch (e) {
      debugPrint('>>> [ImageStorage] Erro ao listar: $e');
      return [];
    }
  }

  /// Deleta uma imagem do Storage e do Banco
  static Future<bool> deletarImagem(String url) async {
    try {
      // 1. Deletar do Banco de Dados
      await SupabaseService.instance.delete('imagens', {'url': url});

      // 2. Deletar do Storage
      if (url.contains('supabase.co')) {
        final uri = Uri.parse(url);
        final pathSegments = uri.pathSegments;
        if (pathSegments.length > 2) {
           // O path no Supabase Storage geralmente começa após o nome do bucket
           // v1/object/public/bucket/PATH
           final storagePath = pathSegments.skip(5).join('/'); 
           await SupabaseService.instance.deleteFile(_bucket, storagePath);
        }
      }
      return true;
    } catch (e) {
      debugPrint('>>> [ImageStorage] Erro ao deletar imagem: $e');
      return false;
    }
  }

  /// Obtém imagem (Alias para manter compatibilidade)
  static Future<String?> obterImagem(String idOuUrl) async {
    return idOuUrl;
  }
  
  /// Calcula estatísticas de uso via Banco
  static Future<Map<String, dynamic>> obterEstatisticas(String empresaId) async {
    try {
      final results = await SupabaseService.instance.select(
        'imagens',
        filters: {'empresa_id': empresaId},
      );

      int total = results.length;
      int bytes = 0;
      for (var item in results) {
        bytes += (item['tamanho_bytes'] as int? ?? 0);
      }

      return {
        'totalImagens': total,
        'tamanhoTotalMB': (bytes / (1024 * 1024)).toStringAsFixed(2),
      };
    } catch (e) {
      debugPrint('>>> [ImageStorage] Erro nas estatísticas: $e');
      return {'totalImagens': 0, 'tamanhoTotalMB': '0.00'};
    }
  }
}
