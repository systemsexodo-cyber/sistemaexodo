class ItemServico {
  final String id;
  final String descricao;
  final double valor;
  final double valorAdicional;
  final String? descricaoAdicional;

  ItemServico({
    required this.id,
    required this.descricao,
    required this.valor,
    this.valorAdicional = 0.0,
    this.descricaoAdicional,
  });

  factory ItemServico.fromMap(Map<String, dynamic> map) {
    return ItemServico(
      id: map['id'] ?? '',
      descricao: map['descricao'] ?? '',
      valor: (map['valor'] ?? 0).toDouble(),
      valorAdicional: (map['valorAdicional'] ?? 0.0).toDouble(),
      descricaoAdicional: map['descricaoAdicional'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'descricao': descricao,
      'valor': valor,
      'valorAdicional': valorAdicional,
      'descricaoAdicional': descricaoAdicional,
    };
  }
}
