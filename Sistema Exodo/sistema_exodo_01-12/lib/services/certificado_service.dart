import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_functions/cloud_functions.dart';
import 'pkcs12_service.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/export.dart';
import 'package:asn1lib/asn1lib.dart' as asn1lib;

/// Modelo para representar um certificado digital
class CertificadoDigital {
  final Uint8List bytes;
  final String senha;
  final String? cnpj;
  final DateTime? validade;
  final RSAPrivateKey? privateKey;

  CertificadoDigital({
    required this.bytes,
    required this.senha,
    this.cnpj,
    this.validade,
    this.privateKey,
  });
}

/// Serviço para manipulação de certificados digitais
class CertificadoService {
  /// Carrega certificado digital a partir de URL/path ou bytes base64
  Future<CertificadoDigital> carregarCertificado(
    String certificadoUrl,
    String senha, {
    String? certificadoDigitalBytes, // Bytes em base64 (prioridade)
  }) async {
    try {
      Uint8List bytes;

      // Prioridade 1: Se tiver bytes em base64, usar diretamente
      if (certificadoDigitalBytes != null && certificadoDigitalBytes.isNotEmpty) {
        try {
          bytes = base64Decode(certificadoDigitalBytes);
          debugPrint('>>> [Certificado] Carregado de base64: ${bytes.length} bytes');
        } catch (e) {
          throw Exception('Erro ao decodificar certificado base64: $e');
        }
      }
      // Prioridade 2: Se for URL (Firebase Storage, etc), fazer download
      else if (certificadoUrl.startsWith('http://') || certificadoUrl.startsWith('https://')) {
        bytes = await _downloadCertificado(certificadoUrl);
      }
      // Prioridade 3: Se for path local, ler arquivo
      else {
        final file = File(certificadoUrl);
        if (await file.exists()) {
          bytes = await file.readAsBytes();
        } else {
          throw Exception('Arquivo de certificado não encontrado: $certificadoUrl. Certifique-se de que o certificado foi selecionado corretamente.');
        }
      }

      // Validar tamanho mínimo do arquivo
      if (bytes.length < 100) {
        throw Exception('Arquivo de certificado muito pequeno (${bytes.length} bytes). Certifique-se de que o arquivo está completo.');
      }
      
      debugPrint('>>> [Certificado] Tamanho do arquivo: ${bytes.length} bytes');
      debugPrint('>>> [Certificado] Iniciando parsing PKCS12...');
      
      // Parse do certificado PKCS12 usando o serviço já implementado
      Map<String, dynamic> pkcs12Result;
      try {
        pkcs12Result = await PKCS12Service.extrairChaveECertificado(bytes, senha);
        debugPrint('>>> [Certificado] PKCS12 parseado com sucesso');
      } catch (e) {
        debugPrint('>>> [Certificado] ERRO no parsing PKCS12: $e');
        
        // Se for erro de _Namespace, tentar processar no Firebase Cloud Function
        final erroStr = e.toString();
        if (erroStr.contains('_Namespace') || 
            erroStr.contains('Biblioteca asn1lib não consegue processar') ||
            erroStr.contains('Unsupported operation')) {
          debugPrint('>>> [Certificado] Tentando processar no Firebase Cloud Function...');
          
          try {
            pkcs12Result = await _processarNoFirebase(bytes, senha);
            debugPrint('>>> [Certificado] Certificado processado no Firebase com sucesso');
          } catch (firebaseError) {
            debugPrint('>>> [Certificado] ERRO no Firebase: $firebaseError');
            // Se o Firebase também falhar, tentar backend local como fallback
            try {
              debugPrint('>>> [Certificado] Tentando backend local como fallback...');
              pkcs12Result = await _processarNoBackend(bytes, senha);
              debugPrint('>>> [Certificado] Certificado processado no backend local com sucesso');
            } catch (backendError) {
              debugPrint('>>> [Certificado] ERRO no backend local: $backendError');
              // Se ambos falharem, lançar erro
              throw Exception('Erro ao processar certificado digital.\n\n'
                  'Tentamos processar localmente, no Firebase e no backend local, mas todos falharam.\n\n'
                  'Verifique:\n'
                  '1. Se a Cloud Function está deployada no Firebase\n'
                  '   Execute: cd functions-certificado && firebase deploy --only functions\n'
                  '2. Se a senha do certificado está correta\n'
                  '3. Se o certificado não está corrompido\n\n'
                  'Erro local: $e\n'
                  'Erro Firebase: $firebaseError\n'
                  'Erro backend local: $backendError');
            }
          }
        } else {
          throw Exception('Erro ao processar certificado digital. Verifique se:\n'
              '1. O arquivo é um certificado válido (.pfx ou .p12)\n'
              '2. A senha está correta\n'
              '3. O certificado não está corrompido\n\n'
              'Erro técnico: $e');
        }
      }
      
      // Extrair chave privada e certificado
      final chavePrivada = pkcs12Result['chavePrivada'] as RSAPrivateKey?;
      final certificadoBytes = pkcs12Result['certificado'] as Uint8List?;
      
      debugPrint('>>> [Certificado] Chave privada: ${chavePrivada != null ? "OK" : "NÃO ENCONTRADA"}');
      debugPrint('>>> [Certificado] Certificado bytes: ${certificadoBytes?.length ?? 0} bytes');

      // Extrair informações básicas (CNPJ, validade) do certificado
      String? cnpj;
      DateTime? validade;
      
      if (certificadoBytes != null) {
        try {
          final info = await PKCS12Service.extrairInformacoesBasicas(bytes);
          cnpj = info['cnpj'];
          validade = info['validade'];
          debugPrint('>>> [Certificado] CNPJ extraído: $cnpj');
          debugPrint('>>> [Certificado] Validade extraída: $validade');
        } catch (e) {
          debugPrint('>>> [Certificado] Aviso: Não foi possível extrair CNPJ/validade: $e');
        }
      }

      // Criar certificado com informações extraídas
      return CertificadoDigital(
        bytes: bytes,
        senha: senha,
        cnpj: cnpj,
        validade: validade,
        privateKey: chavePrivada,
      );
    } catch (e) {
      debugPrint('>>> [Certificado] ERRO ao carregar: $e');
      throw Exception('Erro ao carregar certificado: $e');
    }
  }

  /// Faz download do certificado de uma URL
  Future<Uint8List> _downloadCertificado(String url) async {
    try {
      debugPrint('>>> [Certificado] Fazendo download de: $url');
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode != 200) {
        throw Exception('Erro ao fazer download do certificado: HTTP ${response.statusCode}');
      }
      
      debugPrint('>>> [Certificado] Download concluído: ${response.bodyBytes.length} bytes');
      return response.bodyBytes;
    } catch (e) {
      throw Exception('Erro ao fazer download do certificado: $e');
    }
  }

  /// Valida se o certificado está válido
  Future<bool> validarCertificado(CertificadoDigital certificado) async {
    try {
      // Verificar validade
      if (certificado.validade != null && certificado.validade!.isBefore(DateTime.now())) {
        return false;
      }

      // TODO: Implementar validação completa do certificado
      // Verificar assinatura, cadeia de certificação, etc
      
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Salva certificado temporariamente
  Future<String> salvarCertificadoTemporario(Uint8List bytes) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/certificado_${DateTime.now().millisecondsSinceEpoch}.pfx');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// Processa certificado no Firebase Cloud Function (prioridade)
  Future<Map<String, dynamic>> _processarNoFirebase(
    Uint8List bytes,
    String senha,
  ) async {
    try {
      debugPrint('>>> [Certificado] Enviando para Firebase Cloud Function...');
      
      // Converter bytes para base64
      final certificadoBase64 = base64Encode(bytes);
      
      // Chamar Cloud Function
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('processarCertificado');
      
      final resultado = await callable.call({
        'certificadoBase64': certificadoBase64,
        'senha': senha,
      }).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Timeout ao processar certificado no Firebase. Verifique sua conexão.');
        },
      );

      final data = resultado.data as Map<String, dynamic>;
      
      if (!data['sucesso']) {
        throw Exception(data['mensagem'] ?? 'Erro ao processar certificado no Firebase');
      }

      // Converter PEM para chave privada RSA (PointyCastle)
      final chavePrivada = _pemParaRSAPrivateKey(data['chavePrivadaPem']);
      
      // Converter certificado PEM para bytes
      final certificadoBytes = utf8.encode(data['certificadoPem']);

      // Extrair informações
      final info = data['informacoes'] ?? {};
      final cnpj = info['cnpj'];
      DateTime? validade;
      if (info['validade'] != null && info['validade']['ate'] != null) {
        validade = DateTime.parse(info['validade']['ate']);
      }

      debugPrint('>>> [Certificado] Firebase processou com sucesso');
      debugPrint('>>> [Certificado] CNPJ: $cnpj');
      debugPrint('>>> [Certificado] Validade: $validade');

      return {
        'chavePrivada': chavePrivada,
        'certificado': Uint8List.fromList(certificadoBytes),
        'bytes': bytes,
        'senha': senha,
        'cnpj': cnpj,
        'validade': validade,
      };
    } catch (e) {
      debugPrint('>>> [Certificado] ERRO no Firebase: $e');
      rethrow;
    }
  }

  /// Processa certificado no backend Node.js local (fallback)
  Future<Map<String, dynamic>> _processarNoBackend(
    Uint8List bytes,
    String senha,
  ) async {
    try {
      debugPrint('>>> [Certificado] Enviando para backend...');
      
      // URL do backend (pode ser configurável)
      const backendUrl = 'http://localhost:3001';
      
      // Converter bytes para base64
      final certificadoBase64 = base64Encode(bytes);
      
      // Fazer requisição para o backend
      final response = await http.post(
        Uri.parse('$backendUrl/api/certificado/processar'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'certificadoBase64': certificadoBase64,
          'senha': senha,
        }),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Timeout ao processar certificado no backend. Verifique se o servidor está rodando em $backendUrl');
        },
      );

      if (response.statusCode != 200) {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['mensagem'] ?? 'Erro ao processar certificado no backend');
      }

      final resultado = jsonDecode(response.body);
      
      if (!resultado['sucesso']) {
        throw Exception(resultado['mensagem'] ?? 'Erro ao processar certificado');
      }

      // Converter PEM para chave privada RSA (PointyCastle)
      final chavePrivada = _pemParaRSAPrivateKey(resultado['chavePrivadaPem']);
      
      // Converter certificado PEM para bytes
      final certificadoBytes = utf8.encode(resultado['certificadoPem']);

      // Extrair informações
      final info = resultado['informacoes'] ?? {};
      final cnpj = info['cnpj'];
      DateTime? validade;
      if (info['validade'] != null && info['validade']['ate'] != null) {
        validade = DateTime.parse(info['validade']['ate']);
      }

      debugPrint('>>> [Certificado] Backend processou com sucesso');
      debugPrint('>>> [Certificado] CNPJ: $cnpj');
      debugPrint('>>> [Certificado] Validade: $validade');

      return {
        'chavePrivada': chavePrivada,
        'certificado': Uint8List.fromList(certificadoBytes),
        'bytes': bytes,
        'senha': senha,
        'cnpj': cnpj,
        'validade': validade,
      };
    } catch (e) {
      debugPrint('>>> [Certificado] ERRO no backend: $e');
      rethrow;
    }
  }

  /// Converte PEM para RSAPrivateKey (PointyCastle)
  /// Usa parsing básico do formato PEM/DER
  RSAPrivateKey _pemParaRSAPrivateKey(String pem) {
    try {
      // Remover headers PEM
      final pemClean = pem
          .replaceAll('-----BEGIN PRIVATE KEY-----', '')
          .replaceAll('-----END PRIVATE KEY-----', '')
          .replaceAll('-----BEGIN RSA PRIVATE KEY-----', '')
          .replaceAll('-----END RSA PRIVATE KEY-----', '')
          .replaceAll('\n', '')
          .replaceAll('\r', '')
          .replaceAll(' ', '');

      // Decodificar base64
      final keyBytes = base64Decode(pemClean);

      // Parse DER usando asn1lib (que funciona melhor para DER do que para PKCS12)
      try {
        final asn1Parser = asn1lib.ASN1Parser(keyBytes);
        final keySeq = asn1Parser.nextObject() as asn1lib.ASN1Sequence;
        
        // Se for PKCS8 (PrivateKeyInfo)
        if (keySeq.elements!.length >= 3) {
          final privateKeyOctets = keySeq.elements![2] as asn1lib.ASN1OctetString;
          final privateKeyBytes = Uint8List.fromList(privateKeyOctets.valueBytes());
          
          // Parse RSAPrivateKey
          final rsaParser = asn1lib.ASN1Parser(privateKeyBytes);
          final rsaSeq = rsaParser.nextObject() as asn1lib.ASN1Sequence;
          
          if (rsaSeq.elements!.length >= 6) {
            final modulus = (rsaSeq.elements![1] as asn1lib.ASN1Integer).valueAsBigInteger;
            final privateExponent = (rsaSeq.elements![3] as asn1lib.ASN1Integer).valueAsBigInteger;
            final p = (rsaSeq.elements![4] as asn1lib.ASN1Integer).valueAsBigInteger;
            final q = (rsaSeq.elements![5] as asn1lib.ASN1Integer).valueAsBigInteger;
            
            return RSAPrivateKey(modulus, privateExponent, p, q);
          }
        }
      } catch (e) {
        debugPrint('>>> [Certificado] Erro ao parsear PEM com asn1lib: $e');
      }

      // Se falhar, tentar usar pointycastle diretamente
      // Por enquanto, lançar erro informativo
      throw Exception('Não foi possível converter PEM para chave privada. '
          'O backend processou o certificado, mas é necessário implementar '
          'o parsing completo do formato PEM.');
    } catch (e) {
      throw Exception('Erro ao converter PEM para chave privada: $e');
    }
  }
}

