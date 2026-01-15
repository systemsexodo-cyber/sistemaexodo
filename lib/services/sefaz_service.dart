import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;

/// Exceção customizada para rejeições da SEFAZ com mensagem moderna
class _SEFAZRejectionException implements Exception {
  final String codigo;
  final String motivo;
  final String? chaveAcesso;
  final String tipoErro;

  _SEFAZRejectionException({
    required this.codigo,
    required this.motivo,
    this.chaveAcesso,
    required this.tipoErro,
  });

  @override
  String toString() {
    final buffer = StringBuffer();
    
    // Cabeçalho moderno
    buffer.writeln('╔═══════════════════════════════════════════════════════════════╗');
    buffer.writeln('║          🚫 REJEIÇÃO DA SEFAZ - NFC-e NÃO AUTORIZADA         ║');
    buffer.writeln('╚═══════════════════════════════════════════════════════════════╝');
    buffer.writeln('');
    
    // Tipo de erro
    buffer.writeln('📌 TIPO DE ERRO:');
    buffer.writeln('   $tipoErro');
    buffer.writeln('');
    
    // Código e motivo
    buffer.writeln('📋 INFORMAÇÕES DA REJEIÇÃO:');
    buffer.writeln('   Código: $codigo');
    buffer.writeln('   Motivo: $motivo');
    if (chaveAcesso != null) {
      buffer.writeln('   Chave de Acesso: $chaveAcesso');
    }
    buffer.writeln('');
    
    // Soluções específicas para erro 290
    if (codigo == '290') {
      buffer.writeln('╔═══════════════════════════════════════════════════════════════╗');
      buffer.writeln('║                    🔧 SOLUÇÕES RECOMENDADAS                   ║');
      buffer.writeln('╚═══════════════════════════════════════════════════════════════╝');
      buffer.writeln('');
      
      buffer.writeln('1️⃣ VERIFICAR VALIDADE DO CERTIFICADO');
      buffer.writeln('   → Acesse: Configurações → Empresa → Certificado Digital');
      buffer.writeln('   → Verifique se o certificado não está expirado');
      buffer.writeln('   → Se expirado, renove na autoridade certificadora');
      buffer.writeln('');
      
      buffer.writeln('2️⃣ VERIFICAR FORMATO E CHAVE PRIVADA');
      buffer.writeln('   → Certificado deve estar em formato PKCS#12 (.pfx)');
      buffer.writeln('   → Deve incluir a chave privada na exportação');
      buffer.writeln('   → Re-exporte o certificado incluindo a chave privada');
      buffer.writeln('');
      
      buffer.writeln('3️⃣ VERIFICAR SENHA');
      buffer.writeln('   → Confirme se a senha está correta');
      buffer.writeln('   → A senha é case-sensitive (diferencia maiúsculas/minúsculas)');
      buffer.writeln('   → Teste a senha abrindo o certificado diretamente');
      buffer.writeln('');
      
      buffer.writeln('4️⃣ VERIFICAR AMBIENTE');
      buffer.writeln('   → Certificado de homologação ≠ produção');
      buffer.writeln('   → Use o certificado correto para o ambiente selecionado');
      buffer.writeln('');
      
      buffer.writeln('5️⃣ VERIFICAR CNPJ');
      buffer.writeln('   → CNPJ do certificado deve corresponder ao CNPJ da empresa');
      buffer.writeln('   → Verifique se está usando o certificado correto');
      buffer.writeln('');
      
      buffer.writeln('╔═══════════════════════════════════════════════════════════════╗');
      buffer.writeln('║                    📝 PASSO A PASSO                          ║');
      buffer.writeln('╚═══════════════════════════════════════════════════════════════╝');
      buffer.writeln('');
      buffer.writeln('  1. Abra o certificado no software original (e-CPF/e-CNPJ)');
      buffer.writeln('  2. Exporte novamente em formato PKCS#12 (.pfx)');
      buffer.writeln('  3. ✅ Marque "Incluir chave privada"');
      buffer.writeln('  4. ✅ Use senha simples (apenas letras e números)');
      buffer.writeln('  5. ❌ NÃO marque "Habilitar proteção forte"');
      buffer.writeln('  6. Salve o arquivo .pfx');
      buffer.writeln('  7. No sistema: Configurações → Empresa → Selecione o novo certificado');
      buffer.writeln('  8. Digite a senha correta');
      buffer.writeln('  9. Salve e tente emitir novamente');
      buffer.writeln('');
    } else {
      // Soluções genéricas para outras rejeições
      buffer.writeln('╔═══════════════════════════════════════════════════════════════╗');
      buffer.writeln('║                    🔧 O QUE FAZER AGORA                      ║');
      buffer.writeln('╚═══════════════════════════════════════════════════════════════╝');
      buffer.writeln('');
      buffer.writeln('  1. Verifique os dados da NFC-e (produtos, valores, etc.)');
      buffer.writeln('  2. Confirme se todos os dados estão corretos');
      buffer.writeln('  3. Verifique se o certificado está válido');
      buffer.writeln('  4. Tente emitir novamente');
      buffer.writeln('  5. Se persistir, consulte a documentação do código $codigo');
      buffer.writeln('');
    }
    
    buffer.writeln('╔═══════════════════════════════════════════════════════════════╗');
    buffer.writeln('║                    ℹ️  INFORMAÇÕES TÉCNICAS                    ║');
    buffer.writeln('╚═══════════════════════════════════════════════════════════════╝');
    buffer.writeln('   Código de Status: $codigo');
    buffer.writeln('   Motivo: $motivo');
    if (chaveAcesso != null) {
      buffer.writeln('   Chave de Acesso: $chaveAcesso');
    }
    buffer.writeln('');
    
    return buffer.toString();
  }
}

/// Serviço para comunicação SOAP com SEFAZ
class SEFAZService {
  /// Envia NFC-e para SEFAZ via WebService SOAP
  Future<Map<String, dynamic>> enviarNFCe(
    String xmlNFCe, {
    required bool ambienteHomologacao,
    required String estado,
  }) async {
    try {
      // 1. Obter URL do WebService conforme estado
      final url = _getUrlWebService(estado, ambienteHomologacao);

      // 2. Montar envelope SOAP
      final soapEnvelope = _montarEnvelopeSOAP(xmlNFCe);

      // 3. Fazer requisição SOAP
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'text/xml; charset=utf-8',
          'SOAPAction': 'http://www.portalfiscal.inf.br/nfe/wsdl/NFeAutorizacao4/nfeAutorizacaoLote',
        },
        body: soapEnvelope,
      );

      // 4. Verificar status HTTP antes de processar
      if (response.statusCode != 200) {
        throw Exception('Erro HTTP ${response.statusCode} ao enviar NFC-e para SEFAZ.\n\n'
            'Resposta: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}');
      }

      // 5. Processar resposta
      return _processarRespostaSOAP(response.body);
    } catch (e) {
      // Se já é uma Exception com mensagem detalhada, re-lançar
      if (e is Exception && e.toString().contains('\n')) {
        rethrow;
      }
      throw Exception('Erro ao enviar NFC-e para SEFAZ: $e');
    }
  }

  /// Retorna URL do WebService conforme estado
  /// URLs atualizadas conforme documentação oficial da SEFAZ
  /// 
  /// URLs de Homologação SP (referência):
  /// - NFeAutorizacao4: https://homologacao.nfce.fazenda.sp.gov.br/ws/NFeAutorizacao4.asmx
  /// - NFeRetAutorizacao4: https://homologacao.nfce.fazenda.sp.gov.br/ws/NFeRetAutorizacao4.asmx
  /// - NFeInutilizacao4: https://homologacao.nfce.fazenda.sp.gov.br/ws/NFeInutilizacao4.asmx
  /// - NFeConsultaProtocolo4: https://homologacao.nfce.fazenda.sp.gov.br/ws/NFeConsultaProtocolo4.asmx
  /// - NFeRecepcaoEvento4: https://homologacao.nfce.fazenda.sp.gov.br/ws/NFeRecepcaoEvento4.asmx
  /// - NFeStatusServico4: https://homologacao.nfce.fazenda.sp.gov.br/ws/NFeStatusServico4.asmx
  String _getUrlWebService(String estado, bool homologacao) {
    final urls = {
      'SP': homologacao
          ? 'https://homologacao.nfce.fazenda.sp.gov.br/ws/NFeAutorizacao4.asmx'
          : 'https://nfce.fazenda.sp.gov.br/ws/NFeAutorizacao4.asmx',
      'RJ': homologacao
          ? 'https://nfce-homologacao.svrs.rs.gov.br/ws/NfeAutorizacao/NFeAutorizacao4.asmx'
          : 'https://nfce.svrs.rs.gov.br/ws/NfeAutorizacao/NFeAutorizacao4.asmx',
      'MG': homologacao
          ? 'https://hnfce.fazenda.mg.gov.br/nfce/services/NFeAutorizacao4'
          : 'https://nfce.fazenda.mg.gov.br/nfce/services/NFeAutorizacao4',
      'RS': homologacao
          ? 'https://nfce-homologacao.svrs.rs.gov.br/ws/NfeAutorizacao/NFeAutorizacao4.asmx'
          : 'https://nfce.svrs.rs.gov.br/ws/NfeAutorizacao/NFeAutorizacao4.asmx',
      // Adicionar outros estados conforme necessário
    };

    return urls[estado] ?? urls['SP']!;
  }

  /// Monta envelope SOAP para envio
  String _montarEnvelopeSOAP(String xmlNFCe) {
    // Escapar XML para dentro do envelope SOAP
    final xmlEscapado = xmlNFCe
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');

    return '''<?xml version="1.0" encoding="UTF-8"?>
<soap12:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap12="http://www.w3.org/2003/05/soap-envelope">
  <soap12:Body>
    <nfeAutorizacaoLote xmlns="http://www.portalfiscal.inf.br/nfe/wsdl/NFeAutorizacao4">
      <nfeDadosMsg>
        $xmlEscapado
      </nfeDadosMsg>
    </nfeAutorizacaoLote>
  </soap12:Body>
</soap12:Envelope>''';
  }

  /// Processa resposta SOAP da SEFAZ
  Map<String, dynamic> _processarRespostaSOAP(String respostaSOAP) {
    try {
      // Verificar se a resposta não está vazia
      if (respostaSOAP.isEmpty) {
        throw Exception('Resposta vazia da SEFAZ');
      }

      // Tentar fazer parse do XML
      xml.XmlDocument document;
      try {
        document = xml.XmlDocument.parse(respostaSOAP);
      } catch (e) {
        // Se falhar o parse, pode ser que a resposta já seja um erro
        final preview = respostaSOAP.length > 500 
            ? respostaSOAP.substring(0, 500) 
            : respostaSOAP;
        throw Exception('Erro ao fazer parse da resposta XML da SEFAZ.\n\n'
            'Erro: ${e.toString()}\n\n'
            'Resposta recebida (primeiros 500 caracteres):\n$preview');
      }

      // Verificar se há erro SOAP na resposta
      final faultElements = document.findAllElements('soap:Fault').toList();
      if (faultElements.isEmpty) {
        faultElements.addAll(document.findAllElements('soap12:Fault').toList());
      }
      if (faultElements.isEmpty) {
        faultElements.addAll(document.findAllElements('Fault').toList());
      }

      if (faultElements.isNotEmpty) {
        final fault = faultElements.first;
        final faultCode = fault.findElements('faultcode').firstOrNull?.text ?? 
                         fault.findElements('Code').firstOrNull?.text ?? 
                         'Erro desconhecido';
        final faultString = fault.findElements('faultstring').firstOrNull?.text ?? 
                           fault.findElements('Reason').firstOrNull?.text ?? 
                           fault.findElements('Message').firstOrNull?.text ?? 
                           'Erro na comunicação com SEFAZ';
        
        throw Exception('Erro SOAP da SEFAZ:\nCódigo: $faultCode\nMotivo: $faultString');
      }

      // Extrair o Body do SOAP
      final bodyElements = document.findAllElements('soap:Body').toList();
      if (bodyElements.isEmpty) {
        bodyElements.addAll(document.findAllElements('soap12:Body').toList());
      }
      if (bodyElements.isEmpty) {
        bodyElements.addAll(document.findAllElements('Body').toList());
      }

      if (bodyElements.isEmpty) {
        throw Exception('Resposta SOAP sem Body encontrado');
      }

      final body = bodyElements.first;

      // Procurar retEnviNFe em diferentes namespaces
      xml.XmlElement? retEnviNFe;
      
      // Tentar encontrar sem namespace
      retEnviNFe = body.findAllElements('retEnviNFe').firstOrNull;
      
      // Tentar encontrar em todos os elementos (pode estar em qualquer namespace)
      if (retEnviNFe == null) {
        final allElements = body.findAllElements('*').toList();
        for (var element in allElements) {
          if (element.localName == 'retEnviNFe') {
            retEnviNFe = element;
            break;
          }
        }
      }

      // Se ainda não encontrou, procurar em todo o documento
      if (retEnviNFe == null) {
        retEnviNFe = document.findAllElements('retEnviNFe').firstOrNull;
      }

      if (retEnviNFe == null) {
        // Tentar extrair informações de erro alternativas
        final errorElements = body.findAllElements('*').where((e) => 
          e.localName.toLowerCase().contains('error') ||
          e.localName.toLowerCase().contains('erro') ||
          e.localName.toLowerCase().contains('exception')
        ).toList();

        if (errorElements.isNotEmpty) {
          final errorText = errorElements.map((e) => e.text).join('\n');
          throw Exception('Resposta da SEFAZ não contém retEnviNFe. Possível erro:\n$errorText');
        }

        // Retornar resposta completa para debug
        throw Exception('Resposta inválida da SEFAZ: elemento retEnviNFe não encontrado.\n\n'
            'Estrutura da resposta:\n'
            '${body.toXmlString(pretty: true).substring(0, body.toXmlString(pretty: true).length > 1000 ? 1000 : body.toXmlString(pretty: true).length)}');
      }

      // Extrair dados do retorno (nível do lote)
      final cStatLote = retEnviNFe.findElements('cStat').firstOrNull?.text ?? 
                       retEnviNFe.findAllElements('*').where((e) => e.localName == 'cStat').firstOrNull?.text ?? 
                       '';
      final xMotivoLote = retEnviNFe.findElements('xMotivo').firstOrNull?.text ?? 
                         retEnviNFe.findAllElements('*').where((e) => e.localName == 'xMotivo').firstOrNull?.text ?? 
                         '';

      // Procurar protNFe (protocolo da nota)
      xml.XmlElement? protNFe;
      protNFe = retEnviNFe.findElements('protNFe').firstOrNull;
      if (protNFe == null) {
        protNFe = retEnviNFe.findAllElements('*').where((e) => e.localName == 'protNFe').firstOrNull;
      }

      // Extrair dados do protocolo (infProt)
      String cStat = cStatLote;
      String xMotivo = xMotivoLote;
      String? chaveAcesso;
      String? protocolo;

      if (protNFe != null) {
        // Procurar infProt dentro do protNFe
        xml.XmlElement? infProt;
        infProt = protNFe.findElements('infProt').firstOrNull;
        if (infProt == null) {
          infProt = protNFe.findAllElements('*').where((e) => e.localName == 'infProt').firstOrNull;
        }

        if (infProt != null) {
          // Extrair dados do protocolo (prioridade sobre dados do lote)
          final cStatProt = infProt.findElements('cStat').firstOrNull?.text ?? 
                           infProt.findAllElements('*').where((e) => e.localName == 'cStat').firstOrNull?.text;
          final xMotivoProt = infProt.findElements('xMotivo').firstOrNull?.text ?? 
                             infProt.findAllElements('*').where((e) => e.localName == 'xMotivo').firstOrNull?.text;
          chaveAcesso = infProt.findElements('chNFe').firstOrNull?.text ?? 
                       infProt.findAllElements('*').where((e) => e.localName == 'chNFe').firstOrNull?.text;
          protocolo = infProt.findElements('nProt').firstOrNull?.text ?? 
                     infProt.findAllElements('*').where((e) => e.localName == 'nProt').firstOrNull?.text;

          // Usar dados do protocolo se disponíveis
          if (cStatProt != null && cStatProt.isNotEmpty) {
            cStat = cStatProt;
          }
          if (xMotivoProt != null && xMotivoProt.isNotEmpty) {
            xMotivo = xMotivoProt;
          }
        }
      }

      // Determinar status
      String status;
      if (cStat == '100' || cStat == '150') {
        status = 'autorizada';
      } else if (cStat.startsWith('2')) {
        status = 'rejeitada';
      } else if (cStat.startsWith('3')) {
        status = 'denegada';
      } else {
        status = 'pendente';
      }

      // Tratamento especial para erro 290 (Certificado Assinatura inválido)
      if (cStat == '290') {
        throw _SEFAZRejectionException(
          codigo: cStat,
          motivo: xMotivo,
          chaveAcesso: chaveAcesso,
          tipoErro: 'Certificado Assinatura Inválido',
        );
      }

      // Tratamento para outras rejeições
      if (status == 'rejeitada') {
        throw _SEFAZRejectionException(
          codigo: cStat,
          motivo: xMotivo,
          chaveAcesso: chaveAcesso,
          tipoErro: 'Rejeição da SEFAZ',
        );
      }

      return {
        'status': status,
        'codigo': cStat,
        'motivo': xMotivo,
        'chaveAcesso': chaveAcesso,
        'protocolo': protocolo,
        'xmlRetorno': respostaSOAP,
      };
    } catch (e) {
      // Melhorar mensagem de erro com mais detalhes
      String mensagemErro = 'Erro ao processar resposta da SEFAZ';
      
      if (e is Exception) {
        final erroStr = e.toString();
        // Se já contém mensagem detalhada, usar ela
        if (erroStr.contains('\n') || erroStr.length > 100) {
          mensagemErro = erroStr;
        } else {
          mensagemErro = 'Erro ao processar resposta SOAP da SEFAZ: $erroStr';
        }
      } else if (e is xml.XmlException) {
        mensagemErro = 'Erro ao processar XML da resposta: ${e.message}';
      } else {
        // Converter objeto para string de forma segura
        String erroString;
        try {
          erroString = e.toString();
        } catch (_) {
          erroString = 'Erro desconhecido (tipo: ${e.runtimeType})';
        }
        
        // Se o erro contém referência a Element, é problema de parsing XML
        if (erroString.contains('Element') && erroString.contains('soap-envelope')) {
          mensagemErro = 'Erro ao processar envelope SOAP da SEFAZ.\n\n'
              'A resposta da SEFAZ não está no formato esperado.\n\n'
              'Possíveis causas:\n'
              '1. URL do WebService incorreta\n'
              '2. Ambiente (homologação/produção) incorreto\n'
              '3. Problema de comunicação com a SEFAZ\n'
              '4. Certificado digital inválido ou expirado\n\n'
              'Detalhes técnicos: $erroString';
        } else {
          mensagemErro = 'Erro inesperado ao processar resposta: $erroString';
        }
      }
      
      throw Exception(mensagemErro);
    }
  }

  /// Consulta status de uma NFC-e
  Future<Map<String, dynamic>> consultarStatus(
    String chaveAcesso, {
    required bool ambienteHomologacao,
    required String estado,
  }) async {
    try {
      // TODO: Implementar consulta de status
      // Similar ao envio, mas usando método de consulta
      
      return {'status': 'autorizada'};
    } catch (e) {
      throw Exception('Erro ao consultar status: $e');
    }
  }

}

