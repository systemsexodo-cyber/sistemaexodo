class ItemComposicao {
  final String produtoId;
  final double quantidade;
  final double? pesoTotalSaco; // Peso total do saco inteiro (ex: 15 kg) para conversão de baixa
  final double? fracaoBase;    // Fração que corresponde a 1 unidade de baixa (ex: 1 kg)
  final String? unidadeVenda;  // Unidade do produto VENDIDO na conversão (ex: ML, KG, METRO)
  final String? unidadeBaixa;  // Unidade do ingrediente BAIXADO na conversão (ex: LITRO, SACO, KG)

  ItemComposicao({
    required this.produtoId,
    required this.quantidade,
    this.pesoTotalSaco,
    this.fracaoBase,
    this.unidadeVenda,
    this.unidadeBaixa,
  });

  Map<String, dynamic> toMap() {
    return {
      'produto_id': produtoId,
      'quantidade': quantidade,
      'peso_total_saco': pesoTotalSaco,
      'fracao_base': fracaoBase,
      'unidade_venda': unidadeVenda,
      'unidade_baixa': unidadeBaixa,
    };
  }

  factory ItemComposicao.fromMap(Map<dynamic, dynamic> map) {
    double? parseDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString().replaceAll(',', '.'));
    }

    String? parseUnit(dynamic value) {
      if (value == null) return null;
      final s = value.toString().trim();
      return s.isEmpty ? null : s;
    }

    return ItemComposicao(
      produtoId: map['produto_id']?.toString() ?? map['produtoId']?.toString() ?? '',
      quantidade: (map['quantidade'] is num)
          ? (map['quantidade'] as num).toDouble()
          : (double.tryParse(map['quantidade']?.toString() ?? '') ?? 0.0),
      pesoTotalSaco: parseDouble(map['peso_total_saco'] ?? map['pesoTotalSaco']),
      fracaoBase: parseDouble(map['fracao_base'] ?? map['fracaoBase']),
      unidadeVenda: parseUnit(map['unidade_venda'] ?? map['unidadeVenda']),
      unidadeBaixa: parseUnit(map['unidade_baixa'] ?? map['unidadeBaixa']),
    );
  }

  ItemComposicao copyWith({
    String? produtoId,
    double? quantidade,
    double? pesoTotalSaco,
    double? fracaoBase,
    String? unidadeVenda,
    String? unidadeBaixa,
  }) {
    return ItemComposicao(
      produtoId: produtoId ?? this.produtoId,
      quantidade: quantidade ?? this.quantidade,
      pesoTotalSaco: pesoTotalSaco ?? this.pesoTotalSaco,
      fracaoBase: fracaoBase ?? this.fracaoBase,
      unidadeVenda: unidadeVenda ?? this.unidadeVenda,
      unidadeBaixa: unidadeBaixa ?? this.unidadeBaixa,
    );
  }
}
