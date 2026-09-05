import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Serviço para validação de certificados usando o backend Node.js (Firebase Functions)
class CertificadoNodeService {
  static const String _defaultUrl = '/api'; // URL relativa para quando rodar no Firebase Hosting
  
  final String baseUrl;
  
  CertificadoNodeService({String? baseUrl})
      : baseUrl = baseUrl ?? (kIsWeb ? _defaultUrl : 'http://localhost:3000'); // Fallback para dev
  
  /// Processa um certificado PFX usando o backend Node.js
  Future<Map<String, dynamic>> processarCertificado({
    required List<int> bytes,
    required String senha,
  }) async {
    try {
      debugPrint('>>> [CertificadoNode] Enviando para processamento Node...');
      
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/processar-certificado'));
      request.fields['senha'] = senha;
      request.files.add(http.MultipartFile.fromBytes(
        'certificado',
        bytes,
        filename: 'certificado.pfx',
      ));
      
      var streamedResponse = await request.send().timeout(const Duration(seconds: 45));
      var response = await http.Response.fromStream(streamedResponse);
      
      debugPrint('>>> [CertificadoNode] Status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        debugPrint('>>> [CertificadoNode] ✓ Sucesso no processamento');
        return data;
      } else {
        final errorData = jsonDecode(response.body) as Map<String, dynamic>;
        throw Exception(errorData['erro'] ?? 'Erro no servidor Node');
      }
    } catch (e) {
      debugPrint('>>> [CertificadoNode] ❌ Erro: $e');
      rethrow;
    }
  }
}
