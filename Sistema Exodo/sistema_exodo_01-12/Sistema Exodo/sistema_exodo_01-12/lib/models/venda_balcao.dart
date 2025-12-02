import 'package:sistema_exodo_novo/models/forma_pagamento.dart';

/// Item de uma venda de balcão
class ItemVendaBalcao {
  final String id;
  final String nome;
  final double precoUnitario;
  final int quantidade;
  final bool isServico;
  final int quantidadeDevolvida; // Quantidade que foi devolvida
  final int quantidadeTrocada; // Quantidade que foi trocada por outro produto
  final String? trocadoPor; // Nome do produto pelo qual foi trocado

  ItemVendaBalcao({
    required this.id,
    required this.nome,
    required this.precoUnitario,
    required this.quantidade,
    this.isServico = false,
    this.quantidadeDevolvida = 0,
    this.quantidadeTrocada = 0,
    this.trocadoPor,
  });

  /// Quantidade efetiva (descontando devoluções e trocas)
  int get quantidadeEfetiva =>
      quantidade - quantidadeDevolvida - quantidadeTrocada;

  /// Verifica se o item foi parcialmente devolvido/trocado
  bool get foiParcialmenteDevolvido =>
      quantidadeDevolvida > 0 || quantidadeTrocada > 0;

  /// Verifica se o item foi totalmente devolvido/trocado
  bool get foiTotalmenteDevolvido => quantidadeEfetiva <= 0;

  double get subtotal => precoUnitario * quantidade;

  /// Subtotal efetivo (descontando devoluções)
  double get subtotalEfetivo => precoUnitario * quantidadeEfetiva;

  factory ItemVendaBalcao.fromMap(Map<String, dynamic> map) {
    return ItemVendaBalcao(
      id: map['id'] ?? '',
      nome: map['nome'] ?? '',
      precoUnitario: (map['precoUnitario'] ?? 0).toDouble(),
      quantidade: map['quantidade'] ?? 1,
      isServico: map['isServico'] ?? false,
      quantidadeDevolvida: map['quantidadeDevolvida'] ?? 0,
      quantidadeTrocada: map['quantidadeTrocada'] ?? 0,
      trocadoPor: map['trocadoPor'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'precoUnitario': precoUnitario,
      'quantidade': quantidade,
      'isServico': isServico,
      'quantidadeDevolvida': quantidadeDevolvida,
      'quantidadeTrocada': quantidadeTrocada,
      'trocadoPor': trocadoPor,
    };
  }

  /// Cria uma cópia do item com campos atualizados
  ItemVendaBalcao copyWith({
    String? id,
    String? nome,
    double? precoUnitario,
    int? quantidade,
    bool? isServico,
    int? quantidadeDevolvida,
    int? quantidadeTrocada,
    String? trocadoPor,
  }) {
    return ItemVendaBalcao(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      precoUnitario: precoUnitario ?? this.precoUnitario,
      quantidade: quantidade ?? this.quantidade,
      isServico: isServico ?? this.isServico,
      quantidadeDevolvida: quantidadeDevolvida ?? this.quantidadeDevolvida,
      quantidadeTrocada: quantidadeTrocada ?? this.quantidadeTrocada,
      trocadoPor: trocadoPor ?? this.trocadoPor,
    );
  }
}

/// Venda realizada no balcão (PDV)
class VendaBalcao {
  final String id;
  final String numero; // Número sequencial da venda (VND-0001, VND-0002, etc.)
  final DateTime dataVenda;
  final String? clienteId;
  final String? clienteNome;
  final String? clienteTelefone;
  final List<ItemVendaBalcao> itens;
  final TipoPagamento tipoPagamento;
  final double valorTotal;
  final double? valorRecebido;
  final double? troco;
  final String? operador; // Nome do operador/vendedor
  final String? observacoes;
  final DateTime createdAt;

  VendaBalcao({
    required this.id,
    required this.numero,
    required this.dataVenda,
    this.clienteId,
    this.clienteNome,
    this.clienteTelefone,
    required this.itens,
    required this.tipoPagamento,
    required this.valorTotal,
    this.valorRecebido,
    this.troco,
    this.operador,
    this.observacoes,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  // Quantidade total de itens
  int get quantidadeItens =>
      itens.fold(0, (sum, item) => sum + item.quantidade);

  factory VendaBalcao.fromMap(Map<String, dynamic> map) {
    return VendaBalcao(
      id: map['id'] ?? '',
      numero: map['numero'] ?? '',
      dataVenda: map['dataVenda'] != null
          ? DateTime.parse(map['dataVenda'])
          : DateTime.now(),
      clienteId: map['clienteId'],
      clienteNome: map['clienteNome'],
      clienteTelefone: map['clienteTelefone'],
      itens: (map['itens'] as List<dynamic>? ?? [])
          .map((i) => ItemVendaBalcao.fromMap(i as Map<String, dynamic>))
          .toList(),
      tipoPagamento: TipoPagamento.values.firstWhere(
        (t) => t.name == map['tipoPagamento'],
        orElse: () => TipoPagamento.dinheiro,
      ),
      valorTotal: (map['valorTotal'] ?? 0).toDouble(),
      valorRecebido: map['valorRecebido']?.toDouble(),
      troco: map['troco']?.toDouble(),
      operador: map['operador'],
      observacoes: map['observacoes'],
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'numero': numero,
      'dataVenda': dataVenda.toIso8601String(),
      'clienteId': clienteId,
      'clienteNome': clienteNome,
      'clienteTelefone': clienteTelefone,
      'itens': itens.map((i) => i.toMap()).toList(),
      'tipoPagamento': tipoPagamento.name,
      'valorTotal': valorTotal,
      'valorRecebido': valorRecebido,
      'troco': troco,
      'operador': operador,
      'observacoes': observacoes,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// Cria uma cópia da venda com campos atualizados
  VendaBalcao copyWith({
    String? id,
    String? numero,
    DateTime? dataVenda,
    String? clienteId,
    String? clienteNome,
    String? clienteTelefone,
    List<ItemVendaBalcao>? itens,
    TipoPagamento? tipoPagamento,
    double? valorTotal,
    double? valorRecebido,
    double? troco,
    String? operador,
    String? observacoes,
    DateTime? createdAt,
  }) {
    return VendaBalcao(
      id: id ?? this.id,
      numero: numero ?? this.numero,
      dataVenda: dataVenda ?? this.dataVenda,
      clienteId: clienteId ?? this.clienteId,
      clienteNome: clienteNome ?? this.clienteNome,
      clienteTelefone: clienteTelefone ?? this.clienteTelefone,
      itens: itens ?? this.itens,
      tipoPagamento: tipoPagamento ?? this.tipoPagamento,
      valorTotal: valorTotal ?? this.valorTotal,
      valorRecebido: valorRecebido ?? this.valorRecebido,
      troco: troco ?? this.troco,
      operador: operador ?? this.operador,
      observacoes: observacoes ?? this.observacoes,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
