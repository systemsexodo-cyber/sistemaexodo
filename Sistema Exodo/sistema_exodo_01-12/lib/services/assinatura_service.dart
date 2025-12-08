import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart' as xml;
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'certificado_service.dart';
import 'pkcs12_service.dart';

/// Serviço para assinatura digital de XML
class AssinaturaService {
  /// Assina XML da NFC-e com certificado digital
  Future<String> assinarXML(
    String xmlNFCe,
    CertificadoDigital certificado,
  ) async {
    try {
      debugPrint('>>> [Assinatura] Iniciando assinatura digital...');
      
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
      
      final nfeElement = document.findAllElements('NFe').firstOrNull;
      if (nfeElement == null) {
        throw Exception('XML inválido: elemento NFe não encontrado');
      }

      final infNFe = nfeElement.findAllElements('infNFe').firstOrNull;
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

      // 4. Assinar hash com certificado
      debugPrint('>>> [Assinatura] Assinando hash com certificado...');
      final assinatura = await _assinarHash(hash, certificado);
      debugPrint('>>> [Assinatura] Assinatura gerada: ${assinatura.length} bytes');

      // 5. Montar elemento Signature
      debugPrint('>>> [Assinatura] Montando elemento Signature...');
      final signature = await _montarSignature(id, hash, assinatura, certificado);

      // 6. Adicionar Signature ao XML
      nfeElement.children.add(signature);

      // 7. Retornar XML assinado
      debugPrint('>>> [Assinatura] XML assinado com sucesso');
      return document.toXmlString(pretty: false);
    } catch (e, stackTrace) {
      debugPrint('>>> [Assinatura] ERRO ao assinar XML: $e');
      debugPrint('>>> [Assinatura] Stack trace: $stackTrace');
      throw Exception('Erro ao assinar XML: $e');
    }
  }

  /// Assina hash com certificado digital usando RSA-SHA256
  Future<Uint8List> _assinarHash(
    Uint8List hash,
    CertificadoDigital certificado,
  ) async {
    try {
      debugPrint('>>> [Assinatura] Extraindo chave privada do certificado...');
      
      // 1. Extrair chave privada do certificado PFX
      final dadosCertificado = await PKCS12Service.extrairChaveECertificado(
        certificado.bytes,
        certificado.senha,
      );

      final chavePrivada = PKCS12Service.carregarChavePrivada(dadosCertificado);
      if (chavePrivada == null) {
        throw Exception('Não foi possível extrair a chave privada do certificado. Verifique se a senha está correta e o certificado é válido.');
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
      // No PointyCastle, RSASignature é uma classe que encapsula o BigInt
      // A assinatura RSA é um BigInt que precisa ser convertido para bytes (big-endian)
      // Vamos usar reflexão ou tentar acessar a propriedade diretamente
      
      // Tentar acessar via propriedade 'm' (modulus) - estrutura comum do PointyCastle
      BigInt signatureValue;
      
      // Usar try-catch para tentar diferentes formas de acesso
      try {
        // Tentar acessar via propriedade pública se existir
        signatureValue = (signature as dynamic).m as BigInt;
      } catch (e1) {
        try {
          // Tentar via método toString e parse (fallback)
          // Isso não é ideal, mas pode funcionar como último recurso
          final signatureStr = signature.toString();
          // Remover prefixo se houver
          final cleanStr = signatureStr.replaceAll(RegExp(r'[^\d]'), '');
          signatureValue = BigInt.parse(cleanStr);
        } catch (e2) {
          throw Exception('Não foi possível extrair o valor da assinatura: $e1, $e2');
        }
      }
      
      // Converter BigInt para bytes (big-endian, sem sinal)
      return _bigIntToUint8List(signatureValue);
    } catch (e) {
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
      
      // Extrair certificado X509 do PKCS12
      final dadosCertificado = await PKCS12Service.extrairChaveECertificado(
        certificado.bytes,
        certificado.senha,
      );
      
      final certBytes = PKCS12Service.carregarCertificado(dadosCertificado);
      
      if (certBytes == null) {
        debugPrint('>>> [Assinatura] AVISO: Certificado X509 não encontrado, usando fallback');
        // Fallback: usar bytes completos do PFX (não ideal, mas funciona)
        final certBase64 = base64Encode(certificado.bytes);
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
      }
      
      // Usar certificado X509 extraído
      debugPrint('>>> [Assinatura] Usando certificado X509 extraído: ${certBytes.length} bytes');
      final certBase64 = base64Encode(certBytes);

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

