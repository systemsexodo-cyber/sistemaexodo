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
  // Forma de venda escolhida no PDV (unidade/caixa/pacote/saco) e sua baixa
  final String? unidadeVenda;
  final double? quantidadeBaixa;
  // Preço base ANTES das promoções (para exibir o desconto no cupom/recibo)
  final double? precoSemPromocao;

  ItemPedido({
    required this.id,
    required this.nome,
    required this.quantidade,
    required this.preco,
    this.observacao,
    this.idVariacao,
    this.fornecedorNome,
    List<AdicionalProduto>? adicionais,
    this.unidadeVenda,
    this.quantidadeBaixa,
    this.precoSemPromocao,
  }) : adicionais = adicionais ?? [];

  /// Cópia do item com os campos alterados — usado para editar a quantidade
  /// de um item direto no detalhe do pedido.
  ItemPedido copyWith({
    String? id,
    String? nome,
    double? quantidade,
    double? preco,
    String? observacao,
    String? idVariacao,
    String? fornecedorNome,
    List<AdicionalProduto>? adicionais,
    String? unidadeVenda,
    double? quantidadeBaixa,
    double? precoSemPromocao,
  }) {
    return ItemPedido(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      quantidade: quantidade ?? this.quantidade,
      preco: preco ?? this.preco,
      observacao: observacao ?? this.observacao,
      idVariacao: idVariacao ?? this.idVariacao,
      fornecedorNome: fornecedorNome ?? this.fornecedorNome,
      adicionais: adicionais ?? this.adicionais,
      unidadeVenda: unidadeVenda ?? this.unidadeVenda,
      quantidadeBaixa: quantidadeBaixa ?? this.quantidadeBaixa,
      precoSemPromocao: precoSemPromocao ?? this.precoSemPromocao,
    );
  }

  factory ItemPedido.fromMap(Map<String, dynamic> map) {
    return ItemPedido(
      id: map['id']?.toString() ?? '',
      nome: map['nome'] ?? '',
      quantidade: (map['quantidade'] as num?)?.toDouble() ?? 0.0,
      preco: (map['preco'] ?? 0).toDouble(),
      observacao: map['observacao'],
      idVariacao: map['idVariacao'],
      fornecedorNome: map['fornecedorNome'],
      adicionais: (map['adicionais'] as List<dynamic>?)
          ?.map((a) => AdicionalProduto.fromMap(a as Map<String, dynamic>))
          .toList() ?? [],
      unidadeVenda: map['unidadeVenda'],
      quantidadeBaixa: map['quantidadeBaixa'] != null
          ? (map['quantidadeBaixa'] as num).toDouble()
          : null,
      precoSemPromocao: map['precoSemPromocao'] != null
          ? (map['precoSemPromocao'] as num).toDouble()
          : null,
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
      'unidadeVenda': unidadeVenda,
      'quantidadeBaixa': quantidadeBaixa,
      'precoSemPromocao': precoSemPromocao,
    };
  }
}
