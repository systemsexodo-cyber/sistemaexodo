class ItemMaterial {
  final String produtoId; // ID do produto/material
  final String produtoNome; // Nome do produto (para exibição)
  final double quantidade; // Quantidade a ser dada baixa (permite decimais para baixas fracionadas)
  final String? unidade; // Unidade do produto (UN, KG, L, etc)
  final double? precoCusto; // Preço de custo do material (opcional)
  final double? precoVenda; // Preço de venda do material (opcional)
  final String? observacao; // Observações adicionais sobre o material

  ItemMaterial({
    required this.produtoId,
    required this.produtoNome,
    required this.quantidade,
    this.unidade,
    this.precoCusto,
    this.precoVenda,
    this.observacao,
  });

  factory ItemMaterial.fromMap(Map<String, dynamic> map) {
    return ItemMaterial(
      produtoId: map['produtoId'] as String,
      produtoNome: map['produtoNome'] as String,
      quantidade: (map['quantidade'] as num).toDouble(),
      unidade: map['unidade'] as String?,
      precoCusto: map['precoCusto'] != null ? (map['precoCusto'] as num).toDouble() : null,
      precoVenda: map['precoVenda'] != null ? (map['precoVenda'] as num).toDouble() : null,
      observacao: map['observacao'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'produtoId': produtoId,
      'produtoNome': produtoNome,
      'quantidade': quantidade,
      'unidade': unidade,
      'precoCusto': precoCusto,
      'precoVenda': precoVenda,
      'observacao': observacao,
    };
  }

  ItemMaterial copyWith({
    String? produtoId,
    String? produtoNome,
    double? quantidade,
    String? unidade,
    double? precoCusto,
    double? precoVenda,
    String? observacao,
  }) {
    return ItemMaterial(
      produtoId: produtoId ?? this.produtoId,
      produtoNome: produtoNome ?? this.produtoNome,
      quantidade: quantidade ?? this.quantidade,
      unidade: unidade ?? this.unidade,
      precoCusto: precoCusto ?? this.precoCusto,
      precoVenda: precoVenda ?? this.precoVenda,
      observacao: observacao ?? this.observacao,
    );
  }
}

