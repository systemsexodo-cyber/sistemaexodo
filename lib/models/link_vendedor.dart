class LinkVendedor {
  final String id;
  final String funcionarioId; // ID do funcionário/vendedor
  final String funcionarioNome; // Nome do vendedor
  final String codigoLink; // Código único do link (ex: ABC123)
  final String urlCompleta; // URL completa do link
  final double percentualComissao; // Percentual de comissão (ex: 10.0 = 10%)
  final bool ativo; // Se o link está ativo
  final int totalVendas; // Total de vendas através deste link
  final double totalComissao; // Total de comissão gerada
  final DateTime createdAt;
  final DateTime updatedAt;

  LinkVendedor({
    required this.id,
    required this.funcionarioId,
    required this.funcionarioNome,
    required this.codigoLink,
    required this.urlCompleta,
    this.percentualComissao = 10.0,
    this.ativo = true,
    this.totalVendas = 0,
    this.totalComissao = 0.0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory LinkVendedor.fromMap(Map<String, dynamic> map) {
    return LinkVendedor(
      id: map['id']?.toString() ?? '',
      funcionarioId: map['funcionarioId'] as String,
      funcionarioNome: map['funcionarioNome'] as String,
      codigoLink: map['codigoLink'] as String,
      urlCompleta: map['urlCompleta'] as String,
      percentualComissao: double.tryParse(map['percentualComissao']?.toString() ?? '') ?? 10.0,
      ativo: map['ativo'] ?? true,
      totalVendas: int.tryParse(map['totalVendas']?.toString() ?? '') ?? 0,
      totalComissao: double.tryParse(map['totalComissao']?.toString() ?? '') ?? 0.0,
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
      'funcionarioId': funcionarioId,
      'funcionarioNome': funcionarioNome,
      'codigoLink': codigoLink,
      'urlCompleta': urlCompleta,
      'percentualComissao': percentualComissao,
      'ativo': ativo,
      'totalVendas': totalVendas,
      'totalComissao': totalComissao,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  LinkVendedor copyWith({
    String? id,
    String? funcionarioId,
    String? funcionarioNome,
    String? codigoLink,
    String? urlCompleta,
    double? percentualComissao,
    bool? ativo,
    int? totalVendas,
    double? totalComissao,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return LinkVendedor(
      id: id ?? this.id,
      funcionarioId: funcionarioId ?? this.funcionarioId,
      funcionarioNome: funcionarioNome ?? this.funcionarioNome,
      codigoLink: codigoLink ?? this.codigoLink,
      urlCompleta: urlCompleta ?? this.urlCompleta,
      percentualComissao: percentualComissao ?? this.percentualComissao,
      ativo: ativo ?? this.ativo,
      totalVendas: totalVendas ?? this.totalVendas,
      totalComissao: totalComissao ?? this.totalComissao,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}















