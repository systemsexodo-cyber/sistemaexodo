import 'package:sistema_exodo_novo/models/adicional_produto.dart';

class ItemPedido {
  final String id;
  final String nome;
  final double quantidade;
  final double preco;
  final String? observacao;
  final String? idVariacao; // ID da variação (se for o caso)
  final String? fornecedorNome; // Fornecedor do produto
  final List<AdicionalProduto> adicionais;

  ItemPedido({
    required this.id,
    required this.nome,
    required this.quantidade,
    required this.preco,
    this.observacao,
    this.idVariacao,
    this.fornecedorNome,
    List<AdicionalProduto>? adicionais,
  }) : adicionais = adicionais ?? [];

  factory ItemPedido.fromMap(Map<String, dynamic> map) {
    return ItemPedido(
      id: map['id'] ?? '',
      nome: map['nome'] ?? '',
      quantidade: (map['quantidade'] as num?)?.toDouble() ?? 0.0,
      preco: (map['preco'] ?? 0).toDouble(),
      observacao: map['observacao'],
      idVariacao: map['idVariacao'],
      fornecedorNome: map['fornecedorNome'],
      adicionais: (map['adicionais'] as List<dynamic>?)
          ?.map((a) => AdicionalProduto.fromMap(a as Map<String, dynamic>))
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'quantidade': quantidade,
      'preco': preco,
      'observacao': observacao,
      'idVariacao': idVariacao,
      'fornecedorNome': fornecedorNome,
      'adicionais': adicionais.map((a) => a.toMap()).toList(),
    };
  }
}
