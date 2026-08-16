/// Representa uma forma de venda de um produto.
///
/// Um mesmo produto pode ser vendido de várias formas (unidade, caixa,
/// pacote, saco) sem precisar cadastrar itens duplicados. Cada forma possui
/// seu próprio preço e sua própria quantidade de baixa no estoque.
///
/// Ex.: um saco de ração de 15 kg pode ser vendido:
///   - Por unidade: 1 saco, preço R$ 120, baixa 1 unidade
///   - Por pacote (menor): 1 pacote de 3 kg, preço R$ 30, baixa 1 unidade
///   - A granel (kg): preço por quilo, baixa 1 unidade
class FormaVenda {
  /// Tipo da forma: 'unidade', 'caixa', 'pacote' ou 'saco'.
  final String tipo;
  /// Quantidade de unidades baixadas do estoque a cada 1 item vendido nesta forma.
  final double quantidadeBaixa;
  /// Preço de venda desta forma.
  final double preco;

  const FormaVenda({
    required this.tipo,
    this.quantidadeBaixa = 1.0,
    required this.preco,
  });

  /// Rótulo amigável da forma (para exibição no PDV e formulário).
  String get label {
    switch (tipo) {
      case 'caixa':
        return 'CAIXA';
      case 'pacote':
        return 'PACOTE';
      case 'saco':
        return 'SACO';
      case 'unidade':
        return 'UNIDADE';
      default:
        return tipo.isEmpty ? 'UNIDADE' : tipo.toUpperCase();
    }
  }

  /// True se a forma é por embalagem (caixa, pacote ou saco).
  bool get vendePorEmbalagem =>
      tipo == 'caixa' || tipo == 'pacote' || tipo == 'saco';

  FormaVenda copyWith({
    String? tipo,
    double? quantidadeBaixa,
    double? preco,
  }) {
    return FormaVenda(
      tipo: tipo ?? this.tipo,
      quantidadeBaixa: quantidadeBaixa ?? this.quantidadeBaixa,
      preco: preco ?? this.preco,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'tipo': tipo,
      'quantidade_baixa': quantidadeBaixa,
      'preco': preco,
    };
  }

  factory FormaVenda.fromMap(Map<String, dynamic> map) {
    double? parseDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value);
      return null;
    }

    return FormaVenda(
      tipo: (map['tipo'] ?? map['tipo'] ?? 'unidade').toString(),
      quantidadeBaixa: parseDouble(map['quantidade_baixa'] ?? map['quantidadeBaixa']) ?? 1.0,
      preco: parseDouble(map['preco']) ?? 0.0,
    );
  }
}
