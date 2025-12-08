class Funcionario {
  final String id;
  final String nome;
  final String? telefone;
  final String? email;
  final String? observacoes;
  final bool ativo;
  final DateTime createdAt;
  final DateTime updatedAt;

  Funcionario({
    required this.id,
    required this.nome,
    this.telefone,
    this.email,
    this.observacoes,
    this.ativo = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory Funcionario.fromMap(Map<String, dynamic> map) {
    return Funcionario(
      id: map['id'] as String,
      nome: map['nome'] as String,
      telefone: map['telefone'] as String?,
      email: map['email'] as String?,
      observacoes: map['observacoes'] as String?,
      ativo: map['ativo'] ?? true,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'telefone': telefone,
      'email': email,
      'observacoes': observacoes,
      'ativo': ativo,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  Funcionario copyWith({
    String? id,
    String? nome,
    String? telefone,
    String? email,
    String? observacoes,
    bool? ativo,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Funcionario(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      telefone: telefone ?? this.telefone,
      email: email ?? this.email,
      observacoes: observacoes ?? this.observacoes,
      ativo: ativo ?? this.ativo,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
