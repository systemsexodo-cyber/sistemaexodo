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
  final bool produtoNovo; // Se o produto foi criado por esta nota

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
    this.produtoNovo = false,
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
      precoCustoAnterior: map['precoCustoAnterior'] != null ? (map['precoCustoAnterior'] as num).toDouble() : null,
      precoVendaAnterior: map['precoVendaAnterior'] != null ? (map['precoVendaAnterior'] as num).toDouble() : null,
      estoqueAnterior: map['estoqueAnterior'] != null ? (map['estoqueAnterior'] as num).toInt() : null,
      produtoNovo: map['produtoNovo'] ?? false,
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
      'produtoNovo': produtoNovo,
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

  NotaEntrada({
    required this.id,
    required this.dataCriacao,
    this.dataProcessamento,
    required this.tipo,
    this.status = 'rascunho',
    required this.itens,
    this.observacao,
    this.numeroNotaReal,
  });

  factory NotaEntrada.fromMap(Map<String, dynamic> map) {
    return NotaEntrada(
      id: map['id'] ?? '',
      dataCriacao: map['dataCriacao'] != null
          ? DateTime.parse(map['dataCriacao'])
          : DateTime.now(),
      dataProcessamento: map['dataProcessamento'] != null
          ? DateTime.parse(map['dataProcessamento'])
          : null,
      tipo: map['tipo'] ?? 'manual',
      status: map['status'] ?? 'rascunho',
      itens: (map['itens'] as List<dynamic>?)
              ?.map((item) => ItemNotaEntrada.fromMap(item as Map<String, dynamic>))
              .toList() ??
          [],
      observacao: map['observacao'],
      numeroNotaReal: map['numeroNotaReal'],
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
    );
  }

  bool get isRascunho => status == 'rascunho';
  bool get isProcessada => status == 'processada';
  bool get isCancelada => status == 'cancelada';
  String get numeroNota => numeroNotaReal ?? 'ENT-${id.substring(id.length - 6)}';
  DateTime get dataHora => dataProcessamento ?? dataCriacao;
}
