import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'pkcs12_service.dart';
import 'pem_certificate_service.dart';
import 'certificado_converter_service.dart';
import 'certificado_openssl_service.dart';
import 'certificado_node_service.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/export.dart';

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
    debugPrint('>>> [Certificado] ========================================');
    debugPrint('>>> [Certificado] INÍCIO: carregarCertificado');
    debugPrint('>>> [Certificado] certificadoUrl: "$certificadoUrl"');
    debugPrint('>>> [Certificado] certificadoDigitalBytes: ${certificadoDigitalBytes != null ? "presente (${certificadoDigitalBytes.length} chars)" : "null"}');
    debugPrint('>>> [Certificado] senha: ${senha.isNotEmpty ? "presente (${senha.length} chars)" : "AUSENTE"}');
    debugPrint('>>> [Certificado] ========================================');
    
    // VALIDAÇÃO CRÍTICA: Verificar se temos dados do certificado
    if ((certificadoDigitalBytes == null || certificadoDigitalBytes.isEmpty) &&
        (certificadoUrl.isEmpty || certificadoUrl == 'base64:certificado')) {
      debugPrint('>>> [Certificado] ❌ ERRO: Nenhum dado de certificado fornecido!');
      throw Exception('Certificado digital não fornecido!\n\n'
          'Por favor, forneça o certificado digital (base64 ou URL).\n\n'
          'DIAGNÓSTICO:\n'
          '• Base64: ${certificadoDigitalBytes != null ? "presente" : "ausente"}\n'
          '• URL: ${certificadoUrl.isNotEmpty ? certificadoUrl : "não informada"}');
    }
    
    // VALIDAÇÃO CRÍTICA: Verificar se tem senha
    if (senha.isEmpty) {
      debugPrint('>>> [Certificado] ❌ ERRO: Senha não fornecida!');
      throw Exception('Senha do certificado não fornecida!\n\n'
          'Por favor, forneça a senha do certificado digital.');
    }
    
    try {
      debugPrint('>>> [Certificado] ========================================');
      debugPrint('>>> [Certificado] INÍCIO: carregarCertificado');
      debugPrint('>>> [Certificado] certificadoUrl: $certificadoUrl');
      debugPrint('>>> [Certificado] certificadoDigitalBytes: ${certificadoDigitalBytes != null ? "presente (${certificadoDigitalBytes.length} chars)" : "null"}');
      debugPrint('>>> [Certificado] senha: ${senha.isNotEmpty ? "presente (${senha.length} chars)" : "AUSENTE"}');
      debugPrint('>>> [Certificado] ========================================');
      
      // VALIDAÇÃO CRÍTICA: Verificar se temos os dados necessários
      if (certificadoDigitalBytes == null || certificadoDigitalBytes.isEmpty) {
        if (certificadoUrl.isEmpty || (!certificadoUrl.startsWith('http') && !File(certificadoUrl).existsSync())) {
          debugPrint('>>> [Certificado] ❌ ERRO CRÍTICO: Nenhuma fonte de certificado disponível!');
          throw Exception('Certificado digital não encontrado!\n\n'
              'Por favor, selecione um certificado digital na configuração da empresa.\n\n'
              'URL: ${certificadoUrl.isEmpty ? "não informada" : certificadoUrl}\n'
              'Base64: ${certificadoDigitalBytes != null ? "presente" : "ausente"}');
        }
      }
      
      if (senha.isEmpty) {
        debugPrint('>>> [Certificado] ❌ ERRO CRÍTICO: Senha não fornecida!');
        throw Exception('Senha do certificado é obrigatória!\n\n'
            'Por favor, informe a senha do certificado digital.');
      }
      
      Uint8List bytes;

      // Prioridade 1: Se tiver bytes em base64, usar diretamente
      if (certificadoDigitalBytes != null && certificadoDigitalBytes.isNotEmpty) {
        debugPrint('>>> [Certificado] ========================================');
        debugPrint('>>> [Certificado] Certificado em base64 detectado');
        debugPrint('>>> [Certificado] URL: $certificadoUrl');
        debugPrint('>>> [Certificado] Tamanho base64: ${certificadoDigitalBytes.length} caracteres');
        debugPrint('>>> [Certificado] Primeiros 100 chars: ${certificadoDigitalBytes.length > 100 ? certificadoDigitalBytes.substring(0, 100) : certificadoDigitalBytes}...');
        
        // VALIDAÇÃO CRÍTICA: Verificar se base64 é válido ANTES de tentar decodificar
        // Remover espaços em branco e quebras de linha que podem ter sido adicionados
        String base64Limpo = certificadoDigitalBytes.replaceAll(RegExp(r'\s+'), '');
        if (base64Limpo.length != certificadoDigitalBytes.length) {
          debugPrint('>>> [Certificado] ⚠️ Espaços em branco removidos do base64 (${certificadoDigitalBytes.length} → ${base64Limpo.length} chars)');
          certificadoDigitalBytes = base64Limpo;
        }
        
        try {
          final testDecode = base64Decode(certificadoDigitalBytes);
          debugPrint('>>> [Certificado] ✓ Base64 válido: ${testDecode.length} bytes decodificados');
          if (testDecode.length < 100) {
            throw Exception('Certificado base64 decodificado é muito pequeno (${testDecode.length} bytes). Certifique-se de que o certificado está completo.');
          }
        } catch (e) {
          debugPrint('>>> [Certificado] ❌ ERRO: Base64 inválido ou corrompido!');
          debugPrint('>>> [Certificado] Erro: $e');
          
          // Tentar corrigir base64 removendo caracteres inválidos
          try {
            final base64Corrigido = certificadoDigitalBytes.replaceAll(RegExp(r'[^A-Za-z0-9+/=]'), '');
            if (base64Corrigido.length >= certificadoDigitalBytes.length * 0.9) {
              debugPrint('>>> [Certificado] Tentando corrigir base64 removendo caracteres inválidos...');
              final testDecodeCorrigido = base64Decode(base64Corrigido);
              if (testDecodeCorrigido.length >= 100) {
                debugPrint('>>> [Certificado] ✓✓✓ Base64 corrigido com sucesso!');
                certificadoDigitalBytes = base64Corrigido;
              } else {
                throw Exception('Certificado base64 decodificado é muito pequeno mesmo após correção.');
              }
            } else {
              throw Exception('Base64 muito corrompido para corrigir.');
            }
          } catch (e2) {
            debugPrint('>>> [Certificado] Não foi possível corrigir o base64: $e2');
            throw Exception('Certificado digital está em formato base64 inválido ou corrompido.\n\n'
                'O certificado não pode ser decodificado.\n\n'
                'SOLUÇÃO:\n'
                '1. Vá em "Empresas" → Edite a empresa\n'
                '2. Remova o certificado atual\n'
                '3. Selecione o certificado novamente\n'
                '4. Certifique-se de que aparece "✓ Certificado processado"\n'
                '5. Salve a empresa');
          }
        }
        
        debugPrint('>>> [Certificado] ========================================');
        
        try {
          // Verificar se a URL indica que é PEM (Windows ou arquivo)
          final isPEMFromUrl = certificadoUrl.toLowerCase().contains('pem:') || 
                               certificadoUrl.toLowerCase().contains('windows:pem:') ||
                               certificadoUrl.toLowerCase().endsWith('.pem') ||
                               certificadoUrl.toLowerCase().endsWith('.crt');
          
          debugPrint('>>> [Certificado] isPEMFromUrl: $isPEMFromUrl');
          
          // Tentar decodificar como texto primeiro (PEM)
          String? pemContent;
          try {
            final decodedBytes = base64Decode(certificadoDigitalBytes);
            debugPrint('>>> [Certificado] Base64 decodificado: ${decodedBytes.length} bytes');
            
            // Tentar decodificar como UTF-8 (texto PEM)
            try {
              pemContent = utf8.decode(decodedBytes, allowMalformed: false);
              debugPrint('>>> [Certificado] Decodificado como UTF-8: ${pemContent.length} caracteres');
            } catch (e) {
              debugPrint('>>> [Certificado] Não é UTF-8 válido: $e');
              // Não é texto, tratar como binário
            }
            
            // Verificar se é texto PEM válido
            if (pemContent != null && 
                (isPEMFromUrl || 
                 pemContent.contains('-----BEGIN CERTIFICATE-----') ||
                 pemContent.contains('-----BEGIN RSA PRIVATE KEY-----') ||
                 pemContent.contains('-----BEGIN PRIVATE KEY-----'))) {
              // É PEM em texto
              debugPrint('>>> [Certificado] ✓✓✓ Detectado PEM em base64 (texto)');
              debugPrint('>>> [Certificado] PEM decodificado: ${pemContent.length} caracteres');
              
              // Salvar temporariamente para processar
              Directory tempDir;
              try {
                tempDir = await getTemporaryDirectory();
              } catch (e) {
                tempDir = Directory.systemTemp;
              }
              
              final tempPemFile = File('${tempDir.path}/certificado_pem_${DateTime.now().millisecondsSinceEpoch}.pem');
              await tempPemFile.writeAsString(pemContent);
              debugPrint('>>> [Certificado] Arquivo PEM temporário salvo: ${tempPemFile.path}');
              
              // Processar PEM diretamente
              return await _processarCertificadoPEM(tempPemFile.path, senha);
            }
          } catch (e) {
            debugPrint('>>> [Certificado] Erro ao processar como PEM: $e');
            // Continuar para processar como binário
          }
          
          // Se não for PEM detectado, tratar como binário (PFX)
          debugPrint('>>> [Certificado] Tratando como binário (PFX)...');
          bytes = base64Decode(certificadoDigitalBytes);
          debugPrint('>>> [Certificado] Base64 decodificado: ${bytes.length} bytes');
          debugPrint('>>> [Certificado] Primeiro byte: 0x${bytes[0].toRadixString(16).padLeft(2, '0')}');
          
          // VERIFICAÇÃO CRÍTICA: Se primeiro byte é ASCII imprimível, pode ser:
          // 1. Base64 duplamente codificado (tentar decodificar novamente)
          // 2. Texto PEM que não foi detectado antes
          if (bytes[0] >= 0x20 && bytes[0] <= 0x7E) {
            final primeiroChar = String.fromCharCode(bytes[0]);
            debugPrint('>>> [Certificado] ⚠️ Primeiro byte é ASCII imprimível: "$primeiroChar"');
            debugPrint('>>> [Certificado] Pode ser base64 duplamente codificado ou texto PEM');
            
            // Tentar decodificar como texto UTF-8
            try {
              final texto = utf8.decode(bytes, allowMalformed: false);
              if (texto.contains('-----BEGIN') || texto.contains('-----END')) {
                debugPrint('>>> [Certificado] ✓✓✓ Detectado PEM após decodificar base64!');
                debugPrint('>>> [Certificado] Processando como PEM...');
                
                Directory tempDir;
                try {
                  tempDir = await getTemporaryDirectory();
                } catch (e) {
                  tempDir = Directory.systemTemp;
                }
                
                final tempPemFile = File('${tempDir.path}/certificado_pem_${DateTime.now().millisecondsSinceEpoch}.pem');
                await tempPemFile.writeAsString(texto);
                debugPrint('>>> [Certificado] Arquivo PEM temporário salvo: ${tempPemFile.path}');
                
                return await _processarCertificadoPEM(tempPemFile.path, senha);
              }
            } catch (e) {
              debugPrint('>>> [Certificado] Não é UTF-8 válido: $e');
            }
            
            // Tentar decodificar base64 novamente (caso seja duplamente codificado)
            // Estratégia: Tentar decodificar múltiplas vezes até encontrar PKCS12 válido
            debugPrint('>>> [Certificado] ========================================');
            debugPrint('>>> [Certificado] DETECÇÃO DE BASE64 DUPLAMENTE CODIFICADO');
            debugPrint('>>> [Certificado] Primeiro byte: 0x${bytes[0].toRadixString(16).padLeft(2, '0')} (${String.fromCharCode(bytes[0])})');
            debugPrint('>>> [Certificado] Tamanho: ${bytes.length} bytes');
            debugPrint('>>> [Certificado] ========================================');
            
            Uint8List? bytesCorrigidos;
            int tentativas = 0;
            Uint8List bytesAtuais = bytes;
            
            while (tentativas < 5 && bytesAtuais[0] != 0x30) {
              tentativas++;
              debugPrint('>>> [Certificado] ========================================');
              debugPrint('>>> [Certificado] TENTATIVA $tentativas: Verificando base64 duplamente codificado');
              debugPrint('>>> [Certificado] Primeiro byte atual: 0x${bytesAtuais[0].toRadixString(16).padLeft(2, '0')}');
              debugPrint('>>> [Certificado] Tamanho atual: ${bytesAtuais.length} bytes');
              debugPrint('>>> [Certificado] ========================================');
              
              try {
                // Tentar decodificar como texto UTF-8
                final texto = utf8.decode(bytesAtuais, allowMalformed: true);
                debugPrint('>>> [Certificado] Decodificado como texto: ${texto.length} caracteres');
                debugPrint('>>> [Certificado] Primeiros 100 chars: ${texto.length > 100 ? texto.substring(0, 100) : texto}...');
                
                // Verificar se é base64 válido
                final isBase64 = _isBase64String(texto);
                debugPrint('>>> [Certificado] É base64 válido: $isBase64');
                
                if (isBase64) {
                  debugPrint('>>> [Certificado] ✓✓✓ Detectado base64 válido! Decodificando...');
                  try {
                    // Limpar espaços em branco antes de decodificar
                    final textoLimpo = texto.replaceAll(RegExp(r'\s+'), '');
                    final bytesDecodificados = base64Decode(textoLimpo);
                    debugPrint('>>> [Certificado] Base64 decodificado: ${bytesDecodificados.length} bytes');
                    
                    if (bytesDecodificados.isEmpty) {
                      debugPrint('>>> [Certificado] ❌ Base64 decodificado resultou em bytes vazios');
                      break;
                    }
                    
                    debugPrint('>>> [Certificado] Primeiro byte após decodificar: 0x${bytesDecodificados[0].toRadixString(16).padLeft(2, '0')}');
                    
                    // Se agora começa com 0x30, é PKCS12 válido!
                    if (bytesDecodificados[0] == 0x30) {
                      debugPrint('>>> [Certificado] ✓✓✓✓✓ PKCS12 VÁLIDO encontrado após $tentativas tentativa(s)!');
                      bytesCorrigidos = bytesDecodificados;
                      break;
                    } else {
                      // Continuar tentando com os bytes decodificados
                      debugPrint('>>> [Certificado] Ainda não é PKCS12 (0x30), primeiro byte: 0x${bytesDecodificados[0].toRadixString(16).padLeft(2, '0')}');
                      debugPrint('>>> [Certificado] Continuando tentativa...');
                      
                      // Verificar se os bytes decodificados são menores (pode ser que esteja no caminho certo)
                      if (bytesDecodificados.length < bytesAtuais.length) {
                        bytesAtuais = bytesDecodificados;
                      } else {
                        debugPrint('>>> [Certificado] ⚠️ Bytes decodificados não são menores, pode não ser base64 duplamente codificado');
                        break;
                      }
                    }
                  } catch (e) {
                    debugPrint('>>> [Certificado] ❌ Erro ao decodificar base64: $e');
                    break;
                  }
                } else {
                  debugPrint('>>> [Certificado] Não é base64 válido, parando tentativas');
                  break;
                }
              } catch (e) {
                debugPrint('>>> [Certificado] ❌ Erro ao decodificar como UTF-8: $e');
                break;
              }
            }
            
            // Se encontrou bytes corrigidos, usar eles
            if (bytesCorrigidos != null) {
              debugPrint('>>> [Certificado] ✓✓✓ Usando bytes corrigidos após $tentativas tentativa(s)');
              bytes = bytesCorrigidos;
              debugPrint('>>> [Certificado] Primeiro byte após correção: 0x${bytes[0].toRadixString(16).padLeft(2, '0')}');
            } else {
              debugPrint('>>> [Certificado] ⚠️ Não foi possível corrigir o formato após $tentativas tentativa(s)');
              debugPrint('>>> [Certificado] Primeiro byte ainda é: 0x${bytes[0].toRadixString(16).padLeft(2, '0')}');
              debugPrint('>>> [Certificado] Continuando com bytes originais (pode falhar)');
            }
          } else {
            debugPrint('>>> [Certificado] Primeiro byte não é ASCII imprimível, tratando como binário PKCS12');
          }
          
          debugPrint('>>> [Certificado] Carregado de base64 (binário/PFX): ${bytes.length} bytes');
          debugPrint('>>> [Certificado] Primeiro byte final: 0x${bytes[0].toRadixString(16).padLeft(2, '0')}');
        } catch (e) {
          debugPrint('>>> [Certificado] ERRO ao decodificar base64: $e');
          throw Exception('Erro ao decodificar certificado base64: $e');
        }
      }
      // Prioridade 2: Se for URL (Firebase Storage, etc), fazer download
      else if (certificadoUrl.startsWith('http://') || certificadoUrl.startsWith('https://')) {
        bytes = await _downloadCertificado(certificadoUrl);
      }
      // Prioridade 3: Se for path local, ler arquivo
      else if (certificadoUrl.isNotEmpty && !certificadoUrl.startsWith('http')) {
        debugPrint('>>> [Certificado] Tentando ler arquivo local: $certificadoUrl');
        final file = File(certificadoUrl);
        if (await file.exists()) {
          debugPrint('>>> [Certificado] Arquivo existe: ${await file.length()} bytes');
          // Verificar se é arquivo PEM (texto) ou PFX (binário)
          final extensao = certificadoUrl.toLowerCase();
          if (extensao.endsWith('.pem') || extensao.endsWith('.crt') || extensao.endsWith('.key')) {
            // Arquivo PEM - processar como texto
            debugPrint('>>> [Certificado] Detectado arquivo PEM, processando...');
            return await _processarCertificadoPEM(certificadoUrl, senha);
          } else {
            // Arquivo PFX/P12 - processar como binário
            bytes = await file.readAsBytes();
            debugPrint('>>> [Certificado] Arquivo PFX lido: ${bytes.length} bytes');
          }
        } else {
          debugPrint('>>> [Certificado] ERRO: Arquivo não encontrado: $certificadoUrl');
          throw Exception('Arquivo de certificado não encontrado: $certificadoUrl\n\n'
              'O certificado pode ter sido movido ou deletado.\n'
              'Por favor, selecione o certificado novamente na configuração da empresa.');
        }
      } else {
        // Nenhuma fonte de certificado disponível
        debugPrint('>>> [Certificado] ERRO: Nenhuma fonte de certificado disponível');
        debugPrint('>>> [Certificado] certificadoUrl: "$certificadoUrl"');
        debugPrint('>>> [Certificado] certificadoDigitalBytes: ${certificadoDigitalBytes != null ? "presente" : "null"}');
        throw Exception('Certificado digital não encontrado!\n\n'
            'Por favor, selecione um certificado digital na configuração da empresa.\n\n'
            'URL: ${certificadoUrl.isEmpty ? "não informada" : certificadoUrl}\n'
            'Base64: ${certificadoDigitalBytes != null ? "presente" : "ausente"}');
      }

      // Validar tamanho mínimo do arquivo
      if (bytes.length < 100) {
        throw Exception('Arquivo de certificado muito pequeno (${bytes.length} bytes). Certifique-se de que o arquivo está completo.\n\n'
            'Um certificado digital válido geralmente tem pelo menos 1KB (1024 bytes).\n\n'
            'SOLUÇÃO:\n'
            '1. Verifique se o arquivo do certificado está completo\n'
            '2. Re-exporte o certificado se necessário\n'
            '3. Selecione o certificado novamente no sistema');
      }
      
      // VALIDAÇÃO CRÍTICA: Verificar se começa com 0x30 (PKCS12) ou é PEM
      final primeiroByte = bytes[0];
      final isPKCS12 = primeiroByte == 0x30;
      final isPEM = bytes.length > 20 && 
                   (utf8.decode(bytes.take(20).toList(), allowMalformed: true).contains('-----BEGIN'));
      
      debugPrint('>>> [Certificado] Tamanho do arquivo: ${bytes.length} bytes');
      debugPrint('>>> [Certificado] Primeiro byte: 0x${primeiroByte.toRadixString(16).padLeft(2, '0')}');
      debugPrint('>>> [Certificado] É PKCS12 (0x30): $isPKCS12');
      debugPrint('>>> [Certificado] É PEM: $isPEM');
      
      if (!isPKCS12 && !isPEM) {
        debugPrint('>>> [Certificado] ⚠️ AVISO: Certificado não parece ser PKCS12 nem PEM válido');
        debugPrint('>>> [Certificado] Primeiros 50 bytes (hex): ${bytes.take(50).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
        debugPrint('>>> [Certificado] Tentando processar mesmo assim...');
      }
      
      // ESTRATÉGIA: Tentar parsing direto PRIMEIRO (mais rápido, sem dependência externa)
      // Se falhar, tentar OpenSSL como fallback
      debugPrint('>>> [Certificado] ========================================');
      debugPrint('>>> [Certificado] ESTRATÉGIA: Tentar parsing direto PFX PRIMEIRO');
      debugPrint('>>> [Certificado] ========================================');
      
      // Verificar integridade do certificado antes de processar
      debugPrint('>>> [Certificado] ========================================');
      debugPrint('>>> [Certificado] VERIFICAÇÃO DE INTEGRIDADE');
      debugPrint('>>> [Certificado] Tamanho do arquivo: ${bytes.length} bytes');
      debugPrint('>>> [Certificado] Primeiros bytes: ${bytes.length >= 4 ? bytes.sublist(0, 4).map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ') : 'insuficiente'}');
      debugPrint('>>> [Certificado] Assinatura PKCS12 esperada: 0x30 0x82 (DER sequence)');
      debugPrint('>>> [Certificado] ========================================');
      
      // Verificar se é realmente um arquivo PKCS12 válido
      if (bytes.length < 4) {
        throw Exception('Arquivo de certificado muito pequeno (${bytes.length} bytes). Certifique-se de que o arquivo está completo.');
      }
      
      // Verificar assinatura PKCS12 (deve começar com 0x30 0x82 ou similar)
      final primeiroByteVerificacao = bytes[0];
      final segundoByte = bytes.length > 1 ? bytes[1] : 0;
      debugPrint('>>> [Certificado] Primeiro byte: 0x${primeiroByteVerificacao.toRadixString(16).padLeft(2, '0')}');
      debugPrint('>>> [Certificado] Segundo byte: 0x${segundoByte.toRadixString(16).padLeft(2, '0')}');
      
      // DETECÇÃO AUTOMÁTICA DE FORMATO
      // Se não começar com 0x30 (DER/PKCS12), pode ser:
      // 1. Texto PEM (começa com "-----BEGIN")
      // 2. Base64 ainda não decodificado
      // 3. Arquivo corrompido
      if (primeiroByteVerificacao != 0x30) {
        debugPrint('>>> [Certificado] ⚠️ AVISO: Primeiro byte não é 0x30 (não parece ser DER/PKCS12)');
        debugPrint('>>> [Certificado] Tentando detectar formato alternativo...');
        
        // Tentar detectar se é texto PEM
        try {
          final texto = utf8.decode(bytes.sublist(0, bytes.length > 100 ? 100 : bytes.length), allowMalformed: true);
          if (texto.contains('-----BEGIN') || texto.contains('-----END')) {
            debugPrint('>>> [Certificado] ✓✓✓ Detectado texto PEM dentro dos bytes!');
            debugPrint('>>> [Certificado] Processando como PEM...');
            
            // Salvar temporariamente como PEM
            Directory tempDir;
            try {
              tempDir = await getTemporaryDirectory();
            } catch (e) {
              tempDir = Directory.systemTemp;
            }
            
            final tempPemFile = File('${tempDir.path}/certificado_pem_${DateTime.now().millisecondsSinceEpoch}.pem');
            await tempPemFile.writeAsString(texto);
            debugPrint('>>> [Certificado] Arquivo PEM temporário salvo: ${tempPemFile.path}');
            
            // Processar como PEM
            return await _processarCertificadoPEM(tempPemFile.path, senha);
          }
        } catch (e) {
          debugPrint('>>> [Certificado] Não é texto válido: $e');
        }
        
        // Se primeiro byte é ASCII imprimível (0x20-0x7E), pode ser base64 codificado
        if (primeiroByteVerificacao >= 0x20 && primeiroByteVerificacao <= 0x7E) {
          debugPrint('>>> [Certificado] ⚠️ Primeiro byte é ASCII imprimível: "${String.fromCharCode(primeiroByteVerificacao)}"');
          debugPrint('>>> [Certificado] Pode ser base64 ainda não decodificado');
          
          // Tentar decodificar como base64
          try {
            final texto = utf8.decode(bytes, allowMalformed: true);
            if (_isBase64String(texto)) {
              debugPrint('>>> [Certificado] ✓ Detectado base64 válido! Decodificando...');
              final bytesDecodificados = base64Decode(texto);
              debugPrint('>>> [Certificado] Base64 decodificado: ${bytesDecodificados.length} bytes');
              debugPrint('>>> [Certificado] Primeiro byte após decodificar: 0x${bytesDecodificados[0].toRadixString(16).padLeft(2, '0')}');
              
              // Se agora começa com 0x30, usar esses bytes!
              if (bytesDecodificados[0] == 0x30) {
                debugPrint('>>> [Certificado] ✓✓✓ PKCS12 VÁLIDO encontrado após decodificar base64!');
                bytes = bytesDecodificados;
              } else {
                debugPrint('>>> [Certificado] Ainda não é PKCS12 válido após decodificar');
              }
            }
          } catch (e) {
            debugPrint('>>> [Certificado] Erro ao tentar decodificar base64: $e');
          }
        } else {
          debugPrint('>>> [Certificado] ⚠️ Primeiro byte não é ASCII imprimível nem 0x30');
          debugPrint('>>> [Certificado] Arquivo pode estar corrompido ou em formato desconhecido');
        }
      }
      
      // TENTAR 1: Parsing direto PKCS12 (sem conversão)
      Map<String, dynamic>? pkcs12Result;
      String erroDiretoStr = '';
      try {
        debugPrint('>>> [Certificado] ========================================');
        debugPrint('>>> [Certificado] TENTATIVA 1: Parsing direto do PFX');
        debugPrint('>>> [Certificado] ========================================');
        debugPrint('>>> [Certificado] Tentando parsing direto do PFX...');
        debugPrint('>>> [Certificado] Tamanho: ${bytes.length} bytes');
        debugPrint('>>> [Certificado] Senha: ${senha.isNotEmpty ? "presente (${senha.length} chars)" : "AUSENTE"}');
        pkcs12Result = await PKCS12Service.extrairChaveECertificado(bytes, senha);
        debugPrint('>>> [Certificado] ✓✓✓ PFX processado diretamente com sucesso!');
        
        // Se chegou aqui, o parsing direto funcionou!
        final privateKey = pkcs12Result['privateKey'] as RSAPrivateKey?;
        final certificateBytes = pkcs12Result['certificate'] as Uint8List?;
        
        if (privateKey != null && certificateBytes != null) {
          debugPrint('>>> [Certificado] Chave privada e certificado extraídos com sucesso!');
          debugPrint('>>> [Certificado] Tamanho do certificado: ${certificateBytes.length} bytes');
          
          // Criar objeto CertificadoDigital a partir dos dados extraídos
          final certificado = CertificadoDigital(
            bytes: bytes, // Manter bytes originais do PFX
            senha: senha,
            cnpj: pkcs12Result['cnpj'] as String?,
            validade: pkcs12Result['validade'] as DateTime?,
            privateKey: privateKey,
          );
          
          debugPrint('>>> [Certificado] ✓✓✓ Certificado criado com sucesso do PFX direto!');
          return certificado;
        } else {
          throw Exception('Chave privada ou certificado não encontrados no resultado do parsing');
        }
      } catch (eDireto) {
        erroDiretoStr = eDireto.toString();
        debugPrint('>>> [Certificado] ========================================');
        debugPrint('>>> [Certificado] ❌ TENTATIVA 1 FALHOU: Parsing direto');
        debugPrint('>>> [Certificado] Erro: $erroDiretoStr');
        debugPrint('>>> [Certificado] Tipo: ${eDireto.runtimeType}');
        debugPrint('>>> [Certificado] ========================================');
        
        // Se for erro de senha, não tentar outras estratégias
        if (erroDiretoStr.contains('Senha incorreta') || 
            erroDiretoStr.contains('mac verify failure') ||
            erroDiretoStr.contains('invalid password') ||
            erroDiretoStr.contains('bad password')) {
          debugPrint('>>> [Certificado] ⚠️ Erro de senha detectado - não tentar outras estratégias');
          throw Exception('Senha do certificado incorreta.\n\n'
              'Verifique a senha e tente novamente.\n\n'
              'DICA: A senha é case-sensitive (diferencia maiúsculas de minúsculas).');
        }
        
        // Se não for erro crítico, tentar OpenSSL como fallback
        debugPrint('>>> [Certificado] Tentando conversão OpenSSL como fallback...');
      }
      
      // TENTAR 2: Processamento OpenSSL robusto (similar ao node-forge)
      debugPrint('>>> [Certificado] ========================================');
      debugPrint('>>> [Certificado] TENTATIVA 2: Processamento OpenSSL robusto');
      debugPrint('>>> [Certificado] Abordagem similar ao node-forge (OpenSSL por baixo)');
      debugPrint('>>> [Certificado] ========================================');
      
      try {
        // Verificar se OpenSSL está disponível
        debugPrint('>>> [Certificado] Verificando disponibilidade do OpenSSL...');
        final opensslDisponivel = await CertificadoOpenSSLService.verificarOpenSSL();
        debugPrint('>>> [Certificado] OpenSSL disponível: $opensslDisponivel');
        
        if (!opensslDisponivel) {
          debugPrint('>>> [Certificado] ❌ OpenSSL NÃO está disponível!');
          debugPrint('>>> [Certificado] Tentando encontrar OpenSSL manualmente...');
          
          // Tentar encontrar OpenSSL diretamente
          final opensslPath = await CertificadoConverterService.encontrarOpenSSL();
          debugPrint('>>> [Certificado] OpenSSL encontrado: ${opensslPath ?? "NÃO ENCONTRADO"}');
          
          if (opensslPath == null) {
            throw Exception('OpenSSL não está disponível no sistema.\n\n'
                'SOLUÇÃO:\n'
                '1. Execute: .\\instalar_openssl.ps1\n'
                '2. OU instale Git Bash (já vem com OpenSSL)\n'
                '3. OU converta manualmente: openssl pkcs12 -in certificado.pfx -out certificado.pem -nodes');
          } else {
            debugPrint('>>> [Certificado] ✓ OpenSSL encontrado manualmente: $opensslPath');
          }
        } else {
          debugPrint('>>> [Certificado] ✓ OpenSSL disponível, processando PFX...');
        }
        
        // Usar serviço robusto baseado em OpenSSL
        final resultado = await CertificadoOpenSSLService.processarPFXComOpenSSL(
          pfxBytes: bytes,
          senha: senha,
        );
        
        debugPrint('>>> [Certificado] ✓✓✓ OpenSSL processou com sucesso!');
        
        // Extrair dados do resultado
        final privateKey = resultado['privateKey'] as RSAPrivateKey?;
        final certificateBytes = resultado['certificateBytes'] as Uint8List?;
        
        if (privateKey != null && certificateBytes != null) {
          debugPrint('>>> [Certificado] Chave privada e certificado extraídos com sucesso!');
          
          // Criar objeto CertificadoDigital
          final certificado = CertificadoDigital(
            bytes: certificateBytes,
            senha: senha,
            cnpj: resultado['cnpj'] as String?,
            validade: resultado['validade'] as DateTime?,
            privateKey: privateKey,
          );
          
          debugPrint('>>> [Certificado] ✓✓✓ Certificado criado com sucesso via OpenSSL!');
          return certificado;
        } else {
          throw Exception('Chave privada ou certificado não encontrados no resultado do OpenSSL');
        }
      } catch (eOpenSSL) {
        debugPrint('>>> [Certificado] ========================================');
        debugPrint('>>> [Certificado] ⚠️ Conversão OpenSSL falhou ou não disponível');
        debugPrint('>>> [Certificado] Erro: $eOpenSSL');
        debugPrint('>>> [Certificado] Tipo: ${eOpenSSL.runtimeType}');
        debugPrint('>>> [Certificado] ========================================');
        
        final erroStr = eOpenSSL.toString();
        
        // Se for erro de OpenSSL não encontrado, lançar erro claro
        if (erroStr.contains('OpenSSL não encontrado') || 
            erroStr.contains('OpenSSL não está disponível')) {
          throw Exception('OpenSSL não encontrado para conversão automática.\n\n'
              'SOLUÇÃO:\n'
              '1. Execute: .\\instalar_openssl.ps1\n'
              '2. OU converta manualmente: openssl pkcs12 -in certificado.pfx -out certificado.pem -nodes\n'
              '3. OU re-exporte o certificado em formato PKCS#12 padrão.');
        }
        
        // Se for erro de senha, não tentar parsing direto (vai falhar também)
        if (erroStr.contains('Senha incorreta') || 
            erroStr.contains('invalid password') ||
            erroStr.contains('bad password') ||
            erroStr.contains('mac verify failure')) {
          throw Exception('Senha do certificado incorreta. Verifique a senha e tente novamente.');
        }
        
        // Se chegou aqui, OpenSSL falhou, mas já tentamos parsing direto antes
        
        // TENTAR 3: Cloud Function (Node.js) - Especialmente para Web ou se OpenSSL local falhar
        debugPrint('>>> [Certificado] ========================================');
        debugPrint('>>> [Certificado] TENTATIVA 3: Cloud Function (Node.js)');
        debugPrint('>>> [Certificado] Útil para Web ou fallbacks remotos');
        debugPrint('>>> [Certificado] ========================================');
        
        try {
          final nodeService = CertificadoNodeService();
          final nodeResult = await nodeService.processarCertificado(
            bytes: bytes,
            senha: senha,
          );
          
          if (nodeResult['sucesso'] == true) {
            debugPrint('>>> [Certificado] ✓✓✓ Cloud Function processou com sucesso!');
            
            final certificadoData = nodeResult['certificado'] as Map<String, dynamic>;
            final chaveData = nodeResult['chavePrivada'] as Map<String, dynamic>;
            final info = nodeResult['informacoes'] as Map<String, dynamic>;
            
            // Re-instanciar o service PKCS12 para extrair a chave do PEM retornado (se necessário)
            // Ou converter o PEM direto para o modelo PointyCastle
            // Mas o CertificadoNodeService já retornou os bytes do certificado PEM
            
            // Para extrair a chave privada RSA do PEM retornado:
            final privateKeyPem = chaveData['pem'] as String;
            final privateKey = await PEMCertificateService.extrairChavePrivada(privateKeyPem);
            
            final certificado = CertificadoDigital(
              bytes: bytes,
              senha: senha,
              cnpj: info['cnpj'] as String?,
              validade: info['validade'] != null ? DateTime.parse(info['validade'] as String) : null,
              privateKey: privateKey,
            );
            
            debugPrint('>>> [Certificado] ✓✓✓ Certificado criado com sucesso via Cloud Function!');
            return certificado;
          }
        } catch (eNode) {
          debugPrint('>>> [Certificado] ⚠️ Cloud Function falhou: $eNode');
        }

        // Lançar erro final com diagnóstico detalhado
        final erroOpenSSLStr = eOpenSSL.toString();
        
        debugPrint('>>> [Certificado] ========================================');
        debugPrint('>>> [Certificado] DIAGNÓSTICO FINAL');
        debugPrint('>>> [Certificado] Tamanho do arquivo: ${bytes.length} bytes');
        debugPrint('>>> [Certificado] Primeiro byte: 0x${bytes[0].toRadixString(16).padLeft(2, '0')}');
        final erroDiretoStrFinal = erroDiretoStr.isNotEmpty ? erroDiretoStr : 'não capturado';
        debugPrint('>>> [Certificado] Erro parsing direto: $erroDiretoStrFinal');
        debugPrint('>>> [Certificado] Erro OpenSSL: $erroOpenSSLStr');
        debugPrint('>>> [Certificado] ========================================');
        
        // Verificar se é problema de senha
        if (erroDiretoStrFinal.contains('Senha incorreta') || 
            erroDiretoStrFinal.contains('mac verify failure') ||
            erroDiretoStrFinal.contains('invalid password') ||
            erroDiretoStrFinal.contains('bad password') ||
            erroOpenSSLStr.contains('invalid password') ||
            erroOpenSSLStr.contains('bad password') ||
            erroOpenSSLStr.contains('mac verify failure')) {
          throw Exception('Senha do certificado incorreta.\n\n'
              'Verifique a senha e tente novamente.\n\n'
              'DICA: A senha é case-sensitive (diferencia maiúsculas de minúsculas).');
        }
        
        // Verificar se o arquivo está corrompido
        if (bytes.length < 500) {
          throw Exception('Arquivo de certificado muito pequeno (${bytes.length} bytes).\n\n'
              'O certificado pode estar corrompido ou incompleto.\n\n'
              'SOLUÇÃO:\n'
              '1. Re-exporte o certificado do Windows\n'
              '2. Certifique-se de que o arquivo está completo\n'
              '3. Tente selecionar o certificado novamente');
        }
        
        // Erro genérico
        final erroParsingResumido = erroDiretoStrFinal.isNotEmpty 
            ? (erroDiretoStrFinal.length > 100 ? erroDiretoStrFinal.substring(0, 100) + "..." : erroDiretoStrFinal)
            : "não capturado";
        
        // Diagnóstico do formato
        final primeiroByteHex = bytes[0].toRadixString(16).padLeft(2, '0');
        final primeiroByteChar = (bytes[0] >= 0x20 && bytes[0] <= 0x7E) ? String.fromCharCode(bytes[0]) : 'não imprimível';
        final formatoDetectado = primeiroByteHex == '30' 
            ? 'PKCS12 válido (mas falhou no parsing)'
            : primeiroByteChar != 'não imprimível'
                ? 'Possivelmente texto/base64 (primeiro char: "$primeiroByteChar")'
                : 'Formato desconhecido';
        
        // Verificar se o erro do OpenSSL indica problema específico
        final erroOpenSSLLower = erroOpenSSLStr.toLowerCase();
        final problemaEspecifico = erroOpenSSLLower.contains('no private key') || erroOpenSSLLower.contains('no private keys')
            ? '\n⚠️ PROBLEMA IDENTIFICADO: Certificado exportado SEM chave privada!\n'
              'O certificado foi exportado sem incluir a chave privada.\n'
              'É necessário re-exportar o certificado INCLUINDO a chave privada.\n'
            : erroOpenSSLLower.contains('mac verify') || erroOpenSSLLower.contains('invalid password')
            ? '\n⚠️ PROBLEMA IDENTIFICADO: Senha incorreta!\n'
              'A senha fornecida não consegue descriptografar o certificado.\n'
              'Verifique a senha e tente novamente.\n'
            : '';
        
        throw Exception('🔴 NÃO FOI POSSÍVEL PROCESSAR O CERTIFICADO PFX\n\n'
            'O sistema tentou:\n'
            '1. Parsing direto do PFX (sem conversão) - FALHOU\n'
            '2. Conversão automática usando OpenSSL - FALHOU\n\n'
            'DIAGNÓSTICO:\n'
            '• Tamanho do arquivo: ${bytes.length} bytes\n'
            '• Primeiro byte: 0x$primeiroByteHex ($primeiroByteChar)\n'
            '• Formato detectado: $formatoDetectado\n'
            '• Erro parsing: $erroParsingResumido\n'
            '$problemaEspecifico'
            '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
            '✅ SOLUÇÃO DEFINITIVA:\n\n'
            '1️⃣ RE-EXPORTE O CERTIFICADO:\n'
            '   • Abra o certificado no software original (e-CPF/e-CNPJ Manager)\n'
            '   • Clique com botão direito → Exportar\n'
            '   • ✅ MARQUE "Incluir chave privada" ou "Export private key"\n'
            '   • ✅ Use senha SIMPLES (apenas letras e números)\n'
            '   • ❌ NÃO marque "Habilitar proteção forte"\n'
            '   • Salve como .pfx\n\n'
            '2️⃣ USE O NOVO ARQUIVO:\n'
            '   • Selecione o novo arquivo .pfx no sistema\n'
            '   • Digite a senha simples que você criou\n'
            '   • O sistema processará automaticamente\n\n'
            '3️⃣ ALTERNATIVA: SELECIONAR DO WINDOWS\n'
            '   • Use o botão "Selecionar Certificado do Windows"\n'
            '   • Isso evita problemas de formato\n\n'
            '4️⃣ TESTE MANUAL (se necessário):\n'
            '   openssl pkcs12 -in certificado.pfx -out certificado.pem -nodes\n'
            '   Se funcionar, o certificado está OK e o problema é outro.');
      }
    } catch (e) {
      debugPrint('>>> [Certificado] ERRO ao carregar: $e');
      
      // Se a exceção já tem uma mensagem detalhada (contém quebras de linha ou "SOLUÇÃO"),
      // preservar a mensagem original
      final erroStr = e.toString();
      if (erroStr.contains('\n') || 
          erroStr.contains('SOLUÇÃO') || 
          erroStr.contains('RE-EXPORTAR') ||
          erroStr.contains('Biblioteca asn1lib não consegue processar')) {
        // Re-lançar a exceção original que já tem mensagem detalhada
        rethrow;
      }
      
      // Caso contrário, criar mensagem genérica
      throw Exception('Erro ao carregar certificado: $e');
    }
  }

  /// Verifica se uma string parece ser base64 válido
  bool _isBase64String(String str) {
    if (str.isEmpty) return false;
    
    // Remover espaços em branco e quebras de linha
    final strLimpa = str.replaceAll(RegExp(r'\s+'), '');
    if (strLimpa.isEmpty) return false;
    
    // Base64 válido contém apenas: A-Z, a-z, 0-9, +, /, = (padding)
    final base64Regex = RegExp(r'^[A-Za-z0-9+/=]+$');
    if (!base64Regex.hasMatch(strLimpa)) {
      debugPrint('>>> [Certificado] _isBase64String: Não passa no regex (contém caracteres inválidos)');
      return false;
    }
    
    // Verificar se o comprimento é múltiplo de 4 (ou próximo, considerando padding)
    // Base64 pode ter 0, 1 ou 2 caracteres '=' no final
    final comprimentoSemPadding = strLimpa.replaceAll('=', '').length;
    final comprimentoValido = comprimentoSemPadding % 4 == 0 || 
                             (comprimentoSemPadding + 1) % 4 == 0 || 
                             (comprimentoSemPadding + 2) % 4 == 0;
    
    if (!comprimentoValido) {
      debugPrint('>>> [Certificado] _isBase64String: Comprimento inválido (${strLimpa.length} chars, sem padding: $comprimentoSemPadding)');
    } else {
      debugPrint('>>> [Certificado] _isBase64String: ✓ Base64 válido (${strLimpa.length} chars)');
    }
    
    return comprimentoValido;
  }

  /// Faz download do certificado de uma URL
  /// NOTA: Requer importação de http se necessário
  Future<Uint8List> _downloadCertificado(String url) async {
    try {
      debugPrint('>>> [Certificado] Fazendo download de: $url');
      
      // Usar HttpClient nativo do Dart para evitar dependência de http
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      
      if (response.statusCode != 200) {
        throw Exception('Erro ao fazer download do certificado: HTTP ${response.statusCode}');
      }
      
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
      }
      client.close();
      
      debugPrint('>>> [Certificado] Download concluído: ${bytes.length} bytes');
      return Uint8List.fromList(bytes);
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

  /// Processa certificado em formato PEM
  /// Extrai chave privada RSA e certificado X509
  Future<CertificadoDigital> _processarCertificadoPEM(
    String arquivoPEM,
    String senha,
  ) async {
    try {
      debugPrint('>>> [Certificado] ========================================');
      debugPrint('>>> [Certificado] Processando certificado PEM...');
      debugPrint('>>> [Certificado] Arquivo: $arquivoPEM');
      debugPrint('>>> [Certificado] ========================================');
      
      final file = File(arquivoPEM);
      if (!await file.exists()) {
        throw Exception('Arquivo PEM não encontrado: $arquivoPEM');
      }
      
      final conteudo = await file.readAsString();
      debugPrint('>>> [Certificado] Arquivo PEM lido: ${conteudo.length} caracteres');
      
      if (!PEMCertificateService.isValidPEM(conteudo)) {
        throw Exception('Arquivo PEM inválido ou corrompido. Certifique-se de que o arquivo contém blocos BEGIN/END.');
      }
      
      // Processar PEM usando o serviço
      debugPrint('>>> [Certificado] Extraindo chave privada e certificado do PEM...');
      final resultado = await PEMCertificateService.processarPEM(conteudo, senha);
      
      if (resultado['privateKey'] == null) {
        throw Exception('Chave privada não encontrada no arquivo PEM.\n\n'
            'Certifique-se de que o arquivo PEM contém:\n'
            '• Certificado (-----BEGIN CERTIFICATE-----)\n'
            '• Chave privada (-----BEGIN PRIVATE KEY----- ou -----BEGIN RSA PRIVATE KEY-----)\n\n'
            'Se o arquivo foi convertido do PFX, certifique-se de usar o comando:\n'
            'openssl pkcs12 -in certificado.pfx -out certificado.pem -nodes');
      }
      
      if (resultado['certificate'] == null) {
        throw Exception('Certificado não encontrado no arquivo PEM.\n\n'
            'Certifique-se de que o arquivo PEM contém o certificado X509.');
      }
      
      debugPrint('>>> [Certificado] ✓ Chave privada extraída');
      debugPrint('>>> [Certificado] ✓ Certificado extraído');
      
      // Extrair informações básicas (CNPJ, validade)
      String? cnpj;
      DateTime? validade;
      
      try {
        final info = await PEMCertificateService.extrairInformacoesBasicas(conteudo);
        cnpj = info['cnpj'];
        validade = info['validade'];
        debugPrint('>>> [Certificado] CNPJ: $cnpj');
        debugPrint('>>> [Certificado] Validade: $validade');
      } catch (e) {
        debugPrint('>>> [Certificado] Aviso: Não foi possível extrair CNPJ/validade: $e');
      }
      
      // Ler bytes do arquivo para armazenar
      final bytes = await file.readAsBytes();
      
      // Criar objeto CertificadoDigital
      final certificado = CertificadoDigital(
        bytes: bytes,
        senha: senha,
        cnpj: cnpj,
        validade: validade,
        privateKey: resultado['privateKey'] as RSAPrivateKey?,
      );
      
      debugPrint('>>> [Certificado] ✓✓✓ Certificado PEM processado com sucesso!');
      return certificado;
    } catch (e) {
      debugPrint('>>> [Certificado] ERRO ao processar PEM: $e');
      debugPrint('>>> [Certificado] Tipo do erro: ${e.runtimeType}');
      rethrow;
    }
  }

  /// Salva certificado temporariamente
  Future<String> salvarCertificadoTemporario(Uint8List bytes) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/certificado_${DateTime.now().millisecondsSinceEpoch}.pfx');
    await file.writeAsBytes(bytes);
    return file.path;
  }

}
