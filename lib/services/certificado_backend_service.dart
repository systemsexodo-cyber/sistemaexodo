import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Serviço para validação de certificados usando o backend Python
class CertificadoBackendService {
  static const String _defaultBackendUrl = 'http://localhost:5000';
  
  final String backendUrl;
  
  CertificadoBackendService({String? backendUrl})
      : backendUrl = backendUrl ?? _defaultBackendUrl;
  
  /// Valida um certificado digital usando o backend Python
  /// 
  /// Retorna um mapa com:
  /// - success: bool - se a validação foi bem-sucedida
  /// - valido: bool - se o certificado está válido (não expirado)
  /// - cnpj: String? - CNPJ extraído do certificado
  /// - validade: String? - data de validade em ISO format
  /// - dias_restantes: int? - dias restantes até expirar
  /// - subject: String? - informações do subject do certificado
  /// - error: String? - mensagem de erro se houver
  Future<Map<String, dynamic>> validarCertificado({
    required String certificadoBase64,
    required String senha,
  }) async {
    try {
      debugPrint('>>> [CertificadoBackend] Validando certificado via backend Python...');
      debugPrint('>>> [CertificadoBackend] URL: $backendUrl/api/certificado/validar');
      debugPrint('>>> [CertificadoBackend] Tamanho base64: ${certificadoBase64.length} chars');
      
      final response = await http.post(
        Uri.parse('$backendUrl/api/certificado/validar'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'certificado_base64': certificadoBase64,
          'senha': senha,
        }),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Timeout ao validar certificado. O backend pode estar demorando para responder.');
        },
      );
      
      debugPrint('>>> [CertificadoBackend] Status: ${response.statusCode}');
      debugPrint('>>> [CertificadoBackend] Response: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        debugPrint('>>> [CertificadoBackend] ✓ Certificado validado com sucesso');
        return data;
      } else if (response.statusCode == 503) {
        // Serviço não disponível (PyNFe não instalado)
        debugPrint('>>> [CertificadoBackend] ⚠️ Serviço não disponível (503)');
        return {
          'success': false,
          'error': 'Serviço de certificado não disponível no backend. Verifique se o backend está rodando e se as dependências estão instaladas.',
          'fallback': true,
        };
      } else {
        final errorData = jsonDecode(response.body) as Map<String, dynamic>;
        debugPrint('>>> [CertificadoBackend] ❌ Erro: ${errorData['error']}');
        return {
          'success': false,
          'error': errorData['error'] ?? 'Erro desconhecido ao validar certificado',
        };
      }
    } catch (e) {
      debugPrint('>>> [CertificadoBackend] ❌ Exceção ao validar certificado: $e');
      
      // Se for erro de conexão, indicar que deve usar fallback
      if (e.toString().contains('Failed host lookup') ||
          e.toString().contains('Connection refused') ||
          e.toString().contains('SocketException')) {
        return {
          'success': false,
          'error': 'Não foi possível conectar ao backend Python. Verifique se o servidor está rodando em $backendUrl',
          'fallback': true,
        };
      }
      
      return {
        'success': false,
        'error': 'Erro ao validar certificado: $e',
      };
    }
  }
  
  /// Verifica se o backend está disponível
  Future<bool> verificarDisponibilidade() async {
    try {
      final response = await http.get(
        Uri.parse('$backendUrl/health'),
      ).timeout(const Duration(seconds: 5));
      
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('>>> [CertificadoBackend] Backend não disponível: $e');
      return false;
    }
  }
}


