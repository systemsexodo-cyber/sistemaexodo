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
}
