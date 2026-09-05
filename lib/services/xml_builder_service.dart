import 'package:xml/xml.dart' as xml;
import '../models/empresa.dart';
import '../models/produto.dart';
import '../models/nfce.dart';
import 'digito_verificador_service.dart';

/// Serviço para construção do XML da NFC-e
class XMLBuilderService {
  /// Gera XML da NFC-e conforme layout oficial
  Future<String> gerarXML({
    required Empresa empresa,
    required List<Produto> produtos,
    required Map<String, double> quantidades, // Mapa produtoId -> quantidade
    required List<NFCePagamento> pagamentos,
    required String numero,
    required String serie,
    required double valorTotal,
    String? cpfCnpjConsumidor,
    String? nomeConsumidor,
    String? observacoes,
    required bool ambienteHomologacao,
  }) async {
    try {
      // 1. Calcular código numérico
      final codigoNumerico = _gerarCodigoNumerico();
      final dataEmissao = DateTime.now();

      // 2. Gerar chave de acesso (43 dígitos)
      final chave43Digitos = _gerarChave43Digitos(
        empresa.estado!,
        codigoNumerico,
        numero,
        serie,
        dataEmissao,
        empresa.cnpj!,
      );

      // 3. Calcular dígito verificador
      final digitoVerificador = DigitoVerificadorService.calcularDigitoVerificador(chave43Digitos);
      
      // 4. Chave completa (44 dígitos)
      final chaveAcesso = chave43Digitos + digitoVerificador;

      // 3. Montar XML
      final builder = xml.XmlBuilder();
      builder.processing('xml', 'version="1.0" encoding="UTF-8"');
      // Definir namespace como atributo xmlns no elemento raiz
      // O namespace será herdado por todos os elementos filhos
      builder.element('NFe', 
        attributes: {
          'xmlns': 'http://www.portalfiscal.inf.br/nfe',
        },
        nest: () {
        builder.element('infNFe', attributes: {
          'Id': 'NFe$chaveAcesso',
          'versao': '4.00',
        }, nest: () {
        _buildIde(builder, empresa, numero, serie, codigoNumerico, digitoVerificador, dataEmissao, ambienteHomologacao);
          _buildEmit(builder, empresa);
          if (cpfCnpjConsumidor != null || nomeConsumidor != null) {
            _buildDest(builder, cpfCnpjConsumidor, nomeConsumidor);
          }
          _buildItens(builder, produtos, quantidades, empresa);
          _buildTotal(builder, valorTotal);
          _buildPag(builder, pagamentos);
          if (observacoes != null && observacoes.isNotEmpty) {
            _buildInfAdic(builder, observacoes);
          }
        });
      });

      final document = builder.buildDocument();
      return document.toXmlString(pretty: false);
    } catch (e) {
      throw Exception('Erro ao gerar XML: $e');
    }
  }

  /// Constrói seção ide (Identificação)
  void _buildIde(
    xml.XmlBuilder builder,
    Empresa empresa,
    String numero,
    String serie,
    String codigoNumerico,
    String digitoVerificador,
    DateTime dataEmissao,
    bool ambienteHomologacao,
  ) {
    builder.element('ide', nest: () {
      builder.element('cUF', nest: _getCodigoUF(empresa.estado!));
      builder.element('cNF', nest: codigoNumerico);
      builder.element('mod', nest: '65'); // 65 = NFC-e
      builder.element('serie', nest: serie);
      builder.element('nNF', nest: numero);
      builder.element('dhEmi', nest: _formatarDataSefaz(dataEmissao));
      builder.element('tpNF', nest: '1'); // 1 = Saída
      builder.element('idDest', nest: '1'); // 1 = Operação interna
      builder.element('cMunFG', nest: _getCodigoMunicipio(empresa));
      builder.element('tpImp', nest: '4'); // 4 = NFC-e
      builder.element('tpEmis', nest: '1'); // 1 = Normal
      builder.element('cDV', nest: digitoVerificador);
      builder.element('tpAmb', nest: ambienteHomologacao ? '2' : '1'); // 1=Produção, 2=Homologação
      builder.element('finNFe', nest: '1'); // 1 = Normal
      builder.element('indFinal', nest: '1'); // 1 = Consumidor final
      builder.element('indPres', nest: '1'); // 1 = Presencial
      builder.element('procEmi', nest: '0'); // 0 = Aplicativo próprio
      builder.element('verProc', nest: 'SISTEMA EXODO 1.0');
    });
  }

  /// Constrói seção emit (Emitente)
  void _buildEmit(xml.XmlBuilder builder, Empresa empresa) {
    builder.element('emit', nest: () {
      builder.element('CNPJ', nest: empresa.cnpj!.replaceAll(RegExp(r'[^\d]'), ''));
      builder.element('xNome', nest: empresa.razaoSocial);
      if (empresa.nomeFantasia != null && empresa.nomeFantasia!.isNotEmpty) {
        builder.element('xFant', nest: empresa.nomeFantasia!);
      }
      builder.element('enderEmit', nest: () {
        builder.element('xLgr', nest: empresa.endereco ?? '');
        builder.element('nro', nest: empresa.numero ?? '');
        if (empresa.complemento != null && empresa.complemento!.isNotEmpty) {
          builder.element('xCpl', nest: empresa.complemento!);
        }
        builder.element('xBairro', nest: empresa.bairro ?? '');
        builder.element('cMun', nest: _getCodigoMunicipio(empresa));
        builder.element('xMun', nest: empresa.cidade ?? '');
        builder.element('UF', nest: empresa.estado ?? '');
        if (empresa.cep != null && empresa.cep!.isNotEmpty) {
          builder.element('CEP', nest: empresa.cep!.replaceAll(RegExp(r'[^\d]'), ''));
        }
      });
      if (empresa.inscricaoEstadual != null && empresa.inscricaoEstadual!.isNotEmpty) {
        builder.element('IE', nest: empresa.inscricaoEstadual!);
      }
      builder.element('CRT', nest: empresa.crt.toString());
    });
  }

  /// Constrói seção dest (Destinatário)
  void _buildDest(xml.XmlBuilder builder, String? cpfCnpj, String? nome) {
    builder.element('dest', nest: () {
      if (cpfCnpj != null && cpfCnpj.isNotEmpty) {
        final cpfCnpjLimpo = cpfCnpj.replaceAll(RegExp(r'[^\d]'), '');
        if (cpfCnpjLimpo.length == 11) {
          builder.element('CPF', nest: cpfCnpjLimpo);
        } else if (cpfCnpjLimpo.length == 14) {
          builder.element('CNPJ', nest: cpfCnpjLimpo);
        }
      }
      if (nome != null && nome.isNotEmpty) {
        builder.element('xNome', nest: nome);
      }
    });
  }

  /// Constrói seção det (Itens)
  void _buildItens(xml.XmlBuilder builder, List<Produto> produtos, Map<String, double> quantidades, Empresa empresa) {
    int itemNum = 1;
    for (final produto in produtos) {
      final quantidade = quantidades[produto.id] ?? 1.0;
      final valorTotalItem = produto.preco * quantidade;
      
      builder.element('det', attributes: {'nItem': itemNum.toString()}, nest: () {
        builder.element('prod', nest: () {
          builder.element('cProd', nest: produto.codigo ?? produto.id);
          builder.element('cEAN', nest: (produto.codigoBarras != null && produto.codigoBarras!.isNotEmpty) ? produto.codigoBarras! : 'SEM GTIN');
          builder.element('xProd', nest: produto.nome);
          builder.element('NCM', nest: produto.ncm ?? '00000000');
          
          String cfopFinal = produto.cfop ?? '5102';
          if ((produto.csosn == '500' || produto.icmsCst == '60') && (cfopFinal == '5102' || cfopFinal == '5101')) {
            cfopFinal = '5405';
          }
          builder.element('CFOP', nest: cfopFinal);
          builder.element('uCom', nest: produto.unidade);
          builder.element('qCom', nest: quantidade.toStringAsFixed(4));
          builder.element('vUnCom', nest: produto.preco.toStringAsFixed(4));
          builder.element('vProd', nest: valorTotalItem.toStringAsFixed(2));
          builder.element('cEANTrib', nest: produto.codigoBarras ?? 'SEM GTIN');
          builder.element('uTrib', nest: produto.unidade);
          builder.element('qTrib', nest: quantidade.toStringAsFixed(4));
          builder.element('vUnTrib', nest: produto.preco.toStringAsFixed(4));
          builder.element('indTot', nest: '1'); // 1 = Valor total
        });
        builder.element('imposto', nest: () {
          _buildImposto(builder, produto, empresa);
        });
      });
      itemNum++;
    }
  }

  /// Constrói seção de impostos
  void _buildImposto(xml.XmlBuilder builder, Produto produto, Empresa empresa) {
    final bool isSimplesNacional = empresa.crt == 1 || empresa.crt == null;

    builder.element('ICMS', nest: () {
      if (isSimplesNacional) {
        // Simples Nacional - Mapeamento estrito de tags válidas do Schema SEFAZ
        final String csosn = (produto.csosn != null && produto.csosn!.isNotEmpty) ? produto.csosn! : '102';
        String tagCSOSN = 'ICMSSN102';
        if (csosn == '101') {
          tagCSOSN = 'ICMSSN101';
        } else if (csosn == '102' || csosn == '103' || csosn == '300' || csosn == '400') {
          tagCSOSN = 'ICMSSN102';
        } else if (csosn == '201' || csosn == '202' || csosn == '203') {
          tagCSOSN = 'ICMSSN201';
        } else if (csosn == '500') {
          tagCSOSN = 'ICMSSN500';
        } else if (csosn == '900') {
          tagCSOSN = 'ICMSSN900';
        }

        builder.element(tagCSOSN, nest: () {
          builder.element('orig', nest: produto.origem ?? '0');
          builder.element('CSOSN', nest: csosn);
        });
      } else {
        // Regime Normal
        final String cst = (produto.icmsCst != null && produto.icmsCst!.isNotEmpty) ? produto.icmsCst! : '00';
        final String tagCST = 'ICMS$cst';
        builder.element(tagCST, nest: () {
          builder.element('orig', nest: produto.origem ?? '0');
          builder.element('CST', nest: cst);
          builder.element('modBC', nest: '0');
          builder.element('vBC', nest: '0.00');
          builder.element('pICMS', nest: (produto.icmsAliquota ?? 0).toStringAsFixed(2));
          builder.element('vICMS', nest: '0.00');
        });
      }
    });

    final String pisCst = (produto.pisCst != null && produto.pisCst!.isNotEmpty) ? produto.pisCst! : '01';
    builder.element('PIS', nest: () {
      if (pisCst == '01' || pisCst == '02') {
        builder.element('PISAliq', nest: () {
          builder.element('CST', nest: pisCst);
          builder.element('vBC', nest: '0.00');
          builder.element('pPIS', nest: (produto.pisAliquota ?? 0).toStringAsFixed(2));
          builder.element('vPIS', nest: '0.00');
        });
      } else if (pisCst == '03') {
        builder.element('PISQtde', nest: () {
          builder.element('CST', nest: pisCst);
          builder.element('qBCProd', nest: '0.0000');
          builder.element('vAliqProd', nest: '0.0000');
          builder.element('vPIS', nest: '0.00');
        });
      } else if (pisCst == '04' || pisCst == '05' || pisCst == '06' || pisCst == '07' || pisCst == '08' || pisCst == '09') {
        builder.element('PISNT', nest: () {
          builder.element('CST', nest: pisCst);
        });
      } else {
        builder.element('PISOutr', nest: () {
          builder.element('CST', nest: pisCst);
          builder.element('vBC', nest: '0.00');
          builder.element('pPIS', nest: (produto.pisAliquota ?? 0).toStringAsFixed(2));
          builder.element('vPIS', nest: '0.00');
        });
      }
    });

    final String cofinsCst = (produto.cofinsCst != null && produto.cofinsCst!.isNotEmpty) ? produto.cofinsCst! : '01';
    builder.element('COFINS', nest: () {
      if (cofinsCst == '01' || cofinsCst == '02') {
        builder.element('COFINSAliq', nest: () {
          builder.element('CST', nest: cofinsCst);
          builder.element('vBC', nest: '0.00');
          builder.element('pCOFINS', nest: (produto.cofinsAliquota ?? 0).toStringAsFixed(2));
          builder.element('vCOFINS', nest: '0.00');
        });
      } else if (cofinsCst == '03') {
        builder.element('COFINSQtde', nest: () {
          builder.element('CST', nest: cofinsCst);
          builder.element('qBCProd', nest: '0.0000');
          builder.element('vAliqProd', nest: '0.0000');
          builder.element('vCOFINS', nest: '0.00');
        });
      } else if (cofinsCst == '04' || cofinsCst == '05' || cofinsCst == '06' || cofinsCst == '07' || cofinsCst == '08' || cofinsCst == '09') {
        builder.element('COFINSNT', nest: () {
          builder.element('CST', nest: cofinsCst);
        });
      } else {
        builder.element('COFINSOutr', nest: () {
          builder.element('CST', nest: cofinsCst);
          builder.element('vBC', nest: '0.00');
          builder.element('pCOFINS', nest: (produto.cofinsAliquota ?? 0).toStringAsFixed(2));
          builder.element('vCOFINS', nest: '0.00');
        });
      }
    });
  }

  /// Constrói seção total
  void _buildTotal(xml.XmlBuilder builder, double valorTotal) {
    builder.element('total', nest: () {
      builder.element('ICMSTot', nest: () {
        builder.element('vBC', nest: '0.00');
        builder.element('vICMS', nest: '0.00');
        builder.element('vICMSDeson', nest: '0.00');
        builder.element('vFCP', nest: '0.00');
        builder.element('vBCST', nest: '0.00');
        builder.element('vST', nest: '0.00');
        builder.element('vFCPST', nest: '0.00');
        builder.element('vFCPSTRet', nest: '0.00');
        builder.element('vProd', nest: valorTotal.toStringAsFixed(2));
        builder.element('vFrete', nest: '0.00');
        builder.element('vSeg', nest: '0.00');
        builder.element('vDesc', nest: '0.00');
        builder.element('vII', nest: '0.00');
        builder.element('vIPI', nest: '0.00');
        builder.element('vIPIDevol', nest: '0.00');
        builder.element('vPIS', nest: '0.00');
        builder.element('vCOFINS', nest: '0.00');
        builder.element('vOutro', nest: '0.00');
        builder.element('vNF', nest: valorTotal.toStringAsFixed(2));
        builder.element('vTotTrib', nest: '0.00');
      });
    });
  }

  /// Constrói seção pag (Pagamento)
  void _buildPag(xml.XmlBuilder builder, List<NFCePagamento> pagamentos) {
    builder.element('pag', nest: () {
      for (final pagamento in pagamentos) {
        builder.element('detPag', nest: () {
          builder.element('tPag', nest: pagamento.tipo);
          builder.element('vPag', nest: pagamento.valor.toStringAsFixed(2));
        });
      }
    });
  }

  /// Constrói seção infAdic (Informações Adicionais)
  void _buildInfAdic(xml.XmlBuilder builder, String observacoes) {
    builder.element('infAdic', nest: () {
      builder.element('infCpl', nest: observacoes);
    });
  }

  /// Gera código numérico aleatório
  String _gerarCodigoNumerico() {
    final random = DateTime.now().millisecondsSinceEpoch;
    return random.toString().substring(5, 12);
  }

  /// Gera chave de acesso (43 dígitos, sem o dígito verificador)
  String _gerarChave43Digitos(
    String uf,
    String codigoNumerico,
    String numero,
    String serie,
    DateTime dataEmissao,
    String cnpj,
  ) {
    final codigoUF = _getCodigoUF(uf);
    // Formato AAMM: 2 últimos dígitos do ano + 2 dígitos do mês (4 dígitos total)
    final ano2Digitos = (dataEmissao.year % 100).toString().padLeft(2, '0');
    final mes2Digitos = dataEmissao.month.toString().padLeft(2, '0');
    final anoMes = '$ano2Digitos$mes2Digitos'; // 4 dígitos (AAMM)
    final cnpjLimpo = cnpj.replaceAll(RegExp(r'[^\d]'), '');
    final modelo = '65'; // NFC-e
    final seriePadded = serie.padLeft(3, '0');
    final numeroPadded = numero.padLeft(9, '0');
    final codigoNumericoPadded = codigoNumerico.padLeft(8, '0');

    final chave = '$codigoUF$anoMes$cnpjLimpo$modelo$seriePadded$numeroPadded$codigoNumericoPadded';
    
    // Validar tamanho: deve ter 43 dígitos
    // Estrutura: UF(2) + AAMM(4) + CNPJ(14) + Modelo(2) + Série(3) + Número(9) + Código(8) = 42
    // Mas a chave deve ter 43! Ajustar código numérico para 9 dígitos se necessário
    if (chave.length == 42) {
      // Se tiver 42, adicionar um zero à esquerda do código numérico para ter 43
      final codigo9Digitos = codigoNumerico.padLeft(9, '0');
      return '$codigoUF$anoMes$cnpjLimpo$modelo$seriePadded$numeroPadded$codigo9Digitos';
    }
    
    return chave;
  }

  /// Retorna código do estado (IBGE)
  String _getCodigoUF(String estado) {
    final codigos = {
      'AC': '12', 'AL': '27', 'AP': '16', 'AM': '13', 'BA': '29',
      'CE': '23', 'DF': '53', 'ES': '32', 'GO': '52', 'MA': '21',
      'MT': '51', 'MS': '50', 'MG': '31', 'PA': '15', 'PB': '25',
      'PR': '41', 'PE': '26', 'PI': '22', 'RJ': '33', 'RN': '24',
      'RS': '43', 'RO': '11', 'RR': '14', 'SC': '42', 'SP': '35',
      'SE': '28', 'TO': '17',
    };
    return codigos[estado] ?? '35';
  }

  /// Retorna código do município (IBGE)
  String _getCodigoMunicipio(Empresa empresa) {
    // Usar código IBGE da empresa se disponível
    if (empresa.codigoIBGE != null && empresa.codigoIBGE!.isNotEmpty) {
      return empresa.codigoIBGE!;
    }
    // Fallback: código genérico de São Paulo
    return '3550308'; // São Paulo - SP
  }

  /// Formata data no formato exigido pela SEFAZ: AAAA-MM-DDThh:mm:ssTZD (Ex: 2026-07-11T11:41:51-03:00)
  String _formatarDataSefaz(DateTime dt) {
    final local = dt.toLocal();
    final offset = local.timeZoneOffset;
    final offsetSign = offset.isNegative ? '-' : '+';
    final offsetHours = offset.inHours.abs().toString().padLeft(2, '0');
    final offsetMinutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    
    final datePart = "${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}";
    final timePart = "${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}";
    
    return "${datePart}T$timePart$offsetSign$offsetHours:$offsetMinutes";
  }
}

