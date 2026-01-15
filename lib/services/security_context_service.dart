import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Serviço para configurar SecurityContext com certificado PEM
/// Permite usar certificado para autenticação de cliente HTTPS
/// 
/// NOTA: Esta abordagem expõe a chave privada no frontend.
/// Para produção, considere usar um backend dedicado.
class SecurityContextService {
  /// Cria um SecurityContext configurado com certificado e chave privada PEM
  /// 
  /// Parâmetros:
  /// - [certificadoPEM]: Conteúdo do arquivo certificado_publico.pem
  /// - [chavePrivadaPEM]: Conteúdo do arquivo chave_privada.pem
  /// - [senhaChave]: Senha da chave privada PEM (se houver, null se não criptografada)
  /// 
  /// Retorna: SecurityContext configurado para uso com HttpClient
  static SecurityContext criarSecurityContext({
    required String certificadoPEM,
    required String chavePrivadaPEM,
    String? senhaChave,
  }) {
    try {
      debugPrint('>>> [SecurityContext] Criando SecurityContext com certificado PEM...');
      
      // Converter strings PEM para bytes
      final certificadoBytes = Uint8List.fromList(certificadoPEM.codeUnits);
      final chavePrivadaBytes = Uint8List.fromList(chavePrivadaPEM.codeUnits);
      
      // Criar SecurityContext
      final securityContext = SecurityContext();
      
      // Configurar certificado
      securityContext.useCertificateChainBytes(certificadoBytes);
      debugPrint('>>> [SecurityContext] ✓ Certificado configurado');
      
      // Configurar chave privada
      if (senhaChave != null && senhaChave.isNotEmpty) {
        securityContext.usePrivateKeyBytes(chavePrivadaBytes, password: senhaChave);
        debugPrint('>>> [SecurityContext] ✓ Chave privada configurada (com senha)');
      } else {
        securityContext.usePrivateKeyBytes(chavePrivadaBytes);
        debugPrint('>>> [SecurityContext] ✓ Chave privada configurada (sem senha)');
      }
      
      debugPrint('>>> [SecurityContext] ✓✓✓ SecurityContext criado com sucesso!');
      return securityContext;
    } catch (e) {
      debugPrint('>>> [SecurityContext] ERRO ao criar SecurityContext: $e');
      rethrow;
    }
  }
  
  /// Cria um HttpClient configurado com o certificado para autenticação de cliente
  /// 
  /// Este HttpClient pode ser usado para fazer requisições HTTPS autenticadas
  /// com o certificado digital (ex: comunicação com SEFAZ)
  /// 
  /// Parâmetros:
  /// - [certificadoPEM]: Conteúdo do arquivo certificado_publico.pem
  /// - [chavePrivadaPEM]: Conteúdo do arquivo chave_privada.pem
  /// - [senhaChave]: Senha da chave privada PEM (se houver)
  /// 
  /// Retorna: HttpClient configurado com certificado
  static HttpClient criarHttpClientComCertificado({
    required String certificadoPEM,
    required String chavePrivadaPEM,
    String? senhaChave,
  }) {
    try {
      debugPrint('>>> [SecurityContext] Criando HttpClient com certificado...');
      
      final securityContext = criarSecurityContext(
        certificadoPEM: certificadoPEM,
        chavePrivadaPEM: chavePrivadaPEM,
        senhaChave: senhaChave,
      );
      
      // Criar HttpClient com o SecurityContext
      final client = HttpClient(context: securityContext);
      
      debugPrint('>>> [SecurityContext] ✓✓✓ HttpClient criado com sucesso!');
      return client;
    } catch (e) {
      debugPrint('>>> [SecurityContext] ERRO ao criar HttpClient: $e');
      rethrow;
    }
  }
  
  /// Cria SecurityContext a partir de arquivos PEM gerados pela conversão
  /// 
  /// Parâmetros:
  /// - [caminhoCertificado]: Caminho do arquivo certificado_publico.pem
  /// - [caminhoChavePrivada]: Caminho do arquivo chave_privada.pem
  /// - [senhaChave]: Senha da chave privada PEM (se houver)
  /// 
  /// Retorna: SecurityContext configurado
  static Future<SecurityContext> criarSecurityContextDeArquivos({
    required String caminhoCertificado,
    required String caminhoChavePrivada,
    String? senhaChave,
  }) async {
    try {
      debugPrint('>>> [SecurityContext] Carregando certificado de arquivos...');
      debugPrint('>>> [SecurityContext] Certificado: $caminhoCertificado');
      debugPrint('>>> [SecurityContext] Chave privada: $caminhoChavePrivada');
      
      // Ler arquivos PEM
      final certificadoFile = File(caminhoCertificado);
      final chavePrivadaFile = File(caminhoChavePrivada);
      
      if (!await certificadoFile.exists()) {
        throw Exception('Arquivo de certificado não encontrado: $caminhoCertificado');
      }
      
      if (!await chavePrivadaFile.exists()) {
        throw Exception('Arquivo de chave privada não encontrado: $caminhoChavePrivada');
      }
      
      final certificadoPEM = await certificadoFile.readAsString();
      final chavePrivadaPEM = await chavePrivadaFile.readAsString();
      
      debugPrint('>>> [SecurityContext] Certificado carregado: ${certificadoPEM.length} caracteres');
      debugPrint('>>> [SecurityContext] Chave privada carregada: ${chavePrivadaPEM.length} caracteres');
      
      return criarSecurityContext(
        certificadoPEM: certificadoPEM,
        chavePrivadaPEM: chavePrivadaPEM,
        senhaChave: senhaChave,
      );
    } catch (e) {
      debugPrint('>>> [SecurityContext] ERRO ao carregar de arquivos: $e');
      rethrow;
    }
  }
  
  /// Cria HttpClient com certificado carregado de assets (conforme guia oficial)
  /// 
  /// Este método segue exatamente o exemplo do guia de implementação:
  /// - Carrega certificado_publico.pem de assets
  /// - Carrega chave_privada.pem de assets
  /// - Configura SecurityContext
  /// - Retorna HttpClient pronto para uso
  /// 
  /// Parâmetros:
  /// - [caminhoCertificadoAsset]: Caminho do certificado em assets (ex: 'assets/certificado_publico.pem')
  /// - [caminhoChavePrivadaAsset]: Caminho da chave privada em assets (ex: 'assets/chave_privada.pem')
  /// - [senhaChave]: Senha da chave privada PEM (se houver, null se não criptografada)
  /// 
  /// Retorna: HttpClient configurado com certificado para autenticação HTTPS
  /// 
  /// Exemplo de uso (conforme guia):
  /// ```dart
  /// final client = await SecurityContextService.createHttpClientWithCertificate(
  ///   caminhoCertificadoAsset: 'assets/certificado_publico.pem',
  ///   caminhoChavePrivadaAsset: 'assets/chave_privada.pem',
  ///   senhaChave: 'SUA_SENHA_DA_CHAVE', // ou null se usar -nodes
  /// );
  /// 
  /// final request = await client.getUrl(Uri.parse('https://web-service-sefaz.com.br/nfe'));
  /// final response = await request.close();
  /// ```
  /// 
  /// ⚠️ NOTA DE SEGURANÇA: Esta abordagem expõe a chave privada no frontend.
  /// Para produção, considere usar um backend dedicado.
  static Future<HttpClient> createHttpClientWithCertificate({
    required String caminhoCertificadoAsset,
    required String caminhoChavePrivadaAsset,
    String? senhaChave,
  }) async {
    try {
      debugPrint('>>> [SecurityContext] Carregando certificado de assets...');
      debugPrint('>>> [SecurityContext] Certificado: $caminhoCertificadoAsset');
      debugPrint('>>> [SecurityContext] Chave privada: $caminhoChavePrivadaAsset');
      
      // 1. Carregar o certificado público e a chave privada de assets
      final certificate = await rootBundle.load(caminhoCertificadoAsset);
      final privateKey = await rootBundle.load(caminhoChavePrivadaAsset);
      
      debugPrint('>>> [SecurityContext] Certificado carregado: ${certificate.lengthInBytes} bytes');
      debugPrint('>>> [SecurityContext] Chave privada carregada: ${privateKey.lengthInBytes} bytes');
      
      // 2. Criar o SecurityContext
      final securityContext = SecurityContext()
        ..useCertificateChainBytes(certificate.buffer.asUint8List())
        ..usePrivateKeyBytes(
          privateKey.buffer.asUint8List(),
          password: senhaChave, // Use a senha que você definiu ao extrair a chave
        );
      
      debugPrint('>>> [SecurityContext] ✓ SecurityContext configurado');
      
      // 3. Criar o HttpClient com o contexto de segurança
      final client = HttpClient(context: securityContext);
      
      // Opcional: Ignorar certificados inválidos (NÃO RECOMENDADO EM PRODUÇÃO)
      // client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
      
      debugPrint('>>> [SecurityContext] ✓✓✓ HttpClient criado com sucesso!');
      return client;
    } catch (e) {
      debugPrint('>>> [SecurityContext] ERRO ao carregar de assets: $e');
      rethrow;
    }
  }
}

