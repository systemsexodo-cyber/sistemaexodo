class EstoqueHistorico {
  final String id;
  final String produtoId;
  final DateTime data;
  final double quantidade;
  final String tipo; // 'entrada', 'saida', 'ajuste'
  final String? usuario;
  final String? observacao;
  final String? fornecedorId;
  final String? fornecedorNome;

  EstoqueHistorico({
    required this.id,
    required this.produtoId,
    required this.data,
    required this.quantidade,
    required this.tipo,
    this.usuario,
    this.observacao,
    this.fornecedorId,
    this.fornecedorNome,
  });

  factory EstoqueHistorico.fromMap(Map<String, dynamic> map) {
    return EstoqueHistorico(
      id: map['id'] ?? '',
      produtoId: map['produto_id'] ?? map['produtoId'] ?? '',
      data: map['data'] != null
          ? (map['data'] is DateTime ? map['data'] as DateTime : DateTime.parse(map['data'].toString()))
          : DateTime.now(),
      quantidade: map['quantidade'] != null ? (map['quantidade'] as num).toDouble() : 0.0,
      tipo: map['tipo'] ?? '',
      usuario: map['usuario'],
      observacao: map['observacao'],
      fornecedorId: map['fornecedor_id'] ?? map['fornecedorId'],
      fornecedorNome: map['fornecedor_nome'] ?? map['fornecedorNome'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'produto_id': produtoId,
      'data': data.toIso8601String(),
      'quantidade': quantidade,
      'tipo': tipo,
      'usuario': usuario,
      'observacao': observacao,
      'fornecedor_nome': fornecedorNome,
    };
  }
}
