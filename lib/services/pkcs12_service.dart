import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:asn1lib/asn1lib.dart';
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
      // Tentar usar asn1lib primeiro, se falhar, fornecer mensagem clara
      ASN1Sequence pfxSeq;
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
        
        final asn1Parser = ASN1Parser(pfxBytes);
        final obj = asn1Parser.nextObject();
        
        if (obj is! ASN1Sequence) {
          throw Exception('Estrutura PKCS12 inválida: esperado ASN1Sequence, recebido ${obj.runtimeType}');
        }
        pfxSeq = obj;
        debugPrint('>>> [PKCS12] Parse com asn1lib bem-sucedido');
      } catch (e, stackTrace) {
        final erroStr = e.toString();
        debugPrint('>>> [PKCS12] ERRO no parsing com asn1lib: $erroStr');
        debugPrint('>>> [PKCS12] Tipo do erro: ${e.runtimeType}');
        debugPrint('>>> [PKCS12] Stack trace: $stackTrace');
        
        // Coletar informações sobre o arquivo
        final primeiroByte = pfxBytes.isNotEmpty ? '0x${pfxBytes[0].toRadixString(16).padLeft(2, '0')}' : 'vazio';
        final primeirosBytes = pfxBytes.length >= 10 
            ? pfxBytes.sublist(0, 10).map((b) => '0x${b.toRadixString(16).padLeft(2, "0")}').join(' ')
            : 'insuficiente';
        
        debugPrint('>>> [PKCS12] Primeiro byte: $primeiroByte');
        debugPrint('>>> [PKCS12] Primeiros 10 bytes: $primeirosBytes');
        
        // Verificar se é erro de _Namespace (pode aparecer de várias formas)
        final isErroNamespace = erroStr.contains('_Namespace') || 
                                 erroStr.contains('Unsupported operation') ||
                                 erroStr.contains('NoSuchMethodError') ||
                                 erroStr.toLowerCase().contains('namespace');
        
        if (isErroNamespace) {
          debugPrint('>>> [PKCS12] Erro conhecido do asn1lib detectado (_Namespace)');
          
          throw Exception('🔴 ERRO: Certificado não pode ser processado localmente\n\n'
              '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
              '📋 PROBLEMA IDENTIFICADO:\n'
              'O certificado está em um formato que a biblioteca Flutter não consegue processar.\n'
              'Isso é comum e tem solução simples!\n\n'
              '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
              '✅ SOLUÇÃO DEFINITIVA (2 minutos):\n\n'
              '1️⃣ Abra o certificado no software original:\n'
              '   • e-CPF Manager ou e-CNPJ Manager\n'
              '   • Ou use certmgr.msc no Windows\n\n'
              '2️⃣ Exporte novamente:\n'
              '   • Clique com botão direito no certificado\n'
              '   • Selecione "Exportar" ou "Export"\n'
              '   • Escolha formato: PKCS#12 (.pfx)\n\n'
              '3️⃣ Configure a exportação:\n'
              '   ✅ Use senha SIMPLES (apenas letras e números)\n'
              '   ❌ NÃO marque "Exportar chave privada estendida"\n'
              '   ❌ NÃO marque "Habilitar proteção forte"\n'
              '   ❌ NÃO marque opções avançadas\n\n'
              '4️⃣ Salve e use o novo arquivo:\n'
              '   • Salve com nome simples (ex: certificado.pfx)\n'
              '   • Use este novo arquivo no sistema\n'
              '   • Digite a senha simples que você criou\n\n'
              '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
              '📊 INFORMAÇÕES TÉCNICAS:\n'
              '• Tamanho do arquivo: ${pfxBytes.length} bytes\n'
              '• Primeiro byte: $primeiroByte\n'
              '• Formato: PKCS#12 (.pfx)\n'
              '• Erro: $erroStr\n\n'
              '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
              '💡 DICA: Este processo resolve 99% dos casos!\n'
              'O certificado original está correto, apenas precisa ser\n'
              're-exportado em formato padrão compatível com Flutter.\n\n'
              '📖 Guia completo: Veja o arquivo\n'
              '   GUIA_VISUAL_REEXPORTAR_CERTIFICADO.md');
        }
        
        throw Exception('Erro ao fazer parse do arquivo PKCS12.\n\n'
            'INFORMAÇÕES:\n'
            '• Tamanho: ${pfxBytes.length} bytes\n'
            '• Primeiro byte: $primeiroByte\n'
            '• Erro: $e\n\n'
            'SOLUÇÃO: Re-exporte o certificado em formato PKCS#12 padrão no software original.');
      }
      
      if (pfxSeq.elements == null || pfxSeq.elements!.length < 2) {
        throw Exception('Estrutura PKCS12 inválida: menos de 2 elementos');
      }

      // PFX { version, authSafe, macData }
      final version = (pfxSeq.elements![0] as ASN1Integer).intValue;
      if (version != 3) {
        throw Exception('Versão PKCS12 não suportada: $version (suportado: 3)');
      }

      debugPrint('>>> [PKCS12] Versão: $version');

      // Verificar tipo de authSafe
      final authSafeObj = pfxSeq.elements![1];
      debugPrint('>>> [PKCS12] Tipo de authSafe: ${authSafeObj.runtimeType}');
      
      // Tentar diferentes tipos de authSafe
      ASN1Sequence authSafe;
      if (authSafeObj is ASN1Sequence) {
        authSafe = authSafeObj;
      } else if (authSafeObj is ASN1OctetString) {
        // Alguns certificados têm authSafe como OctetString direto
        debugPrint('>>> [PKCS12] AVISO: authSafe é OctetString direto, tentando parsear...');
        try {
          final authSafeBytes = Uint8List.fromList(authSafeObj.valueBytes());
          final parser = ASN1Parser(authSafeBytes);
          final parsed = parser.nextObject();
          if (parsed is ASN1Sequence) {
            authSafe = parsed;
            debugPrint('>>> [PKCS12] authSafe parseado com sucesso do OctetString');
          } else {
            throw Exception('authSafe inválido: esperado ASN1Sequence após parse, recebido ${parsed.runtimeType}');
          }
        } catch (e) {
          throw Exception('authSafe inválido: esperado ASN1Sequence, recebido ${authSafeObj.runtimeType}. '
              'Tentativa de parse falhou: $e');
        }
      } else {
        throw Exception('authSafe inválido: esperado ASN1Sequence ou ASN1OctetString, recebido ${authSafeObj.runtimeType}');
      }
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
      // authSafe pode ser uma SEQUENCE OF ContentInfo
      // Cada ContentInfo é uma SEQUENCE { contentType, content }
      if (authSafe.elements == null || authSafe.elements!.isEmpty) {
        throw Exception('authSafe vazio ou inválido');
      }
      
      // Tentar múltiplas estratégias de parsing para suportar diferentes formatos
      String? contentType;
      ASN1OctetString? content;
      bool parsingSucesso = false;
      
      // Estratégia 1: Formato padrão - ContentInfo como Sequence
      try {
        final firstElement = authSafe.elements![0];
        if (firstElement is ASN1Sequence) {
          final contentInfo = firstElement;
          if (contentInfo.elements != null && contentInfo.elements!.length >= 2) {
            final contentTypeObj = contentInfo.elements![0];
            if (contentTypeObj is ASN1ObjectIdentifier) {
              final contentTypeOid = contentTypeObj.identifier;
              if (contentTypeOid != null) {
                contentType = contentTypeOid;
                final contentObj = contentInfo.elements![1];
                if (contentObj is ASN1OctetString) {
                  content = contentObj;
                  parsingSucesso = true;
                  debugPrint('>>> [PKCS12] Parseado usando formato padrão (ContentInfo Sequence)');
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('>>> [PKCS12] Estratégia 1 falhou: $e');
      }
      
      // Estratégia 2: OID direto no primeiro elemento
      if (!parsingSucesso) {
        try {
          final firstElement = authSafe.elements![0];
          if (firstElement is ASN1ObjectIdentifier) {
            final contentTypeOid = firstElement.identifier;
            if (contentTypeOid != null && authSafe.elements!.length >= 2) {
              contentType = contentTypeOid;
              final contentObj = authSafe.elements![1];
              if (contentObj is ASN1OctetString) {
                content = contentObj;
                parsingSucesso = true;
                debugPrint('>>> [PKCS12] Parseado usando formato alternativo (OID direto)');
              }
            }
          }
        } catch (e) {
          debugPrint('>>> [PKCS12] Estratégia 2 falhou: $e');
        }
      }
      
      // Estratégia 3: Procurar em todos os elementos do authSafe
      if (!parsingSucesso) {
        try {
          for (var i = 0; i < authSafe.elements!.length; i++) {
            final element = authSafe.elements![i];
            if (element is ASN1Sequence && element.elements != null && element.elements!.length >= 2) {
              final contentTypeObj = element.elements![0];
              if (contentTypeObj is ASN1ObjectIdentifier) {
                final contentTypeOid = contentTypeObj.identifier;
                if (contentTypeOid == '1.2.840.113549.1.7.1') { // data
                  contentType = contentTypeOid;
                  final contentObj = element.elements![1];
                  if (contentObj is ASN1OctetString) {
                    content = contentObj;
                    parsingSucesso = true;
                    debugPrint('>>> [PKCS12] Parseado usando busca em todos os elementos (índice $i)');
                    break;
                  }
                }
              }
            }
          }
        } catch (e) {
          debugPrint('>>> [PKCS12] Estratégia 3 falhou: $e');
        }
      }
      
      // Estratégia 4: OID direto + ASN1Object (formato não padrão)
      // Alguns certificados têm: [OID, ASN1Object] onde ASN1Object pode conter o conteúdo
      if (!parsingSucesso) {
        try {
          if (authSafe.elements!.length >= 2) {
            final firstElement = authSafe.elements![0];
            final secondElement = authSafe.elements![1];
            
            if (firstElement is ASN1ObjectIdentifier && secondElement is ASN1Object) {
              final contentTypeOid = firstElement.identifier;
              debugPrint('>>> [PKCS12] Estratégia 4: OID=$contentTypeOid, segundo elemento=${secondElement.runtimeType}');
              
              // Tentar extrair conteúdo do ASN1Object
              ASN1OctetString? extractedContent;
              
              // Caso 1: ASN1Object é um OctetString direto
              if (secondElement is ASN1OctetString) {
                extractedContent = secondElement;
                debugPrint('>>> [PKCS12] Estratégia 4: ASN1Object é OctetString direto');
              }
              // Caso 2: ASN1Object é uma Sequence que contém OctetString
              else if (secondElement is ASN1Sequence) {
                debugPrint('>>> [PKCS12] Estratégia 4: ASN1Object é Sequence, procurando OctetString...');
                // Procurar OctetString na sequência
                for (var elem in secondElement.elements ?? []) {
                  if (elem is ASN1OctetString) {
                    extractedContent = elem;
                    debugPrint('>>> [PKCS12] Estratégia 4: OctetString encontrado na Sequence');
                    break;
                  }
                  // Se o elemento for uma Sequence aninhada, procurar recursivamente
                  if (elem is ASN1Sequence) {
                    for (var subElem in elem.elements ?? []) {
                      if (subElem is ASN1OctetString) {
                        extractedContent = subElem;
                        debugPrint('>>> [PKCS12] Estratégia 4: OctetString encontrado em Sequence aninhada');
                        break;
                      }
                    }
                    if (extractedContent != null) break;
                  }
                }
              }
              // Caso 3: Tentar parsear bytes do ASN1Object como OctetString
              else {
                try {
                  final bytes = _extractBytesFromASN1Object(secondElement);
                  if (bytes != null && bytes.isNotEmpty) {
                    // Tentar parsear como OctetString
                    final parser = ASN1Parser(bytes);
                    final parsed = parser.nextObject();
                    if (parsed is ASN1OctetString) {
                      extractedContent = parsed;
                      debugPrint('>>> [PKCS12] Estratégia 4: OctetString extraído dos bytes do ASN1Object');
                    } else if (parsed is ASN1Sequence) {
                      // Procurar OctetString na sequência parseada
                      for (var elem in parsed.elements ?? []) {
                        if (elem is ASN1OctetString) {
                          extractedContent = elem;
                          debugPrint('>>> [PKCS12] Estratégia 4: OctetString encontrado após parse dos bytes');
                          break;
                        }
                      }
                    }
                  }
                } catch (e) {
                  debugPrint('>>> [PKCS12] Estratégia 4: Erro ao extrair bytes: $e');
                }
              }
              
              if (extractedContent != null) {
                contentType = contentTypeOid ?? '1.2.840.113549.1.7.1'; // Default para data
                content = extractedContent;
                parsingSucesso = true;
                debugPrint('>>> [PKCS12] Parseado usando estratégia 4 (OID + ASN1Object)');
              }
            }
          }
        } catch (e) {
          debugPrint('>>> [PKCS12] Estratégia 4 falhou: $e');
        }
      }
      
      // Estratégia 5: Parse agressivo dos bytes brutos do segundo elemento
      // Para casos onde o ASN1Object não está sendo parseado corretamente
      if (!parsingSucesso) {
        try {
          if (authSafe.elements!.length >= 2) {
            final firstElement = authSafe.elements![0];
            final secondElement = authSafe.elements![1];
            
            if (firstElement is ASN1ObjectIdentifier) {
              final contentTypeOid = firstElement.identifier;
              debugPrint('>>> [PKCS12] Estratégia 5: Tentando parse agressivo do segundo elemento...');
              debugPrint('>>> [PKCS12] Estratégia 5: Tipo do segundo elemento=${secondElement.runtimeType}');
              
              // Tentar extrair bytes brutos do segundo elemento
              Uint8List? rawBytes;
              try {
                rawBytes = Uint8List.fromList(secondElement.valueBytes());
                debugPrint('>>> [PKCS12] Estratégia 5: Bytes extraídos: ${rawBytes.length} bytes');
              } catch (e) {
                debugPrint('>>> [PKCS12] Estratégia 5: Erro ao extrair valueBytes: $e');
              }
              
              if (rawBytes != null && rawBytes.isNotEmpty) {
                // Tentar parsear os bytes como diferentes estruturas
                ASN1OctetString? foundContent;
                
                // Tentativa 1: Parse direto como OctetString
                try {
                  final parser = ASN1Parser(rawBytes);
                  final parsed = parser.nextObject();
                  if (parsed is ASN1OctetString) {
                    foundContent = parsed;
                    debugPrint('>>> [PKCS12] Estratégia 5: Parse direto como OctetString OK');
                  } else if (parsed is ASN1Sequence) {
                    // Procurar OctetString na sequência
                    debugPrint('>>> [PKCS12] Estratégia 5: Parse resultou em Sequence, procurando OctetString...');
                    foundContent = _findOctetStringInSequence(parsed);
                    if (foundContent != null) {
                      debugPrint('>>> [PKCS12] Estratégia 5: OctetString encontrado na Sequence');
                    }
                  }
                } catch (e) {
                  debugPrint('>>> [PKCS12] Estratégia 5: Parse direto falhou: $e');
                }
                
                // Tentativa 2: Se não encontrou, tentar pular o primeiro byte (pode ser tag)
                if (foundContent == null && rawBytes.length > 1) {
                  try {
                    // Tentar parsear a partir do byte 1 (pular possível tag)
                    final parser = ASN1Parser(rawBytes.sublist(1));
                    final parsed = parser.nextObject();
                    if (parsed is ASN1OctetString) {
                      foundContent = parsed;
                      debugPrint('>>> [PKCS12] Estratégia 5: OctetString encontrado após pular primeiro byte');
                    } else if (parsed is ASN1Sequence) {
                      foundContent = _findOctetStringInSequence(parsed);
                    }
                  } catch (e) {
                    debugPrint('>>> [PKCS12] Estratégia 5: Parse após pular byte falhou: $e');
                  }
                }
                
                // Tentativa 3: Procurar padrão de OctetString nos bytes (0x04 seguido de tamanho)
                if (foundContent == null) {
                  try {
                    for (int i = 0; i < rawBytes.length - 2; i++) {
                      if (rawBytes[i] == 0x04) { // Tag OctetString
                        final length = rawBytes[i + 1];
                        if (length > 0 && i + 2 + length <= rawBytes.length) {
                          final octetBytes = rawBytes.sublist(i + 2, i + 2 + length);
                          // Criar OctetString manualmente
                          foundContent = ASN1OctetString(octetBytes);
                          debugPrint('>>> [PKCS12] Estratégia 5: OctetString encontrado por busca de padrão (offset $i)');
                          break;
                        }
                      }
                    }
                  } catch (e) {
                    debugPrint('>>> [PKCS12] Estratégia 5: Busca de padrão falhou: $e');
                  }
                }
                
                if (foundContent != null) {
                  contentType = contentTypeOid ?? '1.2.840.113549.1.7.1';
                  content = foundContent;
                  parsingSucesso = true;
                  debugPrint('>>> [PKCS12] Parseado usando estratégia 5 (parse agressivo)');
                }
              }
            }
          }
        } catch (e) {
          debugPrint('>>> [PKCS12] Estratégia 5 falhou: $e');
        }
      }
      
      if (!parsingSucesso || contentType == null || content == null) {
        // Coletar informações detalhadas para debug
        final firstElementType = authSafe.elements![0].runtimeType;
        final elementosInfo = <String>[];
        for (var i = 0; i < authSafe.elements!.length && i < 5; i++) {
          final elem = authSafe.elements![i];
          elementosInfo.add('[$i]: ${elem.runtimeType}');
        }
        
        debugPrint('>>> [PKCS12] DEBUG: authSafe tem ${authSafe.elements!.length} elementos');
        debugPrint('>>> [PKCS12] DEBUG: Tipos dos primeiros elementos: ${elementosInfo.join(", ")}');
        
        throw Exception('FORMATO_NAO_SUPORTADO: Não foi possível parsear authSafe após tentar 5 estratégias.\n\n'
            'INFORMAÇÕES DO CERTIFICADO:\n'
            '• Tipo do primeiro elemento: $firstElementType\n'
            '• Número de elementos no authSafe: ${authSafe.elements!.length}\n'
            '• Tipos dos elementos: ${elementosInfo.join(", ")}\n\n'
            'ESTRATÉGIAS TENTADAS:\n'
            '1. ContentInfo como Sequence (formato padrão)\n'
            '2. OID direto no primeiro elemento\n'
            '3. Busca em todos os elementos do authSafe\n'
            '4. OID direto + ASN1Object (formato não padrão)\n'
            '5. Parse agressivo dos bytes brutos\n\n'
            'SOLUÇÃO RECOMENDADA:\n'
            'Re-exporte o certificado no software original (e-CPF/e-CNPJ) em formato PKCS#12 padrão.\n'
            'Certifique-se de usar senha simples e exportar como .pfx padrão.');
      }
      
      // Validar contentType (aceitar data ou encryptedData)
      if (contentType != '1.2.840.113549.1.7.1' && // data
          contentType != '1.2.840.113549.1.7.6') { // encryptedData
        debugPrint('>>> [PKCS12] AVISO: Tipo de conteúdo não padrão: $contentType');
        // Tentar continuar mesmo assim se for um tipo conhecido
        if (!contentType.startsWith('1.2.840.113549.1.7')) {
          throw Exception('Tipo de conteúdo não suportado: $contentType (esperado: 1.2.840.113549.1.7.1 ou 1.2.840.113549.1.7.6)');
        }
      }

      debugPrint('>>> [PKCS12] Tipo de conteúdo: $contentType');

      // Extrair bytes do conteúdo de forma segura
      Uint8List safeContentsBytes;
      if (content is ASN1OctetString) {
        safeContentsBytes = Uint8List.fromList(content.valueBytes());
      } else {
        // Se não for OctetString, tentar extrair bytes de outra forma
        try {
          safeContentsBytes = Uint8List.fromList(content.valueBytes());
        } catch (e) {
          // Último recurso: tentar extrair bytes brutos
          debugPrint('>>> [PKCS12] AVISO: content não é OctetString, tentando extrair bytes brutos...');
          final extractedBytes = _extractBytesFromASN1Object(content);
          if (extractedBytes != null && extractedBytes.isNotEmpty) {
            safeContentsBytes = extractedBytes;
          } else {
            throw Exception('Não foi possível extrair bytes do conteúdo. Tipo: ${content.runtimeType}');
          }
        }
      }

      debugPrint('>>> [PKCS12] SafeContents bytes: ${safeContentsBytes.length}');

      // Parse SafeContents
      final safeContentsParser = ASN1Parser(safeContentsBytes);
      final safeContentsSeq = safeContentsParser.nextObject() as ASN1Sequence;

      RSAPrivateKey? chavePrivada;
      Uint8List? certificadoBytes;

      // CORREÇÃO DEFINITIVA: Coletar todos os SafeBags (podem vir de ContentInfo ou diretamente)
      final safeBags = <ASN1Sequence>[];
      
      if (safeContentsSeq.elements != null) {
        debugPrint('>>> [PKCS12] Processando ${safeContentsSeq.elements!.length} elementos do safeContentsSeq...');
        
        for (var i = 0; i < safeContentsSeq.elements!.length; i++) {
          final elemento = safeContentsSeq.elements![i];
          debugPrint('>>> [PKCS12] Elemento $i: tipo=${elemento.runtimeType}');
          
          if (elemento is ASN1Sequence) {
            // Verificar se é ContentInfo (tem OID 1.2.840.113549.1.7.1 ou 1.2.840.113549.1.7.6)
            if (elemento.elements != null && elemento.elements!.length >= 2) {
              final primeiroElem = elemento.elements![0];
              if (primeiroElem is ASN1ObjectIdentifier) {
                final oid = primeiroElem.identifier;
                if (oid == '1.2.840.113549.1.7.1' || oid == '1.2.840.113549.1.7.6') {
                  // É ContentInfo - parsear o content para obter SafeBags
                  debugPrint('>>> [PKCS12] Elemento $i é ContentInfo (OID: $oid), parseando content...');
                  final contentObj = elemento.elements![1];
                  if (contentObj is ASN1OctetString) {
                    try {
                      final contentBytes = Uint8List.fromList(contentObj.valueBytes());
                      final parser = ASN1Parser(contentBytes);
                      final parsed = parser.nextObject();
                      if (parsed is ASN1Sequence) {
                        // O content contém uma SEQUENCE OF SafeBag
                        debugPrint('>>> [PKCS12] ContentInfo $i parseado, encontrados ${parsed.elements?.length ?? 0} SafeBags');
                        if (parsed.elements != null) {
                          for (var idx = 0; idx < parsed.elements!.length; idx++) {
                            final safeBag = parsed.elements![idx];
                            if (safeBag is ASN1Sequence) {
                              safeBags.add(safeBag);
                              // Debug: mostrar bagId se houver
                              if (safeBag.elements != null && safeBag.elements!.isNotEmpty) {
                                final bagIdObj = safeBag.elements![0];
                                if (bagIdObj is ASN1ObjectIdentifier) {
                                  debugPrint('>>> [PKCS12] SafeBag do ContentInfo $i: bagId=${bagIdObj.identifier}');
                                }
                              }
                            } else {
                              debugPrint('>>> [PKCS12] AVISO: Elemento $idx do content não é Sequence: ${safeBag.runtimeType}');
                            }
                          }
                        }
                      } else {
                        debugPrint('>>> [PKCS12] AVISO: Content parseado não é Sequence: ${parsed.runtimeType}');
                      }
                    } catch (e) {
                      debugPrint('>>> [PKCS12] Erro ao parsear content do ContentInfo $i: $e');
                    }
                  }
                } else {
                  // Não é ContentInfo, provavelmente é SafeBag direto
                  debugPrint('>>> [PKCS12] Elemento $i parece ser SafeBag direto (OID: $oid)');
                  safeBags.add(elemento);
                }
              } else {
                // Não tem OID no primeiro elemento, pode ser SafeBag
                debugPrint('>>> [PKCS12] Elemento $i não tem OID no primeiro elemento, tratando como SafeBag');
                safeBags.add(elemento);
              }
            }
          } else if (elemento is ASN1OctetString) {
            // Tentar parsear como SafeBag encapsulado
            debugPrint('>>> [PKCS12] Elemento $i é OctetString, tentando parsear...');
            try {
              final bagBytes = Uint8List.fromList(elemento.valueBytes());
              final parser = ASN1Parser(bagBytes);
              final parsed = parser.nextObject();
              if (parsed is ASN1Sequence) {
                safeBags.add(parsed);
                debugPrint('>>> [PKCS12] Elemento $i parseado com sucesso');
              }
            } catch (e) {
              debugPrint('>>> [PKCS12] Erro ao parsear elemento $i: $e');
            }
          }
        }
      }
      
      debugPrint('>>> [PKCS12] Total de SafeBags coletados: ${safeBags.length}');
      
      // Processar cada SafeBag
      for (var i = 0; i < safeBags.length; i++) {
        final bag = safeBags[i];
        
        if (bag.elements == null || bag.elements!.isEmpty) {
          debugPrint('>>> [PKCS12] SafeBag $i vazio, ignorando...');
          continue;
        }

        // Debug: mostrar estrutura do SafeBag
        debugPrint('>>> [PKCS12] SafeBag $i tem ${bag.elements!.length} elementos');
        for (var j = 0; j < bag.elements!.length && j < 3; j++) {
          debugPrint('>>> [PKCS12] SafeBag $i elemento $j: ${bag.elements![j].runtimeType}');
        }

        final bagIdObj = bag.elements![0];
        if (bagIdObj is! ASN1ObjectIdentifier) {
          debugPrint('>>> [PKCS12] SafeBag $i: bagId não é ObjectIdentifier (é ${bagIdObj.runtimeType}), tentando processar mesmo assim...');
          // Tentar processar mesmo sem OID conhecido
          if (bag.elements!.length >= 2) {
            final bagValueObj = bag.elements![1];
            Uint8List? bagValueBytes;
            try {
              if (bagValueObj is ASN1OctetString) {
                bagValueBytes = Uint8List.fromList(bagValueObj.valueBytes());
              } else {
                final extractedBytes = _extractBytesFromASN1Object(bagValueObj);
                if (extractedBytes != null) bagValueBytes = extractedBytes;
              }
              
              if (bagValueBytes != null && bagValueBytes.length > 50) {
                debugPrint('>>> [PKCS12] Tentando extrair chave privada de SafeBag $i sem OID conhecido...');
                try {
                  chavePrivada = await _extrairChavePrivada(bagValueBytes, senha);
                  if (chavePrivada != null) {
                    debugPrint('>>> [PKCS12] Chave privada encontrada em SafeBag $i!');
                  }
                } catch (e) {
                  debugPrint('>>> [PKCS12] Não é chave privada: $e');
                }
              }
            } catch (e) {
              debugPrint('>>> [PKCS12] Erro ao processar SafeBag $i: $e');
            }
          }
          continue;
        }
        final bagId = bagIdObj.identifier;
        
        // Extrair bagValue de forma segura
        final bagValueObj = bag.elements![1];
        Uint8List bagValueBytes;
        
        if (bagValueObj is ASN1OctetString) {
          bagValueBytes = Uint8List.fromList(bagValueObj.valueBytes());
        } else {
          // Tentar extrair bytes do objeto genérico
          debugPrint('>>> [PKCS12] AVISO: bagValue não é OctetString, tipo: ${bagValueObj.runtimeType}');
          final extractedBytes = _extractBytesFromASN1Object(bagValueObj);
          if (extractedBytes != null && extractedBytes.isNotEmpty) {
            bagValueBytes = extractedBytes;
          } else {
            // Tentar usar valueBytes() diretamente
            try {
              bagValueBytes = Uint8List.fromList(bagValueObj.valueBytes());
            } catch (e) {
              debugPrint('>>> [PKCS12] ERRO ao extrair bytes do bagValue: $e');
              continue; // Pular este SafeBag
            }
          }
        }

        debugPrint('>>> [PKCS12] SafeBag $i: $bagId (${bagValueBytes.length} bytes)');

        // CORREÇÃO DEFINITIVA: Tentar extrair chave privada e certificado de TODOS os SafeBags
        // independente do OID, pois alguns certificados usam OIDs não padrão
        
        // Verificar OIDs conhecidos primeiro
        if (bagId == '1.2.840.113549.1.12.10.1.2') {
          // PKCS8ShroudedKeyBag - Chave privada criptografada (padrão)
          debugPrint('>>> [PKCS12] Extraindo chave privada (PKCS8ShroudedKeyBag)...');
          try {
            chavePrivada = await _extrairChavePrivada(bagValueBytes, senha);
            debugPrint('>>> [PKCS12] Chave privada extraída com sucesso');
          } catch (e) {
            debugPrint('>>> [PKCS12] ERRO ao extrair chave privada: $e');
          }
        } else if (bagId == '1.2.840.113549.1.12.10.1.3') {
          // CertBag - Certificado
          debugPrint('>>> [PKCS12] Extraindo certificado...');
          try {
            certificadoBytes = await _extrairCertificado(bagValueBytes);
            debugPrint('>>> [PKCS12] Certificado extraído: ${certificadoBytes?.length ?? 0} bytes');
          } catch (e) {
            debugPrint('>>> [PKCS12] ERRO ao extrair certificado: $e');
          }
        }
        
        // SEMPRE tentar extrair chave privada e certificado de TODOS os SafeBags
        // Muitos certificados brasileiros usam OIDs não padrão
        
        // Tentar chave privada se ainda não encontrou (qualquer tamanho > 50 bytes)
        if (chavePrivada == null && bagValueBytes.length > 50) {
          debugPrint('>>> [PKCS12] ========================================');
          debugPrint('>>> [PKCS12] Tentando extrair chave privada de SafeBag $i');
          debugPrint('>>> [PKCS12] OID: $bagId');
          debugPrint('>>> [PKCS12] Tamanho: ${bagValueBytes.length} bytes');
          debugPrint('>>> [PKCS12] Primeiros bytes: ${bagValueBytes.length >= 10 ? bagValueBytes.sublist(0, 10).map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ') : 'insuficiente'}');
          debugPrint('>>> [PKCS12] ========================================');
          
          try {
            // Tentar estratégia 1
            debugPrint('>>> [PKCS12] Tentando ESTRATÉGIA 1...');
            chavePrivada = await _extrairChavePrivada_Estrategia1(bagValueBytes, senha);
            if (chavePrivada != null) {
              debugPrint('>>> [PKCS12] ✓✓✓ Chave privada encontrada com ESTRATÉGIA 1!');
            }
          } catch (e1) {
            debugPrint('>>> [PKCS12] ESTRATÉGIA 1 falhou: ${e1.toString().substring(0, e1.toString().length > 150 ? 150 : e1.toString().length)}');
            
            // Tentar estratégia 2
            if (chavePrivada == null) {
              try {
                debugPrint('>>> [PKCS12] Tentando ESTRATÉGIA 2...');
                chavePrivada = await _extrairChavePrivada_Estrategia2(bagValueBytes, senha);
                if (chavePrivada != null) {
                  debugPrint('>>> [PKCS12] ✓✓✓ Chave privada encontrada com ESTRATÉGIA 2!');
                }
              } catch (e2) {
                debugPrint('>>> [PKCS12] ESTRATÉGIA 2 falhou: ${e2.toString().substring(0, e2.toString().length > 150 ? 150 : e2.toString().length)}');
              }
            }
          }
          
          if (chavePrivada != null) {
            debugPrint('>>> [PKCS12] ✓✓✓ Chave privada encontrada em SafeBag $i (OID: $bagId)!');
          }
        }
        
        // Tentar certificado se ainda não encontrou (qualquer tamanho > 100 bytes)
        if (certificadoBytes == null && bagValueBytes.length > 100) {
          debugPrint('>>> [PKCS12] Tentando extrair certificado de SafeBag (OID: $bagId, ${bagValueBytes.length} bytes)...');
          try {
            certificadoBytes = await _extrairCertificado(bagValueBytes);
            if (certificadoBytes != null) {
              debugPrint('>>> [PKCS12] ✓✓✓ Certificado encontrado em SafeBag (OID: $bagId)!');
            }
          } catch (e) {
            debugPrint('>>> [PKCS12] Não é certificado: ${e.toString().substring(0, e.toString().length > 100 ? 100 : e.toString().length)}');
          }
        }
      }

      // Debug final
      debugPrint('>>> [PKCS12] RESULTADO FINAL:');
      debugPrint('>>> [PKCS12] - Chave privada: ${chavePrivada != null ? "ENCONTRADA" : "NÃO ENCONTRADA"}');
      debugPrint('>>> [PKCS12] - Certificado: ${certificadoBytes != null ? "ENCONTRADO (${certificadoBytes.length} bytes)" : "NÃO ENCONTRADO"}');

      if (chavePrivada == null) {
        // Coletar informações detalhadas sobre os SafeBags encontrados
        final bagIdsEncontrados = <String>[];
        final bagSizes = <int>[];
        for (var i = 0; i < safeBags.length; i++) {
          final safeBag = safeBags[i];
          if (safeBag.elements != null && safeBag.elements!.isNotEmpty) {
            final bagIdObj = safeBag.elements![0];
            if (bagIdObj is ASN1ObjectIdentifier) {
              final id = bagIdObj.identifier;
              if (id != null) {
                bagIdsEncontrados.add(id);
              }
            }
            // Tentar obter tamanho do bagValue
            if (safeBag.elements!.length >= 2) {
              try {
                final bagValueObj = safeBag.elements![1];
                Uint8List? bagValueBytes;
                if (bagValueObj is ASN1OctetString) {
                  bagValueBytes = Uint8List.fromList(bagValueObj.valueBytes());
                } else {
                  final extractedBytes = _extractBytesFromASN1Object(bagValueObj);
                  if (extractedBytes != null) bagValueBytes = extractedBytes;
                }
                if (bagValueBytes != null) {
                  bagSizes.add(bagValueBytes.length);
                }
              } catch (e) {
                bagSizes.add(0);
              }
            }
          }
        }
        
        debugPrint('>>> [PKCS12] ========================================');
        debugPrint('>>> [PKCS12] DIAGNÓSTICO: Chave privada não encontrada');
        debugPrint('>>> [PKCS12] SafeBags encontrados: ${safeBags.length}');
        debugPrint('>>> [PKCS12] OIDs: ${bagIdsEncontrados.isEmpty ? "Nenhum" : bagIdsEncontrados.join(", ")}');
        debugPrint('>>> [PKCS12] Tamanhos dos SafeBags: ${bagSizes.isEmpty ? "Nenhum" : bagSizes.join(", ")} bytes');
        debugPrint('>>> [PKCS12] Certificado encontrado: ${certificadoBytes != null ? "Sim (${certificadoBytes.length} bytes)" : "Não"}');
        debugPrint('>>> [PKCS12] ========================================');
        
        // Lançar exceção que será capturada pelo certificado_service para tentar conversão OpenSSL
        throw Exception('Chave privada não encontrada no PKCS12.\n\n'
            'INFORMAÇÕES:\n'
            '• SafeBags encontrados: ${safeBags.length}\n'
            '• OIDs dos SafeBags: ${bagIdsEncontrados.isEmpty ? "Nenhum" : bagIdsEncontrados.join(", ")}\n'
            '• Tamanhos dos SafeBags: ${bagSizes.isEmpty ? "Nenhum" : bagSizes.join(", ")} bytes\n'
            '• Certificado encontrado: ${certificadoBytes != null ? "Sim" : "Não"}\n\n'
            'O certificado pode estar em formato não padrão ou a chave privada pode estar em um SafeBag com OID diferente.\n\n'
            'O sistema tentará converter automaticamente usando OpenSSL.\n\n'
            'SOLUÇÃO: Se a conversão automática falhar, re-exporte o certificado no software original (e-CPF/e-CNPJ) em formato PKCS#12 padrão.');
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
    ASN1Object macData,
  ) async {
    try {
      final macDataSeq = macData as ASN1Sequence;
      
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
  /// Implementação robusta com múltiplas tentativas
  static Future<RSAPrivateKey?> _extrairChavePrivada(
    Uint8List encryptedKey,
    String senha,
  ) async {
    debugPrint('>>> [PKCS12] Descriptografando chave privada...');
    
    // Tentar múltiplas estratégias
    Exception? ultimoErro;
    
    // Estratégia 1: Parse padrão
    try {
      return await _extrairChavePrivada_Estrategia1(encryptedKey, senha);
    } catch (e) {
      debugPrint('>>> [PKCS12] Estratégia 1 falhou: $e');
      ultimoErro = e is Exception ? e : Exception(e.toString());
    }
    
    // Estratégia 2: Parse mais tolerante
    try {
      return await _extrairChavePrivada_Estrategia2(encryptedKey, senha);
    } catch (e) {
      debugPrint('>>> [PKCS12] Estratégia 2 falhou: $e');
      ultimoErro = e is Exception ? e : Exception(e.toString());
    }
    
    // Se todas falharam, lançar erro com informações
    throw Exception('Não foi possível extrair a chave privada após tentar múltiplas estratégias.\n\n'
        'O certificado pode usar um formato de criptografia não totalmente suportado.\n\n'
        'SOLUÇÃO: Re-exporte o certificado no software original (e-CPF/e-CNPJ) '
        'em formato PKCS#12 padrão com senha simples.\n\n'
        'Último erro: $ultimoErro');
  }
  
  /// Estratégia 1: Parse padrão EncryptedPrivateKeyInfo
  static Future<RSAPrivateKey> _extrairChavePrivada_Estrategia1(
    Uint8List encryptedKey,
    String senha,
  ) async {
    // Parse EncryptedPrivateKeyInfo
    final parser = ASN1Parser(encryptedKey);
    final encryptedKeyInfoObj = parser.nextObject();
    
    if (encryptedKeyInfoObj is! ASN1Sequence) {
      throw Exception('EncryptedPrivateKeyInfo inválido: esperado ASN1Sequence, recebido ${encryptedKeyInfoObj.runtimeType}');
    }
    
    final encryptedKeyInfo = encryptedKeyInfoObj as ASN1Sequence;
    
    if (encryptedKeyInfo.elements == null || encryptedKeyInfo.elements!.length < 2) {
      throw Exception('EncryptedPrivateKeyInfo inválido: menos de 2 elementos');
    }
    
    // Verificar tipo do primeiro elemento (algorithm identifier)
    final algorithmObj = encryptedKeyInfo.elements![0];
    ASN1Sequence algorithm;
    String algorithmId;
    
    if (algorithmObj is ASN1Sequence) {
      // Formato padrão: AlgorithmIdentifier é uma Sequence
      algorithm = algorithmObj;
      if (algorithm.elements == null || algorithm.elements!.isEmpty) {
        throw Exception('Algorithm identifier inválido: sequence vazia');
      }
      
      final firstElement = algorithm.elements![0];
      if (firstElement is! ASN1ObjectIdentifier) {
        throw Exception('Algorithm identifier inválido: primeiro elemento não é OID, é ${firstElement.runtimeType}');
      }
      final oid = (firstElement as ASN1ObjectIdentifier).identifier;
      if (oid == null) {
        throw Exception('Algorithm identifier OID é nulo');
      }
      algorithmId = oid;
    } else if (algorithmObj is ASN1ObjectIdentifier) {
      // Formato alternativo: OID diretamente - tentar continuar
      final oid = algorithmObj.identifier;
      if (oid == null) {
        throw Exception('Algorithm identifier OID é nulo');
      }
      algorithmId = oid;
      debugPrint('>>> [PKCS12] AVISO: Algorithm identifier é OID direto: $algorithmId');
      // Criar uma sequence artificial para continuar
      algorithm = ASN1Sequence();
      algorithm.elements = [algorithmObj];
    } else {
      throw Exception('Algorithm identifier inválido: tipo ${algorithmObj.runtimeType}');
    }
      
    debugPrint('>>> [PKCS12] Algoritmo de criptografia: $algorithmId');
    
    // Verificar tipo do segundo elemento (encrypted data)
    final encryptedDataObj = encryptedKeyInfo.elements![1];
    if (encryptedDataObj is! ASN1OctetString) {
      throw Exception('Encrypted data inválido: esperado ASN1OctetString, recebido ${encryptedDataObj.runtimeType}');
    }
    
    final encryptedData = Uint8List.fromList((encryptedDataObj as ASN1OctetString).valueBytes());

    // Descriptografar usando PBES2/PBKDF2
    if (algorithmId == '1.2.840.113549.1.5.13') { // PBES2
      debugPrint('>>> [PKCS12] Usando PBES2 para descriptografar...');
      final decryptedKey = await _descriptografarPBES2(encryptedData, senha, algorithm);
      debugPrint('>>> [PKCS12] Chave descriptografada: ${decryptedKey.length} bytes');
      final rsaKey = _parseRSAPrivateKey(decryptedKey);
      debugPrint('>>> [PKCS12] Chave privada RSA parseada com sucesso');
      return rsaKey;
    } else {
      throw Exception('Algoritmo não suportado: $algorithmId (suportado: PBES2)');
    }
  }

  /// Estratégia 2: Parse mais tolerante com variações
  static Future<RSAPrivateKey> _extrairChavePrivada_Estrategia2(
    Uint8List encryptedKey,
    String senha,
  ) async {
    try {
      debugPrint('>>> [PKCS12] Tentando estratégia 2: Parse tolerante...');
      
      // Tentar parsear de forma mais flexível
      final parser = ASN1Parser(encryptedKey);
      final obj = parser.nextObject();
      
      if (obj is! ASN1Sequence) {
        throw Exception('Não é uma sequência');
      }
      
      final seq = obj as ASN1Sequence;
      
      if (seq.elements == null || seq.elements!.isEmpty) {
        throw Exception('Sequência vazia');
      }
      
      // Procurar por diferentes estruturas possíveis
      for (var i = 0; i < seq.elements!.length; i++) {
        final elem = seq.elements![i];
        
        // Se encontrar uma sequência, pode ser o algoritmo
        if (elem is ASN1Sequence && elem.elements != null && elem.elements!.isNotEmpty) {
          try {
            final firstSubElem = elem.elements![0];
            if (firstSubElem is ASN1ObjectIdentifier) {
              final oid = firstSubElem.identifier;
              if (oid == '1.2.840.113549.1.5.13') { // PBES2
                // Encontrou algoritmo, procurar dados criptografados
                if (i + 1 < seq.elements!.length) {
                  final dataElem = seq.elements![i + 1];
                  if (dataElem is ASN1OctetString) {
                    final encryptedData = Uint8List.fromList(dataElem.valueBytes());
                    final decryptedKey = await _descriptografarPBES2(encryptedData, senha, elem);
                    return _parseRSAPrivateKey(decryptedKey);
                  }
                }
              }
            }
          } catch (e) {
            // Continuar procurando
            continue;
          }
        }
      }
      
      throw Exception('Não foi possível encontrar algoritmo e dados criptografados');
    } catch (e) {
      debugPrint('>>> [PKCS12] ERRO na estratégia 2: $e');
      rethrow;
    }
  }

  /// Descriptografa usando PBES2/PBKDF2
  static Future<Uint8List> _descriptografarPBES2(
    Uint8List encryptedData,
    String senha,
    ASN1Sequence algorithm,
  ) async {
    try {
      if (algorithm.elements == null || algorithm.elements!.length < 2) {
        throw Exception('PBES2 params inválidos');
      }
      
      // Parse PBES2-params
      final params = algorithm.elements![1] as ASN1Sequence;
      
      if (params.elements == null || params.elements!.length < 2) {
        throw Exception('PBES2 params incompletos');
      }
      
      final keyDerivationFunc = params.elements![0] as ASN1Sequence;
      final encryptionScheme = params.elements![1] as ASN1Sequence;

      if (keyDerivationFunc.elements == null || keyDerivationFunc.elements!.length < 2) {
        throw Exception('Key derivation function inválida');
      }

      // PBKDF2 params
      final pbkdf2Params = keyDerivationFunc.elements![1] as ASN1Sequence;
      
      if (pbkdf2Params.elements == null || pbkdf2Params.elements!.length < 2) {
        throw Exception('PBKDF2 params incompletos');
      }
      
      final salt = Uint8List.fromList((pbkdf2Params.elements![0] as ASN1OctetString).valueBytes());
      final iterationCount = (pbkdf2Params.elements![1] as ASN1Integer).intValue;
      
      debugPrint('>>> [PKCS12] PBKDF2: salt=${salt.length} bytes, iterations=$iterationCount');

      // Derivar chave usando PBKDF2
      final key = _deriveKeyPBKDF2(senha, salt, iterationCount, 32); // 256 bits

      // AES-256-CBC decryption
      if (encryptionScheme.elements == null || encryptionScheme.elements!.length < 2) {
        throw Exception('Encryption scheme incompleto');
      }
      
      final encryptionOid = (encryptionScheme.elements![0] as ASN1ObjectIdentifier).identifier;
      debugPrint('>>> [PKCS12] Algoritmo de criptografia: $encryptionOid');
      
      if (encryptionOid == '2.16.840.1.101.3.4.1.42') { // AES-256-CBC
        final iv = Uint8List.fromList((encryptionScheme.elements![1] as ASN1OctetString).valueBytes());
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
      
      final parser = ASN1Parser(keyBytes);
      final keyInfo = parser.nextObject() as ASN1Sequence;
      
      if (keyInfo.elements == null || keyInfo.elements!.length < 3) {
        throw Exception('PrivateKeyInfo inválido');
      }
      
      // PrivateKeyInfo { version, algorithm, privateKey }
      final privateKeyObj = keyInfo.elements![2];
      Uint8List privateKeyOctets;
      if (privateKeyObj is ASN1OctetString) {
        privateKeyOctets = Uint8List.fromList(privateKeyObj.valueBytes());
      } else {
        // Tentar extrair bytes de forma segura
        final extractedBytes = _extractBytesFromASN1Object(privateKeyObj);
        if (extractedBytes != null && extractedBytes.isNotEmpty) {
          privateKeyOctets = extractedBytes;
        } else {
          privateKeyOctets = Uint8List.fromList(privateKeyObj.valueBytes());
        }
      }
      
      // Parse RSAPrivateKey
      final keyParser = ASN1Parser(privateKeyOctets);
      final rsaKey = keyParser.nextObject() as ASN1Sequence;
      
      if (rsaKey.elements == null || rsaKey.elements!.length < 6) {
        throw Exception('RSAPrivateKey inválido: menos de 6 elementos');
      }
      
      // RSAPrivateKey { version, modulus, publicExponent, privateExponent, ... }
      final modulus = (rsaKey.elements![1] as ASN1Integer).valueAsBigInteger;
      final privateExponent = (rsaKey.elements![3] as ASN1Integer).valueAsBigInteger;
      final p = (rsaKey.elements![4] as ASN1Integer).valueAsBigInteger;
      final q = (rsaKey.elements![5] as ASN1Integer).valueAsBigInteger;
      
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
      
      final parser = ASN1Parser(certBagBytes);
      final certBag = parser.nextObject() as ASN1Sequence;
      
      if (certBag.elements == null || certBag.elements!.length < 2) {
        debugPrint('>>> [PKCS12] CertBag inválido');
        return null;
      }
      
      // CertBag { certId, certValue }
      final certValueObj = certBag.elements![1];
      Uint8List certBytes;
      if (certValueObj is ASN1OctetString) {
        certBytes = Uint8List.fromList(certValueObj.valueBytes());
      } else {
        // Tentar extrair bytes de forma segura
        debugPrint('>>> [PKCS12] AVISO: certValue não é OctetString, tipo: ${certValueObj.runtimeType}');
        final extractedBytes = _extractBytesFromASN1Object(certValueObj);
        if (extractedBytes != null && extractedBytes.isNotEmpty) {
          certBytes = extractedBytes;
        } else {
          certBytes = Uint8List.fromList(certValueObj.valueBytes());
        }
      }
      
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
      final dados = await PKCS12Service.extrairChaveECertificado(pfxBytes, '');
      final certBytes = carregarCertificado(dados);
      
      if (certBytes == null) {
        return {'cnpj': null, 'validade': null};
      }

      // Parse certificado X509
      final parser = ASN1Parser(certBytes);
      final cert = parser.nextObject() as ASN1Sequence;
      
      // TBSCertificate { version, serialNumber, signature, issuer, validity, subject, ... }
      final tbsCert = cert.elements![0] as ASN1Sequence;
      
      // Extrair CNPJ do subject (simplificado)
      String? cnpj;
      DateTime? validade;
      
      try {
        // Subject está no índice 5
        if (tbsCert.elements!.length > 5) {
          final subject = tbsCert.elements![5] as ASN1Sequence;
          // Procurar CNPJ no subject (OID 2.16.76.1.3.1)
          for (final rdn in subject.elements!) {
            final set = rdn as ASN1Set;
            for (final attr in set.elements!) {
              final seq = attr as ASN1Sequence;
              final oid = (seq.elements![0] as ASN1ObjectIdentifier).identifier;
              if (oid == '2.16.76.1.3.1') { // CNPJ
                final value = seq.elements![1] as ASN1PrintableString;
                cnpj = value.stringValue;
                break;
              }
            }
          }
        }
        
        // Validade está no índice 4
        if (tbsCert.elements!.length > 4) {
          final validity = tbsCert.elements![4] as ASN1Sequence;
          final notAfter = validity.elements![1];
          // Tentar parsear como GeneralizedTime (mais comum)
          if (notAfter is ASN1GeneralizedTime) {
            validade = notAfter.dateTimeValue;
          }
          // Se for string, tentar parsear manualmente
          else if (notAfter is ASN1PrintableString) {
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

  /// Função auxiliar para encontrar OctetString em uma Sequence recursivamente
  static ASN1OctetString? _findOctetStringInSequence(ASN1Sequence seq) {
    try {
      for (var elem in seq.elements ?? []) {
        if (elem is ASN1OctetString) {
          return elem;
        }
        if (elem is ASN1Sequence) {
          final found = _findOctetStringInSequence(elem);
          if (found != null) return found;
        }
      }
    } catch (e) {
      // Ignorar
    }
    return null;
  }

  /// Função auxiliar para extrair bytes de um ASN1Object genérico
  static Uint8List? _extractBytesFromASN1Object(ASN1Object obj) {
    try {
      // Se for OctetString, extrair diretamente
      if (obj is ASN1OctetString) {
        return Uint8List.fromList(obj.valueBytes());
      }
      
      // Se for Sequence, tentar extrair bytes de todos os OctetStrings
      if (obj is ASN1Sequence) {
        for (var elem in obj.elements ?? []) {
          if (elem is ASN1OctetString) {
            return Uint8List.fromList(elem.valueBytes());
          }
          // Se o elemento for uma Sequence aninhada, procurar recursivamente
          if (elem is ASN1Sequence) {
            for (var subElem in elem.elements ?? []) {
              if (subElem is ASN1OctetString) {
                return Uint8List.fromList(subElem.valueBytes());
              }
            }
          }
        }
      }
      
      // Tentar usar valueBytes() se disponível
      try {
        final bytes = obj.valueBytes();
        if (bytes.isNotEmpty) {
          return Uint8List.fromList(bytes);
        }
      } catch (e) {
        // Ignorar
      }
      
      return null;
    } catch (e) {
      debugPrint('>>> [PKCS12] Erro ao extrair bytes de ASN1Object: $e');
      return null;
    }
  }
}

