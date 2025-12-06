class EstoqueHistorico {
  final String id;
  final String produtoId;
  final DateTime data;
  final int quantidade;
  final String tipo; // 'entrada', 'saida', 'ajuste'
  final String? usuario;
  final String? observacao;

  EstoqueHistorico({
    required this.id,
    required this.produtoId,
    required this.data,
    required this.quantidade,
    required this.tipo,
    this.usuario,
    this.observacao,
  });

  factory EstoqueHistorico.fromMap(Map<String, dynamic> map) {
    return EstoqueHistorico(
      id: map['id'] ?? '',
      produtoId: map['produtoId'] ?? '',
      data: map['data'] != null
          ? DateTime.parse(map['data'])
          : DateTime.now(),
      quantidade: map['quantidade'] ?? 0,
      tipo: map['tipo'] ?? '',
      usuario: map['usuario'],
      observacao: map['observacao'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'produtoId': produtoId,
      'data': data.toIso8601String(),
      'quantidade': quantidade,
      'tipo': tipo,
      'usuario': usuario,
      'observacao': observacao,
    };
  }
}
