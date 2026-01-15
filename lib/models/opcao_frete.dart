/// Modelo para representar uma opção de frete/entrega
class OpcaoFrete {
  final String id;
  final String nome; // Ex: "PAC", "SEDEX", "Taxa por Bairro", "Cálculo por Distância"
  final String tipo; // 'taxa_bairro', 'correios_pac', 'correios_sedex', 'distancia', 'manual'
  final double valor;
  final int prazo; // Prazo em dias úteis
  final String? codigoServico; // Código do serviço dos Correios (ex: "04510" para PAC)
  final String? descricao;
  final bool disponivel;
  final Map<String, dynamic>? metadados; // Informações adicionais (distância, etc.)

  OpcaoFrete({
    required this.id,
    required this.nome,
    required this.tipo,
    required this.valor,
    required this.prazo,
    this.codigoServico,
    this.descricao,
    this.disponivel = true,
    this.metadados,
  });

  factory OpcaoFrete.fromMap(Map<String, dynamic> map) {
    return OpcaoFrete(
      id: map['id'] ?? '',
      nome: map['nome'] ?? '',
      tipo: map['tipo'] ?? '',
      valor: (map['valor'] ?? 0.0).toDouble(),
      prazo: map['prazo'] ?? 0,
      codigoServico: map['codigoServico'],
      descricao: map['descricao'],
      disponivel: map['disponivel'] ?? true,
      metadados: map['metadados'] != null 
          ? Map<String, dynamic>.from(map['metadados'])
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'tipo': tipo,
      'valor': valor,
      'prazo': prazo,
      'codigoServico': codigoServico,
      'descricao': descricao,
      'disponivel': disponivel,
      'metadados': metadados,
    };
  }

  OpcaoFrete copyWith({
    String? id,
    String? nome,
    String? tipo,
    double? valor,
    int? prazo,
    String? codigoServico,
    String? descricao,
    bool? disponivel,
    Map<String, dynamic>? metadados,
  }) {
    return OpcaoFrete(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      tipo: tipo ?? this.tipo,
      valor: valor ?? this.valor,
      prazo: prazo ?? this.prazo,
      codigoServico: codigoServico ?? this.codigoServico,
      descricao: descricao ?? this.descricao,
      disponivel: disponivel ?? this.disponivel,
      metadados: metadados ?? this.metadados,
    );
  }
}










