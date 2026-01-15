import 'package:sistema_exodo_novo/models/item_pedido.dart';
import 'package:sistema_exodo_novo/models/item_servico.dart';

class Pedido {
  final String id;
  final String clienteId;
  final String clienteNome;
  final DateTime dataPedido;
  final String status;
  final double total;
  final String? observacoes;
  final List<ItemPedido> produtos;
  final List<ItemServico> servicos;
  final DateTime createdAt;
  final DateTime updatedAt;

  Pedido({
    required this.id,
    required this.clienteId,
    required this.clienteNome,
    required this.dataPedido,
    required this.status,
    required this.total,
    this.observacoes,
    required this.produtos,
    required this.servicos,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'clienteId': clienteId,
      'clienteNome': clienteNome,
      'dataPedido': dataPedido.toIso8601String(),
      'status': status,
      'total': total,
      'observacoes': observacoes,
      'produtos': produtos.map((p) => p.toMap()).toList(),
      'servicos': servicos.map((s) => s.toMap()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Pedido.fromMap(Map<String, dynamic> map) {
    return Pedido(
      id: map['id'] ?? '',
      clienteId: map['clienteId'] ?? '',
      clienteNome: map['clienteNome'] ?? '',
      dataPedido: DateTime.parse(map['dataPedido']),
      status: map['status'] ?? 'Pendente',
      total: (map['total'] ?? 0.0).toDouble(),
      observacoes: map['observacoes'],
      produtos: (map['produtos'] as List<dynamic>?)
              ?.map((p) => ItemPedido.fromMap(p as Map<String, dynamic>))
              .toList() ??
          [],
      servicos: (map['servicos'] as List<dynamic>?)
              ?.map((s) => ItemServico.fromMap(s as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: DateTime.parse(map['createdAt']),
      updatedAt: DateTime.parse(map['updatedAt']),
    );
  }

  Pedido copyWith({
    String? id,
    String? clienteId,
    String? clienteNome,
    DateTime? dataPedido,
    String? status,
    double? total,
    String? observacoes,
    List<ItemPedido>? produtos,
    List<ItemServico>? servicos,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Pedido(
      id: id ?? this.id,
      clienteId: clienteId ?? this.clienteId,
      clienteNome: clienteNome ?? this.clienteNome,
      dataPedido: dataPedido ?? this.dataPedido,
      status: status ?? this.status,
      total: total ?? this.total,
      observacoes: observacoes ?? this.observacoes,
      produtos: produtos ?? this.produtos,
      servicos: servicos ?? this.servicos,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() => 'Pedido(id: $id, clienteNome: $clienteNome, total: $total)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Pedido && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

