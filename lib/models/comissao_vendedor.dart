class ComissaoVendedor {
  final String id;
  final String linkVendedorId; // ID do link usado
  final String funcionarioId; // ID do vendedor
  final String funcionarioNome; // Nome do vendedor
  final String pedidoId; // ID do pedido
  final String pedidoNumero; // Número do pedido
  final double valorPedido; // Valor total do pedido
  final double percentualComissao; // Percentual aplicado
  final double valorComissao; // Valor da comissão calculada
  final String status; // Pendente, Paga, Cancelada
  final DateTime? dataPagamento; // Data em que a comissão foi paga
  final DateTime createdAt;
  final DateTime updatedAt;

  ComissaoVendedor({
    required this.id,
    required this.linkVendedorId,
    required this.funcionarioId,
    required this.funcionarioNome,
    required this.pedidoId,
    required this.pedidoNumero,
    required this.valorPedido,
    required this.percentualComissao,
    required this.valorComissao,
    this.status = 'Pendente', // Pendente, Paga, Cancelada
    this.dataPagamento,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory ComissaoVendedor.fromMap(Map<String, dynamic> map) {
    return ComissaoVendedor(
      id: map['id']?.toString() ?? '',
      linkVendedorId: map['linkVendedorId'] as String,
      funcionarioId: map['funcionarioId'] as String,
      funcionarioNome: map['funcionarioNome'] as String,
      pedidoId: map['pedidoId'] as String,
      pedidoNumero: map['pedidoNumero'] as String,
      valorPedido: double.tryParse(map['valorPedido']?.toString() ?? '') ?? 0.0,
      percentualComissao: double.tryParse(map['percentualComissao']?.toString() ?? '') ?? 0.0,
      valorComissao: double.tryParse(map['valorComissao']?.toString() ?? '') ?? 0.0,
      status: map['status'] ?? 'Pendente',
      dataPagamento: map['dataPagamento'] != null
          ? (map['dataPagamento'] is DateTime ? map['dataPagamento'] as DateTime : DateTime.parse(map['dataPagamento'].toString()))
          : null,
      createdAt: map['createdAt'] != null
          ? (map['createdAt'] is DateTime ? map['createdAt'] as DateTime : DateTime.parse(map['createdAt'].toString()))
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? (map['updatedAt'] is DateTime ? map['updatedAt'] as DateTime : DateTime.parse(map['updatedAt'].toString()))
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'linkVendedorId': linkVendedorId,
      'funcionarioId': funcionarioId,
      'funcionarioNome': funcionarioNome,
      'pedidoId': pedidoId,
      'pedidoNumero': pedidoNumero,
      'valorPedido': valorPedido,
      'percentualComissao': percentualComissao,
      'valorComissao': valorComissao,
      'status': status,
      'dataPagamento': dataPagamento?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  ComissaoVendedor copyWith({
    String? id,
    String? linkVendedorId,
    String? funcionarioId,
    String? funcionarioNome,
    String? pedidoId,
    String? pedidoNumero,
    double? valorPedido,
    double? percentualComissao,
    double? valorComissao,
    String? status,
    DateTime? dataPagamento,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ComissaoVendedor(
      id: id ?? this.id,
      linkVendedorId: linkVendedorId ?? this.linkVendedorId,
      funcionarioId: funcionarioId ?? this.funcionarioId,
      funcionarioNome: funcionarioNome ?? this.funcionarioNome,
      pedidoId: pedidoId ?? this.pedidoId,
      pedidoNumero: pedidoNumero ?? this.pedidoNumero,
      valorPedido: valorPedido ?? this.valorPedido,
      percentualComissao: percentualComissao ?? this.percentualComissao,
      valorComissao: valorComissao ?? this.valorComissao,
      status: status ?? this.status,
      dataPagamento: dataPagamento ?? this.dataPagamento,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  // Verifica se a comissão está paga
  bool get isPaga => status == 'Paga';

  // Verifica se a comissão está pendente
  bool get isPendente => status == 'Pendente';

  // Verifica se a comissão está cancelada
  bool get isCancelada => status == 'Cancelada';
}















