/// Modelo para registro de trocas e devoluções
class TrocaDevolucao {
  final String id;
  final String pedidoId; // ID do pedido original
  final String numeroPedido; // Número do pedido original (VND-0001, etc)
  final String? clienteId;
  final String? clienteNome;
  final DateTime dataOperacao;
  final TipoOperacao tipo; // Troca ou Devolução
  final List<ItemTrocaDevolucao> itensDevolvidos;
  final List<ItemTrocaDevolucao>? itensNovos; // Para trocas
  final double valorDevolvido; // Valor total dos itens devolvidos
  final double valorNovosItens; // Valor dos itens novos (se troca)
  final double diferenca; // Diferença a pagar ou receber
  final String? observacao;
  final String status; // Pendente, Concluído, Cancelado
  final DateTime createdAt;

  TrocaDevolucao({
    required this.id,
    required this.pedidoId,
    required this.numeroPedido,
    this.clienteId,
    this.clienteNome,
    required this.dataOperacao,
    required this.tipo,
    required this.itensDevolvidos,
    this.itensNovos,
    required this.valorDevolvido,
    this.valorNovosItens = 0,
    required this.diferenca,
    this.observacao,
    this.status = 'Concluído',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory TrocaDevolucao.fromMap(Map<String, dynamic> map) {
    return TrocaDevolucao(
      id: map['id'] ?? '',
      pedidoId: map['pedidoId'] ?? '',
      numeroPedido: map['numeroPedido'] ?? '',
      clienteId: map['clienteId'],
      clienteNome: map['clienteNome'],
      dataOperacao: map['dataOperacao'] != null
          ? DateTime.parse(map['dataOperacao'])
          : DateTime.now(),
      tipo: TipoOperacao.values.firstWhere(
        (t) => t.name == map['tipo'],
        orElse: () => TipoOperacao.devolucao,
      ),
      itensDevolvidos: (map['itensDevolvidos'] as List<dynamic>? ?? [])
          .map((i) => ItemTrocaDevolucao.fromMap(i as Map<String, dynamic>))
          .toList(),
      itensNovos: map['itensNovos'] != null
          ? (map['itensNovos'] as List<dynamic>)
                .map(
                  (i) => ItemTrocaDevolucao.fromMap(i as Map<String, dynamic>),
                )
                .toList()
          : null,
      valorDevolvido: (map['valorDevolvido'] ?? 0).toDouble(),
      valorNovosItens: (map['valorNovosItens'] ?? 0).toDouble(),
      diferenca: (map['diferenca'] ?? 0).toDouble(),
      observacao: map['observacao'],
      status: map['status'] ?? 'Concluído',
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'pedidoId': pedidoId,
      'numeroPedido': numeroPedido,
      'clienteId': clienteId,
      'clienteNome': clienteNome,
      'dataOperacao': dataOperacao.toIso8601String(),
      'tipo': tipo.name,
      'itensDevolvidos': itensDevolvidos.map((i) => i.toMap()).toList(),
      'itensNovos': itensNovos?.map((i) => i.toMap()).toList(),
      'valorDevolvido': valorDevolvido,
      'valorNovosItens': valorNovosItens,
      'diferenca': diferenca,
      'observacao': observacao,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  TrocaDevolucao copyWith({
    String? id,
    String? pedidoId,
    String? numeroPedido,
    String? clienteId,
    String? clienteNome,
    DateTime? dataOperacao,
    TipoOperacao? tipo,
    List<ItemTrocaDevolucao>? itensDevolvidos,
    List<ItemTrocaDevolucao>? itensNovos,
    double? valorDevolvido,
    double? valorNovosItens,
    double? diferenca,
    String? observacao,
    String? status,
    DateTime? createdAt,
  }) {
    return TrocaDevolucao(
      id: id ?? this.id,
      pedidoId: pedidoId ?? this.pedidoId,
      numeroPedido: numeroPedido ?? this.numeroPedido,
      clienteId: clienteId ?? this.clienteId,
      clienteNome: clienteNome ?? this.clienteNome,
      dataOperacao: dataOperacao ?? this.dataOperacao,
      tipo: tipo ?? this.tipo,
      itensDevolvidos: itensDevolvidos ?? this.itensDevolvidos,
      itensNovos: itensNovos ?? this.itensNovos,
      valorDevolvido: valorDevolvido ?? this.valorDevolvido,
      valorNovosItens: valorNovosItens ?? this.valorNovosItens,
      diferenca: diferenca ?? this.diferenca,
      observacao: observacao ?? this.observacao,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// Tipo de operação
enum TipoOperacao {
  troca,
  devolucao;

  String get nome {
    switch (this) {
      case TipoOperacao.troca:
        return 'Troca';
      case TipoOperacao.devolucao:
        return 'Devolução';
    }
  }
}

/// Item da troca/devolução
class ItemTrocaDevolucao {
  final String produtoId;
  final String produtoNome;
  final int quantidade;
  final double precoUnitario;
  final double valorTotal;
  final String? motivo; // Motivo da devolução/troca

  final String? trocadoPor; // Preenchido apenas em trocas

  ItemTrocaDevolucao({
    required this.produtoId,
    required this.produtoNome,
    required this.quantidade,
    required this.precoUnitario,
    required this.valorTotal,
    this.motivo,
    this.trocadoPor,
  });

  factory ItemTrocaDevolucao.fromMap(Map<String, dynamic> map) {
    return ItemTrocaDevolucao(
      produtoId: map['produtoId'] ?? '',
      produtoNome: map['produtoNome'] ?? '',
      quantidade: map['quantidade'] ?? 0,
      precoUnitario: (map['precoUnitario'] ?? 0).toDouble(),
      valorTotal: (map['valorTotal'] ?? 0).toDouble(),
      motivo: map['motivo'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'produtoId': produtoId,
      'produtoNome': produtoNome,
      'quantidade': quantidade,
      'precoUnitario': precoUnitario,
      'valorTotal': valorTotal,
      'motivo': motivo,
    };
  }
}
