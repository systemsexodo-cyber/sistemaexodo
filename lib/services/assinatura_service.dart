import 'dart:convert';
import 'dart:typed_data';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart' as xml;
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'certificado_service.dart';
import 'pkcs12_service.dart';
import 'pem_certificate_service.dart';

/// Serviço para assinatura digital de XML
class AssinaturaService {
  /// Assina XML da NFC-e com certificado digital
  Future<String> assinarXML(
    String xmlNFCe,
    CertificadoDigital certificado,
  ) async {
    return Isolate.run(() async {
      try {
        debugPrint('>>> [Assinatura] Iniciando assinatura digital em Isolate...');
        
        if (xmlNFCe.isEmpty) {
          throw Exception('XML vazio');
        }
        
        // 1. Parse do XML
        xml.XmlDocument document;
        try {
          document = xml.XmlDocument.parse(xmlNFCe);
        } catch (e) {
          throw Exception('XML malformado: $e');
        }
        
        // Buscar elemento NFe (pode estar com ou sem namespace)
        xml.XmlElement? nfeElement;
        try {
          // Tentar buscar com namespace primeiro
          nfeElement = document.findAllElements('NFe', namespace: 'http://www.portalfiscal.inf.br/nfe').firstOrNull;
        } catch (e) {
          // Se falhar, tentar sem namespace
          debugPrint('>>> [Assinatura] AVISO: Erro ao buscar com namespace: $e');
        }
        
        // Se não encontrou com namespace, tentar sem namespace
        if (nfeElement == null) {
          nfeElement = document.findAllElements('NFe').firstOrNull;
        }
        
        if (nfeElement == null) {
          throw Exception('XML inválido: elemento NFe não encontrado');
        }

        // Buscar infNFe (pode estar com ou sem namespace)
        xml.XmlElement? infNFe;
        try {
          infNFe = nfeElement.findAllElements('infNFe', namespace: 'http://www.portalfiscal.inf.br/nfe').firstOrNull;
        } catch (e) {
          debugPrint('>>> [Assinatura] AVISO: Erro ao buscar infNFe com namespace: $e');
        }
        
        if (infNFe == null) {
          infNFe = nfeElement.findAllElements('infNFe').firstOrNull;
        }
        
        if (infNFe == null) {
          throw Exception('XML inválido: elemento infNFe não encontrado');
        }

        // 2. Obter ID do infNFe (chave de acesso)
        final id = infNFe.getAttribute('Id');
        if (id == null || id.isEmpty) {
          throw Exception('ID do infNFe não encontrado (atributo Id ausente)');
        }

        debugPrint('>>> [Assinatura] ID do infNFe: $id');

        // 3. Calcular hash SHA-256 do infNFe
        final infNFeString = infNFe.toXmlString(pretty: false);
        debugPrint('>>> [Assinatura] Calculando hash SHA-256...');
        final hashBytes = sha256.convert(utf8.encode(infNFeString)).bytes;
        final hash = Uint8List.fromList(hashBytes);
        debugPrint('>>> [Assinatura] Hash calculado: ${hash.length} bytes');

        // 4. Validar certificado antes de assinar
        if (certificado.privateKey == null) {
          throw Exception('Chave privada não encontrada no certificado!\n\n'
              'O certificado foi carregado, mas a chave privada não está disponível.\n'
              'Isso é necessário para assinar a NFC-e.\n\n'
              'SOLUÇÃO:\n'
              '1. Re-exporte o certificado incluindo a chave privada\n'
              '2. Certifique-se de que o certificado está em formato PKCS#12 padrão\n'
              '3. Verifique se a senha está correta');
        }
        
        // 4.1. Validar validade do certificado
        if (certificado.validade != null) {
          final agora = DateTime.now();
          if (certificado.validade!.isBefore(agora)) {
            throw Exception('🔴 CERTIFICADO EXPIRADO!\n\n'
                '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
                'O certificado digital expirou em ${certificado.validade!.toString().split(' ')[0]}.\n'
                'Não é possível assinar a NFC-e com um certificado expirado.\n\n'
                '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
                '✅ SOLUÇÃO:\n\n'
                '1. Renove o certificado na autoridade certificadora\n'
                '2. Importe o novo certificado no sistema\n'
                '3. Configure o novo certificado na empresa\n'
                '4. Tente emitir a NFC-e novamente\n\n'
                '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
          } else {
            final diasRestantes = certificado.validade!.difference(agora).inDays;
            if (diasRestantes <= 30) {
              debugPrint('>>> [Assinatura] ⚠️ AVISO: Certificado expira em $diasRestantes dias!');
            }
          }
        } else {
          debugPrint('>>> [Assinatura] ⚠️ AVISO: Data de validade do certificado não disponível');
        }
        
        debugPrint('>>> [Assinatura] Certificado validado:');
        debugPrint('>>> [Assinatura]   CNPJ: ${certificado.cnpj ?? "não encontrado"}');
        debugPrint('>>> [Assinatura]   Validade: ${certificado.validade ?? "não encontrada"}');
        debugPrint('>>> [Assinatura]   Chave privada: ✓ presente');
        
        // 5. Assinar hash com certificado
        debugPrint('>>> [Assinatura] Assinando hash com certificado...');
        final assinatura = await _assinarHash(hash, certificado);
        debugPrint('>>> [Assinatura] Assinatura gerada: ${assinatura.length} bytes');

        // 5. Montar elemento Signature
        debugPrint('>>> [Assinatura] Montando elemento Signature...');
        final signature = await _montarSignature(id, hash, assinatura, certificado);

        // 6. Adicionar Signature ao XML
        nfeElement.children.add(signature);

        // 7. Retornar XML assinado
        debugPrint('>>> [Assinatura] XML assinado com sucesso em Isolate');
        return document.toXmlString(pretty: false);
      } catch (e, stackTrace) {
        debugPrint('>>> [Assinatura] ERRO ao assinar XML em Isolate: $e');
        debugPrint('>>> [Assinatura] Stack trace: $stackTrace');
        throw Exception('Erro ao assinar XML: $e');
      }
    });
  }

  /// Assina hash com certificado digital usando RSA-SHA256
  Future<Uint8List> _assinarHash(
    Uint8List hash,
    CertificadoDigital certificado,
  ) async {
    try {
      debugPrint('>>> [Assinatura] Extraindo chave privada do certificado...');
      
      // 1. Verificar se a chave privada já foi extraída (PEM processado)
      RSAPrivateKey? chavePrivada = certificado.privateKey;
      
      if (chavePrivada == null) {
        // Se não tiver, tentar extrair do PKCS12
        debugPrint('>>> [Assinatura] Chave privada não encontrada no objeto, tentando extrair do PKCS12...');
        final dadosCertificado = await PKCS12Service.extrairChaveECertificado(
          certificado.bytes,
          certificado.senha,
        );

        chavePrivada = PKCS12Service.carregarChavePrivada(dadosCertificado);
        if (chavePrivada == null) {
          throw Exception('Não foi possível extrair a chave privada do certificado.\n\n'
              'Verifique se:\n'
              '• A senha está correta\n'
              '• O certificado é válido\n'
              '• O certificado foi processado corretamente');
        }
      } else {
        debugPrint('>>> [Assinatura] Usando chave privada já extraída do certificado');
      }
      
      debugPrint('>>> [Assinatura] Chave privada extraída: ${chavePrivada.n!.bitLength} bits');

      // 2. Criar signer RSA com SHA-256
      final signer = RSASigner(SHA256Digest(), '0609608648016503040201'); // SHA-256 OID
      signer.init(true, PrivateKeyParameter<RSAPrivateKey>(chavePrivada));

      // 3. Assinar o hash
      final assinatura = signer.generateSignature(hash);

      // 4. Converter para bytes
      return _rsaSignatureToBytes(assinatura);
    } catch (e) {
      throw Exception('Erro ao assinar hash: $e');
    }
  }

  /// Converte RSASignature para Uint8List
  /// RSASignature no PointyCastle contém um BigInt que precisa ser convertido para bytes
  Uint8List _rsaSignatureToBytes(RSASignature signature) {
    try {
      debugPrint('>>> [Assinatura] Convertendo RSASignature para bytes...');
      
      // No PointyCastle, RSASignature é uma classe que encapsula o BigInt
      // A assinatura RSA é um BigInt que precisa ser convertido para bytes (big-endian)
      BigInt signatureValue;
      
      // Estratégia 1: Tentar acessar via propriedade 'm' (modulus) - estrutura comum do PointyCastle
      try {
        signatureValue = (signature as dynamic).m as BigInt;
        debugPrint('>>> [Assinatura] ✓ Valor extraído via propriedade .m');
      } catch (e1) {
        debugPrint('>>> [Assinatura] ⚠️ Não foi possível acessar via .m: $e1');
        
        // Estratégia 2: Tentar via propriedade 'value'
        try {
          signatureValue = (signature as dynamic).value as BigInt;
          debugPrint('>>> [Assinatura] ✓ Valor extraído via propriedade .value');
        } catch (e2) {
          debugPrint('>>> [Assinatura] ⚠️ Não foi possível acessar via .value: $e2');
          
          // Estratégia 3: Tentar via método encode() se existir
          Exception? e3;
          try {
            final encoded = (signature as dynamic).encode() as Uint8List?;
            if (encoded != null) {
              debugPrint('>>> [Assinatura] ✓ Valor extraído via método .encode()');
              return encoded;
            }
          } catch (err3) {
            e3 = err3 is Exception ? err3 : Exception(err3.toString());
            debugPrint('>>> [Assinatura] ⚠️ Não foi possível acessar via .encode(): $e3');
          }
          
          // Estratégia 4: Tentar via toString e parse (fallback menos confiável)
          Exception? e4;
          try {
            final signatureStr = signature.toString();
            debugPrint('>>> [Assinatura] Tentando parse via toString: ${signatureStr.substring(0, signatureStr.length > 50 ? 50 : signatureStr.length)}...');
            
            // Tentar extrair número do formato "RSASignature(m: ...)" ou similar
            final match = RegExp(r'm:\s*(\d+)').firstMatch(signatureStr);
            if (match != null) {
              signatureValue = BigInt.parse(match.group(1)!);
              debugPrint('>>> [Assinatura] ✓ Valor extraído via regex do toString');
            } else {
              // Última tentativa: remover tudo que não é dígito
              final cleanStr = signatureStr.replaceAll(RegExp(r'[^\d]'), '');
              if (cleanStr.isNotEmpty) {
                signatureValue = BigInt.parse(cleanStr);
                debugPrint('>>> [Assinatura] ✓ Valor extraído via parse direto do toString');
              } else {
                throw Exception('Não foi possível extrair valor numérico do toString');
              }
            }
          } catch (err4) {
            e4 = err4 is Exception ? err4 : Exception(err4.toString());
            throw Exception('Não foi possível extrair o valor da assinatura após tentar todas as estratégias:\n'
                '• .m: $e1\n'
                '• .value: $e2\n'
                '• .encode(): ${e3 ?? "não tentado"}\n'
                '• toString/parse: $e4\n\n'
                'Por favor, verifique a versão do PointyCastle e a estrutura do RSASignature.');
          }
        }
      }
      
      debugPrint('>>> [Assinatura] Valor da assinatura (BigInt): ${signatureValue.toString().substring(0, signatureValue.toString().length > 50 ? 50 : signatureValue.toString().length)}...');
      
      // Converter BigInt para bytes (big-endian, sem sinal)
      final bytes = _bigIntToUint8List(signatureValue);
      debugPrint('>>> [Assinatura] Assinatura convertida para bytes: ${bytes.length} bytes');
      
      return bytes;
    } catch (e) {
      debugPrint('>>> [Assinatura] ❌ ERRO ao converter RSASignature para bytes: $e');
      throw Exception('Erro ao converter RSASignature para bytes: $e');
    }
  }

  /// Converte BigInt para Uint8List (big-endian, sem sinal)
  Uint8List _bigIntToUint8List(BigInt value) {
    if (value == BigInt.zero) {
      return Uint8List(1);
    }

    // Calcular número de bytes necessários
    var temp = value;
    var byteCount = 0;
    while (temp > BigInt.zero) {
      temp = temp >> 8;
      byteCount++;
    }

    // Converter para bytes (big-endian)
    final bytes = Uint8List(byteCount);
    temp = value;
    for (var i = byteCount - 1; i >= 0; i--) {
      bytes[i] = (temp & BigInt.from(0xff)).toInt();
      temp = temp >> 8;
    }

    return bytes;
  }

  /// Monta elemento Signature do XML
  Future<xml.XmlElement> _montarSignature(
    String id,
    Uint8List hash,
    Uint8List assinatura,
    CertificadoDigital certificado,
  ) async {
    // Converter assinatura para Base64
    final assinaturaBase64 = base64Encode(assinatura);
    final hashBase64 = base64Encode(hash);

    // TODO: Implementar montagem completa do Signature
    // Incluir SignedInfo, SignatureValue, KeyInfo, etc
    
    final signature = xml.XmlElement(
      xml.XmlName('Signature'),
      [
        xml.XmlAttribute(xml.XmlName('xmlns'), 'http://www.w3.org/2000/09/xmldsig#'),
      ],
      [
        xml.XmlElement(
          xml.XmlName('SignedInfo'),
          [],
          [
            xml.XmlElement(xml.XmlName('CanonicalizationMethod'), [
              xml.XmlAttribute(xml.XmlName('Algorithm'), 'http://www.w3.org/TR/2001/REC-xml-c14n-20010315'),
            ]),
            xml.XmlElement(xml.XmlName('SignatureMethod'), [
              xml.XmlAttribute(xml.XmlName('Algorithm'), 'http://www.w3.org/2001/04/xmldsig-more#rsa-sha256'),
            ]),
            xml.XmlElement(
              xml.XmlName('Reference'),
              [
                xml.XmlAttribute(xml.XmlName('URI'), '#$id'),
              ],
              [
                xml.XmlElement(xml.XmlName('Transforms'), [], [
                  xml.XmlElement(xml.XmlName('Transform'), [
                    xml.XmlAttribute(xml.XmlName('Algorithm'), 'http://www.w3.org/2000/09/xmldsig#enveloped-signature'),
                  ]),
                  xml.XmlElement(xml.XmlName('Transform'), [
                    xml.XmlAttribute(xml.XmlName('Algorithm'), 'http://www.w3.org/TR/2001/REC-xml-c14n-20010315'),
                  ]),
                ]),
                xml.XmlElement(xml.XmlName('DigestMethod'), [
                  xml.XmlAttribute(xml.XmlName('Algorithm'), 'http://www.w3.org/2001/04/xmlenc#sha256'),
                ]),
                xml.XmlElement(xml.XmlName('DigestValue'), [], [
                  xml.XmlText(hashBase64),
                ]),
              ],
            ),
          ],
        ),
        xml.XmlElement(xml.XmlName('SignatureValue'), [], [
          xml.XmlText(assinaturaBase64),
        ]),
        await _montarKeyInfo(certificado),
      ],
    );

    return signature;
  }

  /// Monta elemento KeyInfo com o certificado
  Future<xml.XmlElement> _montarKeyInfo(CertificadoDigital certificado) async {
    try {
      debugPrint('>>> [Assinatura] Montando KeyInfo com certificado...');
      
      Uint8List? certBytes;
      
      // Verificar se o certificado é PEM (texto) ou PFX (binário)
      final isPEM = certificado.bytes.length > 0 && 
                    (certificado.bytes[0] == 0x2D || // '-'
                     String.fromCharCodes(certificado.bytes.take(20)).contains('BEGIN'));
      
      if (isPEM) {
        // É PEM - extrair certificado do texto
        debugPrint('>>> [Assinatura] Certificado é PEM, extraindo certificado X509...');
        try {
          final pemContent = String.fromCharCodes(certificado.bytes);
          certBytes = PEMCertificateService.extrairCertificado(pemContent);
        } catch (e) {
          debugPrint('>>> [Assinatura] Erro ao extrair certificado do PEM: $e');
        }
      } else {
        // É PFX - tentar extrair do PKCS12
        debugPrint('>>> [Assinatura] Certificado é PFX, extraindo do PKCS12...');
        try {
          final dadosCertificado = await PKCS12Service.extrairChaveECertificado(
            certificado.bytes,
            certificado.senha,
          );
          certBytes = PKCS12Service.carregarCertificado(dadosCertificado);
        } catch (e) {
          debugPrint('>>> [Assinatura] Erro ao extrair certificado do PKCS12: $e');
        }
      }
      
      if (certBytes == null || certBytes.isEmpty) {
        debugPrint('>>> [Assinatura] ❌ ERRO CRÍTICO: Certificado X509 não encontrado!');
        debugPrint('>>> [Assinatura] Isso causará erro 290 na SEFAZ!');
        
        // Tentar extrair novamente com mais força
        if (!isPEM) {
          debugPrint('>>> [Assinatura] Tentando extrair certificado novamente do PKCS12...');
          try {
            // Tentar extrair novamente com senha
            final dadosCertificado = await PKCS12Service.extrairChaveECertificado(
              certificado.bytes,
              certificado.senha,
            );
            certBytes = PKCS12Service.carregarCertificado(dadosCertificado);
            
            if (certBytes == null || certBytes.isEmpty) {
              throw Exception('🔴 ERRO CRÍTICO: Certificado X509 não pode ser extraído!\n\n'
                  'O certificado digital não contém o certificado X509 necessário para assinatura.\n'
                  'Isso causará rejeição pela SEFAZ (erro 290).\n\n'
                  '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
                  '✅ SOLUÇÃO DEFINITIVA:\n\n'
                  '1. Re-exporte o certificado no software original (e-CPF/e-CNPJ)\n'
                  '2. Certifique-se de que o certificado está COMPLETO\n'
                  '3. Use formato PKCS#12 (.pfx) padrão\n'
                  '4. Inclua a chave privada E o certificado X509\n'
                  '5. Use senha simples (apenas letras e números)\n'
                  '6. Não marque "Habilitar proteção forte"\n\n'
                  '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
            }
          } catch (e) {
            throw Exception('🔴 ERRO CRÍTICO: Certificado X509 não pode ser extraído!\n\n'
                'Erro: $e\n\n'
                'O certificado digital não contém o certificado X509 necessário para assinatura.\n'
                'Isso causará rejeição pela SEFAZ (erro 290).\n\n'
                '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
                '✅ SOLUÇÃO DEFINITIVA:\n\n'
                '1. Re-exporte o certificado no software original (e-CPF/e-CNPJ)\n'
                '2. Certifique-se de que o certificado está COMPLETO\n'
                '3. Use formato PKCS#12 (.pfx) padrão\n'
                '4. Inclua a chave privada E o certificado X509\n'
                '5. Use senha simples (apenas letras e números)\n'
                '6. Não marque "Habilitar proteção forte"\n\n'
                '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
          }
        } else {
          throw Exception('Não foi possível extrair o certificado X509 do arquivo PEM para assinatura.');
        }
      }
      
      // VALIDAÇÃO CRÍTICA: Verificar se o certificado X509 é válido
      if (certBytes.length < 200) {
        throw Exception('🔴 ERRO: Certificado X509 muito pequeno (${certBytes.length} bytes)!\n\n'
            'Um certificado X509 válido deve ter pelo menos 200 bytes.\n'
            'O certificado extraído está incompleto ou corrompido.\n\n'
            'Isso causará rejeição pela SEFAZ (erro 290).\n\n'
            'SOLUÇÃO: Re-exporte o certificado incluindo o certificado X509 completo.');
      }
      
      // Verificar se começa com 0x30 (DER SEQUENCE - formato correto de certificado X509)
      if (certBytes[0] != 0x30) {
        debugPrint('>>> [Assinatura] ⚠️ AVISO: Certificado X509 não começa com 0x30 (primeiro byte: 0x${certBytes[0].toRadixString(16).padLeft(2, '0')})');
        debugPrint('>>> [Assinatura] O certificado pode estar em formato incorreto');
      }
      
      // Usar certificado X509 extraído
      debugPrint('>>> [Assinatura] ✓ Certificado X509 extraído e validado: ${certBytes.length} bytes');
      debugPrint('>>> [Assinatura] Primeiro byte: 0x${certBytes[0].toRadixString(16).padLeft(2, '0')} (deve ser 0x30 para DER)');
      final certBase64 = base64Encode(certBytes);
      debugPrint('>>> [Assinatura] Certificado em Base64: ${certBase64.length} caracteres');

      return xml.XmlElement(
        xml.XmlName('KeyInfo'),
        [],
        [
          xml.XmlElement(
            xml.XmlName('X509Data'),
            [],
            [
              xml.XmlElement(xml.XmlName('X509Certificate'), [], [
                xml.XmlText(certBase64),
              ]),
            ],
          ),
        ],
      );
    } catch (e) {
      debugPrint('>>> [Assinatura] ERRO ao montar KeyInfo: $e');
      // Se houver erro, retornar KeyInfo vazio (pode causar rejeição pela SEFAZ)
      debugPrint('>>> [Assinatura] AVISO: KeyInfo vazio pode causar rejeição pela SEFAZ');
      return xml.XmlElement(xml.XmlName('KeyInfo'), [], []);
    }
  }
}

