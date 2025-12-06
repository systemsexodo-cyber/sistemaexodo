class ItemPedido {
  final String id;
  final String nome;
  final int quantidade;
  final double preco;

  ItemPedido({
    required this.id,
    required this.nome,
    required this.quantidade,
    required this.preco,
  });

  factory ItemPedido.fromMap(Map<String, dynamic> map) {
    return ItemPedido(
      id: map['id'] ?? '',
      nome: map['nome'] ?? '',
      quantidade: map['quantidade'] ?? 0,
      preco: (map['preco'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {'id': id, 'nome': nome, 'quantidade': quantidade, 'preco': preco};
  }
}
