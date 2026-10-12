/// Converte valores nulos ou string vazia (ex.: DEFAULT '' do PostgreSQL) em null,
/// para que o merge de lotes compare sempre de forma consistente.
String? _vazioParaNulo(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

/// Representa um lote de um produto com controle de validade.
///
/// Um mesmo produto pode ter vários lotes (ex.: ração comprada em datas
/// diferentes, cada uma com sua validade). O estoque de cada lote é
/// controlado individualmente e a baixa de vendas segue o princípio FEFO
/// (First Expired, First Out — vence antes, sai antes).
///
/// O lote é atrelado ao fornecedor E ao depósito/estoque na entrada: o mesmo
/// produto + nº de lote comprados de fornecedores DIFERENTES, ou que entraram
/// em ESTOQUES diferentes, ficam em lotes separados; entradas do mesmo produto
/// + fornecedor + estoque + nº de lote são unificadas (quantidade somada).
class LoteProduto {
  final String id;
  final String produtoId;
  final String? produtoNome; // Nome do produto (para exibição/listagens)
  final String numeroLote;
  final DateTime? dataFabricacao;
  final DateTime? dataValidade;
  final double quantidade; // Estoque restante do lote
  // Fornecedor de origem (atrelado ao lote na entrada de estoque)
  final String? fornecedorId; // ID/CNPJ do fornecedor
  final String? fornecedorNome; // Nome do fornecedor
  // Depósito/estoque de destino do lote (Loja, Depósito…). Separa o saldo por
  // local: o mesmo produto + lote no depósito e na loja são lotes distintos.
  final String? estoqueId; // id do estoque de destino
  final String? estoqueNome; // nome do estoque (para exibição)
  final double? custoUnitario; // custo unitário de entrada do lote
  final DateTime createdAt;
  final DateTime updatedAt;

  LoteProduto({
    required this.id,
    required this.produtoId,
    this.produtoNome,
    required this.numeroLote,
    this.dataFabricacao,
    this.dataValidade,
    this.quantidade = 0.0,
    this.fornecedorId,
    this.fornecedorNome,
    this.estoqueId,
    this.estoqueNome,
    this.custoUnitario,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Dias restantes até o vencimento (negativo = vencido). Null se não tem validade.
  int? get diasParaVencer {
    if (dataValidade == null) return null;
    final hoje = DateTime.now();
    final hojeDia = DateTime(hoje.year, hoje.month, hoje.day);
    final validadeDia = DateTime(
      dataValidade!.year,
      dataValidade!.month,
      dataValidade!.day,
    );
    return validadeDia.difference(hojeDia).inDays;
  }

  bool get estaVencido {
    final dias = diasParaVencer;
    return dias != null && dias < 0;
  }

  bool get venceHoje {
    final dias = diasParaVencer;
    return dias != null && dias == 0;
  }

  factory LoteProduto.fromMap(Map<String, dynamic> map) {
    return LoteProduto(
      id: map['id']?.toString() ?? '',
      produtoId: map['produto_id'] ?? map['produtoId'] ?? '',
      produtoNome: _vazioParaNulo(map['produto_nome'] ?? map['produtoNome']),
      numeroLote: map['numero_lote'] ?? map['numeroLote'] ?? '',
      dataFabricacao: map['data_fabricacao'] != null
          ? (map['data_fabricacao'] is DateTime
              ? map['data_fabricacao'] as DateTime
              : DateTime.tryParse(map['data_fabricacao'].toString()))
          : null,
      dataValidade: map['data_validade'] != null
          ? (map['data_validade'] is DateTime
              ? map['data_validade'] as DateTime
              : DateTime.tryParse(map['data_validade'].toString()))
          : null,
      quantidade: map['quantidade'] != null
          ? (map['quantidade'] is num
              ? (map['quantidade'] as num).toDouble()
              : double.tryParse(map['quantidade'].toString()) ?? 0.0)
          : 0.0,
      fornecedorId: _vazioParaNulo(map['fornecedor_id'] ?? map['fornecedorId']),
      fornecedorNome: _vazioParaNulo(map['fornecedor_nome'] ?? map['fornecedorNome']),
      estoqueId: _vazioParaNulo(map['estoque_id'] ?? map['estoqueId']),
      estoqueNome: _vazioParaNulo(map['estoque_nome'] ?? map['estoqueNome']),
      custoUnitario: map['custo_unitario'] != null
          ? (map['custo_unitario'] is num
              ? (map['custo_unitario'] as num).toDouble()
              : double.tryParse(map['custo_unitario'].toString()))
          : null,
      createdAt: map['created_at'] != null
          ? (map['created_at'] is DateTime
              ? map['created_at'] as DateTime
              : DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now())
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? (map['updated_at'] is DateTime
              ? map['updated_at'] as DateTime
              : DateTime.tryParse(map['updated_at'].toString()) ?? DateTime.now())
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'produto_id': produtoId,
      'produto_nome': produtoNome,
      'numero_lote': numeroLote,
      'data_fabricacao': dataFabricacao?.toIso8601String(),
      'data_validade': dataValidade?.toIso8601String(),
      'quantidade': quantidade,
      'fornecedor_id': fornecedorId,
      'fornecedor_nome': fornecedorNome,
      'estoque_id': estoqueId,
      'estoque_nome': estoqueNome,
      'custo_unitario': custoUnitario,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  LoteProduto copyWith({
    String? id,
    String? produtoId,
    String? produtoNome,
    String? numeroLote,
    DateTime? dataFabricacao,
    DateTime? dataValidade,
    double? quantidade,
    String? fornecedorId,
    String? fornecedorNome,
    String? estoqueId,
    String? estoqueNome,
    double? custoUnitario,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return LoteProduto(
      id: id ?? this.id,
      produtoId: produtoId ?? this.produtoId,
      produtoNome: produtoNome ?? this.produtoNome,
      numeroLote: numeroLote ?? this.numeroLote,
      dataFabricacao: dataFabricacao ?? this.dataFabricacao,
      dataValidade: dataValidade ?? this.dataValidade,
      quantidade: quantidade ?? this.quantidade,
      fornecedorId: fornecedorId ?? this.fornecedorId,
      fornecedorNome: fornecedorNome ?? this.fornecedorNome,
      estoqueId: estoqueId ?? this.estoqueId,
      estoqueNome: estoqueNome ?? this.estoqueNome,
      custoUnitario: custoUnitario ?? this.custoUnitario,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
