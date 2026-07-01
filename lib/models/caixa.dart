import 'package:sistema_exodo_novo/utils/date_parser.dart';

/// Modelo para representar uma abertura de caixa
class AberturaCaixa {
  final String id;
  final String numero; // Número único do caixa (ex: CAIXA-001)
  final DateTime dataAbertura;
  final double valorInicial;
  final String? observacao;
  final String? responsavel;
  final DateTime createdAt;
  final DateTime updatedAt;

  AberturaCaixa({
    required this.id,
    required this.numero,
    required this.dataAbertura,
    required this.valorInicial,
    this.observacao,
    this.responsavel,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory AberturaCaixa.fromMap(Map<String, dynamic> map) {
    double? parseDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value);
      return null;
    }
    
    return AberturaCaixa(
      id: map['id'] ?? '',
      numero: map['numero'] ?? '',
      dataAbertura: DateParser.parse(map['data_abertura'] ?? map['dataAbertura']),
      valorInicial: parseDouble(map['valor_inicial'] ?? map['valorInicial']) ?? 0.0,
      observacao: map['observacao'],
      responsavel: map['responsavel'],
      createdAt: DateParser.parse(map['created_at'] ?? map['createdAt']),
      updatedAt: DateParser.parse(map['updated_at'] ?? map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'numero': numero,
      'data_abertura': dataAbertura.toIso8601String(),
      'valor_inicial': valorInicial,
      'observacao': observacao,
      'responsavel': responsavel,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

/// Modelo para representar uma sangria do caixa
class SangriaCaixa {
  final String id;
  final DateTime data;
  final double valor;
  final String motivo;
  final String? observacao;
  final String? responsavel;
  final DateTime createdAt;
  final DateTime updatedAt;

  SangriaCaixa({
    required this.id,
    required this.data,
    required this.valor,
    required this.motivo,
    this.observacao,
    this.responsavel,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory SangriaCaixa.fromMap(Map<String, dynamic> map) {
    double? parseDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value);
      return null;
    }

    return SangriaCaixa(
      id: map['id'] ?? '',
      data: DateParser.parse(map['data']),
      valor: parseDouble(map['valor']) ?? 0.0,
      motivo: map['motivo'] ?? '',
      observacao: map['observacao'],
      responsavel: map['responsavel'],
      createdAt: DateParser.parse(map['created_at'] ?? map['createdAt']),
      updatedAt: DateParser.parse(map['updated_at'] ?? map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'data': data.toIso8601String(),
      'valor': valor,
      'motivo': motivo,
      'observacao': observacao,
      'responsavel': responsavel,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

/// Modelo para representar um suprimento do caixa
class SuprimentoCaixa {
  final String id;
  final DateTime data;
  final double valor;
  final String motivo;
  final String? observacao;
  final String? responsavel;
  final DateTime createdAt;
  final DateTime updatedAt;

  SuprimentoCaixa({
    required this.id,
    required this.data,
    required this.valor,
    required this.motivo,
    this.observacao,
    this.responsavel,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory SuprimentoCaixa.fromMap(Map<String, dynamic> map) {
    double? parseDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value);
      return null;
    }

    return SuprimentoCaixa(
      id: map['id'] ?? '',
      data: DateParser.parse(map['data']),
      valor: parseDouble(map['valor']) ?? 0.0,
      motivo: map['motivo'] ?? '',
      observacao: map['observacao'],
      responsavel: map['responsavel'],
      createdAt: DateParser.parse(map['created_at'] ?? map['createdAt']),
      updatedAt: DateParser.parse(map['updated_at'] ?? map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'data': data.toIso8601String(),
      'valor': valor,
      'motivo': motivo,
      'observacao': observacao,
      'responsavel': responsavel,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

/// Modelo para representar um fechamento de caixa
class FechamentoCaixa {
  final String id;
  final String aberturaCaixaId;
  final DateTime dataFechamento;
  final double valorEsperado; // Valor que deveria ter no caixa
  final double valorReal; // Valor que realmente tem no caixa
  final double diferenca; // diferença = valorReal - valorEsperado
  final List<SangriaCaixa> sangrias;
  final List<SuprimentoCaixa> suprimentos;
  final String? observacao;
  final String? responsavel;
  final DateTime createdAt;
  final DateTime updatedAt;

  FechamentoCaixa({
    required this.id,
    required this.aberturaCaixaId,
    required this.dataFechamento,
    required this.valorEsperado,
    required this.valorReal,
    required this.diferenca,
    required this.sangrias,
    List<SuprimentoCaixa>? suprimentos,
    this.observacao,
    this.responsavel,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : suprimentos = suprimentos ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  double get totalSangrias =>
      sangrias.fold(0.0, (sum, s) => sum + s.valor);

  double get totalSuprimentos =>
      suprimentos.fold(0.0, (sum, s) => sum + s.valor);

  factory FechamentoCaixa.fromMap(Map<String, dynamic> map) {
    double? parseDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value);
      return null;
    }

    return FechamentoCaixa(
      id: map['id'] ?? '',
      aberturaCaixaId: map['abertura_caixa_id'] ?? map['aberturaCaixaId'] ?? '',
      dataFechamento: DateParser.parse(map['data_fechamento'] ?? map['dataFechamento']),
      valorEsperado: parseDouble(map['valor_esperado'] ?? map['valorEsperado']) ?? 0.0,
      valorReal: parseDouble(map['valor_real'] ?? map['valorReal']) ?? 0.0,
      diferenca: parseDouble(map['diferenca']) ?? 0.0,
      sangrias: (map['sangrias'] as List<dynamic>? ?? [])
          .map((s) => SangriaCaixa.fromMap(s as Map<String, dynamic>))
          .toList(),
      suprimentos: (map['suprimentos'] as List<dynamic>? ?? [])
          .map((s) => SuprimentoCaixa.fromMap(s as Map<String, dynamic>))
          .toList(),
      observacao: map['observacao'],
      responsavel: map['responsavel'],
      createdAt: DateParser.parse(map['created_at'] ?? map['createdAt']),
      updatedAt: DateParser.parse(map['updated_at'] ?? map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'abertura_caixa_id': aberturaCaixaId,
      'data_fechamento': dataFechamento.toIso8601String(),
      'valor_esperado': valorEsperado,
      'valor_real': valorReal,
      'diferenca': diferenca,
      'sangrias': sangrias.map((s) => s.toMap()).toList(),
      'suprimentos': suprimentos.map((s) => s.toMap()).toList(),
      'observacao': observacao,
      'responsavel': responsavel,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

/// Modelo para representar um caixa completo (abertura + fechamento)
class Caixa {
  final AberturaCaixa abertura;
  final FechamentoCaixa? fechamento;
  final List<SangriaCaixa> sangrias;
  final List<SuprimentoCaixa> suprimentos;

  Caixa({
    required this.abertura,
    this.fechamento,
    List<SangriaCaixa>? sangrias,
    List<SuprimentoCaixa>? suprimentos,
  }) : sangrias = sangrias ?? [],
       suprimentos = suprimentos ?? [];

  bool get isAberto => fechamento == null;

  double get totalSangrias =>
      sangrias.fold(0.0, (sum, s) => sum + s.valor);

  double get totalSuprimentos =>
      suprimentos.fold(0.0, (sum, s) => sum + s.valor);
}




