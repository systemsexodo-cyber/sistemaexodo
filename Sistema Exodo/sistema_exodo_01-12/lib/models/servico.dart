class Servico {
  final String id;
  final String nome;
  final String? descricao;
  final double preco;
  final double valorAdicional;
  final String? descricaoAdicional;
  final DateTime createdAt;
  final DateTime updatedAt;

  Servico({
    required this.id,
    required this.nome,
    this.descricao,
    required this.preco,
    this.valorAdicional = 0.0,
    this.descricaoAdicional,
    required this.createdAt,
    required this.updatedAt,
  });

  // Getter para o preço total (base + adicional)
  double get precoTotal => preco + valorAdicional;

  // Verifica se tem valor adicional
  bool get temAdicional => valorAdicional > 0;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'descricao': descricao,
      'preco': preco,
      'valorAdicional': valorAdicional,
      'descricaoAdicional': descricaoAdicional,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Servico.fromMap(Map<String, dynamic> map) {
    return Servico(
      id: map['id'] as String,
      nome: map['nome'] as String,
      descricao: map['descricao'] as String?,
      preco: (map['preco'] as num).toDouble(),
      valorAdicional: (map['valorAdicional'] as num?)?.toDouble() ?? 0.0,
      descricaoAdicional: map['descricaoAdicional'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }

  Servico copyWith({
    String? id,
    String? nome,
    String? descricao,
    double? preco,
    double? valorAdicional,
    String? descricaoAdicional,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Servico(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      descricao: descricao ?? this.descricao,
      preco: preco ?? this.preco,
      valorAdicional: valorAdicional ?? this.valorAdicional,
      descricaoAdicional: descricaoAdicional ?? this.descricaoAdicional,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
