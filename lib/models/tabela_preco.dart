import 'package:sistema_exodo_novo/utils/date_parser.dart';

enum TipoTabelaPreco {
  percentualAcrescimo,
  percentualDesconto,
  precoFixo,
}

extension TipoTabelaPrecoExtension on TipoTabelaPreco {
  String get nome {
    switch (this) {
      case TipoTabelaPreco.percentualAcrescimo:
        return 'Acréscimo (%)';
      case TipoTabelaPreco.percentualDesconto:
        return 'Desconto (%)';
      case TipoTabelaPreco.precoFixo:
        return 'Preço Fixo por Produto';
    }
  }
}

class TabelaPreco {
  final String id;
  final String nome;
  final TipoTabelaPreco tipo;
  final double? valor; // Usado para acréscimo ou desconto
  final bool ativo;
  final DateTime createdAt;
  final DateTime updatedAt;

  TabelaPreco({
    required this.id,
    required this.nome,
    required this.tipo,
    this.valor,
    this.ativo = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory TabelaPreco.fromMap(Map<String, dynamic> map) {
    return TabelaPreco(
      id: map['id']?.toString() ?? '',
      nome: map['nome'] ?? '',
      tipo: TipoTabelaPreco.values.firstWhere(
        (e) => e.name == map['tipo'],
        orElse: () => TipoTabelaPreco.precoFixo,
      ),
      valor: map['valor'] != null ? double.tryParse(map['valor'].toString()) : null,
      ativo: map['ativo'] ?? true,
      createdAt: map['created_at'] != null ? DateParser.parse(map['created_at']) : DateTime.now(),
      updatedAt: map['updated_at'] != null ? DateParser.parse(map['updated_at']) : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'tipo': tipo.name,
      'valor': valor,
      'ativo': ativo,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  TabelaPreco copyWith({
    String? id,
    String? nome,
    TipoTabelaPreco? tipo,
    double? valor,
    bool? ativo,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TabelaPreco(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      tipo: tipo ?? this.tipo,
      valor: valor ?? this.valor,
      ativo: ativo ?? this.ativo,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}
