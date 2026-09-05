import 'dart:convert';

import 'package:sistema_exodo_novo/utils/date_parser.dart';

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
  final String? metodoEstorno; // fiado, dinheiro, ou null
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
    this.metodoEstorno,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? dataOperacao;

  static dynamic _get(Map<String, dynamic> map, String camel, String snake) =>
      map[camel] ?? map[snake];

  static double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static List<ItemTrocaDevolucao> _parseItens(dynamic raw) {
    if (raw == null) return [];

    List<dynamic> list;
    if (raw is List) {
      list = raw;
    } else if (raw is String && raw.isNotEmpty && raw != '[]' && raw != 'null') {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! List) return [];
        list = decoded;
      } catch (_) {
        return [];
      }
    } else {
      return [];
    }

    return list
        .whereType<Map>()
        .map((i) => ItemTrocaDevolucao.fromMap(Map<String, dynamic>.from(i)))
        .toList();
  }

  factory TrocaDevolucao.fromMap(Map<String, dynamic> map) {
    // Aceita camelCase (local) e snake_case (Supabase).
    // Sem data_operacao, o fallback antigo era DateTime.now() — isso fazia
    // devoluções antigas "nascerem" na data atual ao sincronizar.
    final dataRaw = _get(map, 'dataOperacao', 'data_operacao') ??
        map['data'] ??
        _get(map, 'createdAt', 'created_at');

    final createdRaw = _get(map, 'createdAt', 'created_at') ?? dataRaw;

    final dataOperacao = DateParser.parse(dataRaw);
    final createdAt = DateParser.parse(createdRaw, defaultValue: dataOperacao);

    final tipoRaw = (map['tipo'] ?? 'devolucao').toString();

    final itensDevolvidos = _parseItens(
      _get(map, 'itensDevolvidos', 'itens_devolvidos') ?? map['items'],
    );

    final itensNovosRaw = _get(map, 'itensNovos', 'itens_novos');
    final itensNovosParsed =
        itensNovosRaw != null ? _parseItens(itensNovosRaw) : null;

    return TrocaDevolucao(
      id: map['id']?.toString() ?? '',
      pedidoId: (_get(map, 'pedidoId', 'pedido_id') ??
              _get(map, 'vendaId', 'venda_id') ??
              '')
          .toString(),
      numeroPedido: (_get(map, 'numeroPedido', 'numero_pedido') ??
              map['numero'] ??
              '')
          .toString(),
      clienteId: _get(map, 'clienteId', 'cliente_id')?.toString(),
      clienteNome: _get(map, 'clienteNome', 'cliente_nome')?.toString(),
      dataOperacao: dataOperacao,
      tipo: TipoOperacao.values.firstWhere(
        (t) =>
            t.name == tipoRaw ||
            t.nome.toLowerCase() == tipoRaw.toLowerCase(),
        orElse: () => TipoOperacao.devolucao,
      ),
      itensDevolvidos: itensDevolvidos,
      itensNovos: (itensNovosParsed != null && itensNovosParsed.isEmpty)
          ? null
          : itensNovosParsed,
      valorDevolvido: _toDouble(
        _get(map, 'valorDevolvido', 'valor_devolvido') ??
            _get(map, 'valorTotal', 'valor_total') ??
            map['valor'],
      ),
      valorNovosItens: _toDouble(
        _get(map, 'valorNovosItens', 'valor_novos_itens') ??
            _get(map, 'valorNovo', 'valor_novo'),
      ),
      diferenca: _toDouble(map['diferenca']),
      observacao:
          (_get(map, 'observacao', 'observacao') ?? map['motivo'])?.toString(),
      status: (map['status'] ?? 'Concluído').toString(),
      metodoEstorno: _get(map, 'metodoEstorno', 'metodo_estorno')?.toString(),
      createdAt: createdAt,
    );
  }

  /// Serializa com snake_case (Supabase) e camelCase (local legado).
  Map<String, dynamic> toMap() {
    final itensDev = itensDevolvidos.map((i) => i.toMap()).toList();
    final itensNov = itensNovos?.map((i) => i.toMap()).toList();
    final dataIso = dataOperacao.toIso8601String();
    final createdIso = createdAt.toIso8601String();

    return {
      'id': id,
      // snake_case (Supabase)
      'pedido_id': pedidoId,
      'numero_pedido': numeroPedido,
      'numero': numeroPedido,
      'cliente_id': clienteId,
      'cliente_nome': clienteNome,
      'data_operacao': dataIso,
      'tipo': tipo.name,
      'itens_devolvidos': itensDev,
      'itens_novos': itensNov,
      'valor_devolvido': valorDevolvido,
      'valor_novo': valorNovosItens,
      'diferenca': diferenca,
      'motivo': observacao,
      'observacao': observacao,
      'status': status,
      'metodo_estorno': metodoEstorno,
      'created_at': createdIso,
      // camelCase (local legado / UI)
      'pedidoId': pedidoId,
      'numeroPedido': numeroPedido,
      'clienteId': clienteId,
      'clienteNome': clienteNome,
      'dataOperacao': dataIso,
      'itensDevolvidos': itensDev,
      'itensNovos': itensNov,
      'valorDevolvido': valorDevolvido,
      'valorNovosItens': valorNovosItens,
      'metodoEstorno': metodoEstorno,
      'createdAt': createdIso,
    };
  }

  /// Payload enxuto só com colunas snake_case esperadas no Supabase.
  Map<String, dynamic> toSupabaseMap() {
    return {
      'id': id,
      'pedido_id': pedidoId,
      'numero_pedido': numeroPedido,
      'numero': numeroPedido,
      'cliente_id': clienteId,
      'cliente_nome': clienteNome,
      'data_operacao': dataOperacao.toUtc().toIso8601String(),
      'tipo': tipo.name,
      'itens_devolvidos': itensDevolvidos.map((i) => i.toMap()).toList(),
      'itens_novos': itensNovos?.map((i) => i.toMap()).toList(),
      'valor_devolvido': valorDevolvido,
      'valor_novo': valorNovosItens,
      'diferenca': diferenca,
      'motivo': observacao,
      'status': status,
      'metodo_estorno': metodoEstorno,
      'created_at': createdAt.toUtc().toIso8601String(),
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
    String? metodoEstorno,
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
      metodoEstorno: metodoEstorno ?? this.metodoEstorno,
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
  final double quantidade;
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

  static double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  factory ItemTrocaDevolucao.fromMap(Map<String, dynamic> map) {
    dynamic get(String c, String s) => map[c] ?? map[s];
    return ItemTrocaDevolucao(
      produtoId: (get('produtoId', 'produto_id') ?? map['id'] ?? '').toString(),
      produtoNome:
          (get('produtoNome', 'produto_nome') ?? map['nome'] ?? '').toString(),
      quantidade: _toDouble(map['quantidade']),
      precoUnitario: _toDouble(get('precoUnitario', 'preco_unitario')),
      valorTotal: _toDouble(get('valorTotal', 'valor_total')),
      motivo: map['motivo']?.toString(),
      trocadoPor: get('trocadoPor', 'trocado_por')?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'produtoId': produtoId,
      'produto_id': produtoId,
      'produtoNome': produtoNome,
      'produto_nome': produtoNome,
      'quantidade': quantidade,
      'precoUnitario': precoUnitario,
      'preco_unitario': precoUnitario,
      'valorTotal': valorTotal,
      'valor_total': valorTotal,
      'motivo': motivo,
      'trocadoPor': trocadoPor,
      'trocado_por': trocadoPor,
    };
  }
}
