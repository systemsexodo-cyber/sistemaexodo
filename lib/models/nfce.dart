/// Modelo para representar uma NFC-e
class NFCe {
  final String id;
  final String numero;
  final String serie;
  final DateTime dataEmissao;
  final String empresaId;
  final List<NFCeItem> itens;
  final double valorTotal;
  final String? cpfCnpjConsumidor;
  final String? nomeConsumidor;
  final List<NFCePagamento> pagamentos;
  final String? chaveAcesso;
  final String? protocolo;
  final String? status; // 'pendente', 'autorizada', 'rejeitada', 'denegada', 'cancelada'
  final String? xmlEnviado;
  final String? xmlRetorno;
  final String? qrCode;
  final DateTime createdAt;
  final DateTime updatedAt;

  NFCe({
    required this.id,
    required this.numero,
    required this.serie,
    required this.dataEmissao,
    required this.empresaId,
    required this.itens,
    required this.valorTotal,
    this.cpfCnpjConsumidor,
    this.nomeConsumidor,
    required this.pagamentos,
    this.chaveAcesso,
    this.protocolo,
    this.status,
    this.xmlEnviado,
    this.xmlRetorno,
    this.qrCode,
    required this.createdAt,
    required this.updatedAt,
  });

  factory NFCe.fromMap(Map<String, dynamic> map) {
    return NFCe(
      id: map['id'] ?? '',
      numero: map['numero'] ?? '',
      serie: map['serie'] ?? '',
      dataEmissao: map['dataEmissao'] != null
          ? DateTime.parse(map['dataEmissao'])
          : DateTime.now(),
      empresaId: map['empresaId'] ?? '',
      itens: (map['itens'] as List<dynamic>?)
              ?.map((i) => NFCeItem.fromMap(i as Map<String, dynamic>))
              .toList() ??
          [],
      valorTotal: (map['valorTotal'] as num?)?.toDouble() ?? 0.0,
      cpfCnpjConsumidor: map['cpfCnpjConsumidor'],
      nomeConsumidor: map['nomeConsumidor'],
      pagamentos: (map['pagamentos'] as List<dynamic>?)
              ?.map((p) => NFCePagamento.fromMap(p as Map<String, dynamic>))
              .toList() ??
          [],
      chaveAcesso: map['chaveAcesso'],
      protocolo: map['protocolo'],
      status: map['status'],
      xmlEnviado: map['xmlEnviado'],
      xmlRetorno: map['xmlRetorno'],
      qrCode: map['qrCode'],
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'numero': numero,
      'serie': serie,
      'dataEmissao': dataEmissao.toIso8601String(),
      'empresaId': empresaId,
      'itens': itens.map((i) => i.toMap()).toList(),
      'valorTotal': valorTotal,
      'cpfCnpjConsumidor': cpfCnpjConsumidor,
      'nomeConsumidor': nomeConsumidor,
      'pagamentos': pagamentos.map((p) => p.toMap()).toList(),
      'chaveAcesso': chaveAcesso,
      'protocolo': protocolo,
      'status': status,
      'xmlEnviado': xmlEnviado,
      'xmlRetorno': xmlRetorno,
      'qrCode': qrCode,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

/// Modelo para item da NFC-e
class NFCeItem {
  final String produtoId;
  final String codigo;
  final String descricao;
  final String ncm;
  final String cfop;
  final String unidade;
  final double quantidade;
  final double valorUnitario;
  final double valorTotal;
  final String? origem;
  final String? csosn;
  final double? icmsAliquota;

  NFCeItem({
    required this.produtoId,
    required this.codigo,
    required this.descricao,
    required this.ncm,
    required this.cfop,
    required this.unidade,
    required this.quantidade,
    required this.valorUnitario,
    required this.valorTotal,
    this.origem,
    this.csosn,
    this.icmsAliquota,
  });

  factory NFCeItem.fromMap(Map<String, dynamic> map) {
    return NFCeItem(
      produtoId: map['produtoId'] ?? '',
      codigo: map['codigo'] ?? '',
      descricao: map['descricao'] ?? '',
      ncm: map['ncm'] ?? '',
      cfop: map['cfop'] ?? '',
      unidade: map['unidade'] ?? '',
      quantidade: (map['quantidade'] as num?)?.toDouble() ?? 0.0,
      valorUnitario: (map['valorUnitario'] as num?)?.toDouble() ?? 0.0,
      valorTotal: (map['valorTotal'] as num?)?.toDouble() ?? 0.0,
      origem: map['origem'],
      csosn: map['csosn'],
      icmsAliquota: (map['icmsAliquota'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'produtoId': produtoId,
      'codigo': codigo,
      'descricao': descricao,
      'ncm': ncm,
      'cfop': cfop,
      'unidade': unidade,
      'quantidade': quantidade,
      'valorUnitario': valorUnitario,
      'valorTotal': valorTotal,
      'origem': origem,
      'csosn': csosn,
      'icmsAliquota': icmsAliquota,
    };
  }
}

/// Modelo para forma de pagamento da NFC-e
class NFCePagamento {
  final String tipo; // '01'=Dinheiro, '02'=Cheque, '03'=Cartão Crédito, etc
  final double valor;
  final String? descricao;

  NFCePagamento({
    required this.tipo,
    required this.valor,
    this.descricao,
  });

  factory NFCePagamento.fromMap(Map<String, dynamic> map) {
    return NFCePagamento(
      tipo: map['tipo'] ?? '',
      valor: (map['valor'] as num?)?.toDouble() ?? 0.0,
      descricao: map['descricao'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'tipo': tipo,
      'valor': valor,
      'descricao': descricao,
    };
  }

  String get tipoDescricao {
    switch (tipo) {
      case '01':
        return 'Dinheiro';
      case '02':
        return 'Cheque';
      case '03':
        return 'Cartão de Crédito';
      case '04':
        return 'Cartão de Débito';
      case '05':
        return 'Crédito Loja';
      case '10':
        return 'Vale Alimentação';
      case '11':
        return 'Vale Refeição';
      case '12':
        return 'Vale Presente';
      case '13':
        return 'Vale Combustível';
      case '15':
        return 'Boleto Bancário';
      case '90':
        return 'Sem pagamento';
      case '99':
        return 'Outros';
      default:
        return 'Desconhecido';
    }
  }
}

