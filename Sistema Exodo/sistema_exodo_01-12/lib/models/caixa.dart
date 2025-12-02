/// Modelo para representar uma abertura de caixa
class AberturaCaixa {
  final String id;
  final String numero; // Número único do caixa (ex: CAIXA-001)
  final DateTime dataAbertura;
  final double valorInicial;
  final String? observacao;
  final String? responsavel;

  AberturaCaixa({
    required this.id,
    required this.numero,
    required this.dataAbertura,
    required this.valorInicial,
    this.observacao,
    this.responsavel,
  });

  factory AberturaCaixa.fromMap(Map<String, dynamic> map) {
    return AberturaCaixa(
      id: map['id'] ?? '',
      numero: map['numero'] ?? '',
      dataAbertura: map['dataAbertura'] != null
          ? DateTime.parse(map['dataAbertura'])
          : DateTime.now(),
      valorInicial: (map['valorInicial'] ?? 0).toDouble(),
      observacao: map['observacao'],
      responsavel: map['responsavel'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'numero': numero,
      'dataAbertura': dataAbertura.toIso8601String(),
      'valorInicial': valorInicial,
      'observacao': observacao,
      'responsavel': responsavel,
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

  SangriaCaixa({
    required this.id,
    required this.data,
    required this.valor,
    required this.motivo,
    this.observacao,
    this.responsavel,
  });

  factory SangriaCaixa.fromMap(Map<String, dynamic> map) {
    return SangriaCaixa(
      id: map['id'] ?? '',
      data: map['data'] != null
          ? DateTime.parse(map['data'])
          : DateTime.now(),
      valor: (map['valor'] ?? 0).toDouble(),
      motivo: map['motivo'] ?? '',
      observacao: map['observacao'],
      responsavel: map['responsavel'],
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
  final String? observacao;
  final String? responsavel;

  FechamentoCaixa({
    required this.id,
    required this.aberturaCaixaId,
    required this.dataFechamento,
    required this.valorEsperado,
    required this.valorReal,
    required this.diferenca,
    required this.sangrias,
    this.observacao,
    this.responsavel,
  });

  double get totalSangrias =>
      sangrias.fold(0.0, (sum, s) => sum + s.valor);

  factory FechamentoCaixa.fromMap(Map<String, dynamic> map) {
    return FechamentoCaixa(
      id: map['id'] ?? '',
      aberturaCaixaId: map['aberturaCaixaId'] ?? '',
      dataFechamento: map['dataFechamento'] != null
          ? DateTime.parse(map['dataFechamento'])
          : DateTime.now(),
      valorEsperado: (map['valorEsperado'] ?? 0).toDouble(),
      valorReal: (map['valorReal'] ?? 0).toDouble(),
      diferenca: (map['diferenca'] ?? 0).toDouble(),
      sangrias: (map['sangrias'] as List<dynamic>? ?? [])
          .map((s) => SangriaCaixa.fromMap(s as Map<String, dynamic>))
          .toList(),
      observacao: map['observacao'],
      responsavel: map['responsavel'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'aberturaCaixaId': aberturaCaixaId,
      'dataFechamento': dataFechamento.toIso8601String(),
      'valorEsperado': valorEsperado,
      'valorReal': valorReal,
      'diferenca': diferenca,
      'sangrias': sangrias.map((s) => s.toMap()).toList(),
      'observacao': observacao,
      'responsavel': responsavel,
    };
  }
}

/// Modelo para representar um caixa completo (abertura + fechamento)
class Caixa {
  final AberturaCaixa abertura;
  final FechamentoCaixa? fechamento;
  final List<SangriaCaixa> sangrias;

  Caixa({
    required this.abertura,
    this.fechamento,
    List<SangriaCaixa>? sangrias,
  }) : sangrias = sangrias ?? [];

  bool get isAberto => fechamento == null;

  double get totalSangrias =>
      sangrias.fold(0.0, (sum, s) => sum + s.valor);
}




