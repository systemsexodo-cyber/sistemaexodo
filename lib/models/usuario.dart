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
  final String? funcionarioId; // ID do funcionário associado (para vendedores)
  final bool ativo;
  final bool isMaster; // Usuário master da empresa (pode gerenciar permissões)
  final Set<String>? permissoesPersonalizadas; // Permissões adicionais concedidas
  final Set<String>? permissoesNegadas; // Permissões removidas do padrão
  final List<String>? telasOcultas; // Telas que o usuário não pode ver/acessar
  final int serieNfce; // Série da NFC-e (cada usuário pode ter a sua)
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
    this.funcionarioId,
    this.ativo = true,
    this.isMaster = false,
    this.permissoesPersonalizadas,
    this.permissoesNegadas,
    this.telasOcultas,
    this.serieNfce = 1,
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
    String? funcionarioId,
    bool? ativo,
    bool? isMaster,
    Set<String>? permissoesPersonalizadas,
    Set<String>? permissoesNegadas,
    List<String>? telasOcultas,
    int? serieNfce,
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
      funcionarioId: funcionarioId ?? this.funcionarioId,
      ativo: ativo ?? this.ativo,
      isMaster: isMaster ?? this.isMaster,
      permissoesPersonalizadas: permissoesPersonalizadas ?? this.permissoesPersonalizadas,
      permissoesNegadas: permissoesNegadas ?? this.permissoesNegadas,
      telasOcultas: telasOcultas ?? this.telasOcultas,
      serieNfce: serieNfce ?? this.serieNfce,
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
      funcionarioId: map['funcionarioId'],
      ativo: map['ativo'] ?? true,
      isMaster: map['isMaster'] ?? false,
      permissoesPersonalizadas: map['permissoesPersonalizadas'] != null
          ? Set<String>.from(map['permissoesPersonalizadas'])
          : null,
      permissoesNegadas: map['permissoesNegadas'] != null
          ? Set<String>.from(map['permissoesNegadas'])
          : null,
      telasOcultas: map['telasOcultas'] != null
          ? List<String>.from(map['telasOcultas'])
          : null,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'])
          : DateTime.now(),
      serieNfce: map['serieNfce'] ?? 1,
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
      'funcionarioId': funcionarioId,
      'ativo': ativo,
      'isMaster': isMaster,
      'permissoesPersonalizadas': permissoesPersonalizadas?.toList(),
      'permissoesNegadas': permissoesNegadas?.toList(),
      'serieNfce': serieNfce,
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
  
  /// Verifica se o usuário é master (pode gerenciar permissões)
  bool get podeGerenciarPermissoes => isMaster;
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


