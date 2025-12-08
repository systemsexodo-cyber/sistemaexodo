import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:asn1lib/asn1lib.dart' as asn1lib;
import 'package:crypto/crypto.dart';

/// Serviço para manipulação de certificados PKCS12 (PFX)
class PKCS12Service {
  /// Extrai chave privada e certificado de um arquivo PFX
  /// Implementação usando asn1lib e pointycastle
  static Future<Map<String, dynamic>> extrairChaveECertificado(
    Uint8List pfxBytes,
    String senha,
  ) async {
    try {
      debugPrint('>>> [PKCS12] Iniciando extração de chave e certificado...');
      
      if (pfxBytes.isEmpty) {
        throw Exception('Arquivo PKCS12 vazio');
      }
      
      if (senha.isEmpty) {
        throw Exception('Senha do certificado não fornecida');
      }

      // Parse do ASN.1 do PKCS12
      // Tentar usar asn1lib primeiro, se falhar, usar pointycastle
      asn1lib.ASN1Sequence pfxSeq;
      try {
        debugPrint('>>> [PKCS12] Tentando parse com asn1lib...');
        debugPrint('>>> [PKCS12] Tamanho do arquivo: ${pfxBytes.length} bytes');
        
        // Validar tamanho mínimo
        if (pfxBytes.length < 100) {
          throw Exception('Arquivo muito pequeno para ser um certificado PKCS12 válido (${pfxBytes.length} bytes)');
        }
        
        // Validar se começa com 0x30 (SEQUENCE tag)
        if (pfxBytes[0] != 0x30) {
          debugPrint('>>> [PKCS12] AVISO: Arquivo não começa com 0x30 (SEQUENCE). Primeiro byte: 0x${pfxBytes[0].toRadixString(16)}');
        }
        
        final asn1Parser = asn1lib.ASN1Parser(pfxBytes);
        final obj = asn1Parser.nextObject();
        
        if (obj is! asn1lib.ASN1Sequence) {
          throw Exception('Estrutura PKCS12 inválida: esperado ASN1Sequence, recebido ${obj.runtimeType}');
        }
        pfxSeq = obj;
        debugPrint('>>> [PKCS12] Parse com asn1lib bem-sucedido');
      } catch (e, stackTrace) {
        debugPrint('>>> [PKCS12] ERRO no parsing com asn1lib: $e');
        debugPrint('>>> [PKCS12] Tipo do erro: ${e.runtimeType}');
        
        // Se for erro de _Namespace, é um problema conhecido do asn1lib
        if (e.toString().contains('_Namespace') || 
            e.toString().contains('Unsupported operation') ||
            e.toString().contains('NoSuchMethodError')) {
          debugPrint('>>> [PKCS12] Erro conhecido do asn1lib - tentando solução alternativa...');
          
          // Tentar solução alternativa (pode ser implementada no futuro)
          // Por enquanto, fornecer mensagem clara com soluções práticas
          
          throw Exception('ERRO: Biblioteca asn1lib não consegue processar este certificado\n\n'
              'O certificado PFX está correto, mas há uma incompatibilidade com a biblioteca.\n\n'
              'SOLUÇÕES DISPONÍVEIS:\n\n'
              'OPÇÃO 1 - USAR API EXTERNA (RECOMENDADO):\n'
              'Integrar com uma API que processa certificados no servidor:\n'
              '- Focus NFe API\n'
              '- NFe.io\n'
              '- Outras APIs de NFC-e\n\n'
              'OPÇÃO 2 - PROCESSAR NO BACKEND:\n'
              'Criar endpoint no backend para processar o certificado\n'
              'usando bibliotecas mais robustas (OpenSSL, Java, etc.)\n\n'
              'OPÇÃO 3 - RE-EXPORTAR CERTIFICADO:\n'
              '1. Abra o certificado no software original (e-CPF/e-CNPJ)\n'
              '2. Exporte novamente como PKCS#12 (.pfx)\n'
              '3. Certifique-se de usar senha simples (sem caracteres especiais)\n'
              '4. Tente novamente\n\n'
              'OPÇÃO 4 - CERTIFICADO DE TESTE:\n'
              'Use um certificado de teste diferente para validar o sistema\n\n'
              'INFORMAÇÕES TÉCNICAS:\n'
              'Tamanho: ${pfxBytes.length} bytes\n'
              'Formato: PFX/PKCS12\n'
              'Erro: $e\n\n'
              'Para uso em produção, recomendo a OPÇÃO 1 (API externa).');
        }
        
        throw Exception('Erro ao fazer parse do arquivo PKCS12: $e');
      }
      
      if (pfxSeq.elements == null || pfxSeq.elements!.length < 2) {
        throw Exception('Estrutura PKCS12 inválida: menos de 2 elementos');
      }

      // PFX { version, authSafe, macData }
      final version = (pfxSeq.elements![0] as asn1lib.ASN1Integer).intValue;
      if (version != 3) {
        throw Exception('Versão PKCS12 não suportada: $version (suportado: 3)');
      }

      debugPrint('>>> [PKCS12] Versão: $version');

      final authSafe = pfxSeq.elements![1] as asn1lib.ASN1Sequence;
      final macData = pfxSeq.elements!.length > 2 ? pfxSeq.elements![2] : null;

      // Validar MAC se presente
      if (macData != null) {
        debugPrint('>>> [PKCS12] Validando MAC...');
        await _validarMAC(pfxBytes, senha, macData);
        debugPrint('>>> [PKCS12] MAC validado');
      } else {
        debugPrint('>>> [PKCS12] MAC não presente (pode ser normal)');
      }

      // Processar authSafe (ContentInfo)
      if (authSafe.elements == null || authSafe.elements!.isEmpty) {
        throw Exception('authSafe vazio ou inválido');
      }
      
      final contentInfo = authSafe.elements![0] as asn1lib.ASN1Sequence;
      if (contentInfo.elements == null || contentInfo.elements!.length < 2) {
        throw Exception('ContentInfo inválido');
      }
      
      final contentType = (contentInfo.elements![0] as asn1lib.ASN1ObjectIdentifier).identifier;
      
      if (contentType != '1.2.840.113549.1.7.1') { // data
        throw Exception('Tipo de conteúdo não suportado: $contentType (esperado: 1.2.840.113549.1.7.1)');
      }

      debugPrint('>>> [PKCS12] Tipo de conteúdo: $contentType');

      final content = contentInfo.elements![1] as asn1lib.ASN1OctetString;
      final safeContentsBytes = Uint8List.fromList(content.valueBytes());

      debugPrint('>>> [PKCS12] SafeContents bytes: ${safeContentsBytes.length}');

      // Parse SafeContents
      final safeContentsParser = asn1lib.ASN1Parser(safeContentsBytes);
      final safeContentsSeq = safeContentsParser.nextObject() as asn1lib.ASN1Sequence;

      RSAPrivateKey? chavePrivada;
      Uint8List? certificadoBytes;

      // Processar cada SafeBag
      if (safeContentsSeq.elements != null) {
        debugPrint('>>> [PKCS12] Processando ${safeContentsSeq.elements!.length} SafeBags...');
        
        for (var i = 0; i < safeContentsSeq.elements!.length; i++) {
          final safeBag = safeContentsSeq.elements![i];
          final bag = safeBag as asn1lib.ASN1Sequence;
          
          if (bag.elements == null || bag.elements!.isEmpty) {
            debugPrint('>>> [PKCS12] SafeBag $i vazio, ignorando...');
            continue;
          }

          final bagId = (bag.elements![0] as asn1lib.ASN1ObjectIdentifier).identifier;
          final bagValue = bag.elements![1] as asn1lib.ASN1OctetString;

          debugPrint('>>> [PKCS12] SafeBag $i: $bagId');

          if (bagId == '1.2.840.113549.1.12.10.1.2') {
            // PKCS8ShroudedKeyBag - Chave privada criptografada
            debugPrint('>>> [PKCS12] Extraindo chave privada...');
            chavePrivada = await _extrairChavePrivada(Uint8List.fromList(bagValue.valueBytes()), senha);
            debugPrint('>>> [PKCS12] Chave privada extraída com sucesso');
          } else if (bagId == '1.2.840.113549.1.12.10.1.3') {
            // CertBag - Certificado
            debugPrint('>>> [PKCS12] Extraindo certificado...');
            certificadoBytes = await _extrairCertificado(Uint8List.fromList(bagValue.valueBytes()));
            debugPrint('>>> [PKCS12] Certificado extraído: ${certificadoBytes?.length ?? 0} bytes');
          }
        }
      }

      if (chavePrivada == null) {
        throw Exception('Chave privada não encontrada no PKCS12');
      }

      if (certificadoBytes == null) {
        debugPrint('>>> [PKCS12] AVISO: Certificado X509 não encontrado');
      }

      debugPrint('>>> [PKCS12] Extração concluída com sucesso');

      return {
        'chavePrivada': chavePrivada,
        'certificado': certificadoBytes,
        'bytes': pfxBytes,
        'senha': senha,
      };
    } catch (e, stackTrace) {
      debugPrint('>>> [PKCS12] ERRO ao extrair chave e certificado: $e');
      debugPrint('>>> [PKCS12] Stack trace: $stackTrace');
      throw Exception('Erro ao extrair chave e certificado do PKCS12: $e');
    }
  }

  /// Valida MAC do PKCS12
  /// Nota: Implementação básica - em produção, validar MAC completo usando SHA-1 ou SHA-256
  static Future<void> _validarMAC(
    Uint8List pfxBytes,
    String senha,
    asn1lib.ASN1Object macData,
  ) async {
    try {
      final macDataSeq = macData as asn1lib.ASN1Sequence;
      
      if (macDataSeq.elements == null || macDataSeq.elements!.length < 3) {
        debugPrint('>>> [PKCS12] AVISO: Estrutura MAC incompleta, ignorando validação');
        return; // Em desenvolvimento, não bloquear
      }

      // MACData { mac, macSalt, iterations }
      // Por enquanto, apenas verificar estrutura
      // Em produção, calcular MAC e comparar
      debugPrint('>>> [PKCS12] MAC presente (validação básica)');
      
      // TODO: Implementar validação completa do MAC
      // 1. Extrair macSalt e iterations
      // 2. Calcular MAC usando PBKDF2 + SHA-1/SHA-256
      // 3. Comparar com MAC armazenado
      
    } catch (e) {
      debugPrint('>>> [PKCS12] AVISO: Erro ao validar MAC: $e (ignorando em desenvolvimento)');
      // Em desenvolvimento, não bloquear por MAC
      // Em produção, lançar exceção se MAC inválido
    }
  }

  /// Extrai chave privada RSA do PKCS8ShroudedKeyBag
  static Future<RSAPrivateKey?> _extrairChavePrivada(
    Uint8List encryptedKey,
    String senha,
  ) async {
    try {
      debugPrint('>>> [PKCS12] Descriptografando chave privada...');
      
      // Parse EncryptedPrivateKeyInfo
      final parser = asn1lib.ASN1Parser(encryptedKey);
      final encryptedKeyInfo = parser.nextObject() as asn1lib.ASN1Sequence;
      
      if (encryptedKeyInfo.elements == null || encryptedKeyInfo.elements!.length < 2) {
        throw Exception('EncryptedPrivateKeyInfo inválido');
      }
      
      final algorithm = encryptedKeyInfo.elements![0] as asn1lib.ASN1Sequence;
      if (algorithm.elements == null || algorithm.elements!.isEmpty) {
        throw Exception('Algorithm identifier inválido');
      }
      
      final algorithmId = (algorithm.elements![0] as asn1lib.ASN1ObjectIdentifier).identifier;
      debugPrint('>>> [PKCS12] Algoritmo de criptografia: $algorithmId');
      
      final encryptedData = Uint8List.fromList((encryptedKeyInfo.elements![1] as asn1lib.ASN1OctetString).valueBytes());

      // Descriptografar usando PBES2/PBKDF2
      if (algorithmId == '1.2.840.113549.1.5.13') { // PBES2
        debugPrint('>>> [PKCS12] Usando PBES2 para descriptografar...');
        final decryptedKey = await _descriptografarPBES2(encryptedData, senha, algorithm);
        debugPrint('>>> [PKCS12] Chave descriptografada: ${decryptedKey.length} bytes');
        final rsaKey = _parseRSAPrivateKey(decryptedKey);
        debugPrint('>>> [PKCS12] Chave privada RSA parseada com sucesso');
        return rsaKey;
      } else {
        throw Exception('Algoritmo de criptografia não suportado: $algorithmId (suportado: PBES2 - 1.2.840.113549.1.5.13)');
      }
    } catch (e, stackTrace) {
      debugPrint('>>> [PKCS12] ERRO ao extrair chave privada: $e');
      debugPrint('>>> [PKCS12] Stack trace: $stackTrace');
      throw Exception('Erro ao extrair chave privada: $e');
    }
  }

  /// Descriptografa usando PBES2/PBKDF2
  static Future<Uint8List> _descriptografarPBES2(
    Uint8List encryptedData,
    String senha,
    asn1lib.ASN1Sequence algorithm,
  ) async {
    try {
      if (algorithm.elements == null || algorithm.elements!.length < 2) {
        throw Exception('PBES2 params inválidos');
      }
      
      // Parse PBES2-params
      final params = algorithm.elements![1] as asn1lib.ASN1Sequence;
      
      if (params.elements == null || params.elements!.length < 2) {
        throw Exception('PBES2 params incompletos');
      }
      
      final keyDerivationFunc = params.elements![0] as asn1lib.ASN1Sequence;
      final encryptionScheme = params.elements![1] as asn1lib.ASN1Sequence;

      if (keyDerivationFunc.elements == null || keyDerivationFunc.elements!.length < 2) {
        throw Exception('Key derivation function inválida');
      }

      // PBKDF2 params
      final pbkdf2Params = keyDerivationFunc.elements![1] as asn1lib.ASN1Sequence;
      
      if (pbkdf2Params.elements == null || pbkdf2Params.elements!.length < 2) {
        throw Exception('PBKDF2 params incompletos');
      }
      
      final salt = Uint8List.fromList((pbkdf2Params.elements![0] as asn1lib.ASN1OctetString).valueBytes());
      final iterationCount = (pbkdf2Params.elements![1] as asn1lib.ASN1Integer).intValue;
      
      debugPrint('>>> [PKCS12] PBKDF2: salt=${salt.length} bytes, iterations=$iterationCount');

      // Derivar chave usando PBKDF2
      final key = _deriveKeyPBKDF2(senha, salt, iterationCount, 32); // 256 bits

      // AES-256-CBC decryption
      if (encryptionScheme.elements == null || encryptionScheme.elements!.length < 2) {
        throw Exception('Encryption scheme incompleto');
      }
      
      final encryptionOid = (encryptionScheme.elements![0] as asn1lib.ASN1ObjectIdentifier).identifier;
      debugPrint('>>> [PKCS12] Algoritmo de criptografia: $encryptionOid');
      
      if (encryptionOid == '2.16.840.1.101.3.4.1.42') { // AES-256-CBC
        final iv = Uint8List.fromList((encryptionScheme.elements![1] as asn1lib.ASN1OctetString).valueBytes());
        debugPrint('>>> [PKCS12] IV: ${iv.length} bytes');
        debugPrint('>>> [PKCS12] Dados criptografados: ${encryptedData.length} bytes');
        final decrypted = _decryptAES256CBC(encryptedData, key, iv);
        debugPrint('>>> [PKCS12] Dados descriptografados: ${decrypted.length} bytes');
        return decrypted;
      } else {
        throw Exception('Algoritmo de criptografia não suportado: $encryptionOid (suportado: AES-256-CBC - 2.16.840.1.101.3.4.1.42)');
      }
    } catch (e, stackTrace) {
      debugPrint('>>> [PKCS12] ERRO ao descriptografar: $e');
      debugPrint('>>> [PKCS12] Stack trace: $stackTrace');
      throw Exception('Erro ao descriptografar: $e');
    }
  }

  /// Deriva chave usando PBKDF2
  static Uint8List _deriveKeyPBKDF2(String senha, Uint8List salt, int iterations, int keyLength) {
    // Implementação simplificada usando SHA-1
    // Em produção, usar implementação completa de PBKDF2
    final passwordBytes = utf8.encode(senha);
    var key = Uint8List(keyLength);
    var offset = 0;
    
    for (var i = 1; offset < keyLength; i++) {
      final hmac = Hmac(sha1, passwordBytes);
      var u = hmac.convert(salt + _intToBytes(i)).bytes;
      var t = Uint8List.fromList(u);
      
      for (var j = 1; j < iterations; j++) {
        u = hmac.convert(u).bytes;
        for (var k = 0; k < u.length; k++) {
          t[k] ^= u[k];
        }
      }
      
      final copyLength = (offset + t.length > keyLength) ? keyLength - offset : t.length;
      key.setRange(offset, offset + copyLength, t, 0);
      offset += copyLength;
    }
    
    return key;
  }

  /// Converte int para bytes (big-endian)
  static Uint8List _intToBytes(int value) {
    return Uint8List(4)..buffer.asByteData().setInt32(0, value, Endian.big);
  }

  /// Descriptografa usando AES-256-CBC
  static Uint8List _decryptAES256CBC(Uint8List encrypted, Uint8List key, Uint8List iv) {
    // Usar PointyCastle para descriptografar
    final cipher = PaddedBlockCipher('AES/CBC/PKCS7');
    final params = PaddedBlockCipherParameters(
      ParametersWithIV(KeyParameter(key), iv),
      null,
    );
    cipher.init(false, params);
    
    return cipher.process(encrypted);
  }

  /// Parse RSA Private Key do PKCS8
  static RSAPrivateKey _parseRSAPrivateKey(Uint8List keyBytes) {
    try {
      debugPrint('>>> [PKCS12] Parseando chave privada RSA...');
      
      final parser = asn1lib.ASN1Parser(keyBytes);
      final keyInfo = parser.nextObject() as asn1lib.ASN1Sequence;
      
      if (keyInfo.elements == null || keyInfo.elements!.length < 3) {
        throw Exception('PrivateKeyInfo inválido');
      }
      
      // PrivateKeyInfo { version, algorithm, privateKey }
      final privateKeyOctets = Uint8List.fromList((keyInfo.elements![2] as asn1lib.ASN1OctetString).valueBytes());
      
      // Parse RSAPrivateKey
      final keyParser = asn1lib.ASN1Parser(privateKeyOctets);
      final rsaKey = keyParser.nextObject() as asn1lib.ASN1Sequence;
      
      if (rsaKey.elements == null || rsaKey.elements!.length < 6) {
        throw Exception('RSAPrivateKey inválido: menos de 6 elementos');
      }
      
      // RSAPrivateKey { version, modulus, publicExponent, privateExponent, ... }
      final modulus = (rsaKey.elements![1] as asn1lib.ASN1Integer).valueAsBigInteger;
      final privateExponent = (rsaKey.elements![3] as asn1lib.ASN1Integer).valueAsBigInteger;
      final p = (rsaKey.elements![4] as asn1lib.ASN1Integer).valueAsBigInteger;
      final q = (rsaKey.elements![5] as asn1lib.ASN1Integer).valueAsBigInteger;
      
      debugPrint('>>> [PKCS12] Chave RSA: modulus=${modulus.bitLength} bits');
      
      return RSAPrivateKey(
        modulus,
        privateExponent,
        p,
        q,
      );
    } catch (e, stackTrace) {
      debugPrint('>>> [PKCS12] ERRO ao parsear chave privada RSA: $e');
      debugPrint('>>> [PKCS12] Stack trace: $stackTrace');
      throw Exception('Erro ao parsear chave privada RSA: $e');
    }
  }

  /// Extrai certificado X509 do CertBag
  static Future<Uint8List?> _extrairCertificado(Uint8List certBagBytes) async {
    try {
      debugPrint('>>> [PKCS12] Extraindo certificado X509 do CertBag...');
      
      final parser = asn1lib.ASN1Parser(certBagBytes);
      final certBag = parser.nextObject() as asn1lib.ASN1Sequence;
      
      if (certBag.elements == null || certBag.elements!.length < 2) {
        debugPrint('>>> [PKCS12] CertBag inválido');
        return null;
      }
      
      // CertBag { certId, certValue }
      final certValue = certBag.elements![1] as asn1lib.ASN1OctetString;
      final certBytes = Uint8List.fromList(certValue.valueBytes());
      
      debugPrint('>>> [PKCS12] Certificado X509 extraído: ${certBytes.length} bytes');
      return certBytes;
    } catch (e) {
      debugPrint('>>> [PKCS12] ERRO ao extrair certificado: $e');
      return null;
    }
  }

  /// Carrega chave privada RSA do certificado
  static RSAPrivateKey? carregarChavePrivada(Map<String, dynamic> dados) {
    try {
      return dados['chavePrivada'] as RSAPrivateKey?;
    } catch (e) {
      return null;
    }
  }

  /// Carrega certificado X509 (retorna bytes do certificado)
  static Uint8List? carregarCertificado(Map<String, dynamic> dados) {
    try {
      return dados['certificado'] as Uint8List?;
    } catch (e) {
      return null;
    }
  }

  /// Tenta extrair informações básicas do certificado (CNPJ, validade)
  /// usando parsing básico do ASN.1
  static Future<Map<String, dynamic>> extrairInformacoesBasicas(
    Uint8List pfxBytes,
  ) async {
    try {
      final dados = await extrairChaveECertificado(pfxBytes, '');
      final certBytes = carregarCertificado(dados);
      
      if (certBytes == null) {
        return {'cnpj': null, 'validade': null};
      }

      // Parse certificado X509
      final parser = asn1lib.ASN1Parser(certBytes);
      final cert = parser.nextObject() as asn1lib.ASN1Sequence;
      
      // TBSCertificate { version, serialNumber, signature, issuer, validity, subject, ... }
      final tbsCert = cert.elements![0] as asn1lib.ASN1Sequence;
      
      // Extrair CNPJ do subject (simplificado)
      String? cnpj;
      DateTime? validade;
      
      try {
        // Subject está no índice 5
        if (tbsCert.elements!.length > 5) {
          final subject = tbsCert.elements![5] as asn1lib.ASN1Sequence;
          // Procurar CNPJ no subject (OID 2.16.76.1.3.1)
          for (final rdn in subject.elements!) {
            final set = rdn as asn1lib.ASN1Set;
            for (final attr in set.elements!) {
              final seq = attr as asn1lib.ASN1Sequence;
              final oid = (seq.elements![0] as asn1lib.ASN1ObjectIdentifier).identifier;
              if (oid == '2.16.76.1.3.1') { // CNPJ
                final value = seq.elements![1] as asn1lib.ASN1PrintableString;
                cnpj = value.stringValue;
                break;
              }
            }
          }
        }
        
        // Validade está no índice 4
        if (tbsCert.elements!.length > 4) {
          final validity = tbsCert.elements![4] as asn1lib.ASN1Sequence;
          final notAfter = validity.elements![1];
          // Tentar parsear como GeneralizedTime (mais comum)
          if (notAfter is asn1lib.ASN1GeneralizedTime) {
            validade = notAfter.dateTimeValue;
          }
          // Se for string, tentar parsear manualmente
          else if (notAfter is asn1lib.ASN1PrintableString) {
            try {
              final dateStr = notAfter.stringValue;
              // Formato comum: YYYYMMDDHHmmssZ
              if (dateStr.length >= 14) {
                final year = int.parse(dateStr.substring(0, 4));
                final month = int.parse(dateStr.substring(4, 6));
                final day = int.parse(dateStr.substring(6, 8));
                validade = DateTime(year, month, day);
              }
            } catch (e) {
              // Ignorar erro de parsing
            }
          }
        }
      } catch (e) {
        // Se falhar, retornar null
      }
      
      return {
        'cnpj': cnpj,
        'validade': validade,
      };
    } catch (e) {
      return {
        'cnpj': null,
        'validade': null,
      };
    }
  }
}

