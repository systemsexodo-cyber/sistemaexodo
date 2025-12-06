/// Modelo para representar um usuário do sistema
class Usuario {
  final String id;
  final String nome;
  final String email;
  final String senha; // Em produção, deve ser hash
  final String? telefone;
  final String? fotoUrl;
  final TipoUsuario tipo;
  final String? empresaId; // ID da empresa associada
  final bool ativo;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? ultimoAcesso;

  Usuario({
    required this.id,
    required this.nome,
    required this.email,
    required this.senha,
    this.telefone,
    this.fotoUrl,
    this.tipo = TipoUsuario.operador,
    this.empresaId,
    this.ativo = true,
    required this.createdAt,
    required this.updatedAt,
    this.ultimoAcesso,
  });

  /// Cria uma cópia do usuário com campos atualizados
  Usuario copyWith({
    String? id,
    String? nome,
    String? email,
    String? senha,
    String? telefone,
    String? fotoUrl,
    TipoUsuario? tipo,
    String? empresaId,
    bool? ativo,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? ultimoAcesso,
  }) {
    return Usuario(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      email: email ?? this.email,
      senha: senha ?? this.senha,
      telefone: telefone ?? this.telefone,
      fotoUrl: fotoUrl ?? this.fotoUrl,
      tipo: tipo ?? this.tipo,
      empresaId: empresaId ?? this.empresaId,
      ativo: ativo ?? this.ativo,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      ultimoAcesso: ultimoAcesso ?? this.ultimoAcesso,
    );
  }

  factory Usuario.fromMap(Map<String, dynamic> map) {
    return Usuario(
      id: map['id'] ?? '',
      nome: map['nome'] ?? '',
      email: map['email'] ?? '',
      senha: map['senha'] ?? '',
      telefone: map['telefone'],
      fotoUrl: map['fotoUrl'],
      tipo: TipoUsuario.values.firstWhere(
        (t) => t.name == map['tipo'],
        orElse: () => TipoUsuario.operador,
      ),
      empresaId: map['empresaId'],
      ativo: map['ativo'] ?? true,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'])
          : DateTime.now(),
      ultimoAcesso: map['ultimoAcesso'] != null
          ? DateTime.parse(map['ultimoAcesso'])
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'email': email,
      'senha': senha,
      'telefone': telefone,
      'fotoUrl': fotoUrl,
      'tipo': tipo.name,
      'empresaId': empresaId,
      'ativo': ativo,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'ultimoAcesso': ultimoAcesso?.toIso8601String(),
    };
  }

  /// Retorna o nome do tipo de usuário
  String get tipoNome => tipo.nome;

  /// Verifica se o usuário é administrador
  bool get isAdmin => tipo == TipoUsuario.administrador;

  /// Verifica se o usuário é gerente
  bool get isGerente => tipo == TipoUsuario.gerente;

  /// Verifica se o usuário tem permissões de administrador ou gerente
  bool get podeGerenciarUsuarios => isAdmin || isGerente;
}

/// Tipos de usuário do sistema
enum TipoUsuario {
  administrador,
  gerente,
  operador,
  vendedor,
}

extension TipoUsuarioExtension on TipoUsuario {
  String get nome {
    switch (this) {
      case TipoUsuario.administrador:
        return 'Administrador';
      case TipoUsuario.gerente:
        return 'Gerente';
      case TipoUsuario.operador:
        return 'Operador';
      case TipoUsuario.vendedor:
        return 'Vendedor';
    }
  }

  String get descricao {
    switch (this) {
      case TipoUsuario.administrador:
        return 'Acesso total ao sistema';
      case TipoUsuario.gerente:
        return 'Pode gerenciar operações e relatórios';
      case TipoUsuario.operador:
        return 'Acesso básico ao sistema';
      case TipoUsuario.vendedor:
        return 'Acesso apenas ao PDV e vendas';
    }
  }
}


