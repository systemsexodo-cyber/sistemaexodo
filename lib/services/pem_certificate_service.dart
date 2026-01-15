import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:asn1lib/asn1lib.dart';
import 'pkcs12_service.dart';

/// Serviço para processar certificados em formato PEM
/// Extrai chave privada RSA e certificado X509
class PEMCertificateService {
  /// Processa arquivo PEM completo (certificado + chave privada)
  static Future<Map<String, dynamic>> processarPEM(String pemContent, String senha) async {
    try {
      debugPrint('>>> [PEM] ========================================');
      debugPrint('>>> [PEM] Processando arquivo PEM...');
      debugPrint('>>> [PEM] Tamanho do conteúdo: ${pemContent.length} caracteres');
      debugPrint('>>> [PEM] ========================================');
      
      // Verificar se tem certificado
      final temCertificado = pemContent.contains('-----BEGIN CERTIFICATE-----');
      final temChaveRSA = pemContent.contains('-----BEGIN RSA PRIVATE KEY-----');
      final temChavePrivada = pemContent.contains('-----BEGIN PRIVATE KEY-----');
      
      debugPrint('>>> [PEM] Tem certificado: $temCertificado');
      debugPrint('>>> [PEM] Tem chave RSA: $temChaveRSA');
      debugPrint('>>> [PEM] Tem chave privada: $temChavePrivada');
      
      if (!temCertificado) {
        throw Exception('Certificado não encontrado no arquivo PEM.\n\n'
            'O arquivo deve conter um bloco:\n'
            '-----BEGIN CERTIFICATE-----\n'
            '...\n'
            '-----END CERTIFICATE-----');
      }
      
      if (!temChaveRSA && !temChavePrivada) {
        throw Exception('Chave privada não encontrada no arquivo PEM.\n\n'
            'O arquivo deve conter um bloco:\n'
            '-----BEGIN RSA PRIVATE KEY-----\n'
            'OU\n'
            '-----BEGIN PRIVATE KEY-----\n\n'
            'Se você converteu do PFX, certifique-se de usar:\n'
            'openssl pkcs12 -in certificado.pfx -out certificado.pem -nodes');
      }
      
      // Extrair chave privada
      debugPrint('>>> [PEM] Extraindo chave privada...');
      RSAPrivateKey privateKey;
      try {
        final key = _extrairChavePrivada(pemContent);
        if (key == null) {
          throw Exception('Não foi possível extrair a chave privada do arquivo PEM.');
        }
        privateKey = key;
      } catch (e) {
        debugPrint('>>> [PEM] Erro ao extrair chave privada: $e');
        rethrow;
      }
      
      // Extrair certificado
      debugPrint('>>> [PEM] Extraindo certificado...');
      Uint8List certificate;
      try {
        final cert = extrairCertificado(pemContent);
        if (cert == null) {
          throw Exception('Não foi possível extrair o certificado do arquivo PEM.');
        }
        certificate = cert;
      } catch (e) {
        debugPrint('>>> [PEM] Erro ao extrair certificado: $e');
        rethrow;
      }
      
      debugPrint('>>> [PEM] ✓✓✓ PEM processado com sucesso!');
      debugPrint('>>> [PEM] Chave privada: OK');
      debugPrint('>>> [PEM] Certificado: ${certificate.length} bytes');
      
      return {
        'privateKey': privateKey,
        'certificate': certificate,
      };
    } catch (e) {
      debugPrint('>>> [PEM] ERRO ao processar PEM: $e');
      debugPrint('>>> [PEM] Tipo do erro: ${e.runtimeType}');
      rethrow;
    }
  }
  
  /// Extrai chave privada RSA do conteúdo PEM
  static RSAPrivateKey? _extrairChavePrivada(String pemContent) {
    try {
      debugPrint('>>> [PEM] Extraindo chave privada...');
      
      // Procurar por diferentes formatos de chave privada
      final patterns = [
        RegExp(r'-----BEGIN RSA PRIVATE KEY-----(.*?)-----END RSA PRIVATE KEY-----', dotAll: true),
        RegExp(r'-----BEGIN PRIVATE KEY-----(.*?)-----END PRIVATE KEY-----', dotAll: true),
        RegExp(r'-----BEGIN ENCRYPTED PRIVATE KEY-----(.*?)-----END ENCRYPTED PRIVATE KEY-----', dotAll: true),
      ];
      
      String? keyBase64;
      bool isEncrypted = false;
      
      for (var pattern in patterns) {
        final match = pattern.firstMatch(pemContent);
        if (match != null) {
          keyBase64 = match.group(1)?.replaceAll(RegExp(r'\s'), '');
          isEncrypted = pattern.pattern.contains('ENCRYPTED');
          debugPrint('>>> [PEM] Chave privada encontrada (encrypted: $isEncrypted)');
          break;
        }
      }
      
      if (keyBase64 == null || keyBase64.isEmpty) {
        debugPrint('>>> [PEM] Chave privada não encontrada no PEM');
        return null;
      }
      
      if (isEncrypted) {
        throw Exception('Chave privada está criptografada. Use o comando OpenSSL com -nodes para gerar chave sem criptografia:\n'
            'openssl pkcs12 -in certificado.pfx -out certificado.pem -nodes');
      }
      
      // Decodificar base64
      final keyBytes = base64Decode(keyBase64);
      debugPrint('>>> [PEM] Chave privada decodificada: ${keyBytes.length} bytes');
      
      // Parsear chave privada RSA
      final parser = ASN1Parser(keyBytes);
      final sequence = parser.nextObject() as ASN1Sequence;
      
      final elements = sequence.elements;
      if (elements.length < 6) {
        throw Exception('Estrutura de chave privada RSA inválida');
      }
      
      // RSAPrivateKey { version, modulus, publicExponent, privateExponent, prime1, prime2, ... }
      final modulus = (elements[1] as ASN1Integer).valueAsBigInteger;
      final privateExponent = (elements[3] as ASN1Integer).valueAsBigInteger;
      final p = (elements[4] as ASN1Integer).valueAsBigInteger;
      final q = (elements[5] as ASN1Integer).valueAsBigInteger;
      
      final privateKey = RSAPrivateKey(
        modulus,
        privateExponent,
        p,
        q,
      );
      
      debugPrint('>>> [PEM] ✓ Chave privada RSA parseada com sucesso');
      return privateKey;
    } catch (e, stackTrace) {
      debugPrint('>>> [PEM] ERRO ao extrair chave privada: $e');
      debugPrint('>>> [PEM] Stack trace: $stackTrace');
      
      // Se for erro de estrutura, dar mensagem mais clara
      final erroStr = e.toString();
      if (erroStr.contains('Estrutura de chave privada RSA inválida') ||
          erroStr.contains('elements.length') ||
          erroStr.contains('ASN1Sequence')) {
        throw Exception('Chave privada no arquivo PEM está em formato inválido.\n\n'
            'O arquivo PEM pode estar corrompido ou em formato não suportado.\n\n'
            'SOLUÇÃO:\n'
            '1. Re-converta o certificado PFX para PEM:\n'
            '   openssl pkcs12 -in certificado.pfx -out certificado.pem -nodes -passin pass:SUA_SENHA\n\n'
            '2. Certifique-se de que o arquivo PEM contém:\n'
            '   • Certificado (-----BEGIN CERTIFICATE-----)\n'
            '   • Chave privada (-----BEGIN RSA PRIVATE KEY-----)\n\n'
            '3. Abra o arquivo PEM em um editor de texto e verifique se está completo.');
      }
      
      throw Exception('Erro ao processar chave privada do arquivo PEM: $e');
    }
  }
  
  /// Extrai certificado X509 do conteúdo PEM
  static Uint8List? extrairCertificado(String pemContent) {
    try {
      debugPrint('>>> [PEM] Extraindo certificado...');
      
      final pattern = RegExp(r'-----BEGIN CERTIFICATE-----(.*?)-----END CERTIFICATE-----', dotAll: true);
      final match = pattern.firstMatch(pemContent);
      
      if (match == null) {
        debugPrint('>>> [PEM] Certificado não encontrado no PEM');
        return null;
      }
      
      final certBase64 = match.group(1)?.replaceAll(RegExp(r'\s'), '');
      if (certBase64 == null || certBase64.isEmpty) {
        return null;
      }
      
      final certBytes = base64Decode(certBase64);
      debugPrint('>>> [PEM] ✓ Certificado extraído: ${certBytes.length} bytes');
      return certBytes;
    } catch (e) {
      debugPrint('>>> [PEM] ERRO ao extrair certificado: $e');
      return null;
    }
  }
  
  /// Extrai informações básicas (CNPJ, validade) do certificado
  static Future<Map<String, dynamic>> extrairInformacoesBasicas(String pemContent) async {
    try {
      final certBytes = extrairCertificado(pemContent);
      if (certBytes == null) {
        return {'cnpj': null, 'validade': null};
      }
      
      // Usar o mesmo método do PKCS12Service para extrair informações
      return await PKCS12Service.extrairInformacoesBasicas(certBytes);
    } catch (e) {
      debugPrint('>>> [PEM] ERRO ao extrair informações básicas: $e');
      return {'cnpj': null, 'validade': null};
    }
  }
  
  /// Valida se o conteúdo é um arquivo PEM válido
  static bool isValidPEM(String content) {
    return content.contains('-----BEGIN') && content.contains('-----END');
  }
  
  /// Carrega certificado X509 de um arquivo PEM (método legado)
  static Uint8List? carregarCertificadoPEM(String pemContent) {
    return extrairCertificado(pemContent);
  }
}

