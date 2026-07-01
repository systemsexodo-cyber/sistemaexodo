class ItemComposicao {
  final String produtoId;
  final double quantidade;

  ItemComposicao({
    required this.produtoId,
    required this.quantidade,
  });

  Map<String, dynamic> toMap() {
    return {
      'produto_id': produtoId,
      'quantidade': quantidade,
    };
  }

  factory ItemComposicao.fromMap(Map<String, dynamic> map) {
    return ItemComposicao(
      produtoId: map['produto_id'] as String,
      quantidade: (map['quantidade'] as num).toDouble(),
    );
  }

  ItemComposicao copyWith({
    String? produtoId,
    double? quantidade,
  }) {
    return ItemComposicao(
      produtoId: produtoId ?? this.produtoId,
      quantidade: quantidade ?? this.quantidade,
    );
  }
}
