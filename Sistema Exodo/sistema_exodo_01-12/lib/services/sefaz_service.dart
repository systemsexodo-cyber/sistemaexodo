import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;

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

      // 4. Processar resposta
      return _processarRespostaSOAP(response.body);
    } catch (e) {
      throw Exception('Erro ao enviar NFC-e para SEFAZ: $e');
    }
  }

  /// Retorna URL do WebService conforme estado
  String _getUrlWebService(String estado, bool homologacao) {
    final urls = {
      'SP': homologacao
          ? 'https://homologacao.nfce.fazenda.sp.gov.br/wsdl/NFeAutorizacao4.asmx'
          : 'https://nfce.fazenda.sp.gov.br/wsdl/NFeAutorizacao4.asmx',
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
      final document = xml.XmlDocument.parse(respostaSOAP);
      
      // Extrair dados do retorno
      final retEnviNFe = document.findAllElements('retEnviNFe').firstOrNull;
      if (retEnviNFe == null) {
        throw Exception('Resposta inválida da SEFAZ');
      }

      final cStat = retEnviNFe.findElements('cStat').firstOrNull?.text ?? '';
      final xMotivo = retEnviNFe.findElements('xMotivo').firstOrNull?.text ?? '';
      final chaveAcesso = retEnviNFe.findElements('chNFe').firstOrNull?.text;
      final protocolo = retEnviNFe.findElements('nProt').firstOrNull?.text;

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

      return {
        'status': status,
        'codigo': cStat,
        'motivo': xMotivo,
        'chaveAcesso': chaveAcesso,
        'protocolo': protocolo,
        'xmlRetorno': respostaSOAP,
      };
    } catch (e) {
      throw Exception('Erro ao processar resposta da SEFAZ: $e');
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

