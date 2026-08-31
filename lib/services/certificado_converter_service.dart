import 'dart:io';
import 'package:flutter/foundation.dart';
import 'process_utils.dart';

/// Serviço para converter certificados PFX para PEM
/// Usa OpenSSL através de processo externo
class CertificadoConverterService {
  /// Converte certificado PFX para PEM usando OpenSSL
  /// Retorna mapa com caminhos dos arquivos gerados
  static Future<Map<String, String>> converterPFXParaPEM({
    required String caminhoPFX,
    required String senha,
  }) async {
    try {
      debugPrint('>>> [Converter] Iniciando conversão PFX para PEM...');
      debugPrint('>>> [Converter] Arquivo: $caminhoPFX');
      
      // Verificar se OpenSSL está disponível (já será verificado em _encontrarOpenSSL)
      
      // Verificar se arquivo existe
      final arquivoPFX = File(caminhoPFX);
      if (!await arquivoPFX.exists()) {
        throw Exception('Arquivo PFX não encontrado: $caminhoPFX');
      }
      
      // Obter diretório e nome base
      final diretorio = arquivoPFX.parent.path;
      final nomeBase = arquivoPFX.uri.pathSegments.last
          .replaceAll('.pfx', '')
          .replaceAll('.p12', '');
      
      final caminhoCert = '$diretorio/$nomeBase.crt';
      final caminhoChave = '$diretorio/${nomeBase}_chave_privada.pem';
      
      // Encontrar caminho do OpenSSL
      debugPrint('>>> [Converter] ========================================');
      debugPrint('>>> [Converter] Procurando OpenSSL...');
      debugPrint('>>> [Converter] ========================================');
      String? opensslPath = await encontrarOpenSSL();
      if (opensslPath == null) {
        debugPrint('>>> [Converter] ✗ OpenSSL NÃO encontrado!');
        debugPrint('>>> [Converter] Verificando caminhos alternativos...');
        
        // Tentar caminhos específicos do Windows
        if (Platform.isWindows) {
          final caminhosEspecificos = [
            r'C:\Program Files\Git\usr\bin\openssl.exe',
            r'C:\Program Files (x86)\Git\usr\bin\openssl.exe',
          ];
          
          for (final caminho in caminhosEspecificos) {
            try {
              final file = File(caminho);
              if (await file.exists()) {
                debugPrint('>>> [Converter] ✓ OpenSSL encontrado em: $caminho');
                // Testar se funciona
                final test = await runProcessHidden(caminho, ['version']);
                if (test.exitCode == 0) {
                  debugPrint('>>> [Converter] ✓ OpenSSL funcionando!');
                  // Usar este caminho diretamente
                  opensslPath = caminho;
                  break;
                }
              }
            } catch (e) {
              debugPrint('>>> [Converter] Erro ao testar $caminho: $e');
            }
          }
        }
        
        if (opensslPath == null) {
          throw Exception('OpenSSL não encontrado. '
              'Por favor, instale o OpenSSL para converter certificados.\n\n'
              'Windows: https://slproweb.com/products/Win32OpenSSL.html\n'
              'OU use o Git Bash (já tem OpenSSL)\n'
              'Linux: sudo apt-get install openssl\n'
              'macOS: brew install openssl');
        }
      }
      debugPrint('>>> [Converter] ✓ OpenSSL encontrado: $opensslPath');
      debugPrint('>>> [Converter] Arquivo PFX: $caminhoPFX');
      debugPrint('>>> [Converter] Senha fornecida: ${senha.isNotEmpty ? "SIM (${senha.length} caracteres)" : "NÃO"}');

      // PASSO 1: Extrair certificado público (Certificate)
      // Comando: openssl pkcs12 -in seu_certificado.pfx -clcerts -nokeys -out certificado_publico.pem
      // Este comando extrai o certificado público (e a cadeia de certificados, se houver)
      debugPrint('>>> [Converter] ========================================');
      debugPrint('>>> [Converter] PASSO 1: Extraindo certificado público...');
      debugPrint('>>> [Converter] Comando: $opensslPath pkcs12 -in $caminhoPFX -clcerts -nokeys -out $caminhoCert');
      debugPrint('>>> [Converter] Parâmetros: -clcerts (apenas certificados do cliente), -nokeys (sem chaves)');
      debugPrint('>>> [Converter] ========================================');
      
      // Verificar se arquivo PFX existe e tem tamanho válido
      final arquivoPFXCheck = File(caminhoPFX);
      if (!await arquivoPFXCheck.exists()) {
        throw Exception('Arquivo PFX não encontrado: $caminhoPFX');
      }
      final tamanhoPFX = await arquivoPFXCheck.length();
      debugPrint('>>> [Converter] Tamanho do arquivo PFX: $tamanhoPFX bytes');
      if (tamanhoPFX == 0) {
        throw Exception('Arquivo PFX está vazio: $caminhoPFX');
      }
      
      final resultadoCert = await runProcessHidden(
        opensslPath,
        [
          'pkcs12',
          '-in', caminhoPFX,
          '-clcerts',
          '-nokeys',
          '-out', caminhoCert,
          '-passin', 'pass:$senha',
        ],
      );
      
      if (resultadoCert.exitCode != 0) {
        final erro = resultadoCert.stderr.toString().trim();
        final stdout = resultadoCert.stdout.toString().trim();
        debugPrint('>>> [Converter] ERRO ao extrair certificado');
        debugPrint('>>> [Converter] Exit code: ${resultadoCert.exitCode}');
        debugPrint('>>> [Converter] stderr: $erro');
        debugPrint('>>> [Converter] stdout: $stdout');
        
        // Verificar se é erro de senha
        final erroLower = erro.toLowerCase();
        if (erroLower.contains('mac verify failure') || 
            erroLower.contains('invalid password') ||
            erroLower.contains('bad password') ||
            erroLower.contains('mac verify error') ||
            erroLower.contains('wrong password')) {
          throw Exception('Senha incorreta. Verifique a senha do certificado PFX.\n\n'
              'Dica: Certifique-se de que a senha está correta e não contém caracteres especiais problemáticos.');
        }
        
        // Verificar se é erro de arquivo corrompido
        if (erroLower.contains('bad decrypt') ||
            erroLower.contains('error reading') ||
            erroLower.contains('unable to load')) {
          throw Exception('Arquivo PFX corrompido ou inválido.\n\n'
              'SOLUÇÃO:\n'
              '1. Re-exporte o certificado do navegador/certificado digital\n'
              '2. Certifique-se de incluir a chave privada na exportação\n'
              '3. Use uma senha simples (sem caracteres especiais)\n'
              '4. Tente converter manualmente: openssl pkcs12 -in certificado.pfx -out certificado.pem -nodes');
        }
        
        throw Exception('Erro ao extrair certificado público:\n$erro\n\n'
            'Verifique se:\n'
            '• A senha está correta\n'
            '• O arquivo PFX não está corrompido\n'
            '• O certificado foi exportado corretamente (incluindo chave privada)\n'
            '• O OpenSSL está funcionando corretamente\n\n'
            'Para testar manualmente, execute:\n'
            'openssl pkcs12 -in "$caminhoPFX" -clcerts -nokeys -out teste.crt -passin pass:SUA_SENHA');
      }
      
      debugPrint('>>> [Converter] ✓ Certificado público extraído: $caminhoCert');
      
      // Verificar se arquivo foi criado
      final arquivoCert = File(caminhoCert);
      if (!await arquivoCert.exists()) {
        throw Exception('Arquivo de certificado não foi criado: $caminhoCert');
      }
      
      // PASSO 2: Extrair chave privada (Private Key)
      // Comando: openssl pkcs12 -in seu_certificado.pfx -nocerts -out chave_privada.pem
      // NOTA: Usamos -nodes para não criptografar a chave privada PEM (sem senha adicional)
      // Isso é recomendado para uso em aplicações, mas mantenha o arquivo seguro!
      debugPrint('>>> [Converter] ========================================');
      debugPrint('>>> [Converter] PASSO 2: Extraindo chave privada...');
      debugPrint('>>> [Converter] Comando: $opensslPath pkcs12 -in $caminhoPFX -nocerts -nodes -out $caminhoChave');
      debugPrint('>>> [Converter] Parâmetros: -nocerts (sem certificados), -nodes (sem criptografia DES)');
      debugPrint('>>> [Converter] NOTA: -nodes cria chave privada SEM senha adicional (mantenha seguro!)');
      debugPrint('>>> [Converter] ========================================');
      
      final resultadoChave = await runProcessHidden(
        opensslPath,
        [
          'pkcs12',
          '-in', caminhoPFX,
          '-nocerts',
          '-nodes',
          '-out', caminhoChave,
          '-passin', 'pass:$senha',
        ],
      );
      
      if (resultadoChave.exitCode != 0) {
        final erro = resultadoChave.stderr.toString().trim();
        debugPrint('>>> [Converter] ERRO ao extrair chave privada: $erro');
        debugPrint('>>> [Converter] stdout: ${resultadoChave.stdout}');
        
        // Limpar arquivo de certificado se criado
        try {
          if (await arquivoCert.exists()) {
            await arquivoCert.delete();
          }
        } catch (e) {
          // Ignorar erro ao deletar
        }
        
        final erroLower = erro.toLowerCase();
        
        // Verificar se é erro de senha
        if (erroLower.contains('mac verify failure') || 
            erroLower.contains('invalid password') ||
            erroLower.contains('bad password') ||
            erroLower.contains('mac verify error') ||
            erroLower.contains('wrong password') ||
            erroLower.contains('bad mac decode')) {
          throw Exception('🔴 SENHA INCORRETA\n\n'
              'O OpenSSL não conseguiu descriptografar o certificado com a senha fornecida.\n\n'
              'SOLUÇÃO:\n'
              '1. Verifique se a senha está correta (case-sensitive)\n'
              '2. Certifique-se de que não há espaços antes/depois da senha\n'
              '3. Se a senha contém caracteres especiais, tente re-exportar com senha simples\n'
              '4. Teste a senha manualmente:\n'
              '   openssl pkcs12 -in "$caminhoPFX" -nocerts -nodes -out teste.pem -passin pass:SUA_SENHA\n\n'
              'Se o comando acima funcionar, a senha está correta e o problema é outro.');
        }
        
        // Verificar se é erro de chave privada não encontrada
        if (erroLower.contains('no private keys') ||
            erroLower.contains('no private key') ||
            erroLower.contains('unable to load private key') ||
            erroLower.contains('no key found')) {
          throw Exception('🔴 CHAVE PRIVADA NÃO ENCONTRADA NO CERTIFICADO\n\n'
              'O certificado PFX não contém uma chave privada.\n\n'
              'CAUSA PROVÁVEL:\n'
              'O certificado foi exportado SEM incluir a chave privada.\n\n'
              'SOLUÇÃO DEFINITIVA:\n'
              '1. Abra o certificado no software original (e-CPF/e-CNPJ Manager)\n'
              '2. Exporte novamente o certificado\n'
              '3. CERTIFIQUE-SE de marcar "Incluir chave privada" ou "Export private key"\n'
              '4. Use senha simples (sem caracteres especiais)\n'
              '5. Salve como .pfx ou .p12\n'
              '6. Use este novo arquivo no sistema\n\n'
              'IMPORTANTE: Sem a chave privada, não é possível assinar documentos!');
        }
        
        // Verificar se é erro de arquivo corrompido
        if (erroLower.contains('bad decrypt') ||
            erroLower.contains('error reading') ||
            erroLower.contains('unable to load') ||
            erroLower.contains('bad magic number') ||
            erroLower.contains('not a p12 file')) {
          throw Exception('🔴 ARQUIVO PFX CORROMPIDO OU INVÁLIDO\n\n'
              'O arquivo não é um certificado PKCS12 válido.\n\n'
              'SOLUÇÃO:\n'
              '1. Re-exporte o certificado do navegador/certificado digital\n'
              '2. Certifique-se de incluir a chave privada na exportação\n'
              '3. Use uma senha simples (sem caracteres especiais)\n'
              '4. Tente converter manualmente:\n'
              '   openssl pkcs12 -in certificado.pfx -out certificado.pem -nodes');
        }
        
        // Erro genérico com informações detalhadas
        throw Exception('🔴 ERRO AO EXTRAIR CHAVE PRIVADA COM OPENSSL\n\n'
            'Detalhes do erro:\n$erro\n\n'
            'POSSÍVEIS CAUSAS:\n'
            '1. Senha incorreta\n'
            '2. Certificado exportado sem chave privada\n'
            '3. Arquivo PFX corrompido\n'
            '4. Formato de certificado não suportado\n\n'
            'SOLUÇÃO:\n'
            '1. Verifique a senha do certificado\n'
            '2. Re-exporte o certificado INCLUINDO a chave privada\n'
            '3. Use senha simples (sem caracteres especiais)\n'
            '4. Teste manualmente:\n'
            '   openssl pkcs12 -in "$caminhoPFX" -nocerts -nodes -out teste.pem -passin pass:SUA_SENHA');
      }
      
      debugPrint('>>> [Converter] ✓ Chave privada extraída: $caminhoChave');
      
      // Verificar se arquivo foi criado
      final arquivoChave = File(caminhoChave);
      if (!await arquivoChave.exists()) {
        throw Exception('Arquivo de chave privada não foi criado: $caminhoChave');
      }
      
      // Verificar tamanhos dos arquivos
      final tamanhoCert = await arquivoCert.length();
      final tamanhoChave = await arquivoChave.length();
      debugPrint('>>> [Converter] Tamanho do certificado: $tamanhoCert bytes');
      debugPrint('>>> [Converter] Tamanho da chave privada: $tamanhoChave bytes');
      
      if (tamanhoCert == 0) {
        throw Exception('Arquivo de certificado está vazio. Verifique se o PFX está correto.');
      }
      
      if (tamanhoChave == 0) {
        throw Exception('Arquivo de chave privada está vazio. Verifique se o PFX está correto.');
      }
      
      debugPrint('>>> [Converter] ✓✓✓ Conversão concluída com sucesso!');
      debugPrint('>>> [Converter] Certificado: $caminhoCert ($tamanhoCert bytes)');
      debugPrint('>>> [Converter] Chave privada: $caminhoChave ($tamanhoChave bytes)');
      
      return {
        'certificado': caminhoCert,
        'chavePrivada': caminhoChave,
      };
    } catch (e) {
      debugPrint('>>> [Converter] ERRO na conversão: $e');
      rethrow;
    }
  }
  
  /// Caminho do OpenSSL encontrado (cache)
  static String? _opensslPath;

  /// Verifica se OpenSSL está disponível no sistema
  /// Retorna o caminho do OpenSSL se encontrado
  /// EXPORTADO para uso em outros serviços
  static Future<String?> encontrarOpenSSL() async {
    // Se já encontramos antes, usar cache
    if (_opensslPath != null) {
      try {
        final test = await runProcessHidden(_opensslPath!, ['version']);
        if (test.exitCode == 0) {
          return _opensslPath;
        }
      } catch (e) {
        // Cache inválido, limpar
        _opensslPath = null;
      }
    }

    // Lista de caminhos possíveis para tentar
    final caminhosParaTentar = <String>[];

    // 1. Tentar openssl no PATH
    caminhosParaTentar.add('openssl');

    if (Platform.isWindows) {
      // 2. Git Bash
      caminhosParaTentar.add(r'C:\Program Files\Git\usr\bin\openssl.exe');
      caminhosParaTentar.add(r'C:\Program Files (x86)\Git\usr\bin\openssl.exe');
      
      // 3. OpenSSL instalado diretamente
      caminhosParaTentar.add(r'C:\Program Files\OpenSSL-Win64\bin\openssl.exe');
      caminhosParaTentar.add(r'C:\Program Files (x86)\OpenSSL-Win32\bin\openssl.exe');
      caminhosParaTentar.add(r'C:\OpenSSL-Win64\bin\openssl.exe');
      caminhosParaTentar.add(r'C:\OpenSSL-Win32\bin\openssl.exe');
      
      // 4. Chocolatey
      caminhosParaTentar.add(r'C:\ProgramData\chocolatey\bin\openssl.exe');
      
      // 5. Scoop
      final userProfile = Platform.environment['USERPROFILE'] ?? '';
      if (userProfile.isNotEmpty) {
        caminhosParaTentar.add('$userProfile\\scoop\\apps\\openssl\\current\\bin\\openssl.exe');
      }
    } else if (Platform.isLinux) {
      caminhosParaTentar.add('/usr/bin/openssl');
      caminhosParaTentar.add('/usr/local/bin/openssl');
    } else if (Platform.isMacOS) {
      caminhosParaTentar.add('/usr/bin/openssl');
      caminhosParaTentar.add('/usr/local/bin/openssl');
      caminhosParaTentar.add('/opt/homebrew/bin/openssl');
    }

    // Tentar cada caminho
    for (final caminho in caminhosParaTentar) {
      try {
        debugPrint('>>> [Converter] Tentando OpenSSL em: $caminho');
        
        // Verificar se arquivo existe antes de tentar executar
        if (caminho.contains('/') || caminho.contains('\\')) {
          final file = File(caminho);
          if (!await file.exists()) {
            debugPrint('>>> [Converter] Arquivo não existe: $caminho');
            continue;
          }
        }
        
        // Tentar executar com runInShell no Windows
        final resultado = await runProcessHidden(
          caminho,
          ['version'],
        );
        
        if (resultado.exitCode == 0) {
          debugPrint('>>> [Converter] ✓ OpenSSL encontrado: $caminho');
          debugPrint('>>> [Converter] Versão: ${resultado.stdout}');
          _opensslPath = caminho; // Cache do caminho
          return caminho;
        } else {
          debugPrint('>>> [Converter] OpenSSL retornou exitCode ${resultado.exitCode}');
          debugPrint('>>> [Converter] stderr: ${resultado.stderr}');
        }
      } catch (e) {
        // Continuar tentando outros caminhos
        debugPrint('>>> [Converter] Não encontrado em $caminho: $e');
        debugPrint('>>> [Converter] Tipo do erro: ${e.runtimeType}');
      }
    }

    debugPrint('>>> [Converter] ✗ OpenSSL não encontrado em nenhum caminho testado');
    return null;
  }

}

