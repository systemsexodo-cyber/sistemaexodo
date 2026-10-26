import 'package:flutter/material.dart';
import 'package:sistema_exodo_novo/models/cliente.dart';

/// Tipo de movimento de cash back (crédito ou débito no saldo do cliente).
enum CashBackMovimentoTipo { credito, debito }

extension CashBackMovimentoTipoExtension on CashBackMovimentoTipo {
  String get nome {
    switch (this) {
      case CashBackMovimentoTipo.credito:
        return 'Crédito';
      case CashBackMovimentoTipo.debito:
        return 'Débito';
    }
  }

  IconData get icone {
    switch (this) {
      case CashBackMovimentoTipo.credito:
        return Icons.add_circle;
      case CashBackMovimentoTipo.debito:
        return Icons.remove_circle;
    }
  }

  Color get cor {
    switch (this) {
      case CashBackMovimentoTipo.credito:
        return Colors.green;
      case CashBackMovimentoTipo.debito:
        return Colors.amber;
    }
  }
}

/// Um lançamento do extrato de cash back de um cliente.
///
/// Cada venda que gera ou consome saldo cria um movimento, permitindo ao
/// operador (e ao cliente) ver de onde veio cada centavo do saldo.
class CashBackMovimento {
  final String id;
  final String clienteId;
  final CashBackMovimentoTipo tipo;
  final double valor; // sempre positivo; o sentido vem de [tipo]
  final double saldoApos; // saldo do cliente depois deste movimento
  final String? vendaId; // venda de balcão de origem (quando aplicável)
  final String? vendaNumero; // número da venda (para exibição)
  final DateTime data;
  final String? observacao; // ex: 'Cash back 5% da venda VND-00123'

  /// Quando este CRÉDITO vence (só preenchido em créditos com validade
  /// configurada na empresa). `null` = não expira.
  final DateTime? expiraEm;

  /// Quanto deste CRÉDITO já foi consumido por débitos (uso em venda ou
  /// manual). Débitos consomem os créditos que vencem primeiro (e créditos
  /// sem validade por último) — assim o saldo que ia vencer é usado antes.
  /// Sempre 0 em movimentos de débito.
  final double consumido;

  CashBackMovimento({
    required this.id,
    required this.clienteId,
    required this.tipo,
    required this.valor,
    required this.saldoApos,
    this.vendaId,
    this.vendaNumero,
    required this.data,
    this.observacao,
    this.expiraEm,
    this.consumido = 0.0,
  });

  /// Restante deste crédito: o que ainda não foi consumido nem venceu.
  double get restante => (valor - consumido) < 0 ? 0.0 : valor - consumido;

  factory CashBackMovimento.fromMap(Map<String, dynamic> map) {
    // Lê as DUAS grafias (camelCase em memória/web, snake_case vindo do
    // PostgreSQL local e do Supabase) — mesma convenção de Cliente.fromMap.
    String? texto(String camel, String snake) {
      final v = map[camel] ?? map[snake];
      return v?.toString();
    }

    return CashBackMovimento(
      id: map['id']?.toString() ?? '',
      clienteId: texto('clienteId', 'cliente_id') ?? '',
      tipo: CashBackMovimentoTipo.values.firstWhere(
        (t) => t.name == map['tipo'],
        orElse: () => CashBackMovimentoTipo.credito,
      ),
      valor: (map['valor'] ?? 0).toDouble(),
      saldoApos: (map['saldoApos'] ?? map['saldo_apos'] ?? 0).toDouble(),
      vendaId: texto('vendaId', 'venda_id'),
      vendaNumero: texto('vendaNumero', 'venda_numero'),
      data: DateTime.tryParse(map['data']?.toString() ?? '') ?? DateTime.now(),
      observacao: map['observacao']?.toString(),
      expiraEm: DateTime.tryParse(
            map['expiraEm']?.toString() ?? map['expira_em']?.toString() ?? '',
          ) ??
          null,
      consumido: (map['consumido'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'cliente_id': clienteId,
      'clienteId': clienteId,
      'tipo': tipo.name,
      'valor': valor,
      'saldo_apos': saldoApos,
      'saldoApos': saldoApos,
      'venda_id': vendaId,
      'vendaId': vendaId,
      'venda_numero': vendaNumero,
      'vendaNumero': vendaNumero,
      'data': data.toIso8601String(),
      'observacao': observacao,
      'expiraEm': expiraEm?.toIso8601String(),
      'expira_em': expiraEm?.toIso8601String(),
      'consumido': consumido,
    };
  }

  CashBackMovimento copyWith({
    String? id,
    String? clienteId,
    CashBackMovimentoTipo? tipo,
    double? valor,
    double? saldoApos,
    String? vendaId,
    String? vendaNumero,
    DateTime? data,
    String? observacao,
    DateTime? expiraEm,
    double? consumido,
  }) {
    return CashBackMovimento(
      id: id ?? this.id,
      clienteId: clienteId ?? this.clienteId,
      tipo: tipo ?? this.tipo,
      valor: valor ?? this.valor,
      saldoApos: saldoApos ?? this.saldoApos,
      vendaId: vendaId ?? this.vendaId,
      vendaNumero: vendaNumero ?? this.vendaNumero,
      data: data ?? this.data,
      observacao: observacao ?? this.observacao,
      expiraEm: expiraEm ?? this.expiraEm,
      consumido: consumido ?? this.consumido,
    );
  }

  /// Exibe o valor com sinal (+ crédito, − débito).
  String get valorFormatado {
    final sinal = tipo == CashBackMovimentoTipo.credito ? '+' : '−';
    return '$sinal R\$ ${valor.toStringAsFixed(2)}';
  }
}
