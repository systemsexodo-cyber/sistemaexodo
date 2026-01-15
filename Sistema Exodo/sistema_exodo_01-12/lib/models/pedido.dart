import 'package:sistema_exodo_novo/models/item_pedido.dart';
import 'package:sistema_exodo_novo/models/item_servico.dart';
import 'package:sistema_exodo_novo/models/forma_pagamento.dart';

class Pedido {
  final String id;
  final String numero; // Número sequencial do pedido (PED-0001, PED-0002, etc.)
  final String? clienteId;
  final String? clienteNome;
  final String? clienteTelefone;
  final String? clienteEndereco;
  final DateTime dataPedido;
  final String status; // Pendente, Em Andamento, Concluído, Cancelado
  final double total;
  final String? observacoes;
  final List<ItemPedido> produtos;
  final List<ItemServico> servicos;
  final List<PagamentoPedido> pagamentos; // Formas de pagamento do pedido
  final DateTime createdAt;
  final DateTime updatedAt;

  Pedido({
    required this.id,
    required this.numero,
    this.clienteId,
    this.clienteNome,
    this.clienteTelefone,
    this.clienteEndereco,
    DateTime? dataPedido,
    this.status = 'Pendente',
    this.total = 0.0,
    this.observacoes,
    required this.produtos,
    required this.servicos,
    List<PagamentoPedido>? pagamentos,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : dataPedido = dataPedido ?? DateTime.now(),
       pagamentos = pagamentos ?? [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  // Calcula o total dos produtos
  double get totalProdutos =>
      produtos.fold(0.0, (sum, item) => sum + (item.preco * item.quantidade));

  // Calcula o total dos serviços
  double get totalServicos =>
      servicos.fold(0.0, (sum, item) => sum + item.valor + item.valorAdicional);

  // Calcula o total geral
  double get totalGeral => totalProdutos + totalServicos;

  // Quantidade total de itens
  int get quantidadeItens =>
      produtos.fold(0, (sum, item) => sum + item.quantidade) + servicos.length;

  // Total de pagamentos já lançados
  double get totalPagamentos =>
      pagamentos.fold(0.0, (sum, pag) => sum + pag.valor);

  // Total recebido (confirmado no PDV)
  double get totalRecebido => pagamentos
      .where((p) => p.recebido)
      .fold(0.0, (sum, pag) => sum + pag.valor);

  // Valor pendente (ainda não recebido)
  double get valorPendente => totalPagamentos - totalRecebido;

  // Valor restante a lançar
  double get valorRestante => totalGeral - totalPagamentos;

  // Verifica se o pedido está totalmente pago (pagamentos lançados)
  bool get pagamentoCompleto => valorRestante <= 0;

  // Verifica se todos os pagamentos foram recebidos
  bool get totalmenteRecebido => totalRecebido >= totalGeral;

  // Quantidade de parcelas pendentes
  int get parcelasPendentes => pagamentos.where((p) => !p.recebido).length;

  // Quantidade de parcelas pagas
  int get parcelasPagas => pagamentos.where((p) => p.recebido).length;

  // Total de parcelas
  int get totalParcelas => pagamentos.length;

  // Verifica se tem parcelamento
  bool get temParcelamento => pagamentos.any((p) => p.isParcela);

  // Próxima parcela a vencer (não paga)
  PagamentoPedido? get proximaParcela {
    final pendentes = pagamentos
        .where((p) => !p.recebido && p.dataVencimento != null)
        .toList();
    if (pendentes.isEmpty) return null;
    pendentes.sort((a, b) => a.dataVencimento!.compareTo(b.dataVencimento!));
    return pendentes.first;
  }

  // Parcelas vencidas
  List<PagamentoPedido> get parcelasVencidas =>
      pagamentos.where((p) => p.isVencida).toList();

  // Tem parcelas vencidas?
  bool get temParcelasVencidas => parcelasVencidas.isNotEmpty;

  // Status do parcelamento
  String get statusParcelamento {
    if (pagamentos.isEmpty) return 'Sem pagamento';
    if (totalmenteRecebido) return 'Quitado';
    if (temParcelasVencidas) return 'Em atraso';
    if (parcelasPagas > 0) return 'Parcialmente pago';
    return 'Aguardando';
  }

  factory Pedido.fromMap(Map<String, dynamic> map) {
    return Pedido(
      id: map['id'] ?? '',
      numero: map['numero'] ?? '',
      clienteId: map['clienteId'],
      clienteNome: map['clienteNome'],
      clienteTelefone: map['clienteTelefone'],
      clienteEndereco: map['clienteEndereco'],
      dataPedido: map['dataPedido'] != null
          ? DateTime.parse(map['dataPedido'])
          : DateTime.now(),
      status: map['status'] ?? 'Pendente',
      total: (map['total'] ?? 0).toDouble(),
      observacoes: map['observacoes'],
      produtos: (map['produtos'] as List<dynamic>? ?? [])
          .map((p) => ItemPedido.fromMap(p as Map<String, dynamic>))
          .toList(),
      servicos: (map['servicos'] as List<dynamic>? ?? [])
          .map((s) => ItemServico.fromMap(s as Map<String, dynamic>))
          .toList(),
      pagamentos: (map['pagamentos'] as List<dynamic>? ?? [])
          .map((p) => PagamentoPedido.fromMap(p as Map<String, dynamic>))
          .toList(),
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'numero': numero,
      'clienteId': clienteId,
      'clienteNome': clienteNome,
      'clienteTelefone': clienteTelefone,
      'clienteEndereco': clienteEndereco,
      'dataPedido': dataPedido.toIso8601String(),
      'status': status,
      'total': total,
      'observacoes': observacoes,
      'produtos': produtos.map((p) => p.toMap()).toList(),
      'servicos': servicos.map((s) => s.toMap()).toList(),
      'pagamentos': pagamentos.map((p) => p.toMap()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  // Cria uma cópia do pedido com novos valores
  Pedido copyWith({
    String? id,
    String? numero,
    String? clienteId,
    String? clienteNome,
    String? clienteTelefone,
    String? clienteEndereco,
    DateTime? dataPedido,
    String? status,
    double? total,
    String? observacoes,
    List<ItemPedido>? produtos,
    List<ItemServico>? servicos,
    List<PagamentoPedido>? pagamentos,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Pedido(
      id: id ?? this.id,
      numero: numero ?? this.numero,
      clienteId: clienteId ?? this.clienteId,
      clienteNome: clienteNome ?? this.clienteNome,
      clienteTelefone: clienteTelefone ?? this.clienteTelefone,
      clienteEndereco: clienteEndereco ?? this.clienteEndereco,
      dataPedido: dataPedido ?? this.dataPedido,
      status: status ?? this.status,
      total: total ?? this.total,
      observacoes: observacoes ?? this.observacoes,
      produtos: produtos ?? this.produtos,
      servicos: servicos ?? this.servicos,
      pagamentos: pagamentos ?? this.pagamentos,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}
