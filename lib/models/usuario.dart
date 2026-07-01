import 'dart:convert';
import 'package:sistema_exodo_novo/utils/date_parser.dart';

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
    // Helpers para suportar camelCase (localStorage) e snake_case (Supabase)
    T? get<T>(String camel, String snake) {
      if (map.containsKey(camel)) return map[camel] as T?;
      if (map.containsKey(snake)) return map[snake] as T?;
      return null;
    }

    String? getStr(String camel, String snake) => get<String>(camel, snake);
    bool? getBool(String camel, String snake) => get<bool>(camel, snake);
    List? getList(String camel, String snake) => get<List>(camel, snake);
    Set? getSet(String camel, String snake) => get<Set>(camel, snake);

    String? empId = getStr('empresaId', 'empresa_id');
    if (empId == null || empId.isEmpty) {
      final dados = map['dados_usuario'] ?? map['dadosUsuario'];
      if (dados != null) {
        if (dados is Map) {
          empId = dados['empresa_id']?.toString() ?? dados['empresaId']?.toString();
        } else if (dados is String && dados.isNotEmpty) {
          try {
            final decoded = jsonDecode(dados);
            if (decoded is Map) {
              empId = decoded['empresa_id']?.toString() ?? decoded['empresaId']?.toString();
            }
          } catch (_) {}
        }
      }
    }

    return Usuario(
      id: map['id']?.toString() ?? '',
      nome: map['nome']?.toString() ?? '',
      email: map['email']?.toString() ?? '',
      senha: map['senha']?.toString() ?? '',
      telefone: map['telefone']?.toString(),
      fotoUrl: getStr('fotoUrl', 'foto_url'),
      tipo: TipoUsuario.values.firstWhere(
        (t) => t.name == map['tipo'],
        orElse: () => TipoUsuario.operador,
      ),
      empresaId: empId,
      funcionarioId: getStr('funcionarioId', 'funcionario_id'),
      ativo: getBool('ativo', 'ativo') ?? true,
      isMaster: getBool('isMaster', 'is_master') ?? false,
      permissoesPersonalizadas: get('permissoesPersonalizadas', 'permissoes_personalizadas') != null
          ? Set<String>.from(get('permissoesPersonalizadas', 'permissoes_personalizadas'))
          : null,
      permissoesNegadas: get('permissoesNegadas', 'permissoes_negadas') != null
          ? Set<String>.from(get('permissoesNegadas', 'permissoes_negadas'))
          : null,
      telasOcultas: getList('telasOcultas', 'telas_ocultas') != null
          ? List<String>.from(getList('telasOcultas', 'telas_ocultas')!)
          : null,
      createdAt: DateParser.parse(map['created_at'] ?? map['createdAt']),
      updatedAt: DateParser.parse(map['updated_at'] ?? map['updatedAt']),
      serieNfce: get<num>('serieNfce', 'serie_nfce')?.toInt() ?? 1,
      ultimoAcesso: (map['ultimo_acesso'] ?? map['ultimoAcesso']) != null
          ? DateParser.parse(map['ultimo_acesso'] ?? map['ultimoAcesso'])
          : null,
    );
  }

  static DateTime? getDate(String? val) {
    if (val == null) return null;
    return DateTime.parse(val);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'email': email,
      'senha': senha,
      'telefone': telefone,
      'foto_url': fotoUrl,
      'tipo': tipo.name,
      'empresa_id': empresaId,
      'funcionario_id': funcionarioId,
      'ativo': ativo,
      'is_master': isMaster,
      'permissoes_personalizadas': permissoesPersonalizadas?.toList(),
      'permissoes_negadas': permissoesNegadas?.toList(),
      'telas_ocultas': telasOcultas,
      'serie_nfce': serieNfce,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'ultimo_acesso': ultimoAcesso?.toIso8601String(),
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


