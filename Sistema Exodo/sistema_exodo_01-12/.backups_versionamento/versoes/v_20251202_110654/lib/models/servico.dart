class Servico {
  final String id;
  final String nome;
  final String? descricao;
  final double preco;
  final DateTime createdAt;
  final DateTime updatedAt;

  Servico({
    required this.id,
    required this.nome,
    this.descricao,
    required this.preco,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'descricao': descricao,
      'preco': preco,
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
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }
}
