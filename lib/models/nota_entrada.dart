class ItemNotaEntrada {
  final String codigo;
  final String? codigoBarras;
  final String nome;
  final double quantidade;
  final double quantidadeEmbalagens;
  final double quantidadePorEmbalagem;
  final double precoCusto;
  final double precoVenda;
  final String unidade;
  final String? produtoId; // ID do produto se já existir
  // Valores anteriores para reversão
  final double? precoCustoAnterior;
  final double? precoVendaAnterior;
  final int? estoqueAnterior;
  final int? estoqueMinimo; // Adicionado: estoque mínimo configurado na entrada
  final bool produtoNovo; // Se o produto foi criado por esta nota
  // Controle de validade/lote (pet shop: ração, medicamentos, etc.)
  final String? numeroLote; // Número do lote informado na entrada
  final DateTime? dataValidade; // Validade do lote informado na entrada
  final DateTime? dataFabricacao; // (Opcional) data de fabricação

  ItemNotaEntrada({
    required this.codigo,
    this.codigoBarras,
    required this.nome,
    required this.quantidade,
    required this.quantidadeEmbalagens,
    required this.quantidadePorEmbalagem,
    required this.precoCusto,
    required this.precoVenda,
    required this.unidade,
    this.produtoId,
    this.precoCustoAnterior,
    this.precoVendaAnterior,
    this.estoqueAnterior,
    this.estoqueMinimo,
    this.produtoNovo = false,
    this.numeroLote,
    this.dataValidade,
    this.dataFabricacao,
  });

  factory ItemNotaEntrada.fromMap(Map<String, dynamic> map) {
    return ItemNotaEntrada(
      codigo: map['codigo'] ?? '',
      codigoBarras: map['codigoBarras'],
      nome: map['nome'] ?? '',
      quantidade: (map['quantidade'] ?? 0).toDouble(),
      quantidadeEmbalagens: (map['quantidadeEmbalagens'] ?? 0).toDouble(),
      quantidadePorEmbalagem: (map['quantidadePorEmbalagem'] ?? 1).toDouble(),
      precoCusto: (map['precoCusto'] ?? 0).toDouble(),
      precoVenda: (map['precoVenda'] ?? 0).toDouble(),
      unidade: map['unidade'] ?? 'UN',
      produtoId: map['produtoId'],
      precoCustoAnterior: map['precoCustoAnterior'] != null ? double.tryParse(map['precoCustoAnterior'].toString()) : null,
      precoVendaAnterior: map['precoVendaAnterior'] != null ? double.tryParse(map['precoVendaAnterior'].toString()) : null,
      estoqueAnterior: map['estoqueAnterior'] != null ? int.tryParse(map['estoqueAnterior'].toString()) : null,
      estoqueMinimo: map['estoqueMinimo'] != null ? int.tryParse(map['estoqueMinimo'].toString()) : null,
      produtoNovo: map['produtoNovo'] ?? false,
      numeroLote: map['numeroLote'],
      dataValidade: map['dataValidade'] != null
          ? (map['dataValidade'] is DateTime
              ? map['dataValidade'] as DateTime
              : DateTime.tryParse(map['dataValidade'].toString()))
          : null,
      dataFabricacao: map['dataFabricacao'] != null
          ? (map['dataFabricacao'] is DateTime
              ? map['dataFabricacao'] as DateTime
              : DateTime.tryParse(map['dataFabricacao'].toString()))
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'codigo': codigo,
      'codigoBarras': codigoBarras,
      'nome': nome,
      'quantidade': quantidade,
      'quantidadeEmbalagens': quantidadeEmbalagens,
      'quantidadePorEmbalagem': quantidadePorEmbalagem,
      'precoCusto': precoCusto,
      'precoVenda': precoVenda,
      'unidade': unidade,
      'produtoId': produtoId,
      'precoCustoAnterior': precoCustoAnterior,
      'precoVendaAnterior': precoVendaAnterior,
      'estoqueAnterior': estoqueAnterior,
      'estoqueMinimo': estoqueMinimo,
      'produtoNovo': produtoNovo,
      'numeroLote': numeroLote,
      'dataValidade': dataValidade?.toIso8601String(),
      'dataFabricacao': dataFabricacao?.toIso8601String(),
    };
  }
}

class NotaEntrada {
  final String id;
  final DateTime dataCriacao;
  final DateTime? dataProcessamento;
  final String tipo; // 'xml' ou 'manual'
  final String status; // 'rascunho', 'processada', 'cancelada'
  final List<ItemNotaEntrada> itens;
  final String? observacao;
  final String? numeroNotaReal; // Número real da nota fiscal (do XML)
  // Informações adicionais do XML
  final String? chaveNFe; // Chave de acesso da NFe
  final String? fornecedorNome; // Nome do fornecedor/emitente
  final String? fornecedorCNPJ; // CNPJ do fornecedor
  final DateTime? dataEmissao; // Data de emissão da nota
  final double? valorTotal; // Valor total da nota
  final String? serie; // Série da nota
  final String? modelo; // Modelo da nota (55 = NFe)
  final String? xmlOriginal; // Conteúdo bruto do XML para backup
  final DateTime createdAt;
  final DateTime updatedAt;

  NotaEntrada({
    required this.id,
    required this.dataCriacao,
    this.dataProcessamento,
    required this.tipo,
    this.status = 'rascunho',
    required this.itens,
    this.observacao,
    this.numeroNotaReal,
    this.chaveNFe,
    this.fornecedorNome,
    this.fornecedorCNPJ,
    this.dataEmissao,
    this.valorTotal,
    this.serie,
    this.modelo,
    this.xmlOriginal,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory NotaEntrada.fromMap(Map<String, dynamic> map) {
    return NotaEntrada(
      id: map['id']?.toString() ?? '',
      dataCriacao: map['dataCriacao'] != null
          ? (map['dataCriacao'] is DateTime ? map['dataCriacao'] as DateTime : DateTime.parse(map['dataCriacao'].toString()))
          : DateTime.now(),
      dataProcessamento: map['dataProcessamento'] != null
          ? (map['dataProcessamento'] is DateTime ? map['dataProcessamento'] as DateTime : DateTime.parse(map['dataProcessamento'].toString()))
          : null,
      tipo: map['tipo'] ?? 'manual',
      status: map['status'] ?? 'rascunho',
      itens: (map['itens'] as List<dynamic>?)
              ?.map((item) => ItemNotaEntrada.fromMap(item as Map<String, dynamic>))
              .toList() ??
          [],
      observacao: map['observacao'],
      numeroNotaReal: map['numeroNotaReal'],
      chaveNFe: map['chaveNFe'],
      fornecedorNome: map['fornecedorNome'],
      fornecedorCNPJ: map['fornecedorCNPJ'],
      dataEmissao: map['dataEmissao'] != null
          ? (map['dataEmissao'] is DateTime ? map['dataEmissao'] as DateTime : DateTime.parse(map['dataEmissao'].toString()))
          : null,
      valorTotal: map['valorTotal'] != null ? double.tryParse(map['valorTotal'].toString()) : null,
      serie: map['serie'],
      modelo: map['modelo'],
      xmlOriginal: map['xmlOriginal'],
      createdAt: map['createdAt'] != null ? (map['createdAt'] is DateTime ? map['createdAt'] as DateTime : DateTime.parse(map['createdAt'].toString())) : DateTime.now(),
      updatedAt: map['updatedAt'] != null ? (map['updatedAt'] is DateTime ? map['updatedAt'] as DateTime : DateTime.parse(map['updatedAt'].toString())) : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'dataCriacao': dataCriacao.toIso8601String(),
      'dataProcessamento': dataProcessamento?.toIso8601String(),
      'tipo': tipo,
      'status': status,
      'itens': itens.map((item) => item.toMap()).toList(),
      'observacao': observacao,
      'numeroNotaReal': numeroNotaReal,
      'chaveNFe': chaveNFe,
      'fornecedorNome': fornecedorNome,
      'fornecedorCNPJ': fornecedorCNPJ,
      'dataEmissao': dataEmissao?.toIso8601String(),
      'valorTotal': valorTotal,
      'serie': serie,
      'modelo': modelo,
      'xmlOriginal': xmlOriginal,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  NotaEntrada copyWith({
    String? id,
    DateTime? dataCriacao,
    DateTime? dataProcessamento,
    String? tipo,
    String? status,
    List<ItemNotaEntrada>? itens,
    String? observacao,
    String? numeroNotaReal,
    String? chaveNFe,
    String? fornecedorNome,
    String? fornecedorCNPJ,
    DateTime? dataEmissao,
    double? valorTotal,
    String? serie,
    String? modelo,
    String? xmlOriginal,
  }) {
    return NotaEntrada(
      id: id ?? this.id,
      dataCriacao: dataCriacao ?? this.dataCriacao,
      dataProcessamento: dataProcessamento ?? this.dataProcessamento,
      tipo: tipo ?? this.tipo,
      status: status ?? this.status,
      itens: itens ?? this.itens,
      observacao: observacao ?? this.observacao,
      numeroNotaReal: numeroNotaReal ?? this.numeroNotaReal,
      chaveNFe: chaveNFe ?? this.chaveNFe,
      fornecedorNome: fornecedorNome ?? this.fornecedorNome,
      fornecedorCNPJ: fornecedorCNPJ ?? this.fornecedorCNPJ,
      dataEmissao: dataEmissao ?? this.dataEmissao,
      valorTotal: valorTotal ?? this.valorTotal,
      serie: serie ?? this.serie,
      modelo: modelo ?? this.modelo,
      xmlOriginal: xmlOriginal ?? this.xmlOriginal,
    );
  }

  bool get isRascunho => status == 'rascunho';
  bool get isProcessada => status == 'processada';
  bool get isCancelada => status == 'cancelada';
  String get numeroNota => numeroNotaReal ?? 'ENT-${id.substring(id.length - 6)}';
  DateTime get dataHora => dataProcessamento ?? dataCriacao;
}
