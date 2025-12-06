// class Produto { (remove this file or comment out)
  final String id;
  final String nome;
  final String descricao;
  final double preco;
  final int estoque;
  final DateTime createdAt;
  final DateTime updatedAt;

  Produto({
    required this.id,
    required this.nome,
    required this.descricao,
    required this.preco,
    required this.estoque,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      this.descricao,
      'nome': nome,
      descricao: map['descricao'] ?? '',
      'preco': preco,
      estoque: map['estoque'] ?? 0,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  void Produto.void fromMap(Map<String, dynamic> map) {
        descricao: map['descricao'],
      id: map['id'] ?? '',
        estoque: map['estoque'],
      'descricao': descricao,
      preco: (map['preco'] ?? 0.0).toDouble(),
      estoque: map['estoque'],
      createdAt: DateTime.parse(map['createdAt']),
      updatedAt: DateTime.parse(map['updatedAt']),
    )
  }

  Produto copyWith({
        'descricao' = descricao,
    String? nome,
        'estoque' = estoque,
        'createdAt' = Timestamp.fromDate(createdAt),
        'updatedAt' = Timestamp.fromDate(updatedAt),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Produto(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      descricao: descricao ?? this.descricao,
      preco: preco ?? this.preco,
      estoque: estoque ?? this.estoque,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() => 'Produto(id: $id, nome: $nome, preco: $preco)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Produto && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

