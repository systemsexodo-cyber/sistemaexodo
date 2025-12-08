import 'package:flutter/foundation.dart';
import '../models/nfce.dart';
import '../models/empresa.dart';
import '../models/produto.dart';
import 'sefaz_service.dart';
import 'certificado_service.dart';
import 'assinatura_service.dart';
import 'xml_builder_service.dart';
import 'numero_nfce_service.dart';
import 'qr_code_service.dart';

/// Serviço principal para emissão de NFC-e via SOAP SEFAZ
class NFCeService {
  final SEFAZService _sefazService;
  final CertificadoService _certificadoService;
  final AssinaturaService _assinaturaService;
  final XMLBuilderService _xmlBuilder;

  NFCeService({
    required SEFAZService sefazService,
    required CertificadoService certificadoService,
    required AssinaturaService assinaturaService,
    required XMLBuilderService xmlBuilder,
  })  : _sefazService = sefazService,
        _certificadoService = certificadoService,
        _assinaturaService = assinaturaService,
        _xmlBuilder = xmlBuilder;

  /// Emite uma NFC-e
  Future<NFCe> emitir({
    required Empresa empresa,
    required List<Produto> produtos,
    required Map<String, double> quantidades, // Mapa produtoId -> quantidade
    required List<NFCePagamento> pagamentos,
    required double valorTotal,
    String? cpfCnpjConsumidor,
    String? nomeConsumidor,
    String? observacoes,
    bool ambienteHomologacao = true,
  }) async {
    try {
      debugPrint('>>> [NFCe] Iniciando emissão de NFC-e...');
      debugPrint('>>> [NFCe] Ambiente: ${ambienteHomologacao ? "Homologação" : "Produção"}');
      debugPrint('>>> [NFCe] Empresa: ${empresa.razaoSocial} (${empresa.cnpj})');
      debugPrint('>>> [NFCe] Produtos: ${produtos.length}');
      debugPrint('>>> [NFCe] Valor Total: R\$ $valorTotal');
      
      // 1. Validar dados obrigatórios
      _validarDados(empresa, produtos);
      debugPrint('>>> [NFCe] Validação de dados concluída');

      // 2. Gerar número da NFC-e (sequencial)
      // Usar série da empresa ou padrão "1"
      final serie = empresa.serieNFCe ?? '1';
      final numero = await NumeroNFCeService.obterProximoNumero(empresa.id, serie: serie);
      debugPrint('>>> [NFCe] Número gerado: $numero (Série: $serie)');

      // 3. Montar XML da NFC-e
      debugPrint('>>> [NFCe] Gerando XML...');
      final xmlNFCe = await _xmlBuilder.gerarXML(
        empresa: empresa,
        produtos: produtos,
        quantidades: quantidades,
        pagamentos: pagamentos,
        numero: numero,
        serie: serie,
        valorTotal: valorTotal,
        cpfCnpjConsumidor: cpfCnpjConsumidor,
        nomeConsumidor: nomeConsumidor,
        observacoes: observacoes,
        ambienteHomologacao: ambienteHomologacao,
      );

      // 4. Assinar XML com certificado digital
      final certificado = await _certificadoService.carregarCertificado(
        empresa.certificadoDigitalUrl ?? '',
        empresa.senhaCertificado!,
        certificadoDigitalBytes: empresa.certificadoDigitalBytes,
      );

      final xmlAssinado = await _assinaturaService.assinarXML(
        xmlNFCe,
        certificado,
      );

      // 5. Enviar para SEFAZ
      final resultado = await _sefazService.enviarNFCe(
        xmlAssinado,
        ambienteHomologacao: ambienteHomologacao,
        estado: empresa.estado!,
      );

      // 6. Processar retorno
      final nfce = _processarRetorno(
        empresa: empresa,
        produtos: produtos,
        quantidades: quantidades,
        pagamentos: pagamentos,
        numero: numero,
        serie: serie,
        valorTotal: valorTotal,
        cpfCnpjConsumidor: cpfCnpjConsumidor,
        nomeConsumidor: nomeConsumidor,
        xmlEnviado: xmlAssinado,
        xmlRetorno: resultado['xmlRetorno'],
        resultado: resultado,
      );

      // 7. Gerar QR Code (se autorizada)
      NFCe nfceFinal = nfce;
      if (nfce.status == 'autorizada' && nfce.chaveAcesso != null && empresa.csc != null && empresa.cscIdToken != null) {
        final qrCodeString = QRCodeService.gerarStringQRCode(
          chaveAcesso: nfce.chaveAcesso!,
          urlConsulta: _getUrlConsultaQRCode(empresa.estado!),
          csc: empresa.csc!,
          cscIdToken: empresa.cscIdToken!,
          ambienteHomologacao: ambienteHomologacao,
          dataEmissao: nfce.dataEmissao,
          valorTotal: valorTotal,
        );
        nfceFinal = nfce.copyWith(qrCode: qrCodeString);
      }

      return nfceFinal;
    } catch (e) {
      throw Exception('Erro ao emitir NFC-e: $e');
    }
  }

  /// Valida dados obrigatórios
  void _validarDados(Empresa empresa, List<Produto> produtos) {
    if (empresa.cnpj == null || empresa.cnpj!.isEmpty) {
      throw Exception('CNPJ da empresa é obrigatório');
    }
    if (empresa.inscricaoEstadual == null || empresa.inscricaoEstadual!.isEmpty) {
      throw Exception('Inscrição Estadual é obrigatória');
    }
    if (empresa.certificadoDigitalUrl == null || empresa.certificadoDigitalUrl!.isEmpty) {
      throw Exception('Certificado Digital é obrigatório');
    }
    if (empresa.senhaCertificado == null || empresa.senhaCertificado!.isEmpty) {
      throw Exception('Senha do Certificado é obrigatória');
    }
    if (empresa.crt == null) {
      throw Exception('CRT (Regime Tributário) é obrigatório');
    }
    if (produtos.isEmpty) {
      throw Exception('É necessário pelo menos um produto');
    }

    // Validar produtos
    for (final produto in produtos) {
      if (produto.ncm == null || produto.ncm!.isEmpty) {
        throw Exception('NCM é obrigatório para o produto: ${produto.nome}');
      }
      if (produto.cfop == null || produto.cfop!.isEmpty) {
        throw Exception('CFOP é obrigatório para o produto: ${produto.nome}');
      }
      if (produto.origem == null || produto.origem!.isEmpty) {
        throw Exception('Origem é obrigatória para o produto: ${produto.nome}');
      }
    }
  }


  /// Processa retorno da SEFAZ
  NFCe _processarRetorno({
    required Empresa empresa,
    required List<Produto> produtos,
    required Map<String, double> quantidades,
    required List<NFCePagamento> pagamentos,
    required String numero,
    required String serie,
    required double valorTotal,
    String? cpfCnpjConsumidor,
    String? nomeConsumidor,
    required String xmlEnviado,
    String? xmlRetorno,
    required Map<String, dynamic> resultado,
  }) {
    final status = resultado['status'] ?? 'pendente';
    final chaveAcesso = resultado['chaveAcesso'];
    final protocolo = resultado['protocolo'];
    final qrCode = resultado['qrCode'];

    final itens = produtos.map((p) {
      final quantidade = quantidades[p.id] ?? 1.0;
      final valorTotalItem = p.preco * quantidade;
      return NFCeItem(
        produtoId: p.id,
        codigo: p.codigo ?? p.id,
        descricao: p.nome,
        ncm: p.ncm ?? '00000000',
        cfop: p.cfop ?? '5102',
        unidade: p.unidade,
        quantidade: quantidade,
        valorUnitario: p.preco,
        valorTotal: valorTotalItem,
        origem: p.origem ?? '0',
        csosn: p.csosn,
        icmsAliquota: p.icmsAliquota,
      );
    }).toList();

    return NFCe(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      numero: numero,
      serie: serie,
      dataEmissao: DateTime.now(),
      empresaId: empresa.id,
      itens: itens,
      valorTotal: valorTotal,
      cpfCnpjConsumidor: cpfCnpjConsumidor,
      nomeConsumidor: nomeConsumidor,
      pagamentos: pagamentos,
      chaveAcesso: chaveAcesso,
      protocolo: protocolo,
      status: status,
      xmlEnviado: xmlEnviado,
      xmlRetorno: xmlRetorno,
      qrCode: qrCode,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }


  /// Retorna URL de consulta do QR Code por estado
  String _getUrlConsultaQRCode(String estado) {
    // URLs de consulta pública por estado
    final urls = {
      'SP': 'https://www.nfce.fazenda.sp.gov.br/qrcode',
      'RJ': 'https://www.nfce.fazenda.rj.gov.br/consulta',
      'MG': 'https://www.nfce.mg.gov.br/portalnfce',
      'RS': 'https://www.sefaz.rs.gov.br/NFCE/NFCE-COM.aspx',
      // Adicionar outros estados conforme necessário
    };
    
    return urls[estado] ?? 'https://www.nfce.fazenda.sp.gov.br/qrcode';
  }
}

/// Extensão para criar cópia do NFCe
extension NFCeCopyWith on NFCe {
  NFCe copyWith({
    String? id,
    String? numero,
    String? serie,
    DateTime? dataEmissao,
    String? empresaId,
    List<NFCeItem>? itens,
    double? valorTotal,
    String? cpfCnpjConsumidor,
    String? nomeConsumidor,
    List<NFCePagamento>? pagamentos,
    String? chaveAcesso,
    String? protocolo,
    String? status,
    String? xmlEnviado,
    String? xmlRetorno,
    String? qrCode,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return NFCe(
      id: id ?? this.id,
      numero: numero ?? this.numero,
      serie: serie ?? this.serie,
      dataEmissao: dataEmissao ?? this.dataEmissao,
      empresaId: empresaId ?? this.empresaId,
      itens: itens ?? this.itens,
      valorTotal: valorTotal ?? this.valorTotal,
      cpfCnpjConsumidor: cpfCnpjConsumidor ?? this.cpfCnpjConsumidor,
      nomeConsumidor: nomeConsumidor ?? this.nomeConsumidor,
      pagamentos: pagamentos ?? this.pagamentos,
      chaveAcesso: chaveAcesso ?? this.chaveAcesso,
      protocolo: protocolo ?? this.protocolo,
      status: status ?? this.status,
      xmlEnviado: xmlEnviado ?? this.xmlEnviado,
      xmlRetorno: xmlRetorno ?? this.xmlRetorno,
      qrCode: qrCode ?? this.qrCode,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

