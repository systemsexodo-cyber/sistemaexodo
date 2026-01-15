/// Modelo para representar uma taxa de entrega por bairro
class TaxaEntrega {
  final String id;
  final String bairro;
  final double valor;
  final String? cidade;
  final bool ativo;
  final DateTime createdAt;
  final DateTime updatedAt;

  TaxaEntrega({
    required this.id,
    required this.bairro,
    required this.valor,
    this.cidade,
    this.ativo = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory TaxaEntrega.fromMap(Map<String, dynamic> map) {
    return TaxaEntrega(
      id: map['id'] ?? '',
      bairro: map['bairro'] ?? '',
      valor: (map['valor'] ?? 0.0).toDouble(),
      cidade: map['cidade'],
      ativo: map['ativo'] ?? true,
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
      'bairro': bairro,
      'valor': valor,
      'cidade': cidade,
      'ativo': ativo,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  TaxaEntrega copyWith({
    String? id,
    String? bairro,
    double? valor,
    String? cidade,
    bool? ativo,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TaxaEntrega(
      id: id ?? this.id,
      bairro: bairro ?? this.bairro,
      valor: valor ?? this.valor,
      cidade: cidade ?? this.cidade,
      ativo: ativo ?? this.ativo,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

