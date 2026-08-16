import 'package:flutter/material.dart';

/// Tipos de forma de pagamento disponíveis
enum TipoPagamento {
  dinheiro,
  pix,
  cartaoCredito,
  cartaoDebito,
  boleto,
  crediario,
  fiado,
  outro,
  alimentacao,
  transferencia,
}

/// Extensão para obter informações do tipo de pagamento
extension TipoPagamentoExtension on TipoPagamento {
  String get nome {
    switch (this) {
      case TipoPagamento.dinheiro:
        return 'Dinheiro';
      case TipoPagamento.pix:
        return 'PIX';
      case TipoPagamento.cartaoCredito:
        return 'Cartão de Crédito';
      case TipoPagamento.cartaoDebito:
        return 'Cartão de Débito';
      case TipoPagamento.boleto:
        return 'Boleto';
      case TipoPagamento.crediario:
        return 'Crediário';
      case TipoPagamento.fiado:
        return 'Fiado';
      case TipoPagamento.outro:
        return 'Outro';
      case TipoPagamento.alimentacao:
        return 'Alimentação';
      case TipoPagamento.transferencia:
        return 'Transferência';
    }
  }

  IconData get icone {
    switch (this) {
      case TipoPagamento.dinheiro:
        return Icons.money;
      case TipoPagamento.pix:
        return Icons.qr_code;
      case TipoPagamento.cartaoCredito:
        return Icons.credit_card;
      case TipoPagamento.cartaoDebito:
        return Icons.credit_card;
      case TipoPagamento.boleto:
        return Icons.receipt;
      case TipoPagamento.crediario:
        return Icons.calendar_month;
      case TipoPagamento.fiado:
        return Icons.handshake;
      case TipoPagamento.outro:
        return Icons.more_horiz;
      case TipoPagamento.alimentacao:
        return Icons.restaurant;
      case TipoPagamento.transferencia:
        return Icons.swap_horiz;
    }
  }

  Color get cor {
    switch (this) {
      case TipoPagamento.dinheiro:
        return Colors.green;
      case TipoPagamento.pix:
        return Colors.teal;
      case TipoPagamento.cartaoCredito:
        return Colors.purple;
      case TipoPagamento.cartaoDebito:
        return Colors.blue;
      case TipoPagamento.boleto:
        return Colors.orange;
      case TipoPagamento.crediario:
        return Colors.pink;
      case TipoPagamento.fiado:
        return Colors.red;
      case TipoPagamento.outro:
        return Colors.grey;
      case TipoPagamento.alimentacao:
        return Colors.teal;
      case TipoPagamento.transferencia:
        return Colors.blueAccent;
    }
  }

  /// Verifica se é um pagamento à vista (recebido no momento da venda)
  bool get isAVista {
    return this == TipoPagamento.dinheiro ||
        this == TipoPagamento.pix ||
        this == TipoPagamento.cartaoCredito ||
        this == TipoPagamento.cartaoDebito ||
        this == TipoPagamento.alimentacao;
  }

  /// Verifica se é pagamento a prazo (fiado, boleto, crediário)
  bool get isAPrazo {
    return this == TipoPagamento.fiado ||
        this == TipoPagamento.boleto ||
        this == TipoPagamento.crediario;
  }
}

/// Item de pagamento de um pedido
class PagamentoPedido {
  final String id;
  final TipoPagamento tipo;
  final TipoPagamento?
  tipoOriginal; // Forma de pagamento original (antes de alteração)
  final double valor;
  final int? parcelas; // Número total de parcelas
  final int? numeroParcela; // Número desta parcela (1, 2, 3...)
  final String? parcelamentoId; // ID do parcelamento (agrupa as parcelas)
  final DateTime? dataVencimento; // Data de vencimento da parcela
  final bool recebido; // Se já foi recebido/pago
  final DateTime? dataRecebimento;
  final String? observacao;
  final double? valorRecebido; // Valor que o cliente entregou (para dinheiro)
  final double? troco; // Troco a devolver (para dinheiro)
  final double? desconto;
  final double? acrescimo;

  PagamentoPedido({
    required this.id,
    required this.tipo,
    this.tipoOriginal,
    required this.valor,
    this.parcelas,
    this.numeroParcela,
    this.parcelamentoId,
    this.dataVencimento,
    this.recebido = false,
    this.dataRecebimento,
    this.observacao,
    this.valorRecebido,
    this.troco,
    this.desconto,
    this.acrescimo,
  });

  factory PagamentoPedido.fromMap(Map<String, dynamic> map) {
    return PagamentoPedido(
      id: map['id']?.toString() ?? '',
      tipo: TipoPagamento.values.firstWhere(
        (t) => t.name == map['tipo'],
        orElse: () => TipoPagamento.outro,
      ),
      tipoOriginal: map['tipoOriginal'] != null
          ? TipoPagamento.values.firstWhere(
              (t) => t.name == map['tipoOriginal'],
              orElse: () => TipoPagamento.outro,
            )
          : null,
      valor: (map['valor'] ?? 0).toDouble(),
      parcelas: map['parcelas'],
      numeroParcela: map['numeroParcela'],
      parcelamentoId: map['parcelamentoId'],
      dataVencimento: map['dataVencimento'] != null
          ? DateTime.parse(map['dataVencimento'])
          : null,
      recebido: map['recebido'] ?? false,
      dataRecebimento: map['dataRecebimento'] != null
          ? DateTime.parse(map['dataRecebimento'])
          : null,
      observacao: map['observacao'],
      valorRecebido: map['valorRecebido']?.toDouble(),
      troco: map['troco']?.toDouble(),
      desconto: map['desconto']?.toDouble(),
      acrescimo: map['acrescimo']?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tipo': tipo.name,
      'tipoOriginal': tipoOriginal?.name,
      'valor': valor,
      'parcelas': parcelas,
      'numeroParcela': numeroParcela,
      'parcelamentoId': parcelamentoId,
      'dataVencimento': dataVencimento?.toIso8601String(),
      'recebido': recebido,
      'dataRecebimento': dataRecebimento?.toIso8601String(),
      'observacao': observacao,
      'valorRecebido': valorRecebido,
      'troco': troco,
      'desconto': desconto,
      'acrescimo': acrescimo,
    };
  }

  PagamentoPedido copyWith({
    String? id,
    TipoPagamento? tipo,
    TipoPagamento? tipoOriginal,
    double? valor,
    int? parcelas,
    int? numeroParcela,
    String? parcelamentoId,
    DateTime? dataVencimento,
    bool? recebido,
    DateTime? dataRecebimento,
    String? observacao,
    double? valorRecebido,
    double? troco,
    double? desconto,
    double? acrescimo,
  }) {
    return PagamentoPedido(
      id: id ?? this.id,
      tipo: tipo ?? this.tipo,
      tipoOriginal: tipoOriginal ?? this.tipoOriginal,
      valor: valor ?? this.valor,
      parcelas: parcelas ?? this.parcelas,
      numeroParcela: numeroParcela ?? this.numeroParcela,
      parcelamentoId: parcelamentoId ?? this.parcelamentoId,
      dataVencimento: dataVencimento ?? this.dataVencimento,
      recebido: recebido ?? this.recebido,
      dataRecebimento: dataRecebimento ?? this.dataRecebimento,
      observacao: observacao ?? this.observacao,
      valorRecebido: valorRecebido ?? this.valorRecebido,
      troco: troco ?? this.troco,
      desconto: desconto ?? this.desconto,
      acrescimo: acrescimo ?? this.acrescimo,
    );
  }

  /// Retorna a forma de pagamento original (ou a atual se não houver)
  TipoPagamento get tipoOriginalOuAtual => tipoOriginal ?? tipo;
  double get valorParcela =>
      parcelas != null && parcelas! > 0 ? valor / parcelas! : valor;

  /// Verifica se é uma parcela (parte de um parcelamento)
  bool get isParcela =>
      numeroParcela != null && parcelas != null && parcelas! > 1;

  /// Descrição da parcela (ex: "1/3", "2/3")
  String get descricaoParcela => isParcela ? '$numeroParcela/$parcelas' : '';

  /// Verifica se está vencida
  bool get isVencida =>
      dataVencimento != null &&
      !recebido &&
      dataVencimento!.isBefore(DateTime.now());

  /// Verifica se vence hoje
  bool get venceHoje {
    if (dataVencimento == null || recebido) return false;
    final hoje = DateTime.now();
    return dataVencimento!.year == hoje.year &&
        dataVencimento!.month == hoje.month &&
        dataVencimento!.day == hoje.day;
  }
}
