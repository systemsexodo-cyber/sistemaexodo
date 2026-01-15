import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'certificado_service.dart';

/// Resultado da validação do certificado
class ResultadoValidacaoCertificado {
  final bool valido;
  final List<String> erros;
  final List<String> avisos;
  final Map<String, dynamic> informacoes;

  ResultadoValidacaoCertificado({
    required this.valido,
    this.erros = const [],
    this.avisos = const [],
    this.informacoes = const {},
  });

  String get mensagemResumo {
    if (valido) {
      return '✓ Certificado válido e pronto para uso';
    } else {
      return '✗ Certificado inválido: ${erros.join(", ")}';
    }
  }
}

/// Serviço para validação completa de certificados digitais
class CertificadoValidacaoService {
  /// Valida certificado digital de forma completa
  /// Verifica: validade, formato, senha, chave privada, ambiente
  static Future<ResultadoValidacaoCertificado> validarCertificado({
    required String? certificadoDigitalBytes, // Base64
    required String? certificadoUrl,
    required String senha,
    required String? cnpjEmpresa,
    required bool ambienteHomologacao,
  }) async {
    final erros = <String>[];
    final avisos = <String>[];
    final informacoes = <String, dynamic>{};

    try {
      debugPrint('>>> [Validação] ========================================');
      debugPrint('>>> [Validação] INICIANDO VALIDAÇÃO COMPLETA DO CERTIFICADO');
      debugPrint('>>> [Validação] ========================================');

      // 1. Verificar se o certificado foi fornecido
      if ((certificadoDigitalBytes == null || certificadoDigitalBytes.isEmpty) &&
          (certificadoUrl == null || certificadoUrl.isEmpty)) {
        erros.add('Certificado não fornecido');
        return ResultadoValidacaoCertificado(
          valido: false,
          erros: erros,
          avisos: avisos,
          informacoes: informacoes,
        );
      }

      // 2. Verificar se a senha foi fornecida
      if (senha.isEmpty) {
        erros.add('Senha do certificado não fornecida');
        return ResultadoValidacaoCertificado(
          valido: false,
          erros: erros,
          avisos: avisos,
          informacoes: informacoes,
        );
      }

      // 3. Tentar carregar o certificado
      CertificadoDigital? certificado;
      try {
        debugPrint('>>> [Validação] Tentando carregar certificado...');
        certificado = await CertificadoService().carregarCertificado(
          certificadoUrl ?? '',
          senha,
          certificadoDigitalBytes: certificadoDigitalBytes,
        );
        debugPrint('>>> [Validação] ✓ Certificado carregado com sucesso');
        informacoes['certificadoCarregado'] = true;
      } catch (e) {
        final erroStr = e.toString();
        debugPrint('>>> [Validação] ✗ Erro ao carregar certificado: $e');

        // Verificar tipo de erro
        if (erroStr.contains('Senha incorreta') ||
            erroStr.contains('invalid password') ||
            erroStr.contains('bad password') ||
            erroStr.contains('mac verify failure')) {
          erros.add('Senha do certificado incorreta');
          informacoes['erroSenha'] = true;
        } else if (erroStr.contains('chave privada') ||
                   erroStr.contains('private key')) {
          erros.add('Chave privada não encontrada no certificado');
          informacoes['semChavePrivada'] = true;
        } else if (erroStr.contains('expirado') ||
                   erroStr.contains('expired')) {
          erros.add('Certificado expirado');
          informacoes['expirado'] = true;
        } else {
          erros.add('Erro ao processar certificado: ${erroStr.length > 100 ? erroStr.substring(0, 100) + "..." : erroStr}');
        }

        return ResultadoValidacaoCertificado(
          valido: false,
          erros: erros,
          avisos: avisos,
          informacoes: informacoes,
        );
      }

      // certificado não pode ser null aqui pois se o carregamento falhou,
      // já retornamos acima. Mas vamos manter a verificação para segurança.

      // 4. Verificar formato (PKCS#12)
      debugPrint('>>> [Validação] Verificando formato do certificado...');
      final formatoValido = _verificarFormato(certificado.bytes);
      if (!formatoValido) {
        avisos.add('Formato do certificado pode não ser PKCS#12 padrão');
        informacoes['formatoSuspeito'] = true;
      } else {
        informacoes['formato'] = 'PKCS#12';
        debugPrint('>>> [Validação] ✓ Formato PKCS#12 válido');
      }

      // 5. Verificar validade
      debugPrint('>>> [Validação] Verificando validade do certificado...');
      if (certificado.validade != null) {
        final agora = DateTime.now();
        final diasRestantes = certificado.validade!.difference(agora).inDays;

        informacoes['validade'] = certificado.validade!.toIso8601String();
        informacoes['diasRestantes'] = diasRestantes;

        if (certificado.validade!.isBefore(agora)) {
          erros.add('Certificado expirado em ${certificado.validade!.toString().split(' ')[0]}');
          informacoes['expirado'] = true;
        } else if (diasRestantes <= 0) {
          erros.add('Certificado expirado hoje');
          informacoes['expirado'] = true;
        } else if (diasRestantes <= 30) {
          avisos.add('Certificado expira em $diasRestantes dias');
          informacoes['expirandoEmBreve'] = true;
        } else {
          debugPrint('>>> [Validação] ✓ Certificado válido até ${certificado.validade!.toString().split(' ')[0]} ($diasRestantes dias restantes)');
        }
      } else {
        avisos.add('Data de validade do certificado não disponível');
        informacoes['validadeNaoDisponivel'] = true;
      }

      // 6. Verificar chave privada
      debugPrint('>>> [Validação] Verificando chave privada...');
      if (certificado.privateKey == null) {
        erros.add('Chave privada não encontrada no certificado');
        informacoes['semChavePrivada'] = true;
      } else {
        debugPrint('>>> [Validação] ✓ Chave privada presente');
        informacoes['chavePrivada'] = true;
        informacoes['tamanhoChave'] = certificado.privateKey!.n!.bitLength;
      }

      // 7. Verificar CNPJ (se fornecido)
      if (cnpjEmpresa != null && cnpjEmpresa.isNotEmpty) {
        debugPrint('>>> [Validação] Verificando CNPJ do certificado...');
        if (certificado.cnpj != null && certificado.cnpj!.isNotEmpty) {
          informacoes['cnpjCertificado'] = certificado.cnpj;
          informacoes['cnpjEmpresa'] = cnpjEmpresa;

          // Remover formatação para comparação
          final cnpjCertificadoLimpo = certificado.cnpj!.replaceAll(RegExp(r'[^0-9]'), '');
          final cnpjEmpresaLimpo = cnpjEmpresa.replaceAll(RegExp(r'[^0-9]'), '');

          if (cnpjCertificadoLimpo != cnpjEmpresaLimpo) {
            avisos.add('CNPJ do certificado (${certificado.cnpj}) não corresponde ao CNPJ da empresa ($cnpjEmpresa)');
            informacoes['cnpjNaoCorresponde'] = true;
          } else {
            debugPrint('>>> [Validação] ✓ CNPJ corresponde');
            informacoes['cnpjCorresponde'] = true;
          }
        } else {
          avisos.add('CNPJ do certificado não pôde ser extraído');
          informacoes['cnpjNaoDisponivel'] = true;
        }
      }

      // 8. Verificar ambiente (homologação/produção)
      // Nota: Esta validação é mais informativa, pois não podemos determinar
      // com certeza o ambiente apenas pelo certificado
      debugPrint('>>> [Validação] Ambiente configurado: ${ambienteHomologacao ? "Homologação" : "Produção"}');
      informacoes['ambiente'] = ambienteHomologacao ? 'homologacao' : 'producao';
      avisos.add('Certifique-se de que o certificado corresponde ao ambiente ${ambienteHomologacao ? "de homologação" : "de produção"}');

      // 9. Verificar tamanho do certificado
      debugPrint('>>> [Validação] Verificando tamanho do certificado...');
      informacoes['tamanhoBytes'] = certificado.bytes.length;
      if (certificado.bytes.length < 100) {
        erros.add('Certificado muito pequeno (${certificado.bytes.length} bytes) - pode estar corrompido');
      } else {
        debugPrint('>>> [Validação] ✓ Tamanho do certificado OK (${certificado.bytes.length} bytes)');
      }

      // Resumo final
      final valido = erros.isEmpty;
      debugPrint('>>> [Validação] ========================================');
      debugPrint('>>> [Validação] RESULTADO DA VALIDAÇÃO:');
      debugPrint('>>> [Validação] Válido: $valido');
      debugPrint('>>> [Validação] Erros: ${erros.length}');
      debugPrint('>>> [Validação] Avisos: ${avisos.length}');
      debugPrint('>>> [Validação] ========================================');

      return ResultadoValidacaoCertificado(
        valido: valido,
        erros: erros,
        avisos: avisos,
        informacoes: informacoes,
      );
    } catch (e, stackTrace) {
      debugPrint('>>> [Validação] ERRO INESPERADO: $e');
      debugPrint('>>> [Validação] Stack trace: $stackTrace');
      return ResultadoValidacaoCertificado(
        valido: false,
        erros: ['Erro inesperado na validação: ${e.toString()}'],
        avisos: avisos,
        informacoes: informacoes,
      );
    }
  }

  /// Verifica se o formato do certificado é PKCS#12 válido
  static bool _verificarFormato(Uint8List bytes) {
    if (bytes.isEmpty) return false;

    // PKCS#12 deve começar com 0x30 (DER SEQUENCE)
    if (bytes[0] != 0x30) {
      return false;
    }

    // Verificar tamanho mínimo
    if (bytes.length < 100) {
      return false;
    }

    // Verificar se não é texto PEM
    try {
      final texto = String.fromCharCodes(bytes.take(50));
      if (texto.contains('-----BEGIN') || texto.contains('-----END')) {
        return false; // É PEM, não PKCS#12
      }
    } catch (e) {
      // Não é texto, OK
    }

    return true;
  }

  /// Gera mensagem formatada com orientações para correção
  static String gerarMensagemOrientacao(ResultadoValidacaoCertificado resultado) {
    if (resultado.valido) {
      return '✓ Certificado válido e pronto para uso!';
    }

    final buffer = StringBuffer();
    buffer.writeln('🔴 CERTIFICADO INVÁLIDO');
    buffer.writeln('');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('📋 PROBLEMAS ENCONTRADOS:');
    buffer.writeln('');

    for (var erro in resultado.erros) {
      buffer.writeln('✗ $erro');
    }

    if (resultado.avisos.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('⚠️ AVISOS:');
      for (var aviso in resultado.avisos) {
        buffer.writeln('• $aviso');
      }
    }

    buffer.writeln('');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('✅ SOLUÇÕES:');
    buffer.writeln('');

    // Soluções baseadas nos erros encontrados
    if (resultado.informacoes['erroSenha'] == true) {
      buffer.writeln('1️⃣ SENHA INCORRETA:');
      buffer.writeln('   • Verifique se a senha está correta');
      buffer.writeln('   • A senha é case-sensitive (diferencia maiúsculas/minúsculas)');
      buffer.writeln('   • Teste a senha abrindo o certificado diretamente');
      buffer.writeln('');
    }

    if (resultado.informacoes['semChavePrivada'] == true) {
      buffer.writeln('2️⃣ CHAVE PRIVADA AUSENTE:');
      buffer.writeln('   • Re-exporte o certificado INCLUINDO a chave privada');
      buffer.writeln('   • No Windows: certmgr.msc → Exportar → Marque "Incluir chave privada"');
      buffer.writeln('   • Use formato PKCS#12 (.pfx)');
      buffer.writeln('');
    }

    if (resultado.informacoes['expirado'] == true) {
      buffer.writeln('3️⃣ CERTIFICADO EXPIRADO:');
      buffer.writeln('   • Renove o certificado na autoridade certificadora');
      buffer.writeln('   • Importe o novo certificado no sistema');
      buffer.writeln('');
    }

    if (resultado.informacoes['formatoSuspeito'] == true) {
      buffer.writeln('4️⃣ FORMATO INCORRETO:');
      buffer.writeln('   • Re-exporte o certificado em formato PKCS#12 (.pfx)');
      buffer.writeln('   • Use senha simples (apenas letras e números)');
      buffer.writeln('   • Não marque "Habilitar proteção forte"');
      buffer.writeln('');
    }

    if (resultado.informacoes['cnpjNaoCorresponde'] == true) {
      buffer.writeln('5️⃣ CNPJ NÃO CORRESPONDE:');
      buffer.writeln('   • Use o certificado correto para esta empresa');
      buffer.writeln('   • Verifique se o CNPJ do certificado corresponde ao CNPJ da empresa');
      buffer.writeln('');
    }

    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    return buffer.toString();
  }
}

