/// Modelo para Zona de Entrega (cálculo inteligente por bairro/distância)
class ZonaEntrega {
  final String id;
  final String nome;
  final String tipo; // 'bairro', 'cidade', 'raio', 'regiao'
  final String? bairro;
  final String? cidade;
  final String? estado;
  final double? raioKm; // Raio em km para tipo 'raio'
  final double taxaFixa; // Taxa fixa de entrega
  final double? taxaPorKm; // Taxa adicional por km (opcional)
  final int prazoMinimo; // Prazo mínimo em dias
  final int prazoMaximo; // Prazo máximo em dias
  final bool ativo;
  final int prioridade; // Prioridade (menor número = maior prioridade)
  final DateTime createdAt;
  final DateTime updatedAt;

  ZonaEntrega({
    required this.id,
    required this.nome,
    required this.tipo,
    this.bairro,
    this.cidade,
    this.estado,
    this.raioKm,
    required this.taxaFixa,
    this.taxaPorKm,
    required this.prazoMinimo,
    required this.prazoMaximo,
    this.ativo = true,
    this.prioridade = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'tipo': tipo,
      'bairro': bairro,
      'cidade': cidade,
      'estado': estado,
      'raioKm': raioKm,
      'taxaFixa': taxaFixa,
      'taxaPorKm': taxaPorKm,
      'prazoMinimo': prazoMinimo,
      'prazoMaximo': prazoMaximo,
      'ativo': ativo,
      'prioridade': prioridade,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory ZonaEntrega.fromMap(Map<String, dynamic> map) {
    return ZonaEntrega(
      id: map['id'] ?? '',
      nome: map['nome'] ?? '',
      tipo: map['tipo'] ?? 'bairro',
      bairro: map['bairro'],
      cidade: map['cidade'],
      estado: map['estado'],
      raioKm: map['raioKm']?.toDouble(),
      taxaFixa: (map['taxaFixa'] ?? 0.0).toDouble(),
      taxaPorKm: map['taxaPorKm']?.toDouble(),
      prazoMinimo: map['prazoMinimo'] ?? 1,
      prazoMaximo: map['prazoMaximo'] ?? 3,
      ativo: map['ativo'] ?? true,
      prioridade: map['prioridade'] ?? 0,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'])
          : DateTime.now(),
    );
  }

  ZonaEntrega copyWith({
    String? id,
    String? nome,
    String? tipo,
    String? bairro,
    String? cidade,
    String? estado,
    double? raioKm,
    double? taxaFixa,
    double? taxaPorKm,
    int? prazoMinimo,
    int? prazoMaximo,
    bool? ativo,
    int? prioridade,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ZonaEntrega(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      tipo: tipo ?? this.tipo,
      bairro: bairro ?? this.bairro,
      cidade: cidade ?? this.cidade,
      estado: estado ?? this.estado,
      raioKm: raioKm ?? this.raioKm,
      taxaFixa: taxaFixa ?? this.taxaFixa,
      taxaPorKm: taxaPorKm ?? this.taxaPorKm,
      prazoMinimo: prazoMinimo ?? this.prazoMinimo,
      prazoMaximo: prazoMaximo ?? this.prazoMaximo,
      ativo: ativo ?? this.ativo,
      prioridade: prioridade ?? this.prioridade,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}






