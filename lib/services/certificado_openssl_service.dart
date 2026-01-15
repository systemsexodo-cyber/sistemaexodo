import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'pem_certificate_service.dart';
import 'certificado_converter_service.dart';

/// Serviço robusto para processamento de certificados usando OpenSSL
/// Similar ao node-forge, usa OpenSSL por baixo dos panos
class CertificadoOpenSSLService {
  /// Processa certificado PFX usando OpenSSL (abordagem robusta)
  /// Retorna CertificadoDigital com chave privada e certificado extraídos
  static Future<Map<String, dynamic>> processarPFXComOpenSSL({
    required Uint8List pfxBytes,
    required String senha,
  }) async {
    try {
      debugPrint('>>> [OpenSSL] ========================================');
      debugPrint('>>> [OpenSSL] Processando PFX com OpenSSL (abordagem robusta)');
      debugPrint('>>> [OpenSSL] Tamanho do PFX: ${pfxBytes.length} bytes');
      debugPrint('>>> [OpenSSL] ========================================');

      // 1. Salvar PFX temporariamente
      Directory tempDir;
      try {
        tempDir = await getTemporaryDirectory();
      } catch (e) {
        tempDir = Directory.systemTemp;
      }

      final tempPfxFile = File('${tempDir.path}/certificado_openssl_${DateTime.now().millisecondsSinceEpoch}.pfx');
      await tempPfxFile.writeAsBytes(pfxBytes);
      debugPrint('>>> [OpenSSL] PFX salvo temporariamente: ${tempPfxFile.path}');

      // 2. Converter para PEM usando OpenSSL (processo completo)
      // PASSO 1: Extrair certificado público (-clcerts -nokeys)
      // PASSO 2: Extrair chave privada (-nocerts -nodes)
      // PASSO 3: Combinar em arquivo único (opcional)
      debugPrint('>>> [OpenSSL] Convertendo PFX para PEM (processo completo)...');
      debugPrint('>>> [OpenSSL] PASSO 1: Extraindo certificado público...');
      debugPrint('>>> [OpenSSL] PASSO 2: Extraindo chave privada...');
      debugPrint('>>> [OpenSSL] PASSO 3: Combinando em arquivo único...');
      
      final resultado = await CertificadoConverterService.converterPFXParaPEM(
        caminhoPFX: tempPfxFile.path,
        senha: senha,
      );

      // 3. Ler arquivos PEM gerados
      final certFile = File(resultado['certificado']!);
      final keyFile = File(resultado['chavePrivada']!);
      
      // Preferir arquivo completo se disponível
      File? arquivoCompleto;
      if (resultado['completo'] != null) {
        arquivoCompleto = File(resultado['completo']!);
        if (await arquivoCompleto.exists()) {
          debugPrint('>>> [OpenSSL] Usando arquivo PEM completo (certificado + chave)');
        }
      }

      if (!await certFile.exists() || !await keyFile.exists()) {
        throw Exception('Arquivos PEM não foram gerados corretamente');
      }

      // Ler conteúdo dos arquivos
      final certContent = await certFile.readAsString();
      final keyContent = await keyFile.readAsString();

      debugPrint('>>> [OpenSSL] Certificado PEM: ${certContent.length} caracteres');
      debugPrint('>>> [OpenSSL] Chave privada PEM: ${keyContent.length} caracteres');

      // 4. Processar PEM para extrair informações
      debugPrint('>>> [OpenSSL] Processando PEM para extrair informações...');
      
      // Usar arquivo completo se disponível, senão combinar manualmente
      String pemCompleto;
      File tempPemFile;
      
      if (arquivoCompleto != null && await arquivoCompleto.exists()) {
        // Usar arquivo completo gerado pelo OpenSSL
        pemCompleto = await arquivoCompleto.readAsString();
        tempPemFile = arquivoCompleto;
        debugPrint('>>> [OpenSSL] Usando arquivo PEM completo gerado pelo OpenSSL');
      } else {
        // Combinar certificado e chave manualmente (fallback)
        pemCompleto = '$certContent\n$keyContent';
        tempPemFile = File('${tempDir.path}/certificado_completo_${DateTime.now().millisecondsSinceEpoch}.pem');
        await tempPemFile.writeAsString(pemCompleto);
        debugPrint('>>> [OpenSSL] Arquivo PEM completo criado manualmente');
      }

      // 5. Extrair informações do certificado usando processarPEM
      final certInfo = await PEMCertificateService.processarPEM(pemCompleto, senha);

      // 6. Extrair chave privada do resultado
      final privateKey = certInfo['privateKey'] as RSAPrivateKey?;
      
      // 7. Extrair informações básicas (CNPJ, validade)
      final infoBasicas = await PEMCertificateService.extrairInformacoesBasicas(pemCompleto);

      // 7. Limpar arquivos temporários
      try {
        await tempPfxFile.delete();
        await certFile.delete();
        await keyFile.delete();
        if (arquivoCompleto != null && await arquivoCompleto.exists() && arquivoCompleto.path != tempPemFile.path) {
          await arquivoCompleto.delete();
        }
        if (await tempPemFile.exists()) {
          await tempPemFile.delete();
        }
      } catch (e) {
        debugPrint('>>> [OpenSSL] Aviso: Não foi possível limpar arquivos temporários: $e');
      }

      debugPrint('>>> [OpenSSL] ✓✓✓ Certificado processado com sucesso!');
      debugPrint('>>> [OpenSSL] CNPJ: ${infoBasicas['cnpj'] ?? "não encontrado"}');
      debugPrint('>>> [OpenSSL] Validade: ${infoBasicas['validade'] ?? "não encontrada"}');
      debugPrint('>>> [OpenSSL] Chave privada: ${privateKey != null ? "presente" : "ausente"}');

      return {
        'privateKey': privateKey,
        'certificate': Uint8List.fromList(utf8.encode(certContent)),
        'certificateBytes': Uint8List.fromList(utf8.encode(pemCompleto)),
        'cnpj': infoBasicas['cnpj'] as String?,
        'validade': infoBasicas['validade'] as DateTime?,
      };
    } catch (e) {
      debugPrint('>>> [OpenSSL] ERRO ao processar PFX: $e');
      rethrow;
    }
  }

  /// Processa certificado PEM diretamente
  static Future<Map<String, dynamic>> processarPEM({
    required String pemContent,
    required String senha,
  }) async {
    try {
      debugPrint('>>> [OpenSSL] Processando PEM diretamente...');
      
      // Salvar PEM temporariamente
      Directory tempDir;
      try {
        tempDir = await getTemporaryDirectory();
      } catch (e) {
        tempDir = Directory.systemTemp;
      }

      final tempPemFile = File('${tempDir.path}/certificado_pem_${DateTime.now().millisecondsSinceEpoch}.pem');
      await tempPemFile.writeAsString(pemContent);

      // Extrair informações usando processarPEM
      final certInfo = await PEMCertificateService.processarPEM(pemContent, senha);
      final privateKey = certInfo['privateKey'] as RSAPrivateKey?;
      
      // Extrair informações básicas (CNPJ, validade)
      final infoBasicas = await PEMCertificateService.extrairInformacoesBasicas(pemContent);

      // Limpar arquivo temporário
      try {
        await tempPemFile.delete();
      } catch (e) {
        debugPrint('>>> [OpenSSL] Aviso: Não foi possível limpar arquivo temporário: $e');
      }

      return {
        'privateKey': privateKey,
        'certificateBytes': Uint8List.fromList(utf8.encode(pemContent)),
        'cnpj': infoBasicas['cnpj'] as String?,
        'validade': infoBasicas['validade'] as DateTime?,
      };
    } catch (e) {
      debugPrint('>>> [OpenSSL] ERRO ao processar PEM: $e');
      rethrow;
    }
  }

  /// Verifica se OpenSSL está disponível
  /// Usa o mesmo método do CertificadoConverterService para garantir consistência
  static Future<bool> verificarOpenSSL() async {
    try {
      debugPrint('>>> [OpenSSL] Verificando disponibilidade do OpenSSL...');
      
      // Usar o mesmo método do CertificadoConverterService
      final opensslPath = await CertificadoConverterService.encontrarOpenSSL();
      if (opensslPath != null) {
        debugPrint('>>> [OpenSSL] ✓ OpenSSL encontrado: $opensslPath');
        return true;
      }
      
      debugPrint('>>> [OpenSSL] ✗ OpenSSL não encontrado');
      return false;
    } catch (e) {
      debugPrint('>>> [OpenSSL] ERRO ao verificar OpenSSL: $e');
      return false;
    }
  }
}

