/// Modelo para representar uma variação de produto
/// Exemplos: Tamanho P, Cor Azul, Sabor Morango, etc.
class VariacaoProduto {
  final String id;
  final String nomeAtributo; // Ex: "Tamanho", "Cor", "Sabor"
  final String valor; // Ex: "P", "Azul", "Morango"
  final double? precoAdicional; // Preço adicional para esta variação (pode ser negativo para desconto)
  final int estoque; // Estoque específico desta variação
  final String? codigoBarras; // Código de barras específico da variação
  final String? sku; // SKU específico da variação
  final bool ativo; // Se a variação está ativa/disponível

  VariacaoProduto({
    required this.id,
    required this.nomeAtributo,
    required this.valor,
    this.precoAdicional,
    this.estoque = 0,
    this.codigoBarras,
    this.sku,
    this.ativo = true,
  });

  /// Cria uma cópia da variação com campos atualizados
  VariacaoProduto copyWith({
    String? id,
    String? nomeAtributo,
    String? valor,
    double? precoAdicional,
    int? estoque,
    String? codigoBarras,
    String? sku,
    bool? ativo,
  }) {
    return VariacaoProduto(
      id: id ?? this.id,
      nomeAtributo: nomeAtributo ?? this.nomeAtributo,
      valor: valor ?? this.valor,
      precoAdicional: precoAdicional ?? this.precoAdicional,
      estoque: estoque ?? this.estoque,
      codigoBarras: codigoBarras ?? this.codigoBarras,
      sku: sku ?? this.sku,
      ativo: ativo ?? this.ativo,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nomeAtributo': nomeAtributo,
      'valor': valor,
      'precoAdicional': precoAdicional,
      'estoque': estoque,
      'codigoBarras': codigoBarras,
      'sku': sku,
      'ativo': ativo,
    };
  }

  factory VariacaoProduto.fromMap(Map<String, dynamic> map) {
    return VariacaoProduto(
      id: map['id'] as String,
      nomeAtributo: map['nomeAtributo'] as String,
      valor: map['valor'] as String,
      precoAdicional: map['precoAdicional'] != null
          ? (map['precoAdicional'] as num).toDouble()
          : null,
      estoque: map['estoque'] as int? ?? 0,
      codigoBarras: map['codigoBarras'] as String?,
      sku: map['sku'] as String?,
      ativo: map['ativo'] as bool? ?? true,
    );
  }

  /// Retorna uma string descritiva da variação
  String get descricao => '$nomeAtributo: $valor';

  /// Verifica se a variação está disponível (ativa e com estoque)
  bool get disponivel => ativo && estoque > 0;
}










