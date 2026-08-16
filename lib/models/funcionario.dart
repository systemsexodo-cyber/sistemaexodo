class Funcionario {
  final String id;
  final String nome;
  final String? telefone;
  final String? email;
  final String? senha; // Senha para login no sistema
  final String? observacoes;
  final bool ativo;
  final bool temAcesso; // Se o funcionário tem acesso ao sistema
  final double porcentagemComissao;
  final String tipoComissao; // 'Porcentagem' ou 'Fixo'
  final double valorComissao;
  final DateTime createdAt;
  final DateTime updatedAt;

  Funcionario({
    required this.id,
    required this.nome,
    this.telefone,
    this.email,
    this.senha,
    this.observacoes,
    this.ativo = true,
    this.temAcesso = false, // Por padrão, funcionário não tem acesso
    this.porcentagemComissao = 0.0,
    this.tipoComissao = 'Porcentagem',
    this.valorComissao = 0.0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory Funcionario.fromMap(Map<String, dynamic> map) {
    return Funcionario(
      id: map['id']?.toString() ?? '',
      nome: map['nome'] as String,
      telefone: map['telefone'] as String?,
      email: map['email'] as String?,
      senha: map['senha'] as String?,
      observacoes: map['observacoes'] as String?,
      ativo: map['ativo'] ?? true,
      temAcesso: map['temAcesso'] ?? false,
      porcentagemComissao: double.tryParse(map['porcentagemComissao']?.toString() ?? '') ?? 0.0,
      tipoComissao: map['tipoComissao']?.toString() ?? 'Porcentagem',
      valorComissao: double.tryParse(map['valorComissao']?.toString() ?? '') ?? 0.0,
      createdAt: map['createdAt'] != null
          ? (map['createdAt'] is DateTime ? map['createdAt'] as DateTime : DateTime.parse(map['createdAt'].toString()))
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? (map['updatedAt'] is DateTime ? map['updatedAt'] as DateTime : DateTime.parse(map['updatedAt'].toString()))
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'telefone': telefone,
      'email': email,
      'senha': senha,
      'observacoes': observacoes,
      'ativo': ativo,
      'temAcesso': temAcesso,
      'porcentagemComissao': porcentagemComissao,
      'tipoComissao': tipoComissao,
      'valorComissao': valorComissao,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  Funcionario copyWith({
    String? id,
    String? nome,
    String? telefone,
    String? email,
    String? senha,
    String? observacoes,
    bool? ativo,
    bool? temAcesso,
    double? porcentagemComissao,
    String? tipoComissao,
    double? valorComissao,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Funcionario(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      telefone: telefone ?? this.telefone,
      email: email ?? this.email,
      senha: senha ?? this.senha,
      observacoes: observacoes ?? this.observacoes,
      ativo: ativo ?? this.ativo,
      temAcesso: temAcesso ?? this.temAcesso,
      porcentagemComissao: porcentagemComissao ?? this.porcentagemComissao,
      tipoComissao: tipoComissao ?? this.tipoComissao,
      valorComissao: valorComissao ?? this.valorComissao,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Funcionario && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
