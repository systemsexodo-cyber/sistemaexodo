import 'dart:io';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'process_utils.dart';

/// Serviço para acessar certificados do Windows Certificate Store
class WindowsCertificateService {
  /// Lista certificados disponíveis no Windows Certificate Store
  /// Retorna lista de certificados com informações básicas
  static Future<List<Map<String, dynamic>>> listarCertificados() async {
    try {
      debugPrint('>>> [WindowsCert] Listando certificados do Windows...');
      
      // Script PowerShell para listar certificados
      final script = '''
\$certificados = Get-ChildItem -Path Cert:\\CurrentUser\\My
\$resultado = @()

foreach (\$cert in \$certificados) {
    \$subject = \$cert.Subject
    \$issuer = \$cert.Issuer
    \$thumbprint = \$cert.Thumbprint
    \$notAfter = \$cert.NotAfter
    \$hasPrivateKey = \$cert.HasPrivateKey
    
    if (\$hasPrivateKey) {
        \$resultado += @{
            Subject = \$subject
            Issuer = \$issuer
            Thumbprint = \$thumbprint
            NotAfter = \$notAfter.ToString("yyyy-MM-ddTHH:mm:ss")
            HasPrivateKey = \$true
        }
    }
}

\$resultado | ConvertTo-Json
''';

      // Executar script PowerShell usando método alternativo
      debugPrint('>>> [WindowsCert] Executando PowerShell (método alternativo)...');
      
      // Método alternativo: salvar script em arquivo temporário e executar
      Directory tempDir;
      try {
        tempDir = await getTemporaryDirectory();
      } catch (e) {
        tempDir = Directory.systemTemp;
      }
      
      final scriptFile = File('${tempDir.path}/listar_certificados_${DateTime.now().millisecondsSinceEpoch}.ps1');
      await scriptFile.writeAsString(script);
      debugPrint('>>> [WindowsCert] Script salvo em: ${scriptFile.path}');
      
      // Executar PowerShell sem mostrar janela CMD
      ProcessResult result;
      try {
        result = await runProcessHidden(
          'powershell',
          [
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', scriptFile.path,
          ],
        );
      } catch (e) {
        debugPrint('>>> [WindowsCert] runProcessHidden falhou: $e');
        throw Exception('Não foi possível executar PowerShell.\n\n'
            'Erro: $e\n\n'
            'SOLUÇÃO ALTERNATIVA:\n'
            '1. Execute manualmente o script: testar_certificados_windows.ps1\n'
              '2. Copie o JSON retornado\n'
              '3. Use a opção "Selecionar Arquivo" para importar o certificado');
      }
      
      // Limpar arquivo temporário
      try {
        await scriptFile.delete();
      } catch (_) {}

      debugPrint('>>> [WindowsCert] Exit code: ${result.exitCode}');
      final stdoutStr = result.stdout.toString();
      debugPrint('>>> [WindowsCert] Stdout (primeiros 200 chars): ${stdoutStr.length > 200 ? stdoutStr.substring(0, 200) : stdoutStr}');
      
      if (result.exitCode != 0) {
        debugPrint('>>> [WindowsCert] Erro ao listar certificados: ${result.stderr}');
        throw Exception('Erro ao listar certificados do Windows:\n${result.stderr}\n\nCertifique-se de que o PowerShell está disponível.');
      }

      // Parsear JSON retornado
      final jsonStr = stdoutStr.trim();
      debugPrint('>>> [WindowsCert] JSON recebido: ${jsonStr.length} caracteres');
      
      if (jsonStr.isEmpty || jsonStr == 'null') {
        debugPrint('>>> [WindowsCert] Nenhum certificado encontrado (JSON vazio)');
        return [];
      }

      // PowerShell pode retornar array ou objeto único
      dynamic jsonData;
      try {
        if (jsonStr.startsWith('[')) {
          jsonData = jsonDecode(jsonStr);
        } else if (jsonStr.startsWith('{')) {
          // Objeto único - converter para array
          jsonData = [jsonDecode(jsonStr)];
        } else {
          debugPrint('>>> [WindowsCert] JSON inválido: $jsonStr');
          return [];
        }
      } catch (e) {
        debugPrint('>>> [WindowsCert] Erro ao decodificar JSON: $e');
        debugPrint('>>> [WindowsCert] JSON recebido: $jsonStr');
        throw Exception('Erro ao processar resposta do PowerShell: $e\n\nJSON: $jsonStr');
      }

      final certificados = <Map<String, dynamic>>[];
      if (jsonData is List) {
        for (var item in jsonData) {
          if (item is Map) {
            certificados.add({
              'subject': item['Subject']?.toString() ?? '',
              'issuer': item['Issuer']?.toString() ?? '',
              'thumbprint': item['Thumbprint']?.toString() ?? '',
              'notAfter': item['NotAfter']?.toString() ?? '',
              'hasPrivateKey': item['HasPrivateKey'] == true,
            });
          }
        }
      }

      debugPrint('>>> [WindowsCert] ✓ ${certificados.length} certificado(s) encontrado(s)');
      return certificados;
    } catch (e) {
      debugPrint('>>> [WindowsCert] ERRO: $e');
      throw Exception('Erro ao listar certificados do Windows: $e');
    }
  }

  /// Exporta certificado do Windows para formato PEM
  /// Retorna o certificado e chave privada em formato PEM
  static Future<Map<String, String>> exportarCertificado(
    String thumbprint,
    String senha,
  ) async {
    try {
      debugPrint('>>> [WindowsCert] Exportando certificado: $thumbprint');
      
      // Script PowerShell para exportar certificado
      final script = '''
\$thumbprint = "$thumbprint"
\$senha = ConvertTo-SecureString -String "$senha" -Force -AsPlainText

\$cert = Get-ChildItem -Path Cert:\\CurrentUser\\My | Where-Object { \$_.Thumbprint -eq \$thumbprint }

if (-not \$cert) {
    Write-Error "Certificado não encontrado"
    exit 1
}

if (-not \$cert.HasPrivateKey) {
    Write-Error "Certificado não possui chave privada"
    exit 1
}

# Exportar para PFX temporário
\$tempPfx = [System.IO.Path]::GetTempFileName() + ".pfx"
Export-PfxCertificate -Certificate \$cert -FilePath \$tempPfx -Password \$senha | Out-Null

# Converter PFX para PEM usando OpenSSL (se disponível)
\$openssl = Get-Command openssl -ErrorAction SilentlyContinue
if (\$openssl) {
    \$tempPem = [System.IO.Path]::GetTempFileName() + ".pem"
    & openssl pkcs12 -in \$tempPfx -out \$tempPem -nodes -passin pass:"$senha" 2>&1 | Out-Null
    
    if (Test-Path \$tempPem) {
        \$pemContent = Get-Content \$tempPem -Raw
        Remove-Item \$tempPfx -Force
        Remove-Item \$tempPem -Force
        
        Write-Output \$pemContent
    } else {
        Write-Error "Erro ao converter para PEM"
        exit 1
    }
} else {
    # Se OpenSSL não estiver disponível, retornar apenas o caminho do PFX
    Write-Output "PFX:\$tempPfx"
}
''';

      // Executar script usando método alternativo
      debugPrint('>>> [WindowsCert] Executando PowerShell para exportar certificado...');
      
      // Salvar script em arquivo temporário
      Directory tempDir;
      try {
        tempDir = await getTemporaryDirectory();
      } catch (e) {
        tempDir = Directory.systemTemp;
      }
      
      final scriptFile = File('${tempDir.path}/exportar_certificado_${DateTime.now().millisecondsSinceEpoch}.ps1');
      await scriptFile.writeAsString(script);
      debugPrint('>>> [WindowsCert] Script de exportação salvo em: ${scriptFile.path}');
      
      // Executar PowerShell sem mostrar janela CMD
      ProcessResult result;
      try {
        result = await runProcessHidden(
          'powershell',
          [
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', scriptFile.path,
          ],
        );
      } catch (e) {
        try {
          await scriptFile.delete();
        } catch (_) {}
        debugPrint('>>> [WindowsCert] runProcessHidden falhou: $e');
        throw Exception('Erro ao exportar certificado: $e');
      }
      
      // Limpar arquivo temporário
      try {
        await scriptFile.delete();
      } catch (_) {}

      if (result.exitCode != 0) {
        debugPrint('>>> [WindowsCert] Erro ao exportar: ${result.stderr}');
        throw Exception('Erro ao exportar certificado: ${result.stderr}');
      }

      final output = result.stdout.toString().trim();
      
      if (output.startsWith('PFX:')) {
        // Retornar caminho do PFX
        final pfxPath = output.substring(4);
        return {
          'tipo': 'pfx',
          'caminho': pfxPath,
        };
      } else {
        // Retornar conteúdo PEM
        return {
          'tipo': 'pem',
          'conteudo': output,
        };
      }
    } catch (e) {
      debugPrint('>>> [WindowsCert] ERRO ao exportar certificado: $e');
      throw Exception('Erro ao exportar certificado do Windows: $e');
    }
  }

  /// Abre o diálogo de seleção de certificado do Windows
  /// Retorna o thumbprint do certificado selecionado
  static Future<String?> selecionarCertificadoDialog() async {
    try {
      debugPrint('>>> [WindowsCert] Abrindo diálogo de seleção...');
      
      // Listar certificados disponíveis
      final certificados = await listarCertificados();
      
      if (certificados.isEmpty) {
        throw Exception('Nenhum certificado com chave privada encontrado no Windows.\n\n'
            'Certifique-se de que o certificado está instalado no repositório "Pessoal" do Windows.');
      }

      // Retornar lista para o Flutter escolher
      // O Flutter vai mostrar um diálogo com os certificados
      return null; // Será implementado no Flutter
    } catch (e) {
      debugPrint('>>> [WindowsCert] ERRO: $e');
      rethrow;
    }
  }
}

