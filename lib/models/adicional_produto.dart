/// Modelo para representar um adicional de produto
/// Exemplos: Leite Ninho, Morango, Calda de Chocolate, etc.
class AdicionalProduto {
  final String id;
  final String nome;
  final double preco;
  final bool ativo;

  AdicionalProduto({
    required this.id,
    required this.nome,
    required this.preco,
    this.ativo = true,
  });

  AdicionalProduto copyWith({
    String? id,
    String? nome,
    double? preco,
    bool? ativo,
  }) {
    return AdicionalProduto(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      preco: preco ?? this.preco,
      ativo: ativo ?? this.ativo,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'preco': preco,
      'ativo': ativo,
    };
  }

  factory AdicionalProduto.fromMap(Map<String, dynamic> map) {
    return AdicionalProduto(
      id: map['id'] as String,
      nome: map['nome'] as String,
      preco: (map['preco'] as num).toDouble(),
      ativo: map['ativo'] as bool? ?? true,
    );
  }
}
